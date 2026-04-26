#!/usr/bin/env bash
# Zip dist/SpotNote.dmg into dist/SpotNote-v<version>-dmg.zip so it can be
# attached to a GitHub release. Version is read from the exported app's
# Info.plist by default; pass an explicit version as the first arg to
# override (e.g. `./scripts/zip_dmg.sh 0.1.0`).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="SpotNote"
DMG_PATH="${SPOTNOTE_DMG_PATH:-$ROOT_DIR/dist/$APP_NAME.dmg}"
APP_PATH="${SPOTNOTE_APP_PATH:-$ROOT_DIR/dist/export/$APP_NAME.app}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "ERROR: $DMG_PATH not found. Run ./scripts/release.sh first." >&2
  exit 1
fi

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  if [[ -d "$APP_PATH" ]]; then
    VERSION="$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)"
  else
    echo "ERROR: version not provided and $APP_PATH is missing." >&2
    echo "Pass the version explicitly: ./scripts/zip_dmg.sh <version>" >&2
    exit 1
  fi
fi

OUT_PATH="$ROOT_DIR/dist/$APP_NAME-v$VERSION-dmg.zip"
rm -f "$OUT_PATH"
ditto -c -k --keepParent "$DMG_PATH" "$OUT_PATH"

echo "Wrote $OUT_PATH"
