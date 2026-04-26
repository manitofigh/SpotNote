#!/usr/bin/env bash
# Upload the Sparkle update enclosure (a versioned .zip of SpotNote.app)
# to R2, then offer to delete older enclosures from the bucket. The
# canonical layout is:
#
#   updates.spotnote.org/SpotNote-<version>.zip   (this script)
#   updates.spotnote.org/appcast.xml              (upload_appcast.sh)
#
# Pass --dont-ask to skip the deletion prompt.
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
require_cmd python3
require_env AWS_ACCESS_KEY_ID
require_env AWS_SECRET_ACCESS_KEY
require_env AWS_ENDPOINT_URL
require_env AWS_DEFAULT_REGION

BUCKET="${SPOTNOTE_R2_BUCKET:-spotnote}"
UPDATES_BASE_URL="${SPOTNOTE_UPDATES_BASE_URL:-https://updates.spotnote.org}"

DONT_ASK=false
ZIP_PATH=""
for arg in "$@"; do
  if [[ "$arg" == "--dont-ask" ]]; then
    DONT_ASK=true
  else
    ZIP_PATH="$arg"
  fi
done

if [[ -z "$ZIP_PATH" ]]; then
  ZIP_PATH="$(ls -t "$ROOT_DIR"/dist/updates/SpotNote-*.zip 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$ZIP_PATH" || ! -f "$ZIP_PATH" ]]; then
  echo "ERROR: enclosure zip not found. Run ./scripts/release.sh first." >&2
  exit 1
fi

ZIP_FILENAME="$(basename "$ZIP_PATH")"
DESTINATION="s3://$BUCKET/$ZIP_FILENAME"

parse_version() { echo "$1" | sed 's/SpotNote-\(.*\)\.zip/\1/'; }
version_gt() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ] && [ "$1" != "$2" ]
}

UPLOAD_VERSION="$(parse_version "$ZIP_FILENAME")"

EXISTING_ZIPS=()
while IFS= read -r line; do
  KEY="$(echo "$line" | awk '{$1=$2=$3=""; sub(/^[[:space:]]+/, ""); print}')"
  [[ "$KEY" == "$ZIP_FILENAME" ]] && continue
  [[ "$KEY" == SpotNote-*.zip ]] && EXISTING_ZIPS+=("$KEY")
done < <(aws s3 ls "s3://$BUCKET/" --endpoint-url "$AWS_ENDPOINT_URL" || true)

echo "Uploading enclosure:"
echo "  source: $ZIP_PATH"
echo "  target: $DESTINATION"

aws s3 cp \
  "$ZIP_PATH" \
  "$DESTINATION" \
  --endpoint-url "$AWS_ENDPOINT_URL" \
  --content-type "application/zip" \
  --cache-control "no-cache, no-store, must-revalidate"

echo "Verifying upload..."
aws s3 ls "s3://$BUCKET/$ZIP_FILENAME" --endpoint-url "$AWS_ENDPOINT_URL" >/dev/null
echo "Upload verified."

ENCODED_NAME="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$ZIP_FILENAME")"
echo "Public URL: $UPDATES_BASE_URL/$ENCODED_NAME"

ZIPS_TO_DELETE=()
if [[ ${#EXISTING_ZIPS[@]} -gt 0 ]]; then
  echo ""
  echo "Existing enclosures in bucket:"
  for z in "${EXISTING_ZIPS[@]}"; do
    V="$(parse_version "$z")"
    if version_gt "$V" "$UPLOAD_VERSION"; then
      echo "  ERROR: bucket has newer version $z ($V > $UPLOAD_VERSION). Aborting before any deletion." >&2
      exit 1
    fi
    echo "  Older: $z ($V)"
    ZIPS_TO_DELETE+=("$z")
  done
fi

if [[ ${#ZIPS_TO_DELETE[@]} -gt 0 ]]; then
  DO_DELETE=false
  if [[ "$DONT_ASK" == true ]]; then
    DO_DELETE=true
  else
    echo ""
    read -r -p "Delete older enclosure(s)? [y/N] " REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]] && DO_DELETE=true
  fi
  if [[ "$DO_DELETE" == true ]]; then
    for OLD in "${ZIPS_TO_DELETE[@]}"; do
      echo "  Deleting: $OLD"
      aws s3 rm "s3://$BUCKET/$OLD" --endpoint-url "$AWS_ENDPOINT_URL"
    done
    echo "Old enclosure(s) deleted."
  else
    echo "Skipped deletion."
  fi
fi
