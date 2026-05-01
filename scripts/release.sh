#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Load local release environment values (Team ID, signing identity, etc.).
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

APP_NAME="SpotNote"
SCHEME="SpotNote"
PROJECT_PATH="$ROOT_DIR/SpotNote.xcodeproj"
CONFIGURATION="Release"

TEAM_ID="${SPOTNOTE_TEAM_ID:-}"
SIGNING_IDENTITY="${SPOTNOTE_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${SPOTNOTE_NOTARY_PROFILE:-SpotNote-Profile}"
SIGNING_XCCONFIG="$ROOT_DIR/Config/ReleaseSigning.xcconfig"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/ExportOptions.plist"

RELEASE_STAMP="$(date +%Y%m%d-%H%M%S)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData.release-$RELEASE_STAMP"
ARCHIVE_PATH="$ROOT_DIR/build/$APP_NAME-$RELEASE_STAMP.xcarchive"
EXPORT_DIR="$ROOT_DIR/dist/export"
APP_ZIP_PATH="$ROOT_DIR/dist/$APP_NAME.zip"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Missing required command: $1"
    exit 1
  }
}

require_cmd xcodebuild
require_cmd xcrun
require_cmd codesign
require_cmd spctl
require_cmd security
require_cmd ditto

detect_signing_identity() {
  if [[ -z "$TEAM_ID" ]]; then return 1; fi
  local detected
  detected="$(
    security find-identity -v -p codesigning \
      | awk -F'"' "/Developer ID Application: .*\\($TEAM_ID\\)/ { print \$2; exit }"
  )"
  if [[ -z "$detected" ]]; then
    return 1
  fi
  SIGNING_IDENTITY="$detected"
}

ensure_notary_profile() {
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    return 0
  fi
  echo "ERROR: Notary profile '$NOTARY_PROFILE' is missing."
  echo "Run: ./scripts/setup_notary_profile.sh"
  exit 1
}

# --- Preflight ---

if [[ -z "$TEAM_ID" ]]; then
  echo "ERROR: SPOTNOTE_TEAM_ID is not set."
  echo "Create a .env file with your Team ID or export the variable."
  echo "See .env.example for the required keys."
  exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Xcode project not found at $PROJECT_PATH"
  echo "Generating with xcodegen..."
  require_cmd xcodegen
  xcodegen generate
fi

for required_file in "$SIGNING_XCCONFIG" "$EXPORT_OPTIONS_PLIST"; do
  if [[ ! -f "$required_file" ]]; then
    echo "ERROR: Missing required file: $required_file"
    exit 1
  fi
done

if [[ -z "$SIGNING_IDENTITY" ]]; then
  if ! detect_signing_identity; then
    echo "ERROR: No 'Developer ID Application' identity found for team $TEAM_ID."
    echo "Install a matching Developer ID certificate or set SPOTNOTE_SIGNING_IDENTITY in .env."
    exit 1
  fi
fi

if ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
  echo "ERROR: Selected signing identity not found in keychain:"
  echo "  $SIGNING_IDENTITY"
  exit 1
fi

ensure_notary_profile

echo "Using signing identity: $SIGNING_IDENTITY"
echo "Using notary profile:   $NOTARY_PROFILE"
echo ""

rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA" "$EXPORT_DIR"
mkdir -p "$DERIVED_DATA" "$EXPORT_DIR" "$ROOT_DIR/dist"

# --- Step 1: Archive ---

echo "[1/6] Archiving signed Release build..."
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  -xcconfig "$SIGNING_XCCONFIG" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -jobs "$(sysctl -n hw.logicalcpu)"

ARCHIVE_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ ! -d "$ARCHIVE_APP_PATH" ]]; then
  echo "ERROR: Archived app not found at $ARCHIVE_APP_PATH"
  exit 1
fi

# --- Step 2: Export ---

echo "[2/6] Exporting archive..."

# ExportOptions.plist needs the teamID at export time. Generate a
# temporary copy with the correct value injected so the repo file
# stays identity-free.
EXPORT_PLIST_TMP="$(mktemp)"
cp "$EXPORT_OPTIONS_PLIST" "$EXPORT_PLIST_TMP"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$EXPORT_PLIST_TMP" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID" "$EXPORT_PLIST_TMP"
trap 'rm -f "$EXPORT_PLIST_TMP"' EXIT

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST_TMP"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Exported app not found at $APP_PATH"
  exit 1
fi

SHORT_VERSION="$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)"
BUILD_VERSION="$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion)"

# --- Step 3: Verify signature ---

echo "[3/6] Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# --- Step 4: Notarize ---

echo "[4/6] Notarizing app bundle..."
rm -f "$APP_ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_PATH"
xcrun notarytool submit "$APP_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# --- Step 5: Gatekeeper check ---

echo "[5/6] Gatekeeper validation..."
spctl -a -vvv -t execute "$APP_PATH"

# --- Step 6: Package final zip ---

echo "[6/6] Packaging final distribution archive..."
FINAL_ZIP="$ROOT_DIR/dist/$APP_NAME-$SHORT_VERSION.zip"
rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
echo "[7/9] Building dmg at $DMG_PATH using create-dmg (plain default)..."
require_cmd create-dmg
# Detach any stale mounts that could collide with the volume name.
while IFS= read -r vol; do
  [[ -n "$vol" ]] || continue
  hdiutil detach "$vol" >/dev/null 2>&1 || hdiutil detach -force "$vol" >/dev/null 2>&1 || true
done < <(find /Volumes -maxdepth 1 -mindepth 1 -name "${APP_NAME}*" -print 2>/dev/null)

rm -f "$DMG_PATH" "$ROOT_DIR/dist/$APP_NAME "*.dmg
# sindre/create-dmg writes "<AppName> <Version>.dmg" next to the destination dir.
create-dmg --overwrite --no-code-sign --dmg-title="$APP_NAME" "$APP_PATH" "$ROOT_DIR/dist"
GENERATED_DMG="$(ls -t "$ROOT_DIR"/dist/"$APP_NAME"*.dmg 2>/dev/null | head -n 1 || true)"
if [[ -z "$GENERATED_DMG" || ! -f "$GENERATED_DMG" ]]; then
  echo "ERROR: create-dmg did not produce a dmg in $ROOT_DIR/dist"
  exit 1
fi
if [[ "$GENERATED_DMG" != "$DMG_PATH" ]]; then
  mv -f "$GENERATED_DMG" "$DMG_PATH"
fi
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$DMG_PATH"
echo "Notarizing dmg..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# GitHub-release-friendly zip of the dmg (so users can download a single
# attached file from the Releases page).
"$ROOT_DIR/scripts/zip_dmg.sh" "$SHORT_VERSION"

UPDATES_DIR="$ROOT_DIR/dist/updates"
mkdir -p "$UPDATES_DIR"
APPCAST_PATH="$UPDATES_DIR/appcast.xml"
ENCLOSURE_BASENAME="$APP_NAME-$SHORT_VERSION.zip"
ENCLOSURE_PATH="$UPDATES_DIR/$ENCLOSURE_BASENAME"
RELEASE_NOTES_BASENAME="release-notes-$SHORT_VERSION.html"
RELEASE_NOTES_PATH="$UPDATES_DIR/$RELEASE_NOTES_BASENAME"
rm -f "$ENCLOSURE_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ENCLOSURE_PATH"

UPDATES_BASE_URL="${SPOTNOTE_UPDATES_BASE_URL:-https://updates.spotnote.org}"
ENCODED_NAME="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$ENCLOSURE_BASENAME")"
RELEASE_NOTES_BASE_URL="${SPOTNOTE_RELEASE_NOTES_BASE_URL:-$UPDATES_BASE_URL}"
RELEASE_NOTES_LINK="$RELEASE_NOTES_BASE_URL/$RELEASE_NOTES_BASENAME"

cat > "$RELEASE_NOTES_PATH" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$APP_NAME $SHORT_VERSION Release Notes</title>
</head>
<body>
  <h1>$APP_NAME $SHORT_VERSION</h1>
  <p>Build $BUILD_VERSION</p>
  <p>Published $(date -u +"%Y-%m-%d %H:%M:%S UTC")</p>
</body>
</html>
HTML

echo "[8/9] Generating appcast at $APPCAST_PATH..."
RELEASE_DATE_RFC822="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" standalone="yes"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$APP_NAME</title>
    <description>Production appcast feed for $APP_NAME.</description>
    <language>en</language>
    <item>
      <title>Version $SHORT_VERSION</title>
      <sparkle:version>$BUILD_VERSION</sparkle:version>
      <sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$RELEASE_NOTES_LINK</sparkle:releaseNotesLink>
      <pubDate>$RELEASE_DATE_RFC822</pubDate>
      <enclosure
        url="$UPDATES_BASE_URL/$ENCODED_NAME"
        sparkle:version="$BUILD_VERSION"
        sparkle:shortVersionString="$SHORT_VERSION"
        sparkle:edSignature="INSERT_SPARKLE_EDDSA_SIGNATURE"
        length="0"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

echo "[9/9] Signing appcast enclosure..."
"$ROOT_DIR/scripts/sign_update.sh" "$ENCLOSURE_PATH" "$APPCAST_PATH"

echo ""
echo "Done! Release $SHORT_VERSION (build $BUILD_VERSION)"
echo "  App:       $APP_PATH"
echo "  Zip:       $FINAL_ZIP"
echo "  Dmg:       $DMG_PATH"
echo "  Enclosure: $ENCLOSURE_PATH"
echo "  Appcast:   $APPCAST_PATH"
echo ""
echo "Next: ./scripts/upload_all.sh"
