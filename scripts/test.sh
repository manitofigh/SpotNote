#!/usr/bin/env bash
# Run the full Swift Testing / XCTest suite in parallel with coverage.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
require_cmd swift

cd "$ROOT"
step "swift test --parallel --enable-code-coverage"
swift test --parallel --enable-code-coverage
ok "tests passed"
