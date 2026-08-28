#!/usr/bin/env sh
set -eu

if [ "${1:-}" != "chai" ]; then
  echo "Usage: ./sip chai" >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is required. See RECIPE.md." >&2
  exit 1
fi

if [ ! -x .venv/bin/python ]; then
  echo "Create the backend environment first: python3 -m venv .venv" >&2
  exit 1
fi

if [ ! -d frontend/.dart_tool ]; then
  echo "Preparing Flutter dependencies..."
  (cd frontend && flutter pub get)
fi

cleanup() {
  kill "$backend_pid" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

.venv/bin/python -m flask --app app run --debug --exclude-patterns 'frontend/*' &
backend_pid=$!

cd frontend
flutter run
