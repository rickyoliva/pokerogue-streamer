#!/usr/bin/env bash
# Headless PokeRogue Streaming Server Setup
set -e

echo "=========================================="
echo " PokeRogue Headless Streaming Server Setup"
echo "=========================================="

# 1. Root check
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   echo "If you are running this via curl, try: curl -sSL <url> | sudo bash"
   exit 1
fi

# 2. Get Public IP
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "UNKNOWN_IP")

# 3. Interactive Prompts
PROMPT_FD=0
if [ ! -t 0 ]; then
    if [ -r /dev/tty ]; then
        exec 3</dev/tty
        PROMPT_FD=3
    else
        PROMPT_FD=-1
    fi
fi

RES="640x480"

if [ "$PROMPT_FD" -eq -1 ]; then
    echo "No interactive terminal detected. Skipping Sunshine credentials prompt."
    SUN_USER=""
    SUN_PASS=""
else
    echo "Sunshine Web UI Credentials"
    read -r -u "$PROMPT_FD" -p "Enter Sunshine Admin Username (leave blank to skip): " SUN_USER
    if [ -n "$SUN_USER" ]; then
        read -r -s -u "$PROMPT_FD" -p "Enter Sunshine Admin Password: " SUN_PASS
        echo
    fi
fi

echo "=========================================="
echo " Setup Summary:"
echo " Resolution: $RES"
echo " Web UI User: ${SUN_USER:-(Will be configured on first access)}"
echo " Public IP: $PUBLIC_IP"
echo "=========================================="
echo "Starting installation in 3 seconds..."
sleep 3

# 4. Resolve target user (the user who invoked sudo, or current user)
TARGET_USER="${SUDO_USER:-$USER}"
if [ -z "$TARGET_USER" ] || ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "Could not determine a valid target user."
    exit 1
fi
if [ "$TARGET_USER" = "root" ]; then
    echo "Warning: target user resolved to root. Running services as root is not recommended."
fi

# Ensure the user has the required groups
# input: for /dev/uinput controller creation
# render: for hardware acceleration
usermod -a -G video,audio,input,render "$TARGET_USER" || true

# Add udev rules so the 'input' group can access /dev/uinput
echo 'KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"' > /etc/udev/rules.d/99-sunshine-input.rules
udevadm control --reload-rules || true
udevadm trigger || true
HOMEDIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
UID_PR=$(id -u "$TARGET_USER")
if [ -z "$HOMEDIR" ]; then
    echo "Could not resolve home directory for user '$TARGET_USER'."
    exit 1
fi

# Stop any default xvfb service that might be respawning and causing conflicts
systemctl stop xvfb.service 2>/dev/null || true
systemctl disable xvfb.service 2>/dev/null || true

# Kill rogue processes from previous or failed installations
echo "Killing any existing rogue processes to free up ports..."
killall -9 Xvfb pulseaudio openbox sunshine chromium-browser google-chrome-stable chrome 2>/dev/null || true
pkill -9 -x Xvfb || true
pkill -9 -x pulseaudio || true
pkill -9 -x openbox || true
pkill -9 -x sunshine || true
pkill -9 -x chromium-browser || true
pkill -9 -x google-chrome-stable || true
pkill -9 -x chrome || true
sleep 1

# Clean up lock files left behind by forceful termination
rm -f /tmp/.X99-lock
rm -f /tmp/.X11-unix/X99

# 5. Update and install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y universe
add-apt-repository -y multiverse
apt-get update

# Determine which browser to install based on architecture
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    BROWSER_PKG="google-chrome-stable"
    BROWSER_EXEC="google-chrome-stable"
else
    # For arm64, use chromium-browser from a PPA to avoid the snap package
    # We will use firefox for arm64 instead since chromium non-snap is hard to find reliably.
    BROWSER_PKG="firefox"
    BROWSER_EXEC="firefox"
fi

# Make sure we clean up the old snap wrapper if it exists before proceeding
if dpkg -l | grep -q "^ii  chromium-browser "; then
    echo "Removing existing snap-based chromium-browser..."
    apt-get remove --purge -y chromium-browser || true
    if command -v snap >/dev/null 2>&1; then
        snap remove chromium || true
    fi
fi

# Check if dependencies are already installed to save time on updates
deps_installed=true
for pkg in xvfb openbox $BROWSER_PKG ufw curl wget jq pulseaudio dbus-x11; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        deps_installed=false
        break
    fi
done

if [ "$deps_installed" = false ]; then
    if [ "$BROWSER_PKG" = "google-chrome-stable" ]; then
        if ! dpkg -l | grep -q "^ii  google-chrome-stable "; then
            curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list
            apt-get update
        fi
    else
        # For arm64 we are using firefox instead of chromium.
        # Ubuntu 22.04+ also snaps firefox, so we need to add the mozilla PPA
        add-apt-repository -y ppa:mozillateam/ppa || true

        # Prevent snapd from taking over firefox package
        cat <<EOF3 > /etc/apt/preferences.d/mozilla-firefox
Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001

Package: firefox*
Pin: release o=Ubuntu
Pin-Priority: -1
EOF3
        apt-get update
    fi
    apt-get install -y xvfb openbox $BROWSER_PKG ufw curl wget jq pulseaudio dbus-x11
else
    echo "Dependencies already installed. Skipping apt install."
fi

# 6. Install Sunshine
UBUNTU_VER=$(lsb_release -rs)
ARCH=$(dpkg --print-architecture)
API_URL="https://api.github.com/repos/LizardByte/Sunshine/releases/latest"
echo "Fetching latest Sunshine release for Ubuntu $UBUNTU_VER ($ARCH)..."
LATEST_RELEASE=$(curl -s "$API_URL" | jq -r ".tag_name")
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name | contains(\"ubuntu-${UBUNTU_VER}-${ARCH}.deb\")) | .browser_download_url")

CURRENT_SUNSHINE_VER=$(dpkg-query -W -f='${Version}' sunshine 2>/dev/null || echo "none")
# If the latest release version is found in the current version, OR if they are an exact match (handling v prefix mismatch if any)
if [[ "$CURRENT_SUNSHINE_VER" == *"${LATEST_RELEASE#v}"* ]] && [ "$CURRENT_SUNSHINE_VER" != "none" ] && [ -n "$LATEST_RELEASE" ] && [ "$LATEST_RELEASE" != "null" ]; then
    echo "Sunshine is already at the latest version ($CURRENT_SUNSHINE_VER). Skipping download."
else
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        echo "Could not dynamically find Sunshine release for Ubuntu ${UBUNTU_VER}. Using fallback."
        if [ "$UBUNTU_VER" == "24.04" ]; then
            DOWNLOAD_URL="https://github.com/LizardByte/Sunshine/releases/download/v0.23.1/sunshine-ubuntu-24.04-${ARCH}.deb"
        elif [ "$UBUNTU_VER" == "20.04" ]; then
            # Ubuntu 20.04 support dropped in 0.23.0; use 0.23.1 if possible via focal build or stick to the last known stable avoiding 0.22.2 memory leak
            # Let's use 0.21.0 to be safe since 0.22.2 has issues.
            DOWNLOAD_URL="https://github.com/LizardByte/Sunshine/releases/download/v0.21.0/sunshine-ubuntu-20.04-${ARCH}.deb"
        else
            DOWNLOAD_URL="https://github.com/LizardByte/Sunshine/releases/download/v0.23.1/sunshine-ubuntu-22.04-${ARCH}.deb"
        fi
    fi

    echo "Downloading Sunshine from $DOWNLOAD_URL"
    # Use a temporary directory to avoid "Permission denied" on /tmp/sunshine.deb
    # which happens due to fs.protected_regular if /tmp/sunshine.deb already exists
    # and is owned by a different user.
    TEMP_DIR=$(mktemp -d)
    chmod 755 "$TEMP_DIR" # Allow _apt user to access the deb file
    wget -qO "$TEMP_DIR/sunshine.deb" "$DOWNLOAD_URL"
    chmod 644 "$TEMP_DIR/sunshine.deb"
    apt-get install -y --allow-downgrades "$TEMP_DIR/sunshine.deb"
    rm -rf "$TEMP_DIR"
fi

# Mask the default systemd user service provided by the .deb to prevent port conflicts
systemctl --global disable sunshine.service 2>/dev/null || true
systemctl --global mask sunshine.service 2>/dev/null || true
# Kill any currently running sunshine processes (from manual runs or user services)
pkill -x sunshine || true
sleep 1

# 7. Configure PulseAudio for headless
mkdir -p $HOMEDIR/.config/pulse
cat <<EOF2 > $HOMEDIR/.config/pulse/default.pa
.include /etc/pulse/default.pa
load-module module-null-sink sink_name=pokerogue_sink sink_properties=device.description="PokeRogueSink"
set-default-sink pokerogue_sink
EOF2
chown -R "$TARGET_USER:$TARGET_USER" "$HOMEDIR/.config"

# 8. PokeRogue Launcher
cat <<EOF2 > /usr/local/bin/launch-pokerogue.sh
#!/usr/bin/env bash
export DISPLAY=:99
export XDG_RUNTIME_DIR=/run/user/$UID_PR
export PULSE_SERVER=unix:/run/user/$UID_PR/pulse/native

# Start Browser
if [ "${BROWSER_EXEC}" = "firefox" ]; then
    # Firefox requires different flags and syntax for dimensions
    exec firefox -kiosk -width \$(echo "${RES}" | cut -d'x' -f1) -height \$(echo "${RES}" | cut -d'x' -f2) "https://pokerogue.net/"
else
    # Chrome/Chromium flags
    exec ${BROWSER_EXEC} --kiosk --window-size=${RES/x/,} --window-position=0,0 --no-first-run --disable-restore-session-state --disable-dev-shm-usage "https://pokerogue.net/"
fi
EOF2
chmod +x /usr/local/bin/launch-pokerogue.sh

# 9. Sunshine Config & Apps
mkdir -p $HOMEDIR/.config/sunshine
cat <<EOF2 > $HOMEDIR/.config/sunshine/sunshine.conf
sunshine_name = PokeRogue-Server
encoder = software
p2p_video_encoder = x264
capture = x11
audio_sink = pokerogue_sink
file_apps = $HOMEDIR/.config/sunshine/apps.json
EOF2

cat <<EOF2 > $HOMEDIR/.config/sunshine/apps.json
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

# 10. Systemd Services
# Create the runtime directory service
cat <<EOF2 > /etc/systemd/system/pokerogue-runtime.service
[Unit]
Description=Runtime directory for PokeRogue

[Service]
Type=oneshot
ExecStart=/bin/mkdir -p /run/user/$UID_PR
ExecStart=/bin/chown $TARGET_USER:$TARGET_USER /run/user/$UID_PR
ExecStart=/bin/chmod 700 /run/user/$UID_PR
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF2

# Xvfb Service
cat <<EOF2 > /etc/systemd/system/xvfb-pokerogue.service
[Unit]
Description=Xvfb Display for PokeRogue
After=network.target

[Service]
User=$TARGET_USER
ExecStart=/usr/bin/Xvfb :99 -screen 0 ${RES}x24
Restart=always

[Install]
WantedBy=multi-user.target
EOF2

# PulseAudio Service
cat <<EOF2 > /etc/systemd/system/pulseaudio-pokerogue.service
[Unit]
Description=PulseAudio for PokeRogue
After=pokerogue-runtime.service network.target
Requires=pokerogue-runtime.service

[Service]
User=$TARGET_USER
Environment=HOME=$HOMEDIR
Environment=XDG_RUNTIME_DIR=/run/user/$UID_PR
ExecStart=/usr/bin/pulseaudio --daemonize=no
Restart=always

[Install]
WantedBy=multi-user.target
EOF2

# Openbox Service
cat <<EOF2 > /etc/systemd/system/openbox-pokerogue.service
[Unit]
Description=Openbox for PokeRogue
After=xvfb-pokerogue.service
Requires=xvfb-pokerogue.service

[Service]
User=$TARGET_USER
Environment=DISPLAY=:99
ExecStart=/usr/bin/openbox
Restart=always

[Install]
WantedBy=multi-user.target
EOF2

# Sunshine Service
cat <<EOF2 > /etc/systemd/system/sunshine-pokerogue.service
[Unit]
Description=Sunshine for PokeRogue
After=xvfb-pokerogue.service pulseaudio-pokerogue.service network-online.target
Requires=xvfb-pokerogue.service pulseaudio-pokerogue.service

[Service]
User=$TARGET_USER
Environment=DISPLAY=:99
Environment=HOME=$HOMEDIR
Environment=XDG_RUNTIME_DIR=/run/user/$UID_PR
Environment=PULSE_SERVER=unix:/run/user/$UID_PR/pulse/native
ExecStart=/usr/bin/sunshine $HOMEDIR/.config/sunshine/sunshine.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reload
systemctl enable --now pokerogue-runtime
systemctl enable --now xvfb-pokerogue
systemctl enable --now pulseaudio-pokerogue
systemctl enable --now openbox-pokerogue
systemctl enable --now sunshine-pokerogue

# 11. Sunshine Credentials setup
if [ -n "$SUN_USER" ] && [ -n "$SUN_PASS" ]; then
    echo "Setting Sunshine credentials..."
    systemctl stop sunshine-pokerogue
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR=/run/user/$UID_PR sunshine "$HOMEDIR/.config/sunshine/sunshine.conf" --creds "$SUN_USER" "$SUN_PASS" || true
    systemctl start sunshine-pokerogue
fi

# 12. UFW Firewall Configuration
echo "Configuring UFW firewall rules..."
ufw allow 22/tcp
ufw allow 47984/tcp
ufw allow 47989/tcp
ufw allow 47990/tcp
ufw allow 48010/tcp
ufw allow 47998:48000/udp
ufw allow 48010/udp
echo "y" | ufw enable || ufw --force enable

# 13. Final Output
echo "=========================================="
echo "          SUCCESS! SETUP COMPLETE         "
echo "=========================================="
echo "Your Headless PokeRogue Streaming Server is running."
echo ""
echo "Sunshine Web Management URL:"
echo "  https://$PUBLIC_IP:47990"
if [ -z "$SUN_USER" ]; then
    echo "(Configure your username/password on first access)"
else
    echo "(Login using the credentials you provided during setup)"
fi
echo ""
echo "How to connect with Moonlight (Miyoo Mini Plus):"
echo "  1. Connect your device to the network (or configure it to reach the VPS)."
echo "  2. In Moonlight, add a new PC/Host using the IP: $PUBLIC_IP"
echo "  3. Moonlight will display a 4-digit PIN."
echo "  4. Open the Sunshine Web URL above in a browser."
echo "  5. Go to 'PIN' in the top menu and enter the 4-digit PIN."
echo "  6. Launch 'PokeRogue' from your Moonlight app and enjoy!"
echo "=========================================="
