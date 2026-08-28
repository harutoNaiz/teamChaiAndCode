#!/usr/bin/env sh
set -eu
if [ "${1:-}" != "chai" ]; then
  echo "Usage: ./make chai" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required. Install it, then run ./make chai again." >&2
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is required. Install it, then run ./make chai again." >&2
  exit 1
fi
if [ ! -x .venv/bin/python ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv .venv
fi
echo "Installing backend dependencies..."
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
if [ ! -f frontend/.metadata ]; then
  echo "Initializing Flutter platform files..."
  (cd frontend && flutter create .)
fi
echo "Fetching Flutter dependencies..."
(cd frontend && flutter pub get)
echo "Ready. Start the app with: ./sip chai"
