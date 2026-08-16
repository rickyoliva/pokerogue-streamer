#!/usr/bin/env bash
# install-mac-full.sh
# Near-parity macOS installer for PokeRogue streaming via Sunshine
set -euo pipefail

print_header() {
  echo "=========================================="
  echo " PokeRogue macOS Streaming Setup (Full)"
  echo "=========================================="
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: This installer is for macOS only."
    exit 1
  fi
}

require_user_context() {
  if [[ "${EUID}" -eq 0 ]]; then
    echo "Please run this script as your normal macOS user (not root)."
    echo "The script will use sudo only when needed."
    exit 1
  fi
}

install_homebrew_if_missing() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  echo "Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_brew_path() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "Error: Homebrew not found in PATH after installation."
    exit 1
  fi
}

ensure_formula() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    echo "✓ $formula already installed"
  else
    echo "Installing $formula..."
    brew install "$formula"
  fi
}

ensure_cask() {
  local cask="$1"
  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo "✓ $cask already installed"
  else
    echo "Installing $cask..."
    brew install --cask "$cask"
  fi
}

write_launcher_script() {
  local launcher="/usr/local/bin/launch-pokerogue-mac.sh"
  local chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

  sudo mkdir -p /usr/local/bin

  sudo tee "$launcher" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

URL="https://pokerogue.net/"
PROFILE_DIR="$HOME/.pokerogue-kiosk-profile"

if [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
  exec "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --kiosk \
    --disable-session-crashed-bubble \
    --disable-infobars \
    --autoplay-policy=no-user-gesture-required \
    --user-data-dir="$PROFILE_DIR" \
    "$URL"
fi

if command -v chromium >/dev/null 2>&1; then
  exec chromium \
    --kiosk \
    --disable-session-crashed-bubble \
    --disable-infobars \
    --autoplay-policy=no-user-gesture-required \
    --user-data-dir="$PROFILE_DIR" \
    "$URL"
fi

echo "Error: Neither Google Chrome nor Chromium found."
exit 1
EOF

  sudo chmod +x "$launcher"

  if [[ -x "$chrome_bin" ]]; then
    echo "✓ Launcher ready at $launcher (Chrome detected)"
  else
    echo "✓ Launcher ready at $launcher (will use Chromium fallback if installed)"
  fi
}

write_sunshine_apps_json() {
  local config_dir="$HOME/.config/sunshine"
  mkdir -p "$config_dir"

  cat > "$config_dir/apps.json" <<'EOF'
{
  "env": {
    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  },
  "apps": [
    {
      "name": "PokeRogue",
      "output": "",
      "error": "",
      "image-path": "",
      "prep-cmd": [
        {
          "do": "",
          "undo": ""
        }
      ],
      "cmd": "/usr/local/bin/launch-pokerogue-mac.sh",
      "exclude-global-prep-cmd": "false",
      "elevated": "false",
      "auto-detach": "true",
      "wait-all": "true",
      "exit-timeout": "5"
    }
  ]
}
EOF

  echo "✓ Wrote $config_dir/apps.json"
}

write_helper_scripts() {
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/start-sunshine-mac.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -x "/Applications/Sunshine.app/Contents/MacOS/sunshine" ]]; then
  open -a Sunshine
  exit 0
fi

if command -v sunshine >/dev/null 2>&1; then
  nohup sunshine >/tmp/sunshine.log 2>&1 &
  exit 0
fi

echo "Sunshine binary not found."
exit 1
EOF

  cat > "$bin_dir/stop-sunshine-mac.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
pkill -f "Sunshine.app/Contents/MacOS/sunshine" || true
pkill -x sunshine || true
EOF

  chmod +x "$bin_dir/start-sunshine-mac.sh" "$bin_dir/stop-sunshine-mac.sh"
  echo "✓ Helper scripts written to $bin_dir"
}

print_post_install_notes() {
  cat <<'EOF'

==========================================
 Install complete (near-parity macOS path)
==========================================

What was configured:
- Homebrew dependencies and utilities
- Sunshine app (via Homebrew cask)
- Google Chrome (or Chromium fallback)
- PokeRogue launcher: /usr/local/bin/launch-pokerogue-mac.sh
- Sunshine app mapping: ~/.config/sunshine/apps.json
- Sunshine helper scripts: ~/.local/bin/start-sunshine-mac.sh and stop-sunshine-mac.sh

Manual one-time actions required on macOS:
1) Open Sunshine once and grant requested permissions:
   - Screen Recording
   - Accessibility / Input Monitoring (if prompted)
2) In Sunshine Web UI / Apps list, verify app file points to:
   /usr/local/bin/launch-pokerogue-mac.sh
3) Ensure firewall allows Sunshine incoming connections when prompted.

Run Sunshine:
  ~/.local/bin/start-sunshine-mac.sh

Then pair from Moonlight using your Mac's IP and launch "PokeRogue".

EOF
}

main() {
  print_header
  require_macos
  require_user_context

  install_homebrew_if_missing
  ensure_brew_path

  echo "Updating Homebrew..."
  brew update

  ensure_formula curl
  ensure_formula jq
  ensure_formula wget
  ensure_formula shellcheck

  # Browser + streaming host
  if [[ -d "/Applications/Google Chrome.app" ]] || [[ -d "$HOME/Applications/Google Chrome.app" ]]; then
    echo "✓ google-chrome already installed (app bundle exists)"
  else
    ensure_cask google-chrome
  fi
  ensure_cask sunshine

  # Optional Chromium fallback
  ensure_formula chromium || true

  write_launcher_script
  write_sunshine_apps_json
  write_helper_scripts
  print_post_install_notes
}

main "$@"
