#!/bin/bash
# Offline tests of snapshot.sh and restore.sh --factory with a fake home and a fake system root.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAILN=0
ck() { if eval "$2"; then PASS=$((PASS+1)); echo "ok   $1"; else FAILN=$((FAILN+1)); echo "FAIL $1"; fi; }
H="$T/h"; S="$T/sys"; USB="$T/usb"

mkfactory() {
    chmod -R u+w "$T" 2>/dev/null; rm -rf "$H" "$S" "$USB" "$T/bin"
    mkdir -p "$H/klipper" "$H/klippy-env" "$H/moonraker" "$H/fluidd" "$H/printer_data/config" "$H/printer_data/gcodes" "$H/printer_data/logs" \
             "$H/TM_T1/factory_settings" "$H/TM_T1/scripts" "$H/KlipperScreen" "$S/etc/systemd/system" "$S/etc/network/interfaces.d" "$S/etc/nginx" "$USB" "$T/bin"
    echo "factory klipper" >"$H/klipper/k.py"; echo big >"$H/printer_data/gcodes/huge.gcode"; echo log >"$H/printer_data/logs/klippy.log"
    echo "factory printer" >"$H/printer_data/config/printer.cfg"; echo "t0_offset = (0.0, 0.0, 0.0)" >"$H/printer_data/config/saved_variables.cfg"
    echo "led_open=1" >"$H/printer_data/config/tmt1.ini"; echo "macros factory" >"$H/printer_data/config/macros.cfg"
    cp "$H/printer_data/config/"* "$H/TM_T1/factory_settings/"
    printf '#!/bin/bash\ncp /dev/null /dev/null\ncp "$(dirname "$0")/../factory_settings/macros.cfg" "$HOME/printer_data/config/"\n' >"$H/TM_T1/scripts/restore_factory_settings.sh"
    chmod +x "$H/TM_T1/scripts/restore_factory_settings.sh"
    echo "[Unit] factory klipper" >"$S/etc/systemd/system/klipper.service"; echo "nginx factory" >"$S/etc/nginx/nginx.conf"
    echo "bitrate 1000000" >"$S/etc/network/interfaces.d/can0"
    printf 'Rockchip RK3308B-S evb\0' >"$T/model"; printf 'MemTotal: 498688 kB\nMemAvailable: 349184 kB\n' >"$T/meminfo"
    cat >"$T/bin/systemctl" <<'X'
#!/bin/bash
echo "$@" >>"$FAKE_LOG"
case "$1" in is-enabled) case "$2" in klipper|moonraker|nginx) echo enabled;; *) echo disabled;; esac;; is-active) case "$2" in klipper|moonraker) echo active;; *) echo inactive;; esac;; esac; exit 0
X
    printf '#!/bin/bash\necho "{\\"result\\":{\\"status\\":{\\"print_stats\\":{\\"state\\": \\"${FAKE_PRINT:-standby}\\"}}}}"\n' >"$T/bin/curl"; chmod +x "$T/bin/"*
    export FAKE_LOG="$T/fake.log"; : >"$FAKE_LOG"
    export WM_HOME="$H" HOME="$H" WM_SYS_ROOT="$S" WM_SUDO="" WM_SYSTEMCTL="$T/bin/systemctl" WM_CURL="$T/bin/curl" WM_PROC_MODEL="$T/model" WM_MEMINFO="$T/meminfo" WM_USB_DIR="$USB" FAKE_PRINT=standby
}
vanilla_install() {   # what an install changes
    echo "vanilla klipper" >"$H/klipper/k.py"; mkdir -p "$H/uvtool" "$H/ultra-backup" "$H/wm-vanilla-src" "$H/WM_Ultra_Vanilla_Klipper"; echo v >"$H/uvtool/u"
    echo "calibrated" >"$H/printer_data/config/printer.cfg"; echo "t0_offset = (0.12, -0.3, 0.05)" >"$H/printer_data/config/saved_variables.cfg"
    echo "my macros" >"$H/printer_data/config/macros.cfg"; echo "vanilla.cfg" >"$H/printer_data/config/rpi_base.cfg"
    echo "[Unit] vanilla" >"$S/etc/systemd/system/wm-light.path"; echo "[Unit] vanilla klipper" >"$S/etc/systemd/system/klipper.service"
    printf 'HOMEDIR uvtool\nFILE /etc/systemd/system/wm-light.path\nDIR %s/WM_Ultra_Vanilla_Klipper\n' "$H" >"$H/ultra-backup/installed.manifest"
}
snap() { bash "$HERE/snapshot.sh" "$@" 2>&1; }
rest() { bash "$HERE/restore.sh" "$@" 2>&1; }

mkfactory; out="$(snap create)"; rc=$?
ck "snapshot create passes"                    '[ $rc = 0 ] && [ -f "$H/wm-factory-snapshot/home.tar.gz" ] && [ -f "$H/wm-factory-snapshot/system.tar.gz" ]'
ck "snapshot has checksums that match"         'snap verify | grep -q "complete"'
ck "gcodes and logs are not in the snapshot"   '! tar -tzf "$H/wm-factory-snapshot/home.tar.gz" | grep -q "huge.gcode\|klippy.log"'
ck "system files are in the snapshot"          'tar -tzf "$H/wm-factory-snapshot/system.tar.gz" | grep -q "etc/network/interfaces.d/can0"'
ck "services state saved"                      'grep -q "klipper enabled active" "$H/wm-factory-snapshot/services.state"'
echo "changed" >"$H/klipper/k.py"; out="$(snap create)"
ck "second create keeps the first snapshot"    'grep -q "already exists" <<<"$out" && tar -xzOf "$H/wm-factory-snapshot/home.tar.gz" klipper/k.py | grep -q "factory klipper"'

mkfactory; snap create >/dev/null; out="$(snap usb)"; rc=$?
ck "usb copy passes and is checked"            '[ $rc = 0 ] && [ -f "$USB/wm-factory-snapshot/home.tar.gz" ] && [ -f "$USB/wm-factory-snapshot/README.txt" ] && [ -f "$H/wm-factory-snapshot/home.tar.gz" ]'
mkfactory; export WM_USB_DIR=""; snap create >/dev/null; out="$(WM_USB_DIR="$T/nonexistent" snap usb)"; rc=$?
ck "no stick: clear message"                   '[ $rc != 0 ] || grep -q "copy to\|no USB" <<<"$out"'

# full cycle
mkfactory; snap create >/dev/null; vanilla_install
out="$(rest --factory --yes)"; rc=$?
ck "factory restore passes"                    '[ $rc = 0 ] && grep -q "done" <<<"$out"'
ck "vanilla klipper replaced by factory"       '[ "$(cat "$H/klipper/k.py")" = "factory klipper" ]'
ck "everything the installer recorded is gone" '[ ! -e "$H/uvtool" ] && [ ! -e "$S/etc/systemd/system/wm-light.path" ] && [ ! -e "$H/WM_Ultra_Vanilla_Klipper" ] && [ ! -e "$H/wm-vanilla-src" ]'
ck "factory system files are back"             'grep -q "factory klipper" "$S/etc/systemd/system/klipper.service"'
ck "settings are factory: calibration reset"   '[ "$(cat "$H/printer_data/config/saved_variables.cfg")" = "t0_offset = (0.0, 0.0, 0.0)" ] && [ "$(cat "$H/printer_data/config/printer.cfg")" = "factory printer" ] && [ "$(cat "$H/printer_data/config/macros.cfg")" = "macros factory" ]'
ck "the old calibrated files were saved"       'grep -rq "0.12" "$H"/wm-before-factory-restore-*/config/saved_variables.cfg'
ck "services set as before"                    'grep -q "enable klipper" "$FAKE_LOG" && grep -q "start moonraker" "$FAKE_LOG" && grep -q "stop klipper" "$FAKE_LOG"'
ck "gcodes were not touched"                   '[ -f "$H/printer_data/gcodes/huge.gcode" ]'

# from the USB copy when the board's own copy is gone
mkfactory; snap create >/dev/null; snap usb >/dev/null; vanilla_install; chmod -R u+w "$H/wm-factory-snapshot"; rm -rf "$H/wm-factory-snapshot"
out="$(rest --factory --yes --from "$USB/wm-factory-snapshot")"; rc=$?
ck "restore works from the USB copy alone"     '[ $rc = 0 ] && [ "$(cat "$H/klipper/k.py")" = "factory klipper" ]'

# safety
mkfactory; snap create >/dev/null; vanilla_install; chmod u+w "$H/wm-factory-snapshot/home.tar.gz"; echo junk >>"$H/wm-factory-snapshot/home.tar.gz"
out="$(rest --factory --yes)"; rc=$?
ck "damaged snapshot: stops, nothing changed"  '[ $rc != 0 ] && grep -q "damaged" <<<"$out" && [ "$(cat "$H/klipper/k.py")" = "vanilla klipper" ] && [ -d "$H/uvtool" ]'
mkfactory; snap create >/dev/null; vanilla_install; out="$(FAKE_PRINT=printing rest --factory --yes)"; rc=$?
ck "print running: stops, nothing changed"     '[ $rc != 0 ] && [ -d "$H/uvtool" ]'
mkfactory; snap create >/dev/null; vanilla_install; out="$(echo no | rest --factory)"; rc=$?
ck "no confirmation: stops, nothing changed"   '[ $rc != 0 ] && [ -d "$H/uvtool" ]'
mkfactory; out="$(rest --factory --yes)"; rc=$?
ck "no snapshot: stops"                        '[ $rc != 0 ]'

echo; echo "passed $PASS, failed $FAILN"; [ "$FAILN" = 0 ]
