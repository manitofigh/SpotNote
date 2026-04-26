#!/usr/bin/env bash
# One-time developer bootstrap. Run this BEFORE any other script in this
# directory -- ci.sh, lint.sh, complexity.sh, etc. all depend on the CLIs
# installed here.
#
# Installs, via Homebrew + pipx:
#   - swift-format   (Apple's formatter, RULES.md §6.1)
#   - swiftlint      (RULES.md §6.2)
#   - periphery      (dead-code analyzer, RULES.md §6.3)
#   - pipx           (isolated-env installer for Python tooling)
#   - lizard         (complexity analyzer, RULES.md §6.4)
#
# Safe to re-run: every step is idempotent.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# --- Xcode toolchain -----------------------------------------------------
step "checking Xcode command line tools"
if ! xcode-select -p >/dev/null 2>&1; then
  warn "Xcode command line tools missing -- launching installer"
  xcode-select --install || true
  fail "re-run scripts/setup.sh after the CLT install dialog completes"
fi
ok "xcode-select: $(xcode-select -p)"

require_cmd swift "install Xcode or Xcode command line tools"
require_cmd git   "install Xcode or Xcode command line tools"

# --- Homebrew ------------------------------------------------------------
step "checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found -- installing"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Pick up brew in the current shell (Apple Silicon default path).
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
ok "brew: $(command -v brew)"

# --- Brew formulae -------------------------------------------------------
brew_install() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    ok "$formula already installed"
  else
    step "brew install $formula"
    brew install "$formula"
    ok "$formula installed"
  fi
}

brew_install swift-format
brew_install swiftlint
brew_install periphery
brew_install pipx

# --- pipx path -----------------------------------------------------------
step "pipx ensurepath"
pipx ensurepath >/dev/null
# Make pipx-installed binaries visible in this shell without sourcing rc files.
export PATH="$HOME/.local/bin:$PATH"

# --- lizard --------------------------------------------------------------
if command -v lizard >/dev/null 2>&1; then
  ok "lizard already installed ($(command -v lizard))"
else
  step "pipx install lizard"
  pipx install lizard
  ok "lizard installed"
fi

# --- Verify --------------------------------------------------------------
step "verifying toolchain via tools-check.sh"
"$ROOT/scripts/tools-check.sh"

ok "setup complete -- you can now run ./scripts/ci.sh"
