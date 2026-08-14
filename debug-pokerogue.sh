#!/usr/bin/env bash

# Check root early since journalctl/systemctl need it for system services
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (or with sudo) to check system services and logs."
   exit 1
fi

echo "=========================================="
echo " PokeRogue Streaming Server Debugger"
echo "=========================================="

echo "[1/4] Checking systemd services status..."
SERVICES=("pokerogue-runtime" "xvfb-pokerogue" "pulseaudio-pokerogue" "openbox-pokerogue" "sunshine-pokerogue")
for s in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$s"; then
        echo "  [OK] $s is running."
    else
        echo "  [ERROR] $s is NOT running!"
        systemctl status "$s" --no-pager | head -n 5 || true
    fi
done

echo ""
echo "[2/4] Checking required ports..."
# Sunshine default ports: 47990 (Web UI), 47984, 47989, etc.
if ss -tuln | grep -q ":47990 "; then
    echo "  [OK] Sunshine Web UI port (47990) is listening."
else
    echo "  [ERROR] Sunshine Web UI port (47990) is NOT listening!"
fi

if ss -tuln | grep -q ":47989 "; then
    echo "  [OK] Sunshine streaming port (47989) is listening."
else
    echo "  [WARNING] Sunshine streaming port (47989) is NOT listening. This is normal if Sunshine is just starting up, but if it persists, Sunshine may be failing."
fi

echo ""
echo "[3/4] Checking virtual display / Xvfb..."
if pgrep -f "Xvfb :99" > /dev/null; then
    echo "  [OK] Xvfb process is running on :99."
else
    echo "  [ERROR] Xvfb process is NOT running."
fi

echo ""
echo "[4/4] Checking recent Sunshine logs..."
echo "  Fetching last 20 lines from sunshine-pokerogue service..."
echo "------------------------------------------"
journalctl -u sunshine-pokerogue --no-pager -n 20 || true
echo "------------------------------------------"

echo "Debug complete."