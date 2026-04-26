#!/usr/bin/env bash
# Upload dist/SpotNote.dmg to the spotnote R2 bucket as the canonical
# "latest" download (always overwrites the bucket key SpotNote.dmg).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }
}
require_env() {
  [[ -n "${!1:-}" ]] || { echo "ERROR: missing env var: $1" >&2; exit 1; }
}

require_cmd aws
require_env AWS_ACCESS_KEY_ID
require_env AWS_SECRET_ACCESS_KEY
require_env AWS_ENDPOINT_URL
require_env AWS_DEFAULT_REGION

BUCKET="${SPOTNOTE_R2_BUCKET:-spotnote}"
DOWNLOADS_BASE_URL="${SPOTNOTE_DOWNLOADS_BASE_URL:-https://downloads.spotnote.org}"

DMG_PATH="${1:-$ROOT_DIR/dist/SpotNote.dmg}"
[[ -f "$DMG_PATH" ]] || { echo "ERROR: $DMG_PATH not found. Run ./scripts/release.sh first." >&2; exit 1; }

DESTINATION="s3://$BUCKET/SpotNote.dmg"
echo "Uploading dmg:"
echo "  source: $DMG_PATH"
echo "  target: $DESTINATION"

aws s3 cp \
  "$DMG_PATH" \
  "$DESTINATION" \
  --endpoint-url "$AWS_ENDPOINT_URL" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "application/x-apple-diskimage"

echo "Done. Public URL: $DOWNLOADS_BASE_URL/SpotNote.dmg"
