# Vidya pickup plan — conversation product and grounded presentation

## Start here

Use the prompt in [`../master/WORKER_PROMPT.md`](../master/WORKER_PROMPT.md).
Read [`../master/ARCHITECTURE.md`](../master/ARCHITECTURE.md) and your section
of [`../master/ROLES.md`](../master/ROLES.md). Your work is Flutter UI and local
conversation persistence only; do not implement Android indexing, OCR, model
transport, or vector ranking.

## Owned paths

* `frontend/lib/screens/`
* `frontend/lib/widgets/`
* `frontend/lib/models/chat_*`
* `frontend/lib/services/chat_storage_service.dart`
* Flutter UI/unit tests under `frontend/test/`

Do not edit `agent_service.dart`, Android Kotlin, retrieval services, or native
workers. Consume evidence through a small UI-facing model/interface; use fakes
until Tushar's real coordinator returns it.

## Packages — execute in order

- [ ] **V1: remove upload-era behavior.** Delete attachment state and simulated
  file paths from chat input, messages, and tests. Keep plain text input. A mic
  is only a recording entry point; it must not pretend a transcript exists.
- [ ] **V2: evidence cards.** Create a reusable card for `Evidence`: title,
  kind, snippet, page/segment, citation ID, availability, and an Open callback.
  Include document, image, PDF page, audio, and chat-memory variants.
- [ ] **V3: grounded response states.** Render retrieval pending, no results,
  revoked/unavailable source, index failure, model failure, and uncited answer
  states. None may display fabricated content.
- [ ] **V4: session persistence surface.** Preserve all messages and stable IDs
  in the local Markdown session format; show session indexing state supplied by
  a fake/contract. Do not build chat-memory indexing here.
- [ ] **V5: citation linking.** Given agent output plus `Evidence[]`, connect
  citation IDs to cards and source-open callbacks. Warn if a device-content
  answer has no matching evidence citation.

## Contract to consume

```dart
class RetrievedEvidence { /* identifier, displayName, contentType, snippet,
  sourceUri/openUri, page/segment, availability */ }
```

Treat missing/unavailable values as a state to render, never as a reason to
invent a source.

## Required tests and handoff

Add widget tests for a cited PDF/page, audio transcript segment, chat-memory
card, no-result, revoked URI, model error, and absence of upload controls.
Run `flutter test` and `flutter analyze` from `frontend/`. Handoff a UI fixture
with representative `Evidence[]` values and a short PR note naming any analyzer
advisories that predate the change.

## Done when

A mocked file answer visibly cites and opens its matching source card; failures
remain explicit; the UI contains no upload picker or synthetic file path.
