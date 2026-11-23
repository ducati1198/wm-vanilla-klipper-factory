#!/bin/bash
# Flash the load cell board (CELL) application over CAN with the factory flashtool.py (Katapult tool, in tools/).
# No extra hardware. If the board still has the factory bootloader (which cannot be reached over CAN), it is first
# replaced in software through the running firmware (tools/cell_bl_soft.py); the script asks before it does that.
#
#   bash 2_flash_app_can.sh              flash the newest patched firmware (firmware/LATEST, now V2)
#   bash 2_flash_app_can.sh --factory    way back: flash the original KLP_CELL_WM_ZRU_20251223_162212.bin
#   bash 2_flash_app_can.sh --bin FILE   flash another application file
#   bash 2_flash_app_can.sh --yes        do not ask (used by 4_restore_factory_bootloader.sh)
#   bash 2_flash_app_can.sh --dry-run    check everything and show what it would do, change nothing
#   bash 2_flash_app_can.sh --uuid ID    CAN id of the board (default: canbus_uuid of [mcu CELL] in the printer config)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# the newest patched firmware is named in firmware/LATEST (so an update of the repo can bring a newer one)
LATEST="$(tr -d ' \r\n' < "$HERE/firmware/LATEST" 2>/dev/null)"; LATEST="${LATEST:-KLP_CELL_WM_ZRU_RPI_V2_20261117}"
V2="$HERE/firmware/$LATEST.bin"; V2_MD5="$(grep " firmware/$LATEST.bin\$" "$HERE/MD5SUMS" 2>/dev/null | cut -d' ' -f1)"
FAC="$HERE/firmware/KLP_CELL_WM_ZRU_20251223_162212.bin"; FAC_MD5="e1e4fbc247a306d7854640f22cb6409d"
BIN="$V2"; WANT="$V2_MD5"; DRY=0; UUID=""; YES=0; ASKED=0; CHECK=0
FT="$HERE/tools/flashtool.py"
MOON="http://127.0.0.1:7125"
CFGDIR="${CFGDIR:-$HOME/printer_data/config}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --yes) YES=1 ;;
    --check) CHECK=1 ;;
    --factory) BIN="$FAC"; WANT="$FAC_MD5" ;;
    --bin) shift; BIN="$1"; WANT="" ;;
    --uuid) shift; UUID="$1" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option $1"; exit 2 ;;
  esac
  shift
done
say() { echo "== $*"; }
die() { echo "STOP: $*"; exit 1; }

[ -f "$BIN" ] || die "file not found: $BIN"
SIZE=$(stat -c %s "$BIN"); SUM=$(md5sum "$BIN" | cut -d' ' -f1)
say "file $(basename "$BIN")  $SIZE bytes  md5 $SUM"
[ -z "$WANT" ] || [ "$SUM" = "$WANT" ] || die "md5 should be $WANT (file damaged?)"
[ "$SIZE" -lt 60000 ] || die "too big for the application area (this must be the application file, not a flash dump)"
[ -f "$FT" ] || die "tools/flashtool.py is missing"

[ -n "$UUID" ] || UUID=$(grep -rhA8 '^\[mcu CELL\]' "$CFGDIR" 2>/dev/null | awk -F': *' '/canbus_uuid/{print $2; exit}' | tr -d ' \r')
[ -n "$UUID" ] || die "no canbus_uuid of [mcu CELL] found in $CFGDIR (use --uuid ID or CFGDIR=...)"
say "CELL board CAN id: $UUID"
ip -br link show can0 2>/dev/null | grep -q "UP" || die "can0 is not up"

INFO=$(curl -s --max-time 5 "$MOON/printer/objects/query?mcu%20CELL&print_stats" || true)
CUR=$(echo "$INFO" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["mcu CELL"]["mcu_version"])' 2>/dev/null || true)
PST=$(echo "$INFO" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["print_stats"]["state"])' 2>/dev/null || true)
say "board firmware now: ${CUR:-unknown}   printer state: ${PST:-unknown}"
case "$PST" in printing|paused) die "the printer is printing. Wait until it is finished.";; esac

SOFT="$HERE/tools/cell_bl_soft.py"
NEWBL="$HERE/firmware/KLP_CELL_WM_ZRU_20251223_162212_new_bootloader.bin"
KPY="$HOME/klippy-env/bin/python"; [ -x "$KPY" ] || KPY=python3
PY=python3

. "$HERE/lib_sudo.sh"; ask_sudo
echo
echo "Klipper is stopped now for the check (and for the flash). Heaters off, printer idle."
sudo systemctl stop klipper; sleep 2
back() { sudo systemctl start klipper; }

# which bootloader is on the board? (read through the running application, nothing is written)
say "checking the bootloader of the board"
PROBE="$(timeout 60 "$KPY" "$SOFT" "$UUID" probe 2>&1)"; echo "$PROBE" | sed 's/^/   /'
KIND="$(echo "$PROBE" | sed -n 's/^BOOTLOADER: //p')"
save_bl "$KIND"
if [ $CHECK -eq 1 ]; then back; say "bootloader of the board: ${KIND:-unknown} (nothing was changed)"; exit 0; fi
case "$KIND" in
  new) say "the CAN bootloader is already on the board" ;;
  factory)
    echo
    echo "This board has the FACTORY bootloader, which cannot be reached over CAN (wrong pins)."
    echo "It is replaced now in software, through the running firmware: no Pico, no wires. It takes 1 to 4 seconds (longer on the factory screen board)."
    echo "RISK: if the printer loses power, is switched off or unplugged during that time, the board can stop"
    echo "      starting for good (only an SWD probe brings it back). Do NOT touch the printer or the power until"
    echo "      it says it is finished. You use this at your own risk; the author is not responsible for any damage."
    if [ $DRY -eq 1 ]; then
      say "dry run: would replace the bootloader with $(basename "$NEWBL"), then flash $(basename "$BIN")"
      back; exit 0
    fi
    if [ $YES -eq 0 ]; then read -r -p "Replace the bootloader AND flash $(basename "$BIN")? (yes/no) [no]: " A; [[ "${A,,}" == "yes" || "${A,,}" == "y" ]] || { back; die "cancelled, nothing changed"; }; fi; ASKED=1
    timeout 120 "$KPY" "$SOFT" "$UUID" write "$NEWBL"; RC=$?
    [ $RC -eq 0 ] || { back; die "the bootloader was not replaced (see the lines above). If it says DO NOT power off: run this script again now."; }
    save_bl new
    ;;
  *)
    # the application did not answer or the bootloader is not a known one: maybe the board already sits in the bootloader
    if timeout 20 $PY "$FT" -i can0 -q 2>&1 | grep -qi "$UUID.*Katapult"; then
      say "the board is waiting in its CAN bootloader"
    else
      back
      die "could not identify the bootloader of this board, nothing was changed. (Board not answering: power the printer off and on, then try again.)"
    fi ;;
esac

if [ $DRY -eq 1 ]; then
  say "dry run, would do:"
  echo "   $PY $FT -i can0 -u $UUID -r        (jump into the bootloader)"
  echo "   $PY $FT -i can0 -q                 (must list $UUID)"
  echo "   $PY $FT -i can0 -f $BIN -u $UUID -v"
  back; exit 0
fi
if [ $YES -eq 0 ] && [ $ASKED -eq 0 ]; then read -r -p "Flash $(basename "$BIN")? (yes/no) [no]: " A; [[ "${A,,}" == "yes" || "${A,,}" == "y" ]] || { back; die "cancelled (the firmware was not changed)"; }; fi

L="$(mktemp -d)"
say "1/4 jump into the bootloader"
timeout 20 $PY "$FT" -i can0 -u "$UUID" -r > "$L/r.log" 2>&1; cat "$L/r.log"
sleep 1
say "2/4 query"
timeout 20 $PY "$FT" -i can0 -q > "$L/q.log" 2>&1; cat "$L/q.log"
if ! grep -qi "$UUID" "$L/q.log"; then
  sudo systemctl start klipper
  echo "STOP: the bootloader did not answer. Nothing was written."
  echo "If the board does not come back on its own: power the printer off and on, then run this script again."
  exit 1
fi
say "3/4 flash"
timeout 150 $PY "$FT" -i can0 -f "$BIN" -u "$UUID" -v > "$L/f.log" 2>&1; RC=$?; tail -12 "$L/f.log"
say "flashtool exit code $RC"
sleep 3
sudo systemctl start klipper
say "4/4 check"
NEW=""
for i in $(seq 1 15); do
  sleep 3
  NEW=$(curl -s --max-time 5 "$MOON/printer/objects/query?mcu%20CELL" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["mcu CELL"]["mcu_version"])' 2>/dev/null || true)
  [ -n "$NEW" ] && break
done
say "board firmware now: ${NEW:-not reported yet (look in Fluidd)}"
[ $RC -eq 0 ] || { echo "The flash reported an error. Run this script again: the bootloader is still there and answers."; exit $RC; }
