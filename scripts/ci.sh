#!/usr/bin/env bash
# Umbrella: runs every quality gate in the order RULES.md §8 prescribes.
# Fails fast -- any stage erroring aborts the run.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

cd "$ROOT"
START=$(date +%s)

"$ROOT/scripts/tools-check.sh"
"$ROOT/scripts/fmt-check.sh"
"$ROOT/scripts/lint.sh"
"$ROOT/scripts/build.sh" debug
"$ROOT/scripts/test.sh"
"$ROOT/scripts/periphery.sh"
"$ROOT/scripts/complexity.sh"

END=$(date +%s)
ok "ci passed in $((END - START))s"
