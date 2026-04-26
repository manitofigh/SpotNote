#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_YML="$ROOT_DIR/project.yml"
APP_INFO="$ROOT_DIR/Sources/Core/AppInfo.swift"
BUILD_SCRIPT="$ROOT_DIR/scripts/build.sh"

DRY_RUN=0
BUMP_KIND=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/bump-version.sh patch|minor|major [--dry-run]

Bumps MARKETING_VERSION (semver) and CURRENT_PROJECT_VERSION (integer)
across all source-of-truth files:
  - project.yml           (xcodegen spec)
  - Sources/Core/AppInfo.swift
  - scripts/build.sh      (inline Info.plist)

After bumping, re-run `xcodegen generate` to propagate into the
.xcodeproj.

Options:
  --dry-run  Print computed changes without modifying files
  -h, --help Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    patch|minor|major)
      if [[ -n "$BUMP_KIND" ]]; then
        echo "ERROR: Multiple bump kinds provided."
        usage
        exit 1
      fi
      BUMP_KIND="$arg"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $arg"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$BUMP_KIND" ]]; then
  echo "ERROR: Missing bump kind."
  usage
  exit 1
fi

# --- Read current values from project.yml (canonical source) ---

CURRENT_MARKETING="$(grep -E '^\s+MARKETING_VERSION:' "$PROJECT_YML" | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')"
CURRENT_BUILD="$(grep -E '^\s+CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')"

if [[ -z "$CURRENT_MARKETING" ]]; then
  echo "ERROR: Could not read MARKETING_VERSION from $PROJECT_YML"
  exit 1
fi
if [[ -z "$CURRENT_BUILD" ]]; then
  echo "ERROR: Could not read CURRENT_PROJECT_VERSION from $PROJECT_YML"
  exit 1
fi

# --- Compute next values ---

IFS='.' read -r MAJOR MINOR PATCH <<<"$CURRENT_MARKETING"
case "$BUMP_KIND" in
  patch) NEXT_MARKETING="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  minor) NEXT_MARKETING="$MAJOR.$((MINOR + 1)).0" ;;
  major) NEXT_MARKETING="$((MAJOR + 1)).0.0" ;;
esac

NEXT_BUILD="$((CURRENT_BUILD + 1))"

echo "Bump kind:              $BUMP_KIND"
echo "MARKETING_VERSION:      $CURRENT_MARKETING -> $NEXT_MARKETING"
echo "CURRENT_PROJECT_VERSION: $CURRENT_BUILD -> $NEXT_BUILD"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "Dry run -- no files modified."
  exit 0
fi

# --- Update project.yml ---

sed -i '' \
  -e "s/MARKETING_VERSION: \"$CURRENT_MARKETING\"/MARKETING_VERSION: \"$NEXT_MARKETING\"/" \
  -e "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" \
  "$PROJECT_YML"

if ! grep -q "MARKETING_VERSION: \"$NEXT_MARKETING\"" "$PROJECT_YML"; then
  echo "ERROR: Failed to update project.yml"
  exit 1
fi

echo "  ✓ project.yml"

# --- Update AppInfo.swift ---

sed -i '' \
  "s/static let version = \"$CURRENT_MARKETING\"/static let version = \"$NEXT_MARKETING\"/" \
  "$APP_INFO"

if ! grep -q "\"$NEXT_MARKETING\"" "$APP_INFO"; then
  echo "ERROR: Failed to update AppInfo.swift"
  exit 1
fi

echo "  ✓ Sources/Core/AppInfo.swift"

# --- Update build.sh inline Info.plist ---

sed -i '' \
  -e "s|<string>$CURRENT_MARKETING</string>  <!-- CFBundleShortVersionString -->|<string>$NEXT_MARKETING</string>  <!-- CFBundleShortVersionString -->|" \
  -e "s|CFBundleShortVersionString</key>      <string>$CURRENT_MARKETING</string>|CFBundleShortVersionString</key>      <string>$NEXT_MARKETING</string>|" \
  -e "s|CFBundleVersion</key>                 <string>$CURRENT_BUILD</string>|CFBundleVersion</key>                 <string>$NEXT_BUILD</string>|" \
  "$BUILD_SCRIPT"

echo "  ✓ scripts/build.sh"

# --- Regenerate xcodeproj if xcodegen is available ---

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null 2>&1
  echo "  ✓ SpotNote.xcodeproj regenerated"
fi

echo ""
echo "Done. Version is now $NEXT_MARKETING (build $NEXT_BUILD)."
