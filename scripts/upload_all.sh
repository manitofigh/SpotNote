#!/usr/bin/env bash
# Convenience wrapper: upload appcast + enclosure zip + release notes + dmg to R2.
# Pass --dont-ask to upload_zip.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/upload_appcast.sh"
"$ROOT_DIR/scripts/upload_zip.sh" "$@"
"$ROOT_DIR/scripts/upload_release_notes.sh"
"$ROOT_DIR/scripts/upload_dmg.sh"

echo "============"
echo "UPLOADED ALL"
