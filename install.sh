#!/bin/bash
# wm-vanilla-klipper-factory: run vanilla Klipper + Moonraker + Fluidd on the factory
# WonderMaker ZR Ultra-S screen board (TM-T1, RK3308B, 512 MB).
# It checks the board, saves the factory state, then runs the WM_Ultra_Vanilla_Klipper
# installer with a LEAN profile (no KlipperScreen, no NetworkManager, no Obico,
# no OctoApp, no OctoEverywhere: they cost RAM this board does not have).
#
#   ./install.sh --check              look only, change nothing
#   ./install.sh --dry-run            show what would change, change nothing
#   ./install.sh                      install (asks once)
#   ./install.sh --yes                install without the question
#   ./install.sh --webcam on|off      crowsnest webcam (default off: ~50 MB)
#   ./install.sh --model ultra|ultra-s  printer model (default ultra-s)
#   ./install.sh --ref TAG            version of WM_Ultra_Vanilla_Klipper (default $DEFAULT_REF)
#   ./install.sh --swap auto|zram|off  compressed swap (default auto: only if the kernel has zram)
#   ./install.sh -- ARGS              extra arguments for the vanilla installer
# NOT TESTED ON THE PRINTER YET (branch: testing).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/common.sh"

DEFAULT_REF="v2.25.2"
SRC_URL="${WM_SRC_URL:-https://github.com/ducati1198/WM_Ultra_Vanilla_Klipper}"
SRC_DIR="${WM_SRC_DIR:-$HOME_DIR/wm-vanilla-src}"
MIN_RAM_MB=400; MIN_DISK_MB=1500

MODE=install; YES=0; WEBCAM=off; MODEL=ultra-s; REF="$DEFAULT_REF"; SWAP=auto; EXTRA=()
while [ $# -gt 0 ]; do case "$1" in
    --check) MODE=check ;;  --dry-run) MODE=dry ;;  --yes) YES=1 ;;
    --webcam) WEBCAM="${2:-}"; shift ;;  --model) MODEL="${2:-}"; shift ;;
    --ref) REF="${2:-}"; shift ;;        --swap) SWAP="${2:-}"; shift ;;
    -h|--help) sed -n 2,19p "$0"; exit 0 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) fail "unknown option: $1 (try --help)" ;;
esac; shift; done
case "$WEBCAM" in on|off) ;; *) fail "--webcam needs on or off" ;; esac
case "$MODEL" in ultra|ultra-s) ;; *) fail "--model needs ultra or ultra-s" ;; esac
case "$SWAP" in auto|zram|off) ;; *) fail "--swap needs auto, zram or off" ;; esac

say "== wm-vanilla-klipper-factory ($MODE) =="

# ---- 1. is this the right board? -------------------------------------------
[ "$(id -u)" != 0 ] || [ -n "${WM_ALLOW_ROOT:-}" ] || fail "run this as your normal user (t13dp), not root. It asks for sudo when needed."
[ "$UNAME_M" = aarch64 ] || fail "this is $UNAME_M, not 64-bit ARM. Nothing changed."
M="$(board_model)"
case "$M" in *RK3308*) ok "board: $M" ;; *) fail "unknown board: '${M:-none}'. This project is only for the RK3308B screen board. Nothing changed." ;; esac
R="$(ram_mb)"; [ "${R:-0}" -ge "$MIN_RAM_MB" ] || fail "only ${R:-?} MB RAM (need $MIN_RAM_MB)."
ok "memory: $R MB total, $(avail_mb) MB available"
D="$(disk_free_mb)"; [ "${D:-0}" -ge "$MIN_DISK_MB" ] || fail "only ${D:-?} MB free on disk (need $MIN_DISK_MB). Free space first."
ok "disk: $D MB free"

# ---- 2. safe to touch? ------------------------------------------------------
if print_active; then fail "a print is running or paused. Wait for it to end. Nothing changed."; fi
ok "no print running"
if ip link show can0 >/dev/null 2>&1 || [ -n "${WM_FAKE_CAN0:-}" ]; then ok "can0 is up"
else warn "no can0: the main MCU USB cable is not on this board (or gs_usb did not load). Klipper cannot reach the printer until it is."; fi
for s in $STACK_SERVICES; do say "      $s: enabled=$(service_enabled $s) active=$(service_active $s)"; done
[ "$(service_active klipper)" != active ] || warn "klipper is already running on this board."

[ "$MODE" = check ] && { say "check done: $WARNINGS warning(s). Nothing changed."; exit 0; }

# ---- 3. swap (only when the kernel can do it) ------------------------------------
swap_plan() {
    case "$SWAP" in off) echo off ;; zram) echo zram ;;
        auto) if [ -d "${WM_SYS_ZRAM:-/sys/module/zram}" ] || [ -e "${WM_SYS_ZRAM0:-/sys/block/zram0}" ]; then echo zram; else echo off; fi ;; esac
}
SP="$(swap_plan)"
if [ "$SP" = zram ] && ! [ -d "${WM_SYS_ZRAM:-/sys/module/zram}" ] && ! [ -e "${WM_SYS_ZRAM0:-/sys/block/zram0}" ]; then
    fail "--swap zram asked, but this kernel has no zram. Use --swap off."
fi
say "      swap: $SP$([ "$SP" = off ] && echo ' (this kernel has no zram: no swap is added)')"

# ---- 4. the command that will run --------------------------------------------
CMD=(./installer.sh --model "$MODEL" --screen off --network-manager off --obico off --octoapp off
     --octoeverywhere off --webcam "$WEBCAM" --timelapse off)
[ "$YES" = 1 ] && CMD+=(--yes)
[ "$MODE" = dry ] && CMD+=(--dry-run)
CMD+=("${EXTRA[@]}")
say "      source: $SRC_URL @ $REF -> $SRC_DIR"
say "      command: ${CMD[*]}"

# ---- 5. backup the factory state ----------------------------------------------
BK="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
if [ "$MODE" = dry ]; then say "      would back up the factory state to $BK"
else
    if [ "$YES" != 1 ]; then
        printf 'Install vanilla Klipper on this board now? Klipper, Moonraker and Fluidd will be set up. [yes/NO] '
        read -r a; [ "$a" = yes ] || fail "cancelled. Nothing changed."
    fi
    mkdir -p "$BK" || fail "cannot create $BK"
    : >"$BK/services.state"
    for s in $STACK_SERVICES; do echo "$s $(service_enabled $s) $(service_active $s)" >>"$BK/services.state"; done
    for f in printer_data/config printer_data/KlipperScreen.conf; do
        [ -e "$HOME_DIR/$f" ] && cp -a "$HOME_DIR/$f" "$BK/" 2>/dev/null
    done
    [ -e /etc/network/interfaces.d/can0 ] && cp -a /etc/network/interfaces.d/can0 "$BK/can0.interfaces"
    echo "$(date -Is) $M" >"$BK/MANIFEST"
    ok "factory state saved: $BK"
fi

# ---- 6. get the installer and run it --------------------------------------------
if [ "$MODE" = dry ] && [ ! -d "$SRC_DIR/.git" ] && [ -z "${WM_FORCE_FETCH:-}" ]; then
    say "      would clone $SRC_URL at $REF into $SRC_DIR, then run the command above with --dry-run"
else
    if [ ! -d "$SRC_DIR/.git" ]; then
        $GIT clone --depth 1 --branch "$REF" "$SRC_URL" "$SRC_DIR" || fail "could not download the installer ($SRC_URL @ $REF)."
    else
        ( cd "$SRC_DIR" && $GIT fetch -q --depth 1 origin tag "$REF" && $GIT checkout -q "$REF" ) || fail "could not switch $SRC_DIR to $REF."
    fi
    ( cd "$SRC_DIR" && "${CMD[@]}" ) || fail "the vanilla installer stopped with an error (see above). Restore: ./restore.sh"
fi

# ---- 7. report -----------------------------------------------------------------
say "      memory now: $(avail_mb) MB available of $(ram_mb) MB"
[ "$MODE" = dry ] && say "dry run done: nothing changed." || ok "done. Restore the factory state any time with ./restore.sh"
[ "$WARNINGS" = 0 ] || say "$WARNINGS warning(s): read them above."
exit 0
