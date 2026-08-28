# Team rules

1. Keep exactly two visible top-level project directories: `frontend/` and `master/`.
2. Keep Flask backend code in the repository root. Do not create a backend directory.
3. Keep all Flutter code and Flutter configuration inside `frontend/`.
4. `master/` contains only durable product decisions and team rules.
5. Use `./sip chai` to run the complete development environment.
6. Frontend-only changes must use Flutter hot reload; do not reinstall backend dependencies or restart Flask unless backend files or requirements change.
7. Do not commit secrets, credentials, personal data, caches, virtual environments, or generated build output.
8. Keep changes small and verify the affected layer before asking for review.
