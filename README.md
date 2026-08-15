# Headless PokeRogue Streaming Server

This project provides an automated, interactive bash installer for Ubuntu (22.04/24.04) that transforms any VPS into a headless PokeRogue streaming server using [Sunshine](https://github.com/LizardByte/Sunshine).

It is specifically designed to stream smoothly to Moonlight clients, such as the **Miyoo Mini Plus**, by managing resolutions and controller inputs effortlessly.

## Requirements

- A VPS running **Ubuntu 22.04 or 24.04**
- Internet access
- Root or sudo privileges

## Quick Install

To automatically download and run the installer on your VPS, execute the following command in your terminal:

```bash
curl -sSL <YOUR_INSTALL_SH_RAW_URL> | bash
```

*(Note: Replace `<YOUR_INSTALL_SH_RAW_URL>` with the raw URL to the `install.sh` file from your repository, such as `https://raw.githubusercontent.com/<user>/<repo>/main/install.sh`.)*

## What the Installer Does

1. **User Setup**: Uses the invoking user (the user that ran the installer with sudo) to run all required services.
2. **System Dependencies**: Installs the required packages like `Xvfb` (headless display), `Openbox` (window manager), `Chromium`, `PulseAudio`, and more.
3. **Sunshine Installation**: Dynamically fetches and installs the latest stable version of Sunshine.
4. **Headless Audio**: Sets up a virtual PulseAudio sink to stream high-quality PokeRogue audio directly to your device.
5. **Systemd Services**: Configures automatic startup for display, audio, window manager, and Sunshine.
6. **Firewall (UFW)**: Opens the necessary ports for Moonlight and secures your VPS while preserving SSH access.
7. **PokeRogue Launcher**: Adds "PokeRogue" into Sunshine with the specific browser flags tailored for headless full-screen gameplay.

## Connecting from Miyoo Mini Plus

1. Open **Moonlight** on your device.
2. Add a new PC using the public IP of your VPS (displayed at the end of the installation).
3. Moonlight will generate a **4-digit PIN**.
4. Open the Sunshine Web UI (e.g., `https://<YOUR_VPS_IP>:47990`) in any web browser and log in with your configured credentials.
5. Navigate to the **PIN** tab and enter the 4 digits to pair.
6. Launch **PokeRogue** from Moonlight and play!

## Manual App Configuration

If the "PokeRogue" application does not automatically appear in your Sunshine/Moonlight app list, you can add it manually via the Sunshine Web UI:

1. Open the Sunshine Web UI (e.g., `https://<YOUR_VPS_IP>:47990`) in your browser and log in.
2. Navigate to the **Applications** tab.
3. Click **Add New**.
4. In the **Application Name** field, enter: `PokeRogue`
5. In the **Command** field, enter exactly: `/usr/local/bin/launch-pokerogue.sh`
6. Click **Save** at the bottom.
7. Disconnect and reconnect your Moonlight client; "PokeRogue" should now be available to launch.

## Troubleshooting

- **Audio not working?** Try restarting the pulse service: `sudo systemctl restart pulseaudio-pokerogue`
- **Game not launching?** Check the logs of the Sunshine service: `sudo journalctl -u sunshine-pokerogue -f`
- **Web UI inaccessible?** Make sure UFW is enabled and TCP port 47990 is allowed.
