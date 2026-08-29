package com.example.team_chai_and_code

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.appsearch.app.AppSearchSchema
import androidx.appsearch.app.AppSearchSession
import androidx.appsearch.app.EmbeddingVector
import androidx.appsearch.app.ExperimentalAppSearchApi
import androidx.appsearch.app.GenericDocument
import androidx.appsearch.app.PutDocumentsRequest
import androidx.appsearch.app.RemoveByDocumentIdRequest
import androidx.appsearch.app.SearchSpec
import androidx.appsearch.app.SetSchemaRequest
import androidx.appsearch.localstorage.LocalStorage
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.example.team_chai_and_code.catalog.CatalogWriteResult
import com.example.team_chai_and_code.catalog.ExtractionKind
import com.example.team_chai_and_code.catalog.ExtractionRecord
import com.example.team_chai_and_code.catalog.SharedPreferencesCatalogWriter
import com.example.team_chai_and_code.catalog.SourceRecord
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

@OptIn(ExperimentalAppSearchApi::class)
class AppSearchIndexBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val preferences = appContext.getSharedPreferences("local_index_sources", Context.MODE_PRIVATE)
    private val catalog = SharedPreferencesCatalogWriter(appContext)
    private val embedder = LocalTextEmbedder(appContext)
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
                    "indexChatMemory" -> upsert(readRecord(call.arguments, "chat_memory"))
                    "openUri" -> openUri(readUri(call.arguments))
                    "search" -> search(readSearchRequest(call.arguments))
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
            embedder.close()
        }
        executor.shutdown()
    }

    /** Used only by the scanner bridge after it has obtained an authorised URI. */
    fun indexDirectly(record: Map<String, Any?>, defaultContentType: String): Map<String, Any?> =
        upsert(readRecord(record, defaultContentType))

    private fun openUri(uri: String): Map<String, Any?> {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        appContext.startActivity(intent)
        return mapOf("opened" to true, "uri" to uri)
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
        val catalogResult = catalog.upsert(
            SourceRecord(
                sourceId = record.sourceUri,
                sourceUri = record.sourceUri,
                displayName = record.displayName,
                mimeType = record.mimeType,
                contentVersion = record.id,
                modifiedAtMillis = record.modifiedAt ?: System.currentTimeMillis(),
            ),
            ExtractionRecord(
                extractionId = record.id,
                sourceId = record.sourceUri,
                kind = when (record.contentType) {
                    "pdf_text" -> ExtractionKind.PDF_TEXT
                    "pdf_ocr" -> ExtractionKind.PDF_OCR
                    "image_ocr" -> ExtractionKind.IMAGE_OCR
                    "chat_memory" -> ExtractionKind.CHAT_MEMORY
                    else -> ExtractionKind.TEXT
                },
                text = record.transcription,
                extractorVersion = "bridge-v1",
                extractedAtMillis = record.modifiedAt ?: System.currentTimeMillis(),
                page = record.page,
                confidence = record.ocrConfidence,
            )
        )
        require(catalogResult !is CatalogWriteResult.Rejected) { catalogResult.reason }
        if (catalogResult is CatalogWriteResult.Failed) {
            throw IllegalStateException(catalogResult.reason)
        }
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
        documentBuilder.setPropertyEmbedding(
            "embedding",
            EmbeddingVector(embedder.embed(record.transcription), EMBEDDING_MODEL_SIGNATURE)
        )
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

    private fun search(request: SearchRequest): List<Map<String, Any?>> {
        val query = request.query
        val lexicalSpec = SearchSpec.Builder()
            .setTermMatch(SearchSpec.TERM_MATCH_PREFIX)
            .setSnippetCount(1)
            .setSnippetCountPerProperty(1)
            .build()
        val lexical = collectResults(appSearch().search(query, lexicalSpec), request)
        if (lexical.isNotEmpty()) return lexical
        if (!query.contains(Regex("\\s"))) return lexical
        val queryEmbedding = EmbeddingVector(embedder.embed(query), EMBEDDING_MODEL_SIGNATURE)
        val spec = SearchSpec.Builder()
            .addEmbeddingParameters(queryEmbedding)
            .setListFilterQueryLanguageEnabled(true)
            .setSnippetCount(1)
            .setSnippetCountPerProperty(1)
            .build()
        val searchResults = appSearch().search(
            "semanticSearch(getEmbeddingParameter(0), -1.0, 1.0, \"COSINE\")",
            spec
        )
        return collectResults(searchResults, request)
    }

    private fun collectResults(
        searchResults: androidx.appsearch.app.SearchResults,
        request: SearchRequest,
    ): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        while (true) {
            if (results.size >= request.limit) return results
            val page = searchResults.nextPageAsync.get()
            if (page.isEmpty()) break
            page.forEach { result ->
                if (results.size >= request.limit) return results
                val document = result.genericDocument
                val transcription = document.getPropertyString("transcription") ?: ""
                if (!matchesFilters(document, request)) return@forEach
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
                        "score" to result.rankingSignal,
                        "snippet" to snippetFor(transcription, request.query),
                    )
                )
            }
        }
        return results
    }

    private fun matchesFilters(document: GenericDocument, request: SearchRequest): Boolean {
        val contentType = document.getPropertyString("contentType") ?: return false
        val mimeType = document.getPropertyString("mimeType") ?: return false
        val sourceUri = document.getPropertyString("sourceUri") ?: return false
        return (request.contentTypes.isEmpty() || contentType in request.contentTypes) &&
            (request.mimeTypes.isEmpty() || mimeType in request.mimeTypes) &&
            (request.sourceUri == null || sourceUri == request.sourceUri)
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
        val allowedContentTypes = when (defaultContentType) {
            "text" -> setOf("text", "pdf_text")
            "chat_memory" -> setOf("chat_memory")
            else -> setOf("image_ocr", "pdf_ocr")
        }
        require(contentType in allowedContentTypes) { "content_type is not valid for this index method" }
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

    private fun readSearchRequest(arguments: Any?): SearchRequest {
        val values = arguments as? Map<*, *> ?: throw IllegalArgumentException("Arguments must be an object")
        val query = values["q"] as? String ?: throw IllegalArgumentException("q is required")
        require(query.isNotBlank()) { "q is required" }
        val rawLimit = values["limit"] as? Number
        val limit = rawLimit?.toInt() ?: DEFAULT_RESULT_LIMIT
        require(rawLimit == null || rawLimit.toDouble() == limit.toDouble()) { "limit must be a whole number" }
        require(limit in 1..RESULT_LIMIT) { "limit must be between 1 and $RESULT_LIMIT" }
        fun stringSet(name: String): Set<String> {
            val value = values[name] ?: return emptySet()
            val list = value as? List<*> ?: throw IllegalArgumentException("$name must be a list of strings")
            return list.map {
                val item = it as? String ?: throw IllegalArgumentException("$name must be a list of strings")
                require(item.isNotBlank()) { "$name must not contain blank values" }
                item
            }.toSet()
        }
        val sourceUri = values["source_uri"]
        require(sourceUri == null || sourceUri is String && sourceUri.isNotBlank()) {
            "source_uri must be a non-empty string"
        }
        return SearchRequest(query, limit, stringSet("content_types"), stringSet("mime_types"), sourceUri as? String)
    }

    private fun readUri(arguments: Any?): String {
        val values = arguments as? Map<*, *> ?: throw IllegalArgumentException("Arguments must be an object")
        val uri = values["uri"] as? String ?: throw IllegalArgumentException("uri is required")
        require(uri.isNotBlank()) { "uri is required" }
        return uri
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
        .addProperty(
            AppSearchSchema.EmbeddingPropertyConfig.Builder("embedding")
                .setIndexingType(AppSearchSchema.EmbeddingPropertyConfig.INDEXING_TYPE_SIMILARITY)
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

    private data class SearchRequest(
        val query: String,
        val limit: Int,
        val contentTypes: Set<String>,
        val mimeTypes: Set<String>,
        val sourceUri: String?,
    )

    private companion object {
        const val DATABASE_NAME = "team_chai_local_index"
        const val NAMESPACE = "phone_content"
        const val SCHEMA_TYPE = "IndexedContent"
        const val RESULT_LIMIT = 20
        const val DEFAULT_RESULT_LIMIT = 5
        const val SNIPPET_LENGTH = 160
        const val SNIPPET_RADIUS = 80
        const val EMBEDDING_MODEL_SIGNATURE = "universal-sentence-encoder-v1"
    }
}
