#!/usr/bin/env bash
# CI gate -- fail if any Swift file disagrees with swift-format.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
require_cmd swift-format "brew install swift-format"

cd "$ROOT"
step "swift-format lint --strict"
swift-format lint --strict --recursive \
  --configuration "$SWIFTFORMAT_CONFIG" \
  "${SOURCES[@]}"
ok "formatting clean"
