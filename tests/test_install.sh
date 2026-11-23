#!/bin/bash
# Offline tests: fake board files and fake commands. Run: bash tests/test_install.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAILN=0
ck() { if eval "$2"; then PASS=$((PASS+1)); echo "ok   $1"; else FAILN=$((FAILN+1)); echo "FAIL $1"; fi; }

mkfake() {   # fresh fake home + fake commands
    rm -rf "$T/h" "$T/bin"; mkdir -p "$T/h/printer_data/config" "$T/bin" "$T/sys/etc/network/interfaces.d"; mkdir -p "$T/h/klipper"; echo f >"$T/h/klipper/x"
    echo "factory cfg" >"$T/h/printer_data/config/printer.cfg"
    echo "ks" >"$T/h/printer_data/KlipperScreen.conf"
    printf 'Rockchip RK3308B-S evb analog mic v11 board\0' >"$T/model"
    printf 'MemTotal: 498688 kB\nMemAvailable: 349184 kB\n' >"$T/meminfo"
    cat >"$T/bin/systemctl" <<'S'
#!/bin/bash
echo "$@" >>"$FAKE_LOG"
case "$1" in
  is-enabled) case "$2" in KlipperScreen) echo enabled;; *) echo disabled;; esac ;;
  is-active)  case "$2" in KlipperScreen) echo active;;  *) echo inactive;; esac ;;
esac
exit 0
S
    printf '#!/bin/bash\necho "${FAKE_PRINT:-standby}" | sed "s/.*/{\\"result\\":{\\"status\\":{\\"print_stats\\":{\\"state\\": \\"&\\"}}}}/"\n' >"$T/bin/curl"
    cat >"$T/bin/git" <<'S'
#!/bin/bash
echo "git $*" >>"$FAKE_LOG"
if [ "$1" = clone ]; then
  d="${@: -1}"; mkdir -p "$d/.git"
  printf '#!/bin/bash\necho "$@" >>"$REC"\n' >"$d/installer.sh"; chmod +x "$d/installer.sh"
fi
exit 0
S
    chmod +x "$T/bin/"*
    export FAKE_LOG="$T/fake.log" REC="$T/installer.args"; : >"$FAKE_LOG"; rm -f "$REC"
    export WM_HOME="$T/h" WM_PROC_MODEL="$T/model" WM_MEMINFO="$T/meminfo" WM_UNAME_M=aarch64 \
           WM_SYSTEMCTL="$T/bin/systemctl" WM_CURL="$T/bin/curl" WM_GIT="$T/bin/git" WM_ALLOW_ROOT=1 \
           WM_FAKE_CAN0=1 WM_SYS_ZRAM="$T/nozram" WM_SYS_ZRAM0="$T/nozram0" WM_SUDO="" WM_SYS_ROOT="$T/sys" WM_SRC_DIR="$T/h/src" FAKE_PRINT=standby
}
run() { bash "$HERE/$1" "${@:2}" 2>&1; }

mkfake; out="$(run install.sh --check)"; rc=$?
ck "check on the right board passes"          '[ $rc = 0 ] && grep -q "board: Rockchip RK3308B" <<<"$out"'
ck "check changes nothing"                     '[ ! -d "$T/h/wm-factory-snapshot" ] && [ ! -d "$T/h/src" ]'

mkfake; printf 'Raspberry Pi 4 Model B\0' >"$T/model"; out="$(run install.sh --check)"; rc=$?
ck "wrong board stops"                         '[ $rc != 0 ] && grep -q "only for the RK3308B" <<<"$out"'
mkfake; printf 'MemTotal: 204800 kB\nMemAvailable: 100000 kB\n' >"$T/meminfo"; out="$(run install.sh --check)"; rc=$?
ck "low RAM stops"                             '[ $rc != 0 ] && grep -q "RAM" <<<"$out"'
mkfake; export WM_UNAME_M=armv7l; out="$(run install.sh --check)"; rc=$?
ck "32-bit stops"                              '[ $rc != 0 ] && grep -q "not 64-bit" <<<"$out"'
mkfake; export FAKE_PRINT=printing; out="$(run install.sh --yes)"; rc=$?
ck "a running print stops the install"         '[ $rc != 0 ] && grep -q "print is running" <<<"$out" && [ ! -d "$T/h/wm-factory-snapshot" ]'
mkfake; unset WM_FAKE_CAN0; out="$(run install.sh --check)"; rc=$?
ck "no can0 is a warning, not a stop"          '[ $rc = 0 ] && grep -q "no can0" <<<"$out"'

mkfake; out="$(run install.sh --dry-run)"; rc=$?
ck "dry run passes"                            '[ $rc = 0 ] && grep -q "dry run done" <<<"$out"'
ck "dry run: lean flags present"               'for f in "--screen off" "--network-manager off" "--obico off" "--octoapp off" "--octoeverywhere off" "--webcam off" "--timelapse off" "--dry-run"; do grep -q -- "$f" <<<"$out" || exit 1; done'
ck "dry run: no screen on, no backup, no clone" '! grep -q -- "--screen on" <<<"$out" && [ ! -d "$T/h/wm-factory-snapshot" ] && ! grep -q "^git clone" "$FAKE_LOG"'

mkfake; out="$(run install.sh --yes --webcam on --model ultra -- --acepro off)"; rc=$?
ck "install passes"                            '[ $rc = 0 ]'
ck "installer got the lean arguments"          'a="$(cat "$REC")"; for f in "--model ultra" "--screen off" "--network-manager off" "--obico off" "--octoapp off" "--octoeverywhere off" "--webcam on" "--yes" "--acepro off"; do grep -q -- "$f" <<<"$a" || exit 1; done'
ck "pinned version is cloned"                  'grep -q "clone --depth 1 --branch v2.25.2" "$FAKE_LOG"'
ck "snapshot saved before the install and checked"       '[ -f "$T/h/wm-factory-snapshot/home.tar.gz" ] && ( cd "$T/h/wm-factory-snapshot" && sha256sum -c --quiet SHA256SUMS )'
ck "KlipperScreen is not touched by install"   '! grep -q "disable KlipperScreen\|stop KlipperScreen" "$FAKE_LOG"'

mkfake; out="$(run install.sh --check --swap zram)"; mkfake; out="$(run install.sh --dry-run --swap zram)"; rc=$?
ck "zram asked but kernel has none stops"      '[ $rc != 0 ] && grep -q "no zram" <<<"$out"'
mkfake; mkdir -p "$T/zram"; export WM_SYS_ZRAM="$T/zram"; out="$(run install.sh --dry-run)"
ck "auto swap uses zram when the kernel has it" 'grep -q "swap: zram" <<<"$out"'

echo; echo "passed $PASS, failed $FAILN"; [ "$FAILN" = 0 ]
