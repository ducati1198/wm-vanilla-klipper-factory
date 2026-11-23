#!/bin/bash
# Put the load cell board (CELL) back to the ORIGINAL factory state: original factory firmware and original factory
# bootloader. Done in software over CAN, no Pico. (install.sh option 3 runs this.)
#
#   bash 4_restore_factory_bootloader.sh              firmware first (asks), then bootloader (asks)
#   bash 4_restore_factory_bootloader.sh --dry-run    only check and show what it would do
#
# AFTER this the board has the factory bootloader again: it cannot be flashed over CAN until
# 2_flash_app_can.sh / install.sh option 1 replaces the bootloader again.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_sudo.sh"
OLDBL="$HERE/firmware/KLP_CELL_WM_ZRU_20251223_162212_original_bootloader.bin"; OLD_MD5="7251e472575b1ff1028d25d4478a7050"
SOFT="$HERE/tools/cell_bl_soft.py"
FACTORY_NAME="KLP_CELL_WM_ZRU_20251223_162212"
MOON="http://127.0.0.1:7125"
CFGDIR="${CFGDIR:-$HOME/printer_data/config}"
DRY=0; UUID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --uuid) shift; UUID="$1" ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option $1"; exit 2 ;;
  esac
  shift
done
say() { echo "== $*"; }
die() { echo "STOP: $*"; exit 1; }
cur() { curl -s --max-time 5 "$MOON/printer/objects/query?mcu%20CELL" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["mcu CELL"]["mcu_version"])' 2>/dev/null; }

[ -f "$OLDBL" ] && [ "$(md5sum "$OLDBL" | cut -d' ' -f1)" = "$OLD_MD5" ] || die "the original bootloader file is missing or damaged"
[ -f "$SOFT" ] || die "tools/cell_bl_soft.py is missing"
[ -n "$UUID" ] || UUID=$(grep -rhA8 '^\[mcu CELL\]' "$CFGDIR" 2>/dev/null | awk -F': *' '/canbus_uuid/{print $2; exit}' | tr -d ' \r')
[ -n "$UUID" ] || die "no canbus_uuid of [mcu CELL] found in $CFGDIR (use --uuid ID or CFGDIR=...)"
ip -br link show can0 2>/dev/null | grep -q "UP" || die "can0 is not up"
PST=$(curl -s --max-time 5 "$MOON/printer/objects/query?print_stats" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["print_stats"]["state"])' 2>/dev/null || true)
case "$PST" in printing|paused) die "the printer is printing. Wait until it is finished.";; esac
KPY="$HOME/klippy-env/bin/python"; [ -x "$KPY" ] || KPY=python3
CUR="$(cur)"
say "CELL board CAN id: $UUID   firmware now: ${CUR:-unknown}"

echo
echo "This puts the board back to the original factory state."
echo "AFTER it, the board has the factory bootloader again and can NOT be flashed over CAN"
echo "(until install.sh option 1 replaces the bootloader again)."
echo
echo "RISK: replacing the bootloader takes 1 to 4 seconds (longer on the factory screen board). If the printer loses power, is switched off or"
echo "      unplugged in that time, the board can stop starting for good (only an SWD probe brings it back)."
echo "      Do NOT touch the printer or the power until it says it is finished."
echo "      You use this at your own risk; the author is not responsible for any damage."
echo

ask_sudo
if [ $DRY -eq 0 ]; then
  read -r -p "Put the board back to the original factory state (firmware and bootloader)? (yes/no) [no]: " A
  [[ "${A,,}" == "yes" || "${A,,}" == "y" ]] || die "cancelled, nothing changed"
fi

# 1. the factory firmware first (needs the CAN bootloader, so it must be done BEFORE the bootloader is put back)
if [ "$CUR" != "$FACTORY_NAME" ]; then
  say "step 1: the factory firmware is flashed first (over CAN), because after step 2 CAN flashing no longer works"
  if [ $DRY -eq 1 ]; then bash "$HERE/2_flash_app_can.sh" --factory --dry-run || exit $?
  else bash "$HERE/2_flash_app_can.sh" --factory --yes || die "the factory firmware was not flashed, nothing else was changed"; fi
else
  say "step 1: the board already runs the factory firmware"
fi

# 2. the original bootloader
sudo systemctl stop klipper; sleep 2
back() { sudo systemctl start klipper; }
PROBE="$(timeout 60 "$KPY" "$SOFT" "$UUID" probe 2>&1)"; echo "$PROBE" | sed 's/^/   /'
KIND="$(echo "$PROBE" | sed -n 's/^BOOTLOADER: //p')"
save_bl "$KIND"
case "$KIND" in
  factory) back; say "the board already has the original factory bootloader. Nothing to do."; exit 0 ;;
  new) ;;
  *) back; die "could not identify the bootloader of this board, nothing was changed" ;;
esac
if [ $DRY -eq 1 ]; then say "dry run: would now write $(basename "$OLDBL")"; back; exit 0; fi
timeout 120 "$KPY" "$SOFT" "$UUID" write "$OLDBL"; RC=$?
back
[ $RC -eq 0 ] && save_bl factory
[ $RC -eq 0 ] || die "the bootloader was not replaced (see the lines above). If it says DO NOT power off: run this script again now."
for i in $(seq 1 15); do sleep 3; N="$(cur)"; [ -n "$N" ] && break; done
say "done. Board firmware now: ${N:-not reported yet (look in Fluidd)}. The board has the original factory bootloader again."
