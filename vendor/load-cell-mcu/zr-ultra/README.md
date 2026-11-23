WonderMaker ZR Ultra-S and ZR Ultra  -  load cell board (CELL) firmware V2 and flashing over CAN
===================================================================================

Credit: the idea and the first steps come from ducati1198 (Discord, GitHub name "ducati1198").
Thank you. Everything here was tested on a WonderMaker ZR Ultra-S, from a Raspberry Pi and from the WonderMaker factory screen board (2026-11-18).

WHAT IS IN HERE
  firmware/KLP_CELL_WM_ZRU_20251223_162212.bin
        the FACTORY application of the load cell board, read out of a real board (46732 bytes). Your way back.
  firmware/KLP_CELL_WM_ZRU_RPI_V2_20261117.bin
        the patched application (V2, 46814 bytes), made from the factory file above.
  firmware/KLP_CELL_WM_ZRU_20251223_162212_original_bootloader.bin
        the FACTORY bootloader of the board (3154 bytes). Way back for the bootloader.
  firmware/KLP_CELL_WM_ZRU_20251223_162212_new_bootloader.bin
        a new bootloader (CanBoot, 3798 bytes) that talks CAN on the pins the board really uses (PA11/PA12).
  bootloader_source/   config, patch and commit of that bootloader (CanBoot is GPLv3, source is yours)
  tools/flashtool.py   the factory flash tool (Katapult flashtool, GPLv3, Eric Callahan), unchanged copy
  ../install.sh               the menu (in the main folder of the repo): 1) V2  2) factory  3) restore  b) check bootloader  u) update
  4_restore_factory_bootloader.sh  menu option 3: original firmware + original bootloader, in software
  2_flash_app_can.sh          flash over CAN from the printer's Raspberry Pi or the factory screen board, no extra hardware
  lib_sudo.sh                 asks for the sudo password once; remembers the bootloader state
  firmware/LATEST             name of the newest patched firmware
  tools/cell_bl_soft.py       replaces the bootloader in software (used by 2_flash_app_can.sh)
  1_write_bootloader_swd.sh   rescue only: write a bootloader over SWD with a Pico
  3_flash_app_swd.sh          rescue only: write the application over SWD with a Pico
  ANALYSIS.md         notes about the board and the firmware
  SHA256SUMS / MD5SUMS  check your download

HOW IT WORKS
  The factory bootloader of the load cell board switches its CAN pins to PB8/PB9, but the board is wired to
  PA11/PA12. So the factory bootloader can never answer on CAN, and a normal "flash over CAN" cannot work.
  The running firmware (Klipper) does talk on the right pins, and it has Klipper's debug commands
  (debug_read / debug_write). tools/cell_bl_soft.py uses them to replace the bootloader in software:
  it unlocks the flash of the chip, erases the two bootloader pages, writes the new bootloader and reads
  it back. The new bootloader uses PA11/PA12 and keeps the same CAN id. After that every flash goes over CAN.
  NO Pico, NO wires, NO soldering.

HOW TO FLASH
  bash ../install.sh             menu: 1) flash V2   2) flash the original factory firmware
                                       3) restore the original (factory firmware + original bootloader)
                                       b) check the bootloader   u) update (GitHub version, git pull, firmware)
  or directly (from this folder):
  bash 2_flash_app_can.sh --check          only shows which bootloader the board has (read only)
  bash 2_flash_app_can.sh --dry-run        checks only, changes nothing (Klipper stops for a few seconds)
  bash 2_flash_app_can.sh                  flash V2
  bash 2_flash_app_can.sh --factory        way back: factory application
  The script reads the CAN id from [mcu CELL] in ~/printer_data/config, stops Klipper, looks which bootloader
  is on the board, replaces it if it is the factory one (it asks first), jumps into the bootloader, flashes,
  verifies, starts Klipper and prints the new firmware name. The printer must be idle, heaters off.

THE ONE RISK
  Replacing the bootloader takes about 1.2 seconds on a Raspberry Pi and about 4 seconds on the factory screen board. At the start of it (about 0.2 s on a Raspberry Pi, longer on the screen board) the board has no bootloader.
  If the printer loses power or is switched off in that moment, the board does not start again and only an
  SWD probe (1_write_bootloader_swd.sh) can bring it back. Do not touch the printer while it writes.
  If the tool says the read-back differs, it writes again by itself; never power off in between.
  The tool refuses to write if the firmware, the chip or the bootloader on the board is not one it knows.

WAY BACK  (everything is reversible)
  application:  bash 2_flash_app_can.sh --factory
  bootloader :  sudo systemctl stop klipper
                ~/klippy-env/bin/python tools/cell_bl_soft.py UUID write firmware/KLP_CELL_WM_ZRU_20251223_162212_original_bootloader.bin
                sudo systemctl start klipper
                (flash the application you want BEFORE this: with the factory bootloader CAN flashing is gone again)
  The old bootloader area is saved to ~/wm-load-cell-mcu-backups/cell-bootloader-before-DATE.bin before every bootloader write.

RESCUE WITH A PROBE  (only if something went wrong; not needed normally)
  A Raspberry Pi Pico with the "debugprobe" firmware and openocd on the printer's Pi.
  Wires Pico -> SWD pads of the load cell board:  GP2 -> SWCLK,  GP3 -> SWDIO,  GND -> GND  (no 3.3 V wire)
  bash 1_write_bootloader_swd.sh [--factory]     write the new (or the factory) bootloader
  bash 3_flash_app_swd.sh [--factory]            write the application
  Both save the whole flash to ~/wm-load-cell-mcu-backups/cell-backup-DATE/ first.

WARNINGS
  - You do this at your own risk. The author (ducati1198) is not responsible for any damage. Nothing here is from WonderMaker.
  - DO NOT LOSE POWER while the bootloader is written (1 to 4 seconds): the board can stop starting for good.
    Do not switch off, unplug or touch the printer until the tool says it is finished. Use stable power.
  - Tested on ONE board. If your board is different the tool should stop by itself and change nothing.

TEST STATUS (2026-11-18, ONE board, one printer, a Pico wired as safety net)
  - From the real factory state (factory bootloader + factory application): install.sh option 1 replaced the
    bootloader in software (1.2 s, read back identical on the first attempt) and flashed V2 over CAN: OK.
  - install.sh option 2 (factory application) with the new bootloader already there: OK.
  - Bootloader way back in software (original bootloader written again), then option 1 again: OK.
  - From the factory screen board: options 1, 2, 3, u, b and answering no: OK.
  - After the last run the Pico confirmed bootloader and application byte for byte.
  - The software bootloader write was done many times, every time right on the first attempt (1.2 s on a Raspberry Pi, about 4 s on the factory screen board).
  Not tested: other boards, other firmware versions, a power loss during the write.
