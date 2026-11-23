#!/bin/bash
# Put the services back as the newest (or given) backup of install.sh had them.
#   ./restore.sh [--list] [BACKUP_DIR]
# It restores which services start at boot and the saved config files. It does not
# delete what the installer added (Klipper files stay on disk, only not started).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/common.sh"
if [ "${1:-}" = --list ]; then ls -1 "$BACKUP_ROOT" 2>/dev/null; exit 0; fi
BK="${1:-$(ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | tail -1)}"; BK="${BK%/}"
[ -n "$BK" ] && [ -f "$BK/services.state" ] || fail "no backup found in $BACKUP_ROOT. Nothing changed."
print_active && fail "a print is running. Nothing changed."
say "restoring from $BK"
SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo
# stop everything first, then bring back the saved boot state
while read -r name en act; do
    case "$name" in klipper|moonraker|nginx|crowsnest|klipper-mcu) $SUDO $SYSTEMCTL stop "$name" 2>/dev/null ;; esac
done <"$BK/services.state"
while read -r name en act; do
    case "$en" in enabled) $SUDO $SYSTEMCTL enable "$name" >/dev/null 2>&1 ;; disabled) $SUDO $SYSTEMCTL disable "$name" >/dev/null 2>&1 ;; esac
    [ "$act" = active ] && $SUDO $SYSTEMCTL start "$name" 2>/dev/null
    ok "$name: enabled=$en active=$act"
done <"$BK/services.state"
if [ -d "$BK/config" ]; then
    cp -a "$HOME_DIR/printer_data/config" "$HOME_DIR/printer_data/config.before-restore.$(date +%s)" 2>/dev/null
    cp -a "$BK/config/." "$HOME_DIR/printer_data/config/" && ok "config files restored (the current ones were kept as config.before-restore.*)"
fi
[ -f "$BK/KlipperScreen.conf" ] && cp -a "$BK/KlipperScreen.conf" "$HOME_DIR/printer_data/KlipperScreen.conf" && ok "KlipperScreen.conf restored"
say "done."
