#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load .env if present.
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

PROFILE_NAME="${1:-${SPOTNOTE_NOTARY_PROFILE:-SpotNote-Profile}}"
APPLE_ID="${SPOTNOTE_NOTARY_APPLE_ID:-}"
TEAM_ID="${SPOTNOTE_TEAM_ID:-}"
APP_SPECIFIC_PASSWORD="${SPOTNOTE_NOTARY_PASSWORD:-}"

if [[ -z "$APPLE_ID" ]]; then
  echo "ERROR: Set SPOTNOTE_NOTARY_APPLE_ID in .env or environment."
  exit 1
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "ERROR: Set SPOTNOTE_TEAM_ID in .env or environment."
  exit 1
fi

if [[ -z "$APP_SPECIFIC_PASSWORD" ]]; then
  echo "ERROR: Set SPOTNOTE_NOTARY_PASSWORD to an Apple app-specific password."
  echo "This is only needed once -- the password is stored in Keychain, not in any file."
  exit 1
fi

echo "Storing notarization credentials in Keychain profile '$PROFILE_NAME'..."
xcrun notarytool store-credentials "$PROFILE_NAME" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD"

echo "Validating Keychain profile..."
xcrun notarytool history --keychain-profile "$PROFILE_NAME" >/dev/null
echo "OK: Notary profile '$PROFILE_NAME' is ready."
