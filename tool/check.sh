#!/usr/bin/env bash
# Pre-push check: analyze + tests for backend and frontend, plus a key scan.
# Run manually (./tool/check.sh) or via .githooks/pre-push.
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER="${FLUTTER:-$(command -v flutter || echo "$HOME/development/flutter/bin/flutter")}"
[ -x "$FLUTTER" ] || { echo "flutter not found – set FLUTTER=/path/to/flutter"; exit 1; }
DART="$(dirname "$FLUTTER")/dart"

echo "→ backend: analyze + test"
(cd backend && "$DART" pub get >/dev/null && "$DART" analyze && "$DART" test)

echo "→ frontend: analyze"
(cd frontend && "$FLUTTER" pub get >/dev/null && "$FLUTTER" analyze --no-fatal-infos)

echo "→ scanning tracked files for API keys"
if git grep -nE 'AIza[0-9A-Za-z_-]{30,}' >/dev/null; then
  echo "✗ Gemini API key found in tracked files"
  exit 1
fi

echo "✓ all checks passed"
