#!/usr/bin/env bash
# Whole-program dead-code scan via Periphery (SourceKit-based).
# Fails on any unused declaration unless annotated with `// periphery:ignore`.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
require_cmd periphery "brew install periphery"

cd "$ROOT"
step "periphery scan"
# Periphery auto-detects the SPM Package.swift when no --project is passed
# and no schemes are configured.
periphery scan --config "$PERIPHERY_CONFIG" --disable-update-check
ok "no dead code detected"
