package com.example.team_chai_and_code.catalog

/** The current availability of an original source at its authorised URI. */
enum class SourceAvailability {
    AVAILABLE,
    PERMISSION_REVOKED,
    MISSING,
    UNREADABLE,
}

/**
 * Identifies the original item, never an extracted copy.
 *
 * `sourceUri` is a persisted Android content URI for external content. App-owned
 * chat records use the documented `chat://` URI form. A version changes whenever
 * source bytes or the relevant message body changes.
 */
data class SourceRecord(
    val sourceId: String,
    val sourceUri: String,
    val displayName: String,
    val mimeType: String,
    val contentVersion: String,
    val modifiedAtMillis: Long,
    val availability: SourceAvailability = SourceAvailability.AVAILABLE,
) {
    init {
        require(sourceId.isNotBlank()) { "sourceId is required" }
        require(sourceUri.isNotBlank()) { "sourceUri is required" }
        require(displayName.isNotBlank()) { "displayName is required" }
        require(mimeType.isNotBlank()) { "mimeType is required" }
        require(contentVersion.isNotBlank()) { "contentVersion is required" }
        require(modifiedAtMillis > 0) { "modifiedAtMillis must be positive" }
    }
}

enum class ExtractionKind {
    TEXT,
    PDF_TEXT,
    PDF_OCR,
    IMAGE_OCR,
    AUDIO_TRANSCRIPT,
    CHAT_MEMORY,
}

/**
 * Local text derived from a source. Page is one-based; segment is a stable
 * time/message identifier such as `00:01:12.300-00:01:20.600`.
 */
data class ExtractionRecord(
    val extractionId: String,
    val sourceId: String,
    val kind: ExtractionKind,
    val text: String,
    val extractorVersion: String,
    val extractedAtMillis: Long,
    val page: Int? = null,
    val segment: String? = null,
    val confidence: Double? = null,
) {
    init {
        require(extractionId.isNotBlank()) { "extractionId is required" }
        require(sourceId.isNotBlank()) { "sourceId is required" }
        require(text.isNotBlank()) { "text is required" }
        require(extractorVersion.isNotBlank()) { "extractorVersion is required" }
        require(extractedAtMillis > 0) { "extractedAtMillis must be positive" }
        require(page == null || page > 0) { "page must be positive" }
        require(confidence == null || confidence in 0.0..1.0) {
            "confidence must be between 0 and 1"
        }
    }
}

sealed interface CatalogWriteResult {
    data class Indexed(
        val sourceId: String,
        val extractionId: String,
        val replacedExtractionIds: Set<String> = emptySet(),
    ) : CatalogWriteResult

    data class Rejected(val reason: String) : CatalogWriteResult
    data class Failed(val reason: String, val retryable: Boolean) : CatalogWriteResult
}
