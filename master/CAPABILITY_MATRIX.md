# Capability matrix (implementation truth)

This table is the source of truth for what can be called today. “Wired” means
there is a real local implementation and an explicit result; “contract only”
means the boundary exists but must not be advertised as executable.

| Capability | Status | Current implementation / remaining work |
| --- | --- | --- |
| Lexical + semantic local search | Wired | AppSearch `team_chai_local_index`; source URI and extraction are returned. |
| Durable extraction catalog | Wired | App-private `local_catalog_v1` SharedPreferences; stale unit replacement. |
| CSV mapping | Wired | Every successful index write atomically refreshes `<filesDir>/catalog/catalog_export.csv` with index ID, URI, and extracted context. |
| Chat-memory indexing | Wired | Stored session messages and assistant responses use `chat_memory` records. |
| OCR/PDF ingestion | Wired for authorized SAF items | Native ML Kit/scanner bridge with recursive tree traversal. |
| Burst/background indexing | Wired core | User-selected trees retain SAF grants; cold start and periodic WorkManager passes use the same pipeline. UI progress/pause/cancel remains. |
| Parakeet transcription | Contract only | Recorder/runtime adapter is not installed; UI reports unavailable. |
| Natural-language file search | Wired for indexed content | Agent routes file-search prompts to retrieval; metadata/path predicates need a SAF catalog query adapter. |
| Reminder creation | Wired | Opens a Calendar insert confirmation through Android. |
| Note creation | Wired | Opens Android document-save confirmation with Markdown content. |
| SAF move / rename | Wired | Requires authorised document URIs; returns explicit failure otherwise. |
| Soft-delete / restore / organize | Contract only | Needs trash manifest, undo, and SAF tree adapter; no permanent delete is enabled. |
| OCR action / generic upsert | Wired | Agent dispatches OCR through the scanner bridge and upsert through the local index contract; empty extraction is explicit. |
| WhatsApp | Contract only | Requires a provider/deep-link adapter and explicit approval. |

The catalog is intentionally broader than the native bridge so the planner can
describe the contract, but the executor rejects contract-only rows with an
explicit `UNSUPPORTED_TOOL` result. No contract-only capability returns
simulated success.
