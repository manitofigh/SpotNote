#!/usr/bin/env bash
# Shared helpers sourced by every script in this directory.
# Not intended to be executed directly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES=("Sources" "Tests")
SWIFTLINT_CONFIG="$ROOT/Tools/.swiftlint.yml"
SWIFTFORMAT_CONFIG="$ROOT/Tools/.swift-format"
PERIPHERY_CONFIG="$ROOT/Tools/.periphery.yml"

# Colors (skip when not a TTY or NO_COLOR is set)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_RESET=$'\033[0m'
else
  C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_RESET=""
fi

step() { printf "%s==>%s %s%s%s\n" "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
ok()   { printf "%sok%s   %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%swarn%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
fail() { printf "%sfail%s %s\n" "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

require_cmd() {
  local cmd="$1" hint="${2:-}"
  command -v "$cmd" >/dev/null 2>&1 || fail "missing '$cmd' on PATH${hint:+ -- $hint}"
}
