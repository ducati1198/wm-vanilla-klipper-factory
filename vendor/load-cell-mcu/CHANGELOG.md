# Changelog

## 1.0.15 - 2026-11-18
- The small `rpi/install.sh` that only forwarded to the new `install.sh` is removed. A clone older than 1.0.6 that updates through its old menu now has to run `bash install.sh` from the main folder once (`git pull`, then `bash install.sh`).

## 1.0.14 - 2026-11-18
- The menu no longer prints "No such file or directory" for `.bootloader-state` on a fresh download (seen when the vanilla Klipper installer opens this menu for the first time).
- README: new section about the vanilla Klipper installer, which downloads this project and flashes V2 at the end of a full install.

## 1.0.13 - 2026-11-18
- README and `zr-ultra/README.md` checked against the repo and corrected (screen board, menu keys, files, tests, retry numbers). `MD5SUMS` and `SHA256SUMS` refreshed: they still had the checksum of the old `cell_bl_soft.py`.

## 1.0.12 - 2026-11-18
- All backups now go into one folder, `~/wm-load-cell-mcu-backups/`, not into the home folder: the bootloader backup (`cell-bootloader-before-DATE.bin`) and the full-flash backups of the SWD rescue scripts (`cell-backup-DATE/`).

## 1.0.11 - 2026-11-18
- The menu header shows which bootloader is on the board (NEW or FACTORY, with the time it was checked). It is remembered in `.bootloader-state` after every check, install and restore.
- New menu option `b`: check the bootloader now (read only; Klipper stops for about 30 s). Also `2_flash_app_can.sh --check`.

## 1.0.10 - 2026-11-18
- The confirmation question now reads `(yes/no) [no]`: pressing Enter, or anything except yes or y, means no and nothing is changed.

## 1.0.9 - 2026-11-18
- The wait for Klipper after a flash or a cancel now follows the Klipper service (the 1.0.8 check was not enough).

## 1.0.8 - 2026-11-18
- The menu waits (up to about 30 s) for Klipper to finish starting before it shows the board firmware, so it no longer says "unknown" right after a flash or a cancel.
- All menu options tested on the WonderMaker factory screen board: 1, 2, 3, u (also from the factory state), u when up to date, and answering no.

## 1.0.7 - 2026-11-18
- Tested on the WonderMaker factory screen board: install from the factory state works (bootloader replaced, V2 flashed over CAN, verified). It is slower than a Raspberry Pi: the bootloader write took 3.9 s (1.2 s on a Pi), the whole run about 1 min 20 s. README warning and script texts now say "1 to 4 seconds".

## 1.0.6 - 2026-11-18
- The folder `rpi` is now `zr-ultra`, and `install.sh` is in the main folder: `bash install.sh`. Run it on the printer's Raspberry Pi or on the WonderMaker factory screen board.
- A small `rpi/install.sh` stays only so that an update from an older version (`u` in the menu) still finds its way to the new place.

## 1.0.5 - 2026-11-18
- The install, update and restore also add the user to the `sudo` group automatically if it is not in it yet (the password is still asked only once).

## 1.0.4 - 2026-11-18
- The install, the update and the restore ask for the sudo password **one time** at the start and keep it for all steps (stop Klipper, flash, start Klipper). New `zr-ultra/lib_sudo.sh`. Needed on boards where `sudo` asks for a password (for example the factory screen board).

## 1.0.3 - 2026-11-18
- `install.sh` menu option `u` (Update): checks the version on GitHub, updates this folder (`git pull`, or a new download if you did not use git), then offers the newest firmware if the board does not run it. The menu header shows when a new version is on GitHub.
- Only ONE confirmation (`yes`) in the install and in the restore (it used to ask twice).
- `zr-ultra/firmware/LATEST` names the newest patched firmware, so an update can bring a newer one.

## 1.0.2 - 2026-11-18
- README: update section simplified (`git pull`). Same firmware, bootloader and scripts as 1.0.0.

## 1.0.0 - 2026-11-18
- `zr-ultra/install.sh`: menu to flash the load cell board (CELL) over CAN: 1) V2 (`KLP_CELL_WM_ZRU_RPI_V2_20261117`), 2) the original factory firmware (`KLP_CELL_WM_ZRU_20251223_162212`), 3) restore the original factory state (factory firmware + original factory bootloader, `zr-ultra/4_restore_factory_bootloader.sh`).
- `zr-ultra/tools/cell_bl_soft.py`: replaces the factory bootloader (CAN on the wrong pins) in software, through the running firmware. No SWD programmer, no Pico, no wires, no soldering. `2_flash_app_can.sh` does it automatically and asks first.
- Firmware files: V2, factory application, new CAN bootloader, original factory bootloader. Bootloader source (config, patch, commit).
- Rescue scripts for an SWD probe (Pico): `1_write_bootloader_swd.sh`, `3_flash_app_swd.sh`.
- README for the WonderMaker ZR Ultra-S and the ZR Ultra (tested on an Ultra-S only), with warning, power-loss warning, install, update and way back.
- Tested on one board (see `zr-ultra/README.md`, TEST STATUS).
