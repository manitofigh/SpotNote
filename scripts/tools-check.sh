#!/usr/bin/env bash
# Verify every CLI the developer workflow depends on is installed.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

declare -a REQUIRED=(
  "swift|Xcode Command Line Tools"
  "codesign|Xcode Command Line Tools"
  "swift-format|brew install swift-format"
  "swiftlint|brew install swiftlint"
  "periphery|brew install periphery"
  "lizard|pipx install lizard"
  "git|Xcode Command Line Tools"
)

missing=0
for entry in "${REQUIRED[@]}"; do
  cmd="${entry%%|*}"
  hint="${entry#*|}"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd ($(command -v "$cmd"))"
  else
    warn "$cmd missing -- $hint"
    missing=$((missing + 1))
  fi
done

if [[ $missing -gt 0 ]]; then
  fail "$missing required tool(s) missing"
fi
ok "all tools present"
