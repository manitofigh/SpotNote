#!/usr/bin/env bash
# Convenience wrapper: upload release assets to R2, then publish the appcast last.
# Pass --dont-ask to upload_zip.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/upload_zip.sh" "$@"
"$ROOT_DIR/scripts/upload_release_notes.sh"
"$ROOT_DIR/scripts/upload_dmg.sh"
"$ROOT_DIR/scripts/upload_appcast.sh"

echo "============"
echo "UPLOADED ALL"
