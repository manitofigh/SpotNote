#!/usr/bin/env bash
# Sign a Sparkle update enclosure with the local EdDSA private key
# (stored in Keychain by `generate_keys`) and patch the appcast in
# place with the resulting `sparkle:edSignature` and `length`
# attributes.
#
# Usage:
#   ./scripts/sign_update.sh <enclosure-path> [appcast-path]
#
# `appcast-path` defaults to `dist/updates/appcast.xml`. The script
# locates the `<enclosure ... url="...<basename>" ...>` element inside
# the appcast and rewrites its sparkle:edSignature/length attributes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ENCLOSURE_PATH="${1:-}"
APPCAST_PATH="${2:-$ROOT_DIR/dist/updates/appcast.xml}"

if [[ -z "$ENCLOSURE_PATH" ]]; then
  echo "ERROR: enclosure path is required" >&2
  echo "Usage: $0 <enclosure-path> [appcast-path]" >&2
  exit 1
fi
if [[ ! -f "$ENCLOSURE_PATH" ]]; then
  echo "ERROR: enclosure not found at $ENCLOSURE_PATH" >&2
  exit 1
fi
if [[ ! -f "$APPCAST_PATH" ]]; then
  echo "ERROR: appcast not found at $APPCAST_PATH" >&2
  exit 1
fi

find_sign_update() {
  local candidates=(
    "/opt/homebrew/Caskroom/sparkle/2.9.1/bin/sign_update"
    "$(ls -d "$ROOT_DIR/build/DerivedData"*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1 || true)"
    "$(ls -d "$HOME/Library/Developer/Xcode/DerivedData"/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1 || true)"
  )
  for c in "${candidates[@]}"; do
    [[ -x "$c" ]] && echo "$c" && return 0
  done
  return 1
}

SIGN_UPDATE="$(find_sign_update || true)"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "ERROR: sign_update not found. Install Sparkle: brew install --cask sparkle" >&2
  exit 1
fi

SIGN_OUTPUT="$("$SIGN_UPDATE" "$ENCLOSURE_PATH")"
SIG="$(printf '%s' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n 1)"
LEN="$(printf '%s' "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p' | head -n 1)"

if [[ -z "$SIG" || -z "$LEN" ]]; then
  echo "ERROR: sign_update did not return signature/length. Output:" >&2
  echo "$SIGN_OUTPUT" >&2
  exit 1
fi

ENCLOSURE_BASENAME="$(basename "$ENCLOSURE_PATH")"

python3 - "$APPCAST_PATH" "$ENCLOSURE_BASENAME" "$SIG" "$LEN" <<'PY'
import pathlib
import re
import sys
import urllib.parse

appcast = pathlib.Path(sys.argv[1])
basename = sys.argv[2]
sig = sys.argv[3]
length = sys.argv[4]

content = appcast.read_text()

# The enclosure URL is percent-encoded in the appcast (spaces -> %20).
encoded = urllib.parse.quote(basename)
candidates = {basename, encoded}

found = False
for candidate in candidates:
    pattern = re.compile(
        rf'(<enclosure\b[^>]*url="[^"]*{re.escape(candidate)}"[^>]*?)'
        r'sparkle:edSignature="[^"]*"',
        flags=re.DOTALL,
    )
    new_content, n = pattern.subn(rf'\1sparkle:edSignature="{sig}"', content)
    if n > 0:
        content = new_content
        found = True

    pattern = re.compile(
        rf'(<enclosure\b[^>]*url="[^"]*{re.escape(candidate)}"[^>]*?)'
        r'length="[^"]*"',
        flags=re.DOTALL,
    )
    new_content, n = pattern.subn(rf'\1length="{length}"', content)
    if n > 0:
        content = new_content
        found = True
    if found:
        break

if not found:
    print(f"ERROR: enclosure for {basename} not found in {appcast}", file=sys.stderr)
    sys.exit(1)

appcast.write_text(content)
print(f'patched {appcast} -> length="{length}" sparkle:edSignature="{sig}"')
PY
