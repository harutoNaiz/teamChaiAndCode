package com.example.team_chai_and_code.catalog

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Private durable catalog for the first on-device release.
 *
 * AppSearch remains the search engine; this store owns source/extraction
 * provenance and stale-unit replacement metadata. It is deliberately isolated
 * behind [CatalogWriter] so it can migrate to Room without changing workers.
 */
class SharedPreferencesCatalogWriter(context: Context) : CatalogWriter {
    private val preferences = context.applicationContext
        .getSharedPreferences("local_catalog_v1", Context.MODE_PRIVATE)

    override fun upsert(source: SourceRecord, extraction: ExtractionRecord): CatalogWriteResult {
        return try {
            if (source.sourceId != extraction.sourceId) {
                return CatalogWriteResult.Rejected("extraction sourceId does not match source")
            }
            val unitKey = "unit:${source.sourceId}:${extraction.kind}:${extraction.page ?: 0}:${extraction.segment ?: ""}"
            val existingId = preferences.getString(unitKey, null)
            val sourceJson = JSONObject()
                .put("sourceId", source.sourceId)
                .put("sourceUri", source.sourceUri)
                .put("displayName", source.displayName)
                .put("mimeType", source.mimeType)
                .put("contentVersion", source.contentVersion)
                .put("modifiedAtMillis", source.modifiedAtMillis)
                .put("availability", source.availability.name)
            val extractionJson = JSONObject()
                .put("extractionId", extraction.extractionId)
                .put("sourceId", extraction.sourceId)
                .put("kind", extraction.kind.name)
                .put("text", extraction.text)
                .put("extractorVersion", extraction.extractorVersion)
                .put("extractedAtMillis", extraction.extractedAtMillis)
                .put("page", extraction.page)
                .put("segment", extraction.segment)
                .put("confidence", extraction.confidence)
            val replaced = existingId?.takeIf { it != extraction.extractionId }?.let { setOf(it) } ?: emptySet()
            preferences.edit()
                .putString("source:${source.sourceId}", sourceJson.toString())
                .putString("extraction:${extraction.extractionId}", extractionJson.toString())
                .putString(unitKey, extraction.extractionId)
                .apply {
                    replaced.forEach { remove("extraction:$it") }
                }
                .apply()
            CatalogWriteResult.Indexed(source.sourceId, extraction.extractionId, replaced)
        } catch (error: Exception) {
            CatalogWriteResult.Failed(error.message ?: "Unable to persist catalog record", retryable = true)
        }
    }

    fun sourceJson(sourceId: String): JSONObject? =
        preferences.getString("source:$sourceId", null)?.let(::JSONObject)

    fun extractionIdsForSource(sourceId: String): List<String> =
        preferences.all.filterKeys { it.startsWith("unit:$sourceId:") }.values
            .filterIsInstance<String>()
            .distinct()

    fun exportRows(): JSONArray = JSONArray().also { output ->
        preferences.all.filterKeys { it.startsWith("extraction:") }.values
            .filterIsInstance<String>().forEach { output.put(JSONObject(it)) }
    }
}
