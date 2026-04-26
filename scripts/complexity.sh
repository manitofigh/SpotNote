#!/usr/bin/env bash
# Cyclomatic complexity + function length + parameter count check via lizard.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
require_cmd lizard "pipx install lizard"

cd "$ROOT"
REPORT_DIR="$ROOT/Tools/reports"
mkdir -p "$REPORT_DIR"

step "lizard Sources Tests"
lizard -l swift \
  --CCN 17 \
  --length 100 \
  --arguments 7 \
  --warnings_only \
  "${SOURCES[@]}" | tee "$REPORT_DIR/lizard.txt"

# lizard exits 0 even when thresholds are exceeded; detect violations ourselves.
if grep -Eq "^[^ ].*!!!!" "$REPORT_DIR/lizard.txt" 2>/dev/null \
   || grep -Eiq "warning" "$REPORT_DIR/lizard.txt"; then
  fail "complexity thresholds exceeded -- see $REPORT_DIR/lizard.txt"
fi

# Also emit a full report for trend tracking (committed).
lizard -l swift --xml "${SOURCES[@]}" > "$REPORT_DIR/lizard.xml" 2>/dev/null || true
ok "complexity within thresholds"
