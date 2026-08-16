#!/usr/bin/env bash
set -e

UNINSTALL_SUNSHINE=false
UNINSTALL_DEPS=false
REMOVE_OLD_USER=false
ASSUME_YES=false

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -s, --sunshine          Uninstall Sunshine package
  -d, --dependencies      Uninstall dependencies installed by install.sh
  -u, --remove-old-user   Remove legacy 'pokerogue' user from old installs
  -a, --all               Run all uninstall actions
  -y, --yes               Skip confirmation prompt
  -h, --help              Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--sunshine)
      UNINSTALL_SUNSHINE=true
      shift
      ;;
    -d|--dependencies)
      UNINSTALL_DEPS=true
      shift
      ;;
    -u|--remove-old-user)
      REMOVE_OLD_USER=true
      shift
      ;;
    -a|--all)
      UNINSTALL_SUNSHINE=true
      UNINSTALL_DEPS=true
      REMOVE_OLD_USER=true
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$UNINSTALL_SUNSHINE" = false && "$UNINSTALL_DEPS" = false && "$REMOVE_OLD_USER" = false ]]; then
  echo "No uninstall action selected."
  usage
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

echo "Selected actions:"
[[ "$UNINSTALL_SUNSHINE" = true ]] && echo "- Uninstall Sunshine"
[[ "$UNINSTALL_DEPS" = true ]] && echo "- Uninstall dependencies"
[[ "$REMOVE_OLD_USER" = true ]] && echo "- Remove legacy 'pokerogue' user"

if [[ "$ASSUME_YES" = false ]]; then
  read -r -p "Continue? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

remove_systemd_unit() {
  local unit="$1"
  systemctl stop "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
  rm -f "/etc/systemd/system/${unit}.service"
}

remove_project_runtime() {
  remove_systemd_unit "pokerogue-runtime"
  remove_systemd_unit "xvfb-pokerogue"
  remove_systemd_unit "pulseaudio-pokerogue"
  remove_systemd_unit "openbox-pokerogue"
  remove_systemd_unit "sunshine-pokerogue"
  systemctl daemon-reload

  # Kill any lingering rogue processes
  killall -9 Xvfb pulseaudio openbox sunshine chromium-browser 2>/dev/null || true
  pkill -9 -x Xvfb || true
  pkill -9 -x pulseaudio || true
  pkill -9 -x openbox || true
  pkill -9 -x sunshine || true
  pkill -9 -x chromium-browser || true

  # Clean up lock files left behind by forceful termination
  rm -f /tmp/.X99-lock
  rm -f /tmp/.X11-unix/X99

  rm -f /usr/local/bin/launch-pokerogue.sh
  rm -f /etc/udev/rules.d/99-sunshine-input.rules
  udevadm control --reload-rules 2>/dev/null || true
  udevadm trigger 2>/dev/null || true

  if [[ -n "$TARGET_HOME" && -d "$TARGET_HOME/.config/sunshine" ]]; then
    rm -rf "$TARGET_HOME/.config/sunshine"
  fi
  if [[ -n "$TARGET_HOME" && -f "$TARGET_HOME/.config/pulse/default.pa" ]]; then
    rm -f "$TARGET_HOME/.config/pulse/default.pa"
  fi
  if [[ -d "/home/pokerogue/.config/sunshine" ]]; then
    rm -rf "/home/pokerogue/.config/sunshine"
  fi
  if [[ -f "/home/pokerogue/.config/pulse/default.pa" ]]; then
    rm -f "/home/pokerogue/.config/pulse/default.pa"
  fi
}

if [[ "$UNINSTALL_SUNSHINE" = true ]]; then
  echo "Removing Sunshine..."
  remove_project_runtime
  systemctl --global unmask sunshine.service 2>/dev/null || true
  systemctl --global enable sunshine.service 2>/dev/null || true
  apt-get remove --purge -y sunshine || true
fi

if [[ "$UNINSTALL_DEPS" = true ]]; then
  echo "Removing installer dependencies..."
  apt-get remove --purge -y xvfb openbox chromium-browser ufw curl wget jq pulseaudio dbus-x11 software-properties-common || true
  apt-get autoremove -y
fi

if [[ "$REMOVE_OLD_USER" = true ]]; then
  echo "Removing legacy pokerogue user..."
  if id -u pokerogue >/dev/null 2>&1; then
    loginctl terminate-user pokerogue 2>/dev/null || true
    pkill -u pokerogue 2>/dev/null || true
    userdel -r pokerogue 2>/dev/null || true
  else
    echo "Legacy user 'pokerogue' does not exist. Skipping."
  fi
fi

echo "Uninstall actions complete."
