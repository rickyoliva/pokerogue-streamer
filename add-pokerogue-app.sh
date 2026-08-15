#!/usr/bin/env bash
# Script to configure the PokeRogue application in Sunshine for existing installations.
set -e

echo "=========================================="
echo " PokeRogue Sunshine App Configurator"
echo "=========================================="

# 1. Root check
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   echo "If you are running this via curl, try: curl -sSL <url> | sudo bash"
   exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
if [ -z "$TARGET_USER" ] || ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "Could not determine a valid target user."
    exit 1
fi

HOMEDIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$HOMEDIR" ]; then
    echo "Could not resolve home directory for user '$TARGET_USER'."
    exit 1
fi
SUNSHINE_CONF="$HOMEDIR/.config/sunshine/sunshine.conf"
APPS_JSON="$HOMEDIR/.config/sunshine/apps.json"

echo "Checking Sunshine configuration at $SUNSHINE_CONF..."
if [ -f "$SUNSHINE_CONF" ]; then
    if ! grep -q "^file_apps" "$SUNSHINE_CONF"; then
        echo "Adding file_apps pointer to sunshine.conf..."
        echo "file_apps = $APPS_JSON" >> "$SUNSHINE_CONF"
    else
        echo "file_apps pointer is already present in sunshine.conf."
    fi
else
    echo "Error: $SUNSHINE_CONF not found. Creating a minimal config."
    mkdir -p "$HOMEDIR/.config/sunshine"
    cat <<EOF2 > "$SUNSHINE_CONF"
sunshine_name = PokeRogue-Server
encoder = software
p2p_video_encoder = x264
capture = x11
audio_sink = pokerogue_sink
file_apps = $APPS_JSON
EOF2
    chown -R "$TARGET_USER:$TARGET_USER" "$HOMEDIR/.config/sunshine"
fi

echo "Ensuring apps.json is correctly configured..."
mkdir -p "$HOMEDIR/.config/sunshine"
cat <<EOF2 > "$APPS_JSON"
{
  "env": {
    "PATH": "$(echo $PATH)"
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
      "cmd": "/usr/local/bin/launch-pokerogue.sh",
      "exclude-global-prep-cmd": "false",
      "elevated": "false",
      "auto-detach": "true",
      "wait-all": "true",
      "exit-timeout": "5"
    }
  ]
}
EOF2
chown -R "$TARGET_USER:$TARGET_USER" "$HOMEDIR/.config/sunshine"

echo "Restarting sunshine-pokerogue service..."
systemctl restart sunshine-pokerogue || echo "Warning: Failed to restart sunshine-pokerogue. It may not be running yet."

echo "=========================================="
echo "          SUCCESS! APPS CONFIGURED        "
echo "=========================================="
echo "PokeRogue is now properly configured in Sunshine."
echo "You can connect using Moonlight to see 'PokeRogue' as an available application."
