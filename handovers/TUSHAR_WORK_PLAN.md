# Tushar pickup plan — catalog, retrieval, and evidence coordinator

## Start here

Use the prompt in [`../master/WORKER_PROMPT.md`](../master/WORKER_PROMPT.md).
Read [`../master/ARCHITECTURE.md`](../master/ARCHITECTURE.md) and your role
section. The current AppSearch bridge is an early provenance/semantic-index
implementation; validate it before treating it as production-ready. For T7/T8
also read [`FILE_OPERATION_CONTRACT.md`](FILE_OPERATION_CONTRACT.md).

## Owned paths

* `frontend/lib/services/agent_service.dart`
* `frontend/lib/services/retrieval_tool.dart`
* `frontend/lib/models/retrieved_evidence.dart`
* `frontend/lib/services/conversation_context_service.dart` (new)
* `frontend/lib/services/chat_memory_index_service.dart` (new)
* Kotlin only below `.../catalog/` and `.../retrieval/`
* `local_index.py`, `app.py`, and retrieval/agent tests

Do not edit chat UI/widgets, source discovery, OCR, recording, or worker code.
Offer stable `CatalogWriter`, `RetrievalRequest`, and `Evidence` contracts so
Vidya and Suprith can work independently.

## Packages — execute in order

- [ ] **T1: contract-first catalog.** Define `SourceRecord`, `ExtractionRecord`,
  availability, content version, and `CatalogWriter`. Migrate the existing
  source/page stale-replacement semantics; CSV is export only, not storage.
- [ ] **T2: hybrid retrieval.** Complete bounded lexical/vector ranking, filters,
  snippets, availability exclusion, and evidence selection. Validate embedding
  schema/runtime on device; defer runtime selection to Suprith's benchmark.
- [ ] **T3: full-session context builder.** Build context from the complete local
  active session, with a documented token budget, recent verbatim turns, and
  stable-ID compression/relevance selection for older turns.
- [ ] **T4: chat-memory index.** After local session persistence, upsert important
  messages as `chat_memory` extraction records with session/message/role/time
  provenance. Add cross-session relevance and isolation tests.
- [ ] **T5: evidence-first coordinator.** Retrieve before content/file answers;
  provide the model selected snippets/provenance only; require matching citations;
  produce typed no-result, index failure, and model failure states.
- [ ] **T6: regression proof.** Cover poorly named PDF/photo, OCR, PDF page,
  audio transcript, chat memory, stale replacement, filters, revocation, max
  result bound, and proof that original files do not enter cloud payloads.
- [ ] **T7: composable file-operation planning.** Add a typed predicate AST and
  validated `FileOperationPlan` for metadata, filename/path, content, and
  compound AND/OR/NOT conditions. Resolve a bounded deduplicated candidate
  manifest; models propose plans but never raw filesystem commands.
- [ ] **T8: safe provider executor.** Use Suprith's metadata/capability adapter
  to recheck each URI/version, preview exact candidates, confirm, perform only
  provider-supported move/rename/soft-delete, and emit local audit/undo receipts.
  Permanent deletion is explicitly out of scope.

## Contracts to hand off first

```text
CatalogWriter.upsert(SourceRecord, ExtractionRecord) -> current record
AgentRetrieval.search(RetrievalRequest) -> List<Evidence>
ConversationContext.build(ChatSession, budget) -> model messages + retained IDs
FileQuery.resolve(FileOperationPlan) -> CandidateFile[]
FileAction.preview(operation, candidates) -> PreviewManifest
FileAction.execute(approvedManifest) -> ExecutionReceipt
```

Make fake in-memory implementations available in your test fixtures. Do not
change these contracts without synchronising the role document and handoff note.

## Required tests and handoff

Run `.venv/bin/python -m unittest -v`, `flutter test`, and `flutter analyze`.
Run Android/device tests when a Java runtime/device is available. Handoff fake
catalog/evidence fixtures, test results, migration notes, and any device-only
limit. Do not claim model inference, OCR, or device indexing from a mock.

## Done when

An indexed, poorly named source is semantically retrieved as provenance-bearing
evidence; a cloud payload contains only bounded chat context plus selected text
evidence; a cited answer can be connected to an openable source; chat memory and
audio segments follow the same contract.

For file operations, metadata, path/name, and content predicates can be
combined; every destructive request is a capability-aware previewed soft-delete
or a rejected unsupported operation, never an irreversible raw-path command.
