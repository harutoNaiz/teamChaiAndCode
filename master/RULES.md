# Team rules

## Current baseline

1. The Android Flutter chat app, conversation context, model selection, and direct OpenRouter chat are working.
2. The Android-native local index can store and search explicitly supplied text and OCR records with source provenance. It does not yet scan the phone or feed results into chat.
3. Flask is a development companion for contracts and local-index tests. It is not the production path for Android file access.
4. OCR extraction, folder scanning, semantic/vector retrieval, and real Android actions are not complete. Do not present them as working features.

## Repository and security

5. Keep versioned product code in `frontend/`, durable decisions in `master/`, and scoped hand-offs in `handovers/`. Keep Flask code in the repository root.
6. Keep Flutter code and Flutter configuration inside `frontend/`.
7. The shared OpenRouter development key is intentionally committed for this private team repository. Do not add any other personal credentials, tokens, user documents, chats, device data, caches, virtual environments, or generated build output.
8. Test documents remain local and untracked unless the team explicitly approves a synthetic committed test corpus.

## Delivery workflow

9. Read `master/ROLES.md` before taking work. Pick the next incomplete delivery item and preserve the listed contract.
10. Implement behind the existing boundaries: chat shell, model provider, retrieval/index, OCR ingestion, and Android actions must remain separately replaceable.
11. A cloud model must not claim it searched a file, read an image, or completed an Android action unless the corresponding tool returned evidence.
12. Every search result must retain its source and location. Every mutating action must show a preview and require confirmation.
13. Use `./make chai` once for setup and `./sip chai` to run the development environment. Frontend-only changes use hot reload; backend changes restart Flask.
14. Before requesting merge, run the affected tests, state what was actually tested, and document any limitation in the relevant hand-off or role item.
