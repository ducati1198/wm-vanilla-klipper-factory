#!/bin/bash
# Back to factory: delete what the vanilla install added, put the factory files back, reset the
# factory settings so the printer has to be calibrated again.
#   ./restore.sh --factory [--from DIR] [--yes] [--reboot]
#   ./restore.sh --list
# DIR = a folder holding the snapshot (the USB stick copy). Default: ~/wm-factory-snapshot
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/snapshot.sh"
FROM="$SNAP_DIR"; YES=0; REBOOT=0; DO=""
while [ $# -gt 0 ]; do case "$1" in
    --factory) DO=factory ;; --list) DO=list ;; --from) FROM="${2:-}"; shift ;; --yes) YES=1 ;; --reboot) REBOOT=1 ;;
    -h|--help) sed -n 2,8p "$0"; exit 0 ;; *) fail "unknown option: $1" ;;
esac; shift; done
[ "$DO" = list ] && { snapshot_exists && cat "$SNAP_DIR/MANIFEST" || say "no snapshot"; exit 0; }
[ "$DO" = factory ] || fail "use --factory (or --list). See --help."

print_active && fail "a print is running. Nothing changed."
snapshot_verify "$FROM" || fail "the snapshot in $FROM is missing or damaged (checksum). Nothing changed."
ok "snapshot checked: $FROM"
if [ "$YES" != 1 ]; then
    say "This DELETES everything the vanilla install added (Klipper, Moonraker, Fluidd, their configs and the installer files),"
    say "puts the factory files back, and resets the factory settings: the printer must be calibrated again."
    printf 'Type FACTORY to continue: '; read -r a; [ "$a" = FACTORY ] || fail "cancelled. Nothing changed."
fi

# 0. keep a copy of the current settings (small), then stop everything
KEEP="$HOME_DIR/wm-before-factory-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$KEEP" && [ -d "$HOME_DIR/printer_data/config" ] && cp -a "$HOME_DIR/printer_data/config" "$KEEP/" 2>/dev/null
ok "your current settings are copied to $KEEP (delete it when you do not need it)"
wipe_home_dir() {   # delete a folder of the home directory. printer_data keeps gcodes, timelapse and logs
    local d="$HOME_DIR/$1"; [ -e "$d" ] || return 0
    if [ "$1" = printer_data ]; then
        find "$d" -mindepth 1 -maxdepth 1 ! -name gcodes ! -name timelapse ! -name logs -exec rm -rf {} + 2>/dev/null
    else rm -rf "$d"; fi
}

# 1. stop everything
for s in $STACK_SERVICES makerbase-client; do $SUDO $SYSTEMCTL stop "$s" 2>/dev/null; done

# 2. delete what the vanilla install added: the installer's own record first, then the stack folders
MAN="$HOME_DIR/ultra-backup/installed.manifest"; [ -f "$MAN" ] || MAN="$(ls "$HOME_DIR"/*/installed.manifest 2>/dev/null | head -1)"
if [ -n "${MAN:-}" ] && [ -f "$MAN" ]; then
    while read -r kind path; do
        case "$kind" in
            HOMEDIR) [ -n "$path" ] && wipe_home_dir "$path" ;;
            DIR)     case "$path" in "$HOME_DIR"/*) rm -rf "$path" ;; esac ;;
            FILE)    [ -n "$path" ] && $SUDO rm -f "$SYS_ROOT$path" ;;
        esac
    done <"$MAN"
    ok "removed what the installer recorded ($MAN)"
else
    warn "no installer record found: only the stack folders are replaced"
fi
for i in $SNAP_HOME_ITEMS; do wipe_home_dir "$i"; done
rm -rf "$HOME_DIR/wm-vanilla-src" "$HOME_DIR/WM_Ultra_Vanilla_Klipper" "$HOME_DIR/WM_Ultra_Vanilla_Klipper-main"

# 3. put the factory files back
tar -C "$HOME_DIR" -xzf "$FROM/home.tar.gz" || fail "could not unpack home.tar.gz (the board may be half restored: run this again)"
[ -f "$FROM/system.tar.gz" ] && { $SUDO tar -C "$SYS_ROOT" -xzf "$FROM/system.tar.gz" || fail "could not unpack system.tar.gz"; }
$SUDO $SYSTEMCTL daemon-reload 2>/dev/null
ok "factory files back in place"

# 4. factory reset of the settings (what the factory app's reset does, plus the saved calibration)
FS="$HOME_DIR/TM_T1/factory_settings"; CFG="$HOME_DIR/printer_data/config"
if [ -d "$FS" ]; then
    mkdir -p "$CFG"
    OLD="$KEEP/config"
    if [ -x "$HOME_DIR/TM_T1/scripts/restore_factory_settings.sh" ] && [ -z "${WM_NO_FACTORY_SCRIPT:-}" ]; then
        bash "$HOME_DIR/TM_T1/scripts/restore_factory_settings.sh" >/dev/null 2>&1 && ok "factory settings script ran"
    fi
    for f in printer.cfg saved_variables.cfg tmt1.ini; do   # the script leaves these out: they hold the calibration
        [ -f "$FS/$f" ] && cp -a "$FS/$f" "$CFG/$f"
    done
    ok "factory settings and the factory calibration values restored: the printer must be calibrated again (previous files in $OLD)"
else
    warn "TM_T1/factory_settings not found: settings were NOT reset"
fi

# 5. services as they were
while read -r name en act; do
    case "$en" in enabled) $SUDO $SYSTEMCTL enable "$name" >/dev/null 2>&1 ;; disabled) $SUDO $SYSTEMCTL disable "$name" >/dev/null 2>&1 ;; esac
done <"$FROM/services.state"
while read -r name en act; do [ "$act" = active ] && $SUDO $SYSTEMCTL start "$name" 2>/dev/null; done <"$FROM/services.state"
ok "services set as before the install"
[ "$WARNINGS" = 0 ] || say "$WARNINGS warning(s): read them above."
if [ "$REBOOT" = 1 ]; then say "rebooting"; $SUDO reboot; else say "done. Reboot the board to finish: sudo reboot"; fi
