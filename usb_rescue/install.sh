#!/bin/bash
# Install / remove the USB boot check. Run by install.sh (step before the vanilla install).
#   usb_rescue/install.sh [--remove]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
SYS="${WM_SYS_ROOT:-}"; SUDO="${WM_SUDO-sudo}"; [ "$(id -u)" = 0 ] && [ -z "${WM_SUDO+x}" ] && SUDO=""
SYSTEMCTL="${WM_SYSTEMCTL:-systemctl}"
APP="$SYS/opt/wm-factory-rescue"; UNIT="$SYS/etc/systemd/system/wm-factory-usb.service"; CONF="$SYS/etc/default/wm-factory-usb"
if [ "${1:-}" = --remove ]; then
    $SUDO $SYSTEMCTL disable wm-factory-usb.service >/dev/null 2>&1
    $SUDO rm -rf "$APP" "$UNIT" "$CONF"; $SUDO $SYSTEMCTL daemon-reload 2>/dev/null; echo "USB boot check removed"; exit 0
fi
$SUDO mkdir -p "$APP" "$(dirname "$UNIT")" "$(dirname "$CONF")" || exit 1
$SUDO cp -a "$ROOT/restore.sh" "$ROOT/lib" "$HERE/wm-usb-check" "$APP/" || exit 1
$SUDO chmod +x "$APP/wm-usb-check" "$APP/restore.sh"
$SUDO cp "$HERE/wm-factory-usb.service" "$UNIT"
printf 'WM_USER=%s\nWM_HOME=%s\n' "$(id -un)" "${WM_HOME:-$HOME}" | $SUDO tee "$CONF" >/dev/null
$SUDO $SYSTEMCTL daemon-reload 2>/dev/null; $SUDO $SYSTEMCTL enable wm-factory-usb.service >/dev/null 2>&1
echo "USB boot check installed: put an empty file WM-FACTORY on a stick and reboot to go back to factory"
