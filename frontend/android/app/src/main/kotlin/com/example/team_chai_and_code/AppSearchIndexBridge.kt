package com.example.team_chai_and_code

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.appsearch.app.AppSearchSchema
import androidx.appsearch.app.AppSearchSession
import androidx.appsearch.app.GenericDocument
import androidx.appsearch.app.PutDocumentsRequest
import androidx.appsearch.app.RemoveByDocumentIdRequest
import androidx.appsearch.app.SearchSpec
import androidx.appsearch.app.SetSchemaRequest
import androidx.appsearch.localstorage.LocalStorage
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

class AppSearchIndexBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val preferences = appContext.getSharedPreferences("local_index_sources", Context.MODE_PRIVATE)
    private var session: AppSearchSession? = null
    @Volatile private var closed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            failure(result, "index_closed", "Index bridge is closed")
            return
        }
        try { executor.execute {
            if (closed) {
                failure(result, "index_closed", "Index bridge is closed")
                return@execute
            }
            try {
                when (call.method) {
                    "indexText" -> upsert(readRecord(call.arguments, "text"))
                    "indexOcr" -> upsert(readRecord(call.arguments, "image_ocr"))
                    "search" -> search(readQuery(call.arguments))
                    else -> throw UnsupportedOperationException("Unknown method: ${call.method}")
                }.also { value -> success(result, value) }
            } catch (error: IllegalArgumentException) {
                failure(result, "invalid_argument", error.message ?: "Invalid argument")
            } catch (error: Exception) {
                failure(result, "index_error", error.message ?: "Index operation failed")
            }
        } } catch (error: RejectedExecutionException) {
            failure(result, "index_closed", "Index bridge is closed")
        }
    }

    fun close() {
        if (closed) return
        closed = true
        executor.execute {
            session?.close()
            session = null
        }
        executor.shutdown()
    }

    private fun appSearch(): AppSearchSession {
        session?.let { return it }
        val created = LocalStorage.createSearchSessionAsync(
            LocalStorage.SearchContext.Builder(appContext, DATABASE_NAME).build()
        ).get()
        created.setSchemaAsync(SetSchemaRequest.Builder().addSchemas(schema()).build()).get()
        session = created
        return created
    }

    private fun upsert(record: IndexRecord): Map<String, Any?> {
        val sourceKey = "${record.sourceUri}|${record.page ?: 0}"
        val previousId = preferences.getString(sourceKey, null)
        val identifierKey = "id:${record.id}"
        val existingSourceKey = preferences.getString(identifierKey, null)
        require(existingSourceKey == null || existingSourceKey == sourceKey) { "id belongs to another source" }
        val store = appSearch()
        if (previousId != null && previousId != record.id) {
            store.removeAsync(
                RemoveByDocumentIdRequest.Builder(NAMESPACE).addIds(previousId).build()
            ).get()
            preferences.edit().remove("id:$previousId").apply()
        }
        val documentBuilder =
            GenericDocument.Builder<GenericDocument.Builder<*>>(NAMESPACE, record.id, SCHEMA_TYPE)
        documentBuilder.setPropertyString("sourceUri", record.sourceUri)
        documentBuilder.setPropertyString("displayName", record.displayName)
        documentBuilder.setPropertyString("mimeType", record.mimeType)
        documentBuilder.setPropertyString("contentType", record.contentType)
        documentBuilder.setPropertyString("transcription", record.transcription)
        record.page?.let { documentBuilder.setPropertyLong("page", it.toLong()) }
        record.ocrConfidence?.let {
            documentBuilder.setPropertyDouble("ocrConfidence", it)
        }
        record.modifiedAt?.let { documentBuilder.setPropertyLong("modifiedAt", it) }
        val document = documentBuilder.build()
        store.putAsync(PutDocumentsRequest.Builder().addGenericDocuments(document).build()).get()
        preferences.edit()
            .putString(sourceKey, record.id)
            .putString(identifierKey, sourceKey)
            .apply()
        return mapOf("id" to record.id, "indexed" to true, "open_uri" to record.sourceUri)
    }

    private fun search(query: String): List<Map<String, Any?>> {
        require(query.isNotBlank()) { "q is required" }
        val spec = SearchSpec.Builder()
            .setTermMatch(SearchSpec.TERM_MATCH_PREFIX)
            .setSnippetCount(1)
            .setSnippetCountPerProperty(1)
            .build()
        val results = mutableListOf<Map<String, Any?>>()
        val searchResults = appSearch().search(query, spec)
        while (true) {
            if (results.size >= RESULT_LIMIT) return results
            val page = searchResults.nextPageAsync.get()
            if (page.isEmpty()) break
            page.forEach { result ->
                if (results.size >= RESULT_LIMIT) return results
                val document = result.genericDocument
                val transcription = document.getPropertyString("transcription") ?: ""
                results.add(
                    mapOf(
                        "identifier" to document.id,
                        "source_uri" to document.getPropertyString("sourceUri"),
                        "open_uri" to document.getPropertyString("sourceUri"),
                        "display_name" to document.getPropertyString("displayName"),
                        "mime_type" to document.getPropertyString("mimeType"),
                        "content_type" to document.getPropertyString("contentType"),
                        "transcription" to transcription,
                        "page" to document.getPropertyLong("page"),
                        "ocr_confidence" to document.getPropertyDouble("ocrConfidence"),
                        "modified_at" to document.getPropertyLong("modifiedAt"),
                        "snippet" to snippetFor(transcription, query),
                    )
                )
            }
        }
        return results
    }

    private fun snippetFor(text: String, query: String): String {
        val position = text.indexOf(query, ignoreCase = true)
        if (position < 0) return text.take(SNIPPET_LENGTH)
        val start = maxOf(0, position - SNIPPET_RADIUS)
        val end = minOf(text.length, position + query.length + SNIPPET_RADIUS)
        return text.substring(start, end).trim()
    }

    private fun readRecord(arguments: Any?, defaultContentType: String): IndexRecord {
        val values = arguments as? Map<*, *> ?: throw IllegalArgumentException("Arguments must be an object")
        val suppliedContentType = values["content_type"]
        require(suppliedContentType == null || suppliedContentType is String) { "content_type must be a string" }
        val contentType = (suppliedContentType as? String) ?: defaultContentType
        val allowedContentTypes = if (defaultContentType == "text") setOf("text", "pdf_text") else setOf("image_ocr", "pdf_ocr")
        fun required(name: String): String {
            val value = values[name] as? String ?: throw IllegalArgumentException("$name is required")
            require(value.isNotBlank()) { "$name is required" }
            return value
        }
        val confidence = (values["ocr_confidence"] as? Number)?.toDouble()
        require(confidence == null || confidence in 0.0..1.0) { "ocr_confidence must be between 0 and 1" }
        val rawPage = values["page"] as? Number
        val page = rawPage?.toInt()
        require(rawPage == null || rawPage.toDouble() == page?.toDouble()) { "page must be a whole number" }
        require(page == null || page > 0) { "page must be positive" }
        val rawModifiedAt = values["modified_at"] as? Number
        val modifiedAt = rawModifiedAt?.toLong()
        require(rawModifiedAt == null || rawModifiedAt.toDouble() == modifiedAt?.toDouble()) { "modified_at must be a whole number" }
        require(modifiedAt == null || modifiedAt > 0) { "modified_at must be positive" }
        return IndexRecord(
            id = required("id"),
            sourceUri = required("source_uri"),
            displayName = required("display_name"),
            mimeType = required("mime_type"),
            contentType = contentType,
            transcription = required("transcription"),
            page = page,
            ocrConfidence = confidence,
            modifiedAt = modifiedAt,
        )
    }

    private fun readQuery(arguments: Any?): String {
        val values = arguments as? Map<*, *> ?: throw IllegalArgumentException("Arguments must be an object")
        return values["q"] as? String ?: throw IllegalArgumentException("q is required")
    }

    private fun success(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun failure(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    private fun schema(): AppSearchSchema = AppSearchSchema.Builder(SCHEMA_TYPE)
        .addProperty(
            AppSearchSchema.StringPropertyConfig.Builder("sourceUri")
                .setCardinality(AppSearchSchema.PropertyConfig.CARDINALITY_REQUIRED)
                .build()
        )
        .addProperty(
            AppSearchSchema.StringPropertyConfig.Builder("displayName")
                .setCardinality(AppSearchSchema.PropertyConfig.CARDINALITY_REQUIRED)
                .setIndexingType(AppSearchSchema.StringPropertyConfig.INDEXING_TYPE_PREFIXES)
                .setTokenizerType(AppSearchSchema.StringPropertyConfig.TOKENIZER_TYPE_PLAIN)
                .build()
        )
        .addProperty(
            AppSearchSchema.StringPropertyConfig.Builder("mimeType")
                .setCardinality(AppSearchSchema.PropertyConfig.CARDINALITY_REQUIRED)
                .build()
        )
        .addProperty(
            AppSearchSchema.StringPropertyConfig.Builder("contentType")
                .setCardinality(AppSearchSchema.PropertyConfig.CARDINALITY_REQUIRED)
                .build()
        )
        .addProperty(
            AppSearchSchema.StringPropertyConfig.Builder("transcription")
                .setCardinality(AppSearchSchema.PropertyConfig.CARDINALITY_REQUIRED)
                .setIndexingType(AppSearchSchema.StringPropertyConfig.INDEXING_TYPE_PREFIXES)
                .setTokenizerType(AppSearchSchema.StringPropertyConfig.TOKENIZER_TYPE_PLAIN)
                .build()
        )
        .addProperty(AppSearchSchema.LongPropertyConfig.Builder("page").build())
        .addProperty(AppSearchSchema.DoublePropertyConfig.Builder("ocrConfidence").build())
        .addProperty(AppSearchSchema.LongPropertyConfig.Builder("modifiedAt").build())
        .build()

    private data class IndexRecord(
        val id: String,
        val sourceUri: String,
        val displayName: String,
        val mimeType: String,
        val contentType: String,
        val transcription: String,
        val page: Int?,
        val ocrConfidence: Double?,
        val modifiedAt: Long?,
    )

    private companion object {
        const val DATABASE_NAME = "team_chai_local_index"
        const val NAMESPACE = "phone_content"
        const val SCHEMA_TYPE = "IndexedContent"
        const val RESULT_LIMIT = 20
        const val SNIPPET_LENGTH = 160
        const val SNIPPET_RADIUS = 80
    }
}
