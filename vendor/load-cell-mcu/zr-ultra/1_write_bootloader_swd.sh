#!/bin/bash
# STEP 1 (once per board): write the CAN bootloader that talks on PA11/PA12 into the load cell board (CELL)
# over SWD with a Raspberry Pi Pico running "debugprobe", and openocd on the printer's Raspberry Pi.
# Only the bootloader area (0x08000000...) is written. The application at 0x08002000 is not touched.
#
# Wires (Pico -> SWD pads of the load cell board):  GP2 -> SWCLK,  GP3 -> SWDIO,  GND -> GND.  No 3.3 V wire.
#
#   bash 1_write_bootloader_swd.sh              back up, write KLP_CELL_WM_ZRU_20251223_162212_new_bootloader.bin, verify
#   bash 1_write_bootloader_swd.sh --dry-run    only check the probe and the board, write nothing
#   bash 1_write_bootloader_swd.sh --factory    way back: write the original factory bootloader again
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
NEW="$HERE/firmware/KLP_CELL_WM_ZRU_20251223_162212_new_bootloader.bin"; NEW_MD5="49340e49d8fec9a74f76a8dce60eb6b0"
OLD="$HERE/firmware/KLP_CELL_WM_ZRU_20251223_162212_original_bootloader.bin"; OLD_MD5="7251e472575b1ff1028d25d4478a7050"
BIN="$NEW"; WANT="$NEW_MD5"; DRY=0
MOON="http://127.0.0.1:7125"
OUT="${OUT:-$HOME/wm-load-cell-mcu-backups/cell-backup-$(date +%Y%m%d-%H%M%S)}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --factory) BIN="$OLD"; WANT="$OLD_MD5" ;;
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
[ "$SUM" = "$WANT" ] || die "md5 should be $WANT (file damaged?)"
[ "$SIZE" -lt 8192 ] || die "a bootloader must be smaller than 8192 bytes"

command -v openocd >/dev/null || die "openocd is not installed (sudo apt install openocd)"
for f in interface/cmsis-dap.cfg target/stm32f1x.cfg; do
  [ -f "/usr/share/openocd/scripts/$f" ] || die "openocd script $f not found"
done
command -v lsusb >/dev/null && { lsusb | grep -qi "2e8a" || die "no Raspberry Pi Pico found on USB (plugged in, with the debugprobe firmware?)"; }

PST=$(curl -s --max-time 5 "$MOON/printer/objects/query?print_stats" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["print_stats"]["state"])' 2>/dev/null || true)
say "printer state: ${PST:-unknown}"
case "$PST" in printing|paused) die "the printer is printing. Wait until it is finished.";; esac

# the chip is a Cortex-M4 clone of the STM32F103, so the TAP id check is switched off (CPUTAPID 0)
OCD=(openocd -f interface/cmsis-dap.cfg -c "set CPUTAPID 0" -f target/stm32f1x.cfg -c "adapter speed 1000")

if [ $DRY -eq 1 ]; then
  say "dry run: reading the chip only (Klipper is stopped for a few seconds)"
  sudo systemctl stop klipper; sleep 2
  "${OCD[@]}" -c init -c "targets" -c "mdw 0x08000000 2" -c "mdw 0x08002000 2" -c shutdown; RC=$?
  sudo systemctl start klipper
  [ $RC -eq 0 ] && echo "The probe sees the board. Nothing was written." || echo "The probe does NOT see the board (check wires, printer on)."
  exit $RC
fi

echo "This stops Klipper for about a minute. Heaters off, printer idle."
read -r -p "Write $(basename "$BIN")? (yes/no) [no]: " A; [[ "${A,,}" == "yes" || "${A,,}" == "y" ]] || die "cancelled, nothing changed"
mkdir -p "$OUT"
sudo systemctl stop klipper; sleep 2
say "1/3 backup of the whole flash to $OUT/cell_512k_backup.bin"
"${OCD[@]}" -c init -c "dump_image $OUT/cell_512k_backup.bin 0x08000000 0x80000" -c shutdown \
  || { sudo systemctl start klipper; die "backup failed, nothing was written"; }
say "2/3 write (always reset halt first, else the board's watchdog resets the chip in the middle of the write)"
"${OCD[@]}" -c init -c "reset halt" \
  -c "flash write_image erase $BIN 0x08000000 bin" \
  -c "verify_image $BIN 0x08000000 bin" \
  -c "reset run" -c shutdown
RC=$?
[ $RC -eq 0 ] || { sudo systemctl start klipper; echo "The write stopped with an error. Run this script again. Backup: $OUT"; exit $RC; }
sleep 4
say "3/3 check: application must be unchanged"
"${OCD[@]}" -c init -c "dump_image $OUT/cell_after.bin 0x08000000 0x80000" -c "reset run" -c shutdown >/dev/null 2>&1
python3 - "$OUT/cell_512k_backup.bin" "$OUT/cell_after.bin" "$BIN" <<'PY'
import sys
a=open(sys.argv[1],"rb").read(); b=open(sys.argv[2],"rb").read(); n=open(sys.argv[3],"rb").read()
print("application (0x2000...) identical to before:", a[0x2000:]==b[0x2000:])
print("bootloader on the board equals the file    :", b[:len(n)]==n)
PY
sudo systemctl start klipper
echo "Done. Backup of the old flash: $OUT/cell_512k_backup.bin (keep it)."
if [ "$BIN" = "$NEW" ]; then echo "Next: bash 2_flash_app_can.sh   (flash over CAN, no Pico needed any more)"; fi
