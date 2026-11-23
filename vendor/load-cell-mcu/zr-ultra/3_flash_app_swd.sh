#!/bin/bash
# OPTIONAL fallback: flash the load cell board (CELL) APPLICATION over SWD with the Pico (works with any bootloader,
# also with the original factory one). Only 0x08002000... is written, the bootloader is never touched.
#
# Wires (Pico -> SWD pads):  GP2 -> SWCLK,  GP3 -> SWDIO,  GND -> GND.  No 3.3 V wire.
#
#   bash 3_flash_app_swd.sh              back up, flash KLP_CELL_WM_ZRU_RPI_V2_20261117.bin, verify
#   bash 3_flash_app_swd.sh --factory    way back: flash the original KLP_CELL_WM_ZRU_20251223_162212.bin
#   bash 3_flash_app_swd.sh --bin FILE   flash another application file
#   bash 3_flash_app_swd.sh --dry-run    only check the probe and the board, write nothing
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
V2="$HERE/firmware/KLP_CELL_WM_ZRU_RPI_V2_20261117.bin";  V2_MD5="a202b3e1a7cab0d77c4c78ca65334945"
FAC="$HERE/firmware/KLP_CELL_WM_ZRU_20251223_162212.bin"; FAC_MD5="e1e4fbc247a306d7854640f22cb6409d"
BIN="$V2"; WANT="$V2_MD5"; DRY=0
MOON="http://127.0.0.1:7125"
OUT="${OUT:-$HOME/wm-load-cell-mcu-backups/cell-backup-$(date +%Y%m%d-%H%M%S)}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --factory) BIN="$FAC"; WANT="$FAC_MD5" ;;
    --bin) shift; BIN="$1"; WANT="" ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
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
[ "$SIZE" -lt 60000 ] || die "too big for the application area (application file, not a flash dump)"
command -v openocd >/dev/null || die "openocd is not installed (sudo apt install openocd)"
for f in interface/cmsis-dap.cfg target/stm32f1x.cfg; do
  [ -f "/usr/share/openocd/scripts/$f" ] || die "openocd script $f not found"
done
command -v lsusb >/dev/null && { lsusb | grep -qi "2e8a" || die "no Raspberry Pi Pico found on USB"; }
PST=$(curl -s --max-time 5 "$MOON/printer/objects/query?print_stats" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["print_stats"]["state"])' 2>/dev/null || true)
say "printer state: ${PST:-unknown}"
case "$PST" in printing|paused) die "the printer is printing. Wait until it is finished.";; esac
OCD=(openocd -f interface/cmsis-dap.cfg -c "set CPUTAPID 0" -f target/stm32f1x.cfg -c "adapter speed 1000")

if [ $DRY -eq 1 ]; then
  sudo systemctl stop klipper; sleep 2
  "${OCD[@]}" -c init -c "targets" -c shutdown; RC=$?
  sudo systemctl start klipper
  [ $RC -eq 0 ] && echo "The probe sees the board. Nothing was written." || echo "The probe does NOT see the board."
  exit $RC
fi
read -r -p "Heaters off, printer idle. Flash? (yes/no) [no]: " A; [[ "${A,,}" == "yes" || "${A,,}" == "y" ]] || die "cancelled, nothing changed"
mkdir -p "$OUT"; sudo systemctl stop klipper; sleep 2
say "1/3 backup of the whole flash to $OUT/cell_512k_backup.bin"
"${OCD[@]}" -c init -c "dump_image $OUT/cell_512k_backup.bin 0x08000000 0x80000" -c shutdown \
  || { sudo systemctl start klipper; die "backup failed, nothing was written"; }
say "2/3 flash (reset halt first)"
"${OCD[@]}" -c init -c "reset halt" \
  -c "flash write_image erase $BIN 0x08002000 bin" \
  -c "verify_image $BIN 0x08002000 bin" \
  -c "reset run" -c shutdown
RC=$?
sudo systemctl start klipper
[ $RC -eq 0 ] || { echo "The flash stopped with an error. The bootloader is never written: run this script again. Backup: $OUT"; exit $RC; }
say "3/3 check"
NEW=""
for i in $(seq 1 15); do
  sleep 3
  NEW=$(curl -s --max-time 5 "$MOON/printer/objects/query?mcu%20CELL" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["mcu CELL"]["mcu_version"])' 2>/dev/null || true)
  [ -n "$NEW" ] && break
done
say "board firmware now: ${NEW:-not reported yet (look in Fluidd)}"
echo "(openocd may print 'checksum mismatch - attempting binary compare' and then 'verified': that is normal.)"
echo "Backup: $OUT/cell_512k_backup.bin"
