# Catalog contract

This is the cross-owner contract for local ingestion. It belongs to Tushar;
Suprith writes through it, and Vidya consumes the evidence produced downstream.

## Kotlin boundary

```kotlin
CatalogWriter.upsert(source: SourceRecord, extraction: ExtractionRecord)
    -> CatalogWriteResult.Indexed | Rejected | Failed
```

The authoritative models are in:

* `frontend/android/app/src/main/kotlin/com/example/team_chai_and_code/catalog/CatalogModels.kt`
* `frontend/android/app/src/main/kotlin/com/example/team_chai_and_code/catalog/CatalogWriter.kt`

`SourceRecord` identifies an original item. External sources must use an
authorised persisted `content://` URI; `chat://` is reserved for app-owned chat
memory. `ExtractionRecord` stores non-empty local text derived from that source.
An extractor must return `Rejected`/`Failed` rather than writing empty text.

## Stale replacement

The writer treats `(sourceId, kind, page, segment)` as one logical source unit.
A new content version replaces prior extractions/vectors for that unit atomically.
If availability is `PERMISSION_REVOKED`, `MISSING`, or `UNREADABLE`, it must not
be returned as current evidence. The source state may remain locally for UI/audit
purposes.

## Required mapping

| Producer | Source | Extraction kind | Location |
| --- | --- | --- | --- |
| native text file | authorised file URI | `TEXT` | none |
| PDF native extraction | authorised PDF URI | `PDF_TEXT` | one-based `page` |
| scanned PDF page | authorised PDF URI | `PDF_OCR` | one-based `page` |
| image OCR | authorised image URI | `IMAGE_OCR` | none |
| recording | app/openable recording URI | `AUDIO_TRANSCRIPT` | time-coded `segment` |
| stored chat message | `chat://session/<id>/message/<id>` | `CHAT_MEMORY` | message ID segment |

## Not part of this contract

* UI cards/open actions
* SAF/MediaStore discovery and Android scheduling
* OCR or audio runtime selection
* vector ranking and model prompting
* CSV export format (it is derived from the catalog, never the catalog itself)
