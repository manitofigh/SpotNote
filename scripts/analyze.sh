#!/usr/bin/env bash
# SwiftLint analyze -- cross-file rules that need the compiler log.
# Produces a compiler log via `swift build -v`, then feeds it to swiftlint.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
require_cmd swiftlint "brew install swiftlint"
require_cmd swift "install Xcode command line tools"

cd "$ROOT"
LOG="$ROOT/.build/analyze.log"
mkdir -p "$(dirname "$LOG")"

step "swift build -v -> $LOG"
swift build -v > "$LOG" 2>&1

step "swiftlint analyze --strict"
swiftlint analyze --strict \
  --config "$SWIFTLINT_CONFIG" \
  --compiler-log-path "$LOG"
ok "analyze clean"
