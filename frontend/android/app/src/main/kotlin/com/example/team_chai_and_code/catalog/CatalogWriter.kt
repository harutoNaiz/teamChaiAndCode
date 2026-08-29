package com.example.team_chai_and_code.catalog

/**
 * Single ingestion boundary shared by SAF/MediaStore discovery, OCR, PDF text,
 * audio transcription, and chat-memory indexing. Implementations persist the
 * source/extraction relationship and replace stale records for the same logical
 * source unit before exposing it to retrieval.
 */
interface CatalogWriter {
    fun upsert(source: SourceRecord, extraction: ExtractionRecord): CatalogWriteResult
}
