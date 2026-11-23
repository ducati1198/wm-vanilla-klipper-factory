# wm-vanilla-klipper-factory

Run vanilla Klipper + Moonraker + Fluidd on the factory screen board (TM-T1, RK3308B, 512 MB)
of the WonderMaker ZR Ultra-S, so the printer works without a Raspberry Pi.

**Status: branch `testing`. Tested offline only (23 tests). Never run on the printer.**

## What the installer does
1. Checks the board (RK3308B, aarch64, RAM, disk), that no print is running, and whether `can0` exists.
2. Saves the factory state (service states, printer_data/config, KlipperScreen.conf, can0 file).
3. Runs the [WM_Ultra_Vanilla_Klipper](https://github.com/ducati1198/WM_Ultra_Vanilla_Klipper) installer (pinned to v2.25.2) with a **lean profile**:
   no KlipperScreen, no NetworkManager, no Obico, no OctoApp, no OctoEverywhere, no timelapse, webcam off by default.
   These cost RAM this board does not have.
4. `./restore.sh` puts the saved service states and config back.

KlipperScreen already on the board is **not touched**. The touch UI choice (KlipperScreen on a diet or GuppyScreen) comes later.

## Use
```
./install.sh --check      # look only
./install.sh --dry-run    # show the plan, change nothing
./install.sh              # install (asks once)
./restore.sh --list
./restore.sh
```
Options: `--webcam on|off`, `--model ultra|ultra-s`, `--ref TAG`, `--swap auto|zram|off`, `-- EXTRA ARGS`.

## Requirements before a real run
- The main MCU USB cable must be on this board (it shows as `can0`). Without it the install warns and Klipper cannot reach the printer.
- Printer idle. The Pi host must not run Klipper at the same time.

## Tests
`bash tests/test_install.sh` (fake board files and fake commands, no hardware).

See `docs/FINDINGS-01-board-survey.md` for what the board has and the open tests.
