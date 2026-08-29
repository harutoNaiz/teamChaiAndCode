# Team ownership

## Vidya — app shell and agent experience

**Owns** the Flutter skeleton and the user-facing agent flow.

- Build chat and search as switchable surfaces without losing the active conversation context.
- Define conversation/message state, model-selection state, loading/error states, and result cards.
- Define a model-provider interface so local and remote models can be selected without rewriting the UI.
- Create visible insertion points for agent tools, tool previews, permission prompts, and confirmed results.
- Render retrieval results with title, source type, snippet, and provenance.

**Delivers** a navigable Flutter app in which a user can select a model, continue a conversation, move to search, and see mocked tool/search results.

**Does not own** OCR engines, filesystem crawling, or Android action implementations. Those are consumed through stable interfaces.

## Suprith — local intelligence and Snapdragon research

**Owns** the local OCR and local-model capability investigation.

- Evaluate offline OCR for camera images, gallery photos, and scanned PDFs; report accuracy, latency, package size, and supported scripts.
- Prototype local model inference for chat, summarisation, structured JSON extraction, and tool-call selection.
- Investigate the available Snapdragon acceleration path on target Android hardware. Measure actual gains and retain a CPU/portable fallback; do not make a vendor-specific assumption the app cannot recover from.
- Define model capability metadata: model ID, local/remote, context limit, supported tasks, availability, and failure reason.
- Provide an Android-facing interface that the app shell can call without knowing the model/OCR implementation.
- Build the phone scanner and OCR-to-index pipeline according to [`../handovers/LOCAL_INDEX_OCR_HANDOVER.md`](../handovers/LOCAL_INDEX_OCR_HANDOVER.md). The scanner owns permission-aware source discovery and must send the specified JSON records to the existing local index.

**Delivers** a reproducible benchmark note, a selected local OCR approach, and a model runtime adapter with graceful fallback behavior.

## Tushar — device index and retrieval tools

**Owns** indexed access to user content and the agent’s retrieval interface.

- Design Android-safe filesystem discovery using MediaStore and the Storage Access Framework; avoid broad storage access unless truly required.
- Build a local index for file metadata, extracted document text, OCR text, timestamps, types, and stable source URIs.
- Implement search with ranked results, snippets, and provenance so the model can ground answers in a specific file/page/image.
- Define the document and photo ingestion pipeline, including change detection, re-indexing, and failure states.
- Expose retrieval as a typed agent tool. Later, extend the same tool system for notes, alarms, and file operations.

**Delivers** a searchable local index that can find a poorly named Aadhaar PDF/photo by its extracted content and return a source-backed result.

## Shared integration rules

- Agree tool, search-result, and model-provider contracts in `master/` before crossing ownership boundaries.
- Keep device-content access on Android and behind explicit permission/confirmation policies.
- Test the happy path together: retrieve a document, generate a JSON draft, preview it, confirm it, and create a note.
- Record benchmark results, permission decisions, and changes to scope in `master/`.
