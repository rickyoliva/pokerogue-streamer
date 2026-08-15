#!/usr/bin/env bash
# diagnose-pokerogue.sh
# Collect logs and diagnostic info for sunshine / Xvfb / PulseAudio for PokeRogue
# Usage: sudo ./diagnose-pokerogue.sh
set -u
OUTDIR="/tmp/pokerogue-diagnostics-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTDIR"
echo "Writing outputs to $OUTDIR"

run() {
  local file="$1"
  shift
  echo "=== Running: $* ===" > "$OUTDIR/$file"
  if "$@" >> "$OUTDIR/$file" 2>&1; then
    echo "OK: $file"
  else
    echo "ERROR (exit $?): $file"
  fi
}

# Basic service status & logs
run "systemctl_status_sunshine.txt" sudo systemctl status -l sunshine-pokerogue.service
run "journal_sunshine_last500.txt" sudo journalctl -u sunshine-pokerogue.service -b --no-pager | tail -n 500

# Dependencies and units
run "list_dependencies_reverse.txt" sudo systemctl list-dependencies --reverse sunshine-pokerogue.service || true
run "systemctl_cat_units.txt" sudo systemctl cat sunshine-pokerogue.service pulseaudio-pokerogue.service xvfb-pokerogue.service || true

# Failed units quick status + logs
run "status_pulseaudio_xvfb.txt" sudo systemctl status -l pulseaudio-pokerogue.service xvfb-pokerogue.service || true
run "journal_pulseaudio_last500.txt" sudo journalctl -u pulseaudio-pokerogue.service -b --no-pager | tail -n 500 || true
run "journal_xvfb_last500.txt" sudo journalctl -u xvfb-pokerogue.service -b --no-pager | tail -n 500 || true

# System checks
run "systemctl_failed.txt" sudo systemctl --failed || true
run "which_binaries.txt" which Xvfb pulseaudio || true
run "dpkg_list_xvfb.txt" dpkg -l | egrep "xvfb|xserver-xorg-core|xvfb-run" || true

# Processes and files
run "ps_aux_xvfb_pulse_sunshine.txt" ps aux | egrep "Xvfb|pulseaudio|sunshine" || true
run "display_and_xauthority.txt" bash -lc "echo DISPLAY=\$DISPLAY; ls -l /home/ubuntu/.Xauthority 2>/dev/null || true"

# Check binary versions (non-daemonizing calls)
if [ -x /usr/bin/Xvfb ]; then
  run "Xvfb_version.txt" /usr/bin/Xvfb -help || true
else
  echo "/usr/bin/Xvfb not found or not executable" > "$OUTDIR/Xvfb_version.txt"
fi

if [ -x /usr/bin/pulseaudio ]; then
  run "pulseaudio_version.txt" /usr/bin/pulseaudio --version || true
else
  echo "/usr/bin/pulseaudio not found or not executable" > "$OUTDIR/pulseaudio_version.txt"
fi

# Try a safe non-blocking test to run the binaries as ubuntu (will not leave a daemon running)
# (we do NOT start services; just capture immediate stderr if executable refuses to run)
run "xvfb_test_attempt.txt" sudo -u ubuntu bash -lc "(/usr/bin/Xvfb :99 -screen 0 640x480x24 >/dev/null 2>&1 & sleep 0.5; ps -o pid,cmd -u ubuntu | egrep 'Xvfb' || true); killall Xvfb 2>/dev/null || true" || true
run "pulseaudio_test_attempt.txt" sudo -u ubuntu bash -lc "/usr/bin/pulseaudio --daemonize=no --log-level=warning --log-target=stderr 2>&1 || true" || true

# Summaries
echo "---- brief summary ----" > "$OUTDIR/summary.txt"
echo "Timestamp: $(date -Iseconds)" >> "$OUTDIR/summary.txt"
echo "" >> "$OUTDIR/summary.txt"
echo "Systemctl --failed (first 100 lines):" >> "$OUTDIR/summary.txt"
sudo systemctl --failed | sed -n '1,100p' >> "$OUTDIR/summary.txt" 2>&1 || true

# Compress results
ARCHIVE="${OUTDIR}.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$OUTDIR")" "$(basename "$OUTDIR")"
echo "Archive created: $ARCHIVE"
ls -lh "$ARCHIVE"

echo "Done. Upload the archive or paste the outputs. If you want, I can add this file to a repository — tell me owner/repo and path."

Notes / safety:
- The script avoids leaving daemons running. It attempts safe, brief checks only.
- Run as root (sudo) so journalctl and systemctl outputs are readable.
- If you want the script to also attempt to start the failing services and capture their start attempts, tell me and I can add safe 'systemctl start --no-block' lines.
