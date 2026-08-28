# The Recipe: sip chai

This is the only project layout:

```text
.              Flask backend: app.py and requirements.txt
frontend/      Flutter app: pubspec.yaml and lib/
master/        Product brief and team rules
```

Do not add another top-level project directory. Backend code stays at the repository root; Flutter code stays in `frontend/`.

## Run everything

From the repository root:

```sh
./sip chai
```

The command starts Flask in debug mode and runs Flutter on the selected device. Flask reloads only when backend files change. A frontend-only change uses Flutter hot reload and does not rebuild or reinstall backend dependencies.

## First-time setup

Install Python 3, Flutter, and a Flutter-supported emulator or device. Then run:

```sh
./make chai
```

`make chai` creates the local Python environment, installs Flask dependencies, initializes the Flutter platform files when needed, and fetches Flutter packages. It never starts either application. After that, use `./sip chai` for normal development.

## Agent checklist

1. Read this recipe and `master/RULES.md`.
2. Put the change in its correct location.
3. Verify only the affected layer whenever possible.
4. Do not commit secrets or generated files.
