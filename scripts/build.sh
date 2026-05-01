#!/usr/bin/env bash
# Build SpotNote as a swift-build executable and assemble a .app bundle.
# Usage: ./scripts/build.sh [debug|release]   (default: debug)
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="$ROOT/build/SpotNote.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"

cp "$BIN_PATH/SpotNoteApp" "$MACOS/SpotNote"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>       <string>en</string>
  <key>CFBundleExecutable</key>              <string>SpotNote</string>
  <key>CFBundleIdentifier</key>              <string>com.spotnote.SpotNote</string>
  <key>CFBundleInfoDictionaryVersion</key>   <string>6.0</string>
  <key>CFBundleName</key>                    <string>SpotNote</string>
  <key>CFBundleDisplayName</key>             <string>SpotNote</string>
  <key>CFBundlePackageType</key>             <string>APPL</string>
  <key>CFBundleShortVersionString</key>      <string>0.2.0</string>
  <key>CFBundleVersion</key>                 <string>2</string>
  <key>LSMinimumSystemVersion</key>          <string>14.0</string>
  <key>LSUIElement</key>                     <true/>
  <key>CFBundleIconFile</key>                <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>         <true/>
  <key>NSSupportsAutomaticTermination</key>  <false/>
  <key>NSSupportsSuddenTermination</key>     <false/>
</dict>
</plist>
PLIST

RESOURCES="$CONTENTS/Resources"
mkdir -p "$RESOURCES"
ICNS_PATH="$ROOT/App/AppIcon.icns"
if [[ -f "$ICNS_PATH" ]]; then
  cp "$ICNS_PATH" "$RESOURCES/AppIcon.icns"
fi

FRAMEWORKS_DIR="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
shopt -s nullglob
for fw in "$BIN_PATH"/*.framework; do
  rm -rf "$FRAMEWORKS_DIR/$(basename "$fw")"
  cp -R "$fw" "$FRAMEWORKS_DIR/"
done
shopt -u nullglob

# `swift build` does not add `@executable_path/../Frameworks` to the
# binary's rpath search list, so dyld can't resolve embedded
# frameworks (Sparkle, etc.) from the standard .app layout. Add it.
if ! otool -l "$MACOS/SpotNote" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/SpotNote"
fi

echo "==> codesigning (ad-hoc)"
# Sparkle.framework's top-level path can be ambiguous to `codesign`
# ("could be app or framework"). Sign concrete Versions/* bundles first.
shopt -s nullglob
for fw in "$FRAMEWORKS_DIR"/*.framework; do
  if [[ -d "$fw/Versions" ]]; then
    for version_dir in "$fw"/Versions/*; do
      [[ -d "$version_dir" ]] || continue
      codesign --force --sign - "$version_dir" >/dev/null
    done
  else
    codesign --force --sign - "$fw" >/dev/null
  fi
done
shopt -u nullglob
codesign --force --sign - "$APP_DIR" >/dev/null

echo "OK: $APP_DIR"
