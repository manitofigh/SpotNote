#!/usr/bin/env bash
# Backward-compatible wrapper for older release docs/commands.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/upload_all.sh" "$@"
