#!/usr/bin/env bash
# install-mac.sh
# macOS bootstrap for local PokeRogue streaming helper tools
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_header() {
  echo "=========================================="
  echo "   PokeRogue Streamer macOS Installer"
  echo "=========================================="
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: install-mac.sh is for macOS only."
    exit 1
  fi
}

install_homebrew_if_missing() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  echo "Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Ensure brew is available in this shell
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_tool() {
  local tool="$1"
  local formula="${2:-$1}"

  if command -v "$tool" >/dev/null 2>&1; then
    echo "✓ $tool already installed"
  else
    echo "Installing $formula..."
    brew install "$formula"
  fi
}

main() {
  print_header
  require_macos
  install_homebrew_if_missing

  echo "Updating Homebrew..."
  brew update

  # Core tools used by repository scripts
  ensure_tool curl
  ensure_tool jq
  ensure_tool wget

  # Nice to have for shell checks if expanded later
  ensure_tool shellcheck

  echo
  echo "Running dependency check script..."
  if [[ -f "$REPO_ROOT/test_deps.sh" ]]; then
    bash "$REPO_ROOT/test_deps.sh"
  else
    echo "Warning: test_deps.sh not found. Skipping dependency test."
  fi

  cat <<'EOF'

Done ✅

This repository's main installer (install.sh) is Ubuntu/VPS-specific and uses apt/systemd.
On macOS, use this repo's helper/debug scripts and run Linux-only setup on an Ubuntu host.

Suggested next steps:
  1) Open README.md for Ubuntu server setup details.
  2) Use install.sh on Ubuntu 22.04/24.04 for full Sunshine headless streaming setup.
EOF
}

main "$@"
