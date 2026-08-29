# How to work in this repository

This guide is for every teammate and coding agent working on teamChaiAndCode.

## Start here

1. Read `RECIPE.md`, then this guide and `master/RULES.md`.
2. Run setup once from the repository root.
3. Use the project launchers; do not invent parallel setup commands.

```sh
./make chai
./sip chai
```

## Layout

- Repository root: Flask backend (`app.py`, `requirements.txt`, launchers).
- `frontend/`: Flutter application, its tests, and platform configuration.
- `master/`: product brief, durable decisions, and team rules.

## Rules

- Keep Flask code at the root and Flutter code in `frontend/`.
- Keep only `frontend/` and `master/` as visible top-level project directories.
- Never commit secrets, credentials, virtual environments, caches, or build output.
- Make focused changes and avoid unrelated formatting or generated-file churn.

## Validate changes

- Backend: run the relevant Python test or call the affected endpoint.
- Frontend: run `cd frontend && flutter analyze && flutter test`.
- Run `./sip chai` when a change affects both layers or their integration.

## Current integration contract

- Flask exposes `GET /health` and responds with `{"status":"ok"}`.
- The Flutter app and backend will communicate over the development API configured by the project launchers.
