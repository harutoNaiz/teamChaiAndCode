# Team ownership and delivery plan

## Shared baseline

`main` contains the merged work from Tushar, Srividya, and Suprith as of
2026-08-29. It is a local clean baseline until the owner approves a push.
Read [`ARCHITECTURE.md`](ARCHITECTURE.md) before implementation: it distinguishes
working code from scaffolds and defines the only stable contracts.

Each owner works on the named paths and public contract only. Do not edit
another owner's implementation path except for a small, agreed contract change.
Each task must include tests and an evidence note in its pull request.

## Vidya — conversation product and grounded presentation

**Owns:** `frontend/lib/screens/`, `frontend/lib/widgets/`,
`frontend/lib/models/chat_*`, `frontend/lib/services/chat_storage_service.dart`,
and UI tests. Vidya does not implement Android indexing, OCR, vectors, or model
provider transport.

### Work packages

1. **Remove upload-era UI completely.** Remove attachment state, picker sheets,
   attachment-only prompts, and fake paths from the chat input/message surfaces.
   Retain text entry and a clearly labelled recording entry point only when the
   native recording contract exists.
2. **Grounded evidence presentation.** Add reusable source cards for document,
   image, PDF page, audio segment, and chat-memory evidence. Show title, kind,
   snippet, page/time segment, citation ID, availability, and open action.
3. **Conversation persistence presentation.** Preserve full local sessions and
   message IDs in Markdown storage; expose session-level indexing status without
   building the index itself.
4. **Whole-session UI states.** Show provider/privacy state, retrieval in
   progress, no-result, permission-revoked, indexing-progress, and model-error
   states. No placeholder result may look completed.
5. **Grounded answer rendering.** Parse source citations from agent responses,
   connect them to supplied evidence cards, and show a visible uncited-warning
   for an answer that claims a device fact without evidence.
6. **File-action preview and audit UI.** Render a read-only candidate manifest,
   matching reasons, risk/undo state, confirmation, and execution receipt. Do
   not resolve candidates or mutate sources in Flutter.

### Acceptance

With mocked `Evidence` values, a file question shows citation-linked cards and
open availability. With no result, a model failure, or a revoked source, the UI
shows the correct state and no fake file/OCR/action detail. The input contains
no upload picker or synthetic attachment path.

## Suprith — authorised ingestion, OCR/audio, and device acceleration

**Owns:** new Android-native ingestion/extraction code under
`frontend/android/app/src/main/kotlin/.../ingestion/`,
`.../extraction/`, `.../workers/`, Android permissions/manifest entries,
recording/transcription integration, and Android device tests. Suprith writes
through `CatalogWriter` only; he does not alter Flutter chat UI or ranking.

### Work packages

1. **Authorised source discovery.** Implement SAF tree/document selection and
   MediaStore discovery with persisted URI permission, source metadata, and
   explicit permission/revocation states.
2. **Shared source pipeline.** Implement a `SourceRecord` change stream used by
   both scheduled incremental work and user-started burst indexing. Deduplicate
   by URI plus content version; support pause, resume, cancel, and progress.
3. **Text/PDF/OCR extraction.** Extract native document/PDF text; render scanned
   PDF pages when needed; run measured local image/PDF OCR; emit typed
   `ExtractionRecord` success/failure with page and confidence.
4. **Audio capture and transcription.** Record local meetings, preserve a local
   recording URI, run a real measured Parakeet-compatible local transcription
   runtime, and emit time-coded `audio_transcript` segments. Remove current
   simulated Parakeet output as part of this package.
5. **Target-device runtime study.** Benchmark OCR, transcription, and embedding
   candidate runtimes on the Snapdragon Gen 5 target: accuracy/recall, latency,
   package size, RAM, battery, NPU/GPU/CPU path, and CPU fallback. Publish the
   chosen runtime only after evidence.
6. **Metadata/capability adapter.** Provide authorised MediaStore and SAF source
   metadata plus provider capabilities to Tushar's file-query/executor contract.
   Do not implement planning or destructive policy; report unavailable creation
   time/capability truthfully.

### Acceptance

On an Android device, an authorised poorly named photo and page 2 of a PDF are
extracted, persisted via `CatalogWriter`, indexed, retrieved, and opened with
the original URI. A recorded meeting yields a local time-coded transcript that
is searchable. New and burst sources use the same pipeline; no content is
uploaded.

## Tushar — catalog/index, retrieval, and agent evidence coordinator

**Owns:** `frontend/lib/services/retrieval_tool.dart`,
`frontend/lib/models/retrieved_evidence.dart`,
`frontend/lib/services/agent_service.dart`, `local_index.py`, `app.py`, and new
Android-native code under `.../catalog/` and `.../retrieval/`. Tushar does not
edit input/UI widgets, picker/OCR workers, or recording UI.

### Work packages

1. **Production catalog.** Replace preference-only record linkage with a private
   local catalog for `SourceRecord`, `ExtractionRecord`, and vector metadata.
   Provide `CatalogWriter`; preserve source/page stale replacement, availability,
   and migration from existing AppSearch records. Generate CSV only as an export.
2. **Hybrid retrieval.** Complete lexical/vector ranking, content/MIME/source
   filters, snippets, source availability filtering, and bounded evidence
   selection. Validate the current semantic implementation on device and use
   Suprith's measured runtime decision rather than an unmeasured model.
3. **Full-session context.** Add `ConversationContext` with a documented token
   budget: preserve a complete local transcript, send recent turns verbatim,
   compact/select older turns with stable message IDs, and send selected local
   evidence only for content queries.
4. **Chat-memory indexing.** After a session is persisted, create/update
   provenance-bearing `chat_memory` extraction records for important messages.
   Support cross-session retrieval without leaking unrelated private content.
5. **Evidence-to-model coordinator.** Detect retrieval intent, retrieve before
   completion, select snippets/provenance only, require citation IDs in the
   response, and return typed no-result/index/model failures. Do not implement
   Android mutations here.
6. **Composable file-operation planner.** Define and validate the typed
   `FileOperationPlan` predicate AST; resolve metadata, path/name, and content
   predicates to a deduplicated bounded candidate manifest. Compose conditions
   with AND/OR/NOT; never permit raw filesystem commands from a model.
7. **Capability-aware file executor.** Implement preview/confirmation manifest
   validation, URI/version recheck, provider-supported move/rename/soft-delete,
   local audit receipts, and restore/undo when the provider supports it. Reject
   permanent delete and unsupported providers in this release.
8. **Test suite and compatibility.** Add unit, Flutter integration, and Android
   device tests for poorly named files, PDF pages, OCR, audio, chat memory,
   stale replacement, filters, revoked URI, no-file-to-model behavior, metadata
   filters, path matching, compound predicates, preview changes, and undo.

### Acceptance

An Aadhaar-style query finds a poorly named indexed source by its extraction,
the model request contains only selected evidence text/provenance, and the
rendered answer identifies an openable cited source. A fact in an older or
different chat session is returned as `chat_memory` evidence with source
metadata, not silently injected into the model context.

## Integration order

1. Tushar lands stable `CatalogWriter`, `Evidence`, and context contracts with
   fake implementations for tests.
2. Vidya consumes the fake contracts for UI and removes all upload simulation.
3. Suprith writes real discovery/extraction output through `CatalogWriter` and
   proves it on a device.
4. Tushar enables hybrid retrieval and model evidence selection against those
   real records.
5. Vidya enables the source-card/open UI against the final evidence contract.
6. Only after grounded search and answer acceptance: propose a structured note
   action, show its preview, confirm, then create it natively.
7. File operations begin with read-only planning/listing, then provider-backed
   move/rename/soft-delete preview; permanent delete is out of scope.

## Cross-team rules

* Do not claim OCR, Parakeet transcription, local inference, Snapdragon
  acceleration, watcher indexing, or actions are complete without device proof.
* Do not introduce a second OCR store or send source files to a cloud model.
* Do not call Android background work a cron job; use Android-supported
  scheduling and document its constraints.
* Do not use raw filesystem paths as authority. Android operations must use
  authorised MediaStore/SAF URIs and advertised provider capabilities.
* Keep original user data and generated indexes out of Git. Synthetic test
  fixtures require team approval before being committed.
