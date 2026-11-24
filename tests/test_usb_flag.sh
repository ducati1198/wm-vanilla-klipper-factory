#!/bin/bash
# Offline tests of the WM-FACTORY / WM-RESCUE USB boot check. Run: bash tests/test_usb_flag.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAILN=0
ck() { if eval "$2"; then PASS=$((PASS+1)); echo "ok   $1"; else FAILN=$((FAILN+1)); echo "FAIL $1"; fi; }
setup() {
    rm -rf "$T"/*; mkdir -p "$T/stick" "$T/home/wm-factory-snapshot" "$T/app"
    echo data >"$T/home/x"; tar -C "$T/home" -czf "$T/home/wm-factory-snapshot/home.tar.gz" x
    ( cd "$T/home/wm-factory-snapshot" && sha256sum home.tar.gz >SHA256SUMS )
    printf '#!/bin/bash\necho "restore $*" >>"%s/calls"; echo restoring\n' "$T" >"$T/restore.sh"; chmod +x "$T/restore.sh"
    printf '#!/bin/bash\necho reboot >>"%s/calls"\n' "$T" >"$T/reboot.sh"; chmod +x "$T/reboot.sh"
    export WM_USB_CONF=/nonexistent WM_HOME="$T/home" WM_USB_LOG="$T/usb.log" WM_RESTORE="$T/restore.sh" WM_REBOOT="$T/reboot.sh" WM_USB_MEDIA_DIR="$T/stick"
}
run() { bash "$HERE/usb_rescue/wm-usb-check" 2>&1; }

setup; run >/dev/null
ck "no flag: nothing runs"                       '[ ! -f "$T/calls" ]'
setup; touch "$T/stick/WM-FACTORY"; run >/dev/null
ck "WM-FACTORY runs restore --factory --yes"     'grep -q "restore --factory --yes --from $T/home/wm-factory-snapshot" "$T/calls"'
ck "board reboots after the restore"             'grep -q "^reboot" "$T/calls"'
ck "flag renamed to .done (no loop)"             '[ ! -e "$T/stick/WM-FACTORY" ] && [ -e "$T/stick/WM-FACTORY.done" ]'
ck "report written to the stick"                 'grep -q "restore finished, exit code 0" "$T/stick/WM-FACTORY-LOG.txt"'
setup; touch "$T/stick/wm-factory"; run >/dev/null
ck "flag name in lower case also works"          'grep -q "^restore" "$T/calls"'
setup; touch "$T/stick/WM-FACTORY"; mkdir -p "$T/stick/wm-factory-snapshot"; cp "$T/home/wm-factory-snapshot/"* "$T/stick/wm-factory-snapshot/"; run >/dev/null
ck "snapshot on the stick is preferred"          'grep -q "from $T/stick/wm-factory-snapshot" "$T/calls"'
setup; touch "$T/stick/WM-FACTORY"; echo bad >"$T/home/wm-factory-snapshot/home.tar.gz"; run >/dev/null
ck "damaged snapshot: nothing changed, no reboot" '[ ! -f "$T/calls" ] && grep -q "no snapshot that passes" "$T/stick/WM-FACTORY-LOG.txt" && [ -e "$T/stick/WM-FACTORY.done" ]'
setup; touch "$T/stick/WM-RESCUE"; run >/dev/null
ck "WM-RESCUE writes a report, restores nothing" '[ ! -f "$T/calls" ] && grep -q "snapshot on the board: ok" "$T/stick/WM-FACTORY-LOG.txt" && [ -e "$T/stick/WM-RESCUE.done" ]'
setup; touch "$T/stick/WM-FACTORY" "$T/stick/WM-RESCUE"; run >/dev/null
ck "both flags: WM-FACTORY wins"                 'grep -q "^restore" "$T/calls" && [ -e "$T/stick/WM-RESCUE" ]'
# installer of the boot check
setup; export WM_SYS_ROOT="$T/sys" WM_SUDO="" WM_SYSTEMCTL=true; unset WM_USB_MEDIA_DIR
bash "$HERE/usb_rescue/install.sh" >/dev/null
ck "install copies script, restore, unit, config" '[ -x "$T/sys/opt/wm-factory-rescue/wm-usb-check" ] && [ -f "$T/sys/opt/wm-factory-rescue/restore.sh" ] && [ -d "$T/sys/opt/wm-factory-rescue/lib" ] && [ -f "$T/sys/etc/systemd/system/wm-factory-usb.service" ] && grep -q WM_HOME "$T/sys/etc/default/wm-factory-usb"'
bash "$HERE/usb_rescue/install.sh" --remove >/dev/null
ck "remove deletes all of it"                    '[ ! -e "$T/sys/opt/wm-factory-rescue" ] && [ ! -e "$T/sys/etc/systemd/system/wm-factory-usb.service" ]'
echo; echo "passed $PASS, failed $FAILN"; [ "$FAILN" = 0 ]
