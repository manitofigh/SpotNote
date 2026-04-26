#!/usr/bin/env bash
# Style + per-file correctness checks via SwiftLint.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
require_cmd swiftlint "brew install swiftlint"

cd "$ROOT"
step "swiftlint --strict"
swiftlint --strict --config "$SWIFTLINT_CONFIG"
ok "lint clean"
