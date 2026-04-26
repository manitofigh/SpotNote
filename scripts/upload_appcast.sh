#!/usr/bin/env bash
# Upload the Sparkle appcast XML to R2 at the well-known location
# updates.spotnote.org/appcast.xml.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
require_env() { [[ -n "${!1:-}" ]] || { echo "ERROR: missing env var: $1" >&2; exit 1; }; }

require_cmd aws
require_env AWS_ACCESS_KEY_ID
require_env AWS_SECRET_ACCESS_KEY
require_env AWS_ENDPOINT_URL
require_env AWS_DEFAULT_REGION

BUCKET="${SPOTNOTE_R2_BUCKET:-spotnote}"
UPDATES_BASE_URL="${SPOTNOTE_UPDATES_BASE_URL:-https://updates.spotnote.org}"

APPCAST_PATH="${1:-$ROOT_DIR/dist/updates/appcast.xml}"
[[ -f "$APPCAST_PATH" ]] || { echo "ERROR: $APPCAST_PATH not found. Run ./scripts/release.sh first." >&2; exit 1; }

DESTINATION="s3://$BUCKET/appcast.xml"
echo "Uploading appcast:"
echo "  source: $APPCAST_PATH"
echo "  target: $DESTINATION"

aws s3 cp \
  "$APPCAST_PATH" \
  "$DESTINATION" \
  --endpoint-url "$AWS_ENDPOINT_URL" \
  --content-type "application/xml" \
  --cache-control "no-cache, no-store, must-revalidate"

echo "Done. Public URL: $UPDATES_BASE_URL/appcast.xml"
