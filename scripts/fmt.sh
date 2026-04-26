#!/usr/bin/env bash
# Reformat all Swift sources in place using swift-format.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
require_cmd swift-format "brew install swift-format"

cd "$ROOT"
step "swift-format format --in-place"
swift-format format --in-place --recursive \
  --configuration "$SWIFTFORMAT_CONFIG" \
  "${SOURCES[@]}"
ok "formatted ${SOURCES[*]}"
