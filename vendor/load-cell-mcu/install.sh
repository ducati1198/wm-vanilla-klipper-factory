#!/bin/bash
# WonderMaker ZR Ultra-S / ZR Ultra, Raspberry Pi: menu to flash the load cell board (CELL) over CAN with the factory flash tool.
#
#   bash install.sh
#
#   1) Flash the newest patched firmware (V2)
#   2) Flash the original factory firmware (KLP_CELL_WM_ZRU_20251223_162212)
#   3) Put the board back to the original factory state (factory firmware + original factory bootloader)
#   b) Check which bootloader the board has (read only)
#   u) Update: check the version on GitHub, update this folder (git pull), then offer the newest firmware
#
# No extra hardware. If the board still has the factory bootloader, 2_flash_app_can.sh replaces it in software
# first (it asks once). Read README.md, "The one risk".
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"
ZR="$HERE/zr-ultra"
CAN="$ZR/2_flash_app_can.sh"
MOON="http://127.0.0.1:7125"
RAW="https://raw.githubusercontent.com/ducati1198/wm-load-cell-mcu/main"
API="https://api.github.com/repos/ducati1198/wm-load-cell-mcu/contents"
TARBALL="https://github.com/ducati1198/wm-load-cell-mcu/archive/refs/heads/main.tar.gz"
. "$ZR/lib_sudo.sh"
[ -f "$CAN" ] || { echo "zr-ultra/2_flash_app_can.sh is missing next to install.sh"; exit 1; }

local_version()  { tr -d ' \r\n' < "$ROOT/VERSION" 2>/dev/null || echo "?"; }
latest_fw()      { tr -d ' \r\n' < "$ZR/firmware/LATEST" 2>/dev/null; }
remote_version() {   # the GitHub API is always current; the raw address is cached for some minutes, so it is only the fallback
  local V
  V="$(curl -fsS --max-time 5 -H "Accept: application/vnd.github.raw+json" "$API/VERSION" 2>/dev/null | tr -d ' \r\n')"
  [ -n "$V" ] || V="$(curl -fsS --max-time 5 "$RAW/VERSION" 2>/dev/null | tr -d ' \r\n')"
  echo "$V"
}
current() {   # firmware name of the board; waits up to ~30 s while Klipper is still starting after a flash
  local i V
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    V="$(curl -s --max-time 5 "$MOON/printer/objects/query?mcu%20CELL" 2>/dev/null \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"]["mcu CELL"]["mcu_version"])' 2>/dev/null)"
    [ -n "$V" ] && { echo "$V"; return; }
    systemctl is-active --quiet klipper 2>/dev/null || return   # Klipper is not running: nothing to wait for
    sleep 2
  done
}
bl_state() {   # last known bootloader of the board (written by the scripts after a check, install or restore)
  local K T; { read -r K T < "$ROOT/.bootloader-state"; } 2>/dev/null || { echo "not checked yet (type b to check)"; return; }
  T="$(date -d "@$T" '+%Y-%m-%d %H:%M' 2>/dev/null)"
  case "$K" in
    new)     echo "NEW (CAN bootloader, PA11/PA12), checked $T" ;;
    factory) echo "FACTORY (original, not reachable over CAN), checked $T" ;;
    *)       echo "not checked yet (type b to check)" ;;
  esac
}
newer() { [ -n "$1" ] && [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }   # is $1 newer than $2

# firmware part of the update: is the newest firmware on the board?
firmware_check() {
  local NEWFW CUR; NEWFW="$(latest_fw)"; CUR="$(current)"
  echo
  echo "== Firmware: newest in this folder = ${NEWFW:-?}   on the board = ${CUR:-unknown (Klipper not running?)}"
  if [ -z "$CUR" ]; then echo "   The board firmware cannot be read, so it is not offered."; return; fi
  if [ "$CUR" = "$NEWFW" ]; then echo "   The board already runs the newest firmware."; return; fi
  echo "   The board does not run the newest firmware. Flashing it now (the script asks once before it changes anything)."
  bash "$CAN"
}

do_update() {
  local L R; L="$(local_version)"; R="$(remote_version)"
  echo
  if [ -n "$R" ]; then echo "== Version: this folder = v$L   on GitHub = v$R"; else echo "== Version: this folder = v$L   on GitHub = (could not reach GitHub)"; fi
  if [ -z "$R" ]; then echo "   Check the internet connection of the Pi, then try again."; firmware_check; return; fi
  if newer "$R" "$L"; then
    echo "   A newer version is on GitHub. Updating this folder..."
    if [ -d "$ROOT/.git" ]; then
      if ! git -C "$ROOT" pull --ff-only; then
        echo "STOP: git pull did not work (you changed files here?). Try:  cd $ROOT && git stash && git pull"
        return
      fi
    else
      local T; T="$(mktemp -d)"
      if curl -fsSL --max-time 120 "$TARBALL" | tar xz -C "$T" && [ -d "$T/wm-load-cell-mcu-main" ]; then
        cp -r "$T/wm-load-cell-mcu-main/." "$ROOT/" && echo "   Files updated from the GitHub download."
      else
        echo "STOP: the download failed, nothing was changed."; rm -rf "$T"; return
      fi
      rm -rf "$T"
    fi
    echo "   Now v$(local_version). What changed: $ROOT/CHANGELOG.md"
    exec bash "$HERE/install.sh" --firmware-check          # start the new menu code, then the firmware part
  else
    echo "   This folder is up to date."
  fi
  firmware_check
}

if [ "${1:-}" = "--firmware-check" ]; then firmware_check; fi

REMOTE="$(remote_version)"
while true; do
  CUR="$(current)"; VER="$(local_version)"; NEWFW="$(latest_fw)"
  echo
  echo "=========================================================="
  echo " WonderMaker load cell board (CELL) - flash over CAN   v$VER"
  echo " Board firmware now: ${CUR:-unknown (Klipper not running?)}"
  echo " Bootloader on the board: $(bl_state)"
  if newer "$REMOTE" "$VER"; then echo " NEW VERSION ON GITHUB: v$REMOTE  (type u to update)"; fi
  echo "=========================================================="
  echo "  1) Flash V2        ${NEWFW:-KLP_CELL_WM_ZRU_RPI_V2_20261117}"
  echo "  2) Flash factory   KLP_CELL_WM_ZRU_20251223_162212"
  echo "  3) Restore original (factory firmware + original bootloader)"
  echo "  b) Check the bootloader of the board now (read only, Klipper stops for about 30 s)"
  echo "  u) Update (check GitHub, update this folder, update the firmware)"
  echo "  q) Quit"
  read -r -p "Choose: " C
  case "$C" in
    1) ask_sudo; bash "$CAN" ;;
    2) ask_sudo; bash "$CAN" --factory ;;
    3) ask_sudo; bash "$ZR/4_restore_factory_bootloader.sh" ;;
    b|B) ask_sudo; bash "$CAN" --check ;;
    u|U) ask_sudo; do_update; REMOTE="$(remote_version)" ;;
    q|Q|"") exit 0 ;;
    *) echo "Please type 1, 2, 3, b, u or q." ;;
  esac
done
