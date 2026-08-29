# Team ownership and delivery plan

## Shared starting point

The app currently has a working Android chat shell with conversation context, model selection, and real OpenRouter responses. A native local index also exists, but it only searches records explicitly inserted into it. The next release is to connect phone content to grounded chat responses.

Work in this order. A contributor picks the next uncompleted item in their section, keeps the stated boundary, and adds evidence before merge.

## Vidya — app shell and grounded agent experience

**Current ownership:** Flutter chat, conversations, model choice, loading/error states, tool previews, and result cards.

### Next tasks

1. Add a stable chat-facing retrieval boundary: chat can request a search and receive a list of source-backed results without knowing how Android indexing works.
2. Render retrieved documents/photos as cards with title, source type, snippet, and location. A model answer must visibly cite the result it used.
3. Replace silent simulated fallbacks with an explicit offline/error state. The UI must never make a fake file/OCR/action result look real.
4. Keep model selection provider-agnostic: cloud, local, and unavailable models must have clear status.

**Acceptance:** With supplied mock retrieval results, a question shows source cards and an answer that cites one; a failed model request shows an error rather than a fabricated answer.

## Suprith — local OCR, scanner, and Snapdragon capability

**Current ownership:** the phone-content ingestion side: discovery, OCR, and local-model investigation. The existing remote `ocr-branch` contains lint/setup changes only; OCR scanning is still unimplemented.

### Next tasks

1. Implement Android-safe source selection/discovery using Storage Access Framework or MediaStore, with a clear permission state.
2. Connect the selected local OCR engine to photos and scanned-PDF pages. Measure accuracy, latency, package size, and supported scripts on the target phone.
3. Send each successful OCR result to the existing index using the JSON contract in [`../handovers/LOCAL_INDEX_OCR_HANDOVER.md`](../handovers/LOCAL_INDEX_OCR_HANDOVER.md). Preserve source URI, display name, page, MIME type, transcription, and confidence.
4. Report a portable local-model/Snapdragon runtime choice with a CPU fallback. Do not wire an unmeasured model into chat.

**Acceptance:** Choose a phone folder, scan at least one photo and one PDF page, index their extracted text, then search and open the original source from the result.

## Tushar — retrieval quality and agent retrieval tool

**Current ownership:** indexed access, retrieval ranking, provenance contracts, and the bridge from retrieved evidence to the agent.

### Next tasks

1. Replace the current keyword-only retrieval approach with a local semantic/vector-capable index while preserving the existing source/provenance record contract.
2. Add ranking, snippets, filters, re-indexing, and failure states for document text and OCR records.
3. Expose retrieval as a typed agent tool: query in, ranked evidence out. The model receives only the selected snippets and provenance.
4. Create integration tests covering poorly named PDF/photo discovery, OCR text search, stale-record replacement, and provenance returned to chat.

**Acceptance:** A query for Aadhaar-style details finds a poorly named indexed PDF or photo by its extracted text and returns a source-backed result suitable for the chat layer.

## Shared integration milestones

1. **Grounded search:** scanner/OCR inserts records; retrieval returns ranked source-backed evidence; chat renders it.
2. **Grounded answer:** agent searches before answering a file question, gives the model only retrieved evidence, and cites the chosen source.
3. **Safe action:** model produces a structured note draft from retrieved evidence; user previews and confirms it; Android creates the note.

Do not begin real file move/delete, messages, or alarms until milestone 2 is demonstrated end-to-end.
