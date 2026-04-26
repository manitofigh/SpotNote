#!/usr/bin/env bash
# Build then launch SpotNote.app.
# Usage: ./scripts/run.sh [debug|release]   (default: debug)
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/build.sh" "$CONFIG"

APP="$ROOT/build/SpotNote.app"

# Kill any previous instance so hotkey registration doesn't collide.
pkill -x SpotNote 2>/dev/null || true

echo "==> opening $APP"
open "$APP"
echo "Press ⌘⇧Space to toggle SpotNote."
