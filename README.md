# wm-vanilla-klipper-factory

Run vanilla Klipper + Moonraker + Fluidd on the factory screen board (TM-T1, RK3308B, 512 MB)
of the WonderMaker ZR Ultra-S, so the printer works without a Raspberry Pi.

**Status: branch `testing`. Tested offline only (38 tests of this project, plus the ported suite). Never run on the printer.**

## What the installer does
1. Checks the board (RK3308B, aarch64, RAM, disk), that no print is running, and whether `can0` exists.
2. Saves a **factory snapshot** once (`~/wm-factory-snapshot/`: the factory folders, system files, service states, SHA-256 checksums). It is never overwritten. `./snapshot.sh usb` copies it to a USB stick and checks the copy.
3. Runs this repository's own `installer.sh` (a port of the WM_Ultra_Vanilla_Klipper Pi installer; the Fluidd/ACE panel and load cell tools come from `vendor/`) with a **lean profile**:
   no KlipperScreen, no NetworkManager, no Obico, no OctoApp, no OctoEverywhere, no timelapse, webcam off by default.
   These cost RAM this board does not have.
4. `./restore.sh --factory` (type FACTORY to confirm): deletes everything the vanilla install added, unpacks the snapshot, resets the factory settings (the factory printer.cfg, saved_variables.cfg and tmt1.ini, so the calibration is gone and the printer has to be calibrated again), sets the services as before. A small copy of your current settings goes to `~/wm-before-factory-restore-DATE`. Gcodes and logs are kept. `--from DIR` restores from the USB copy.

KlipperScreen already on the board is **not touched**. The touch UI choice (KlipperScreen on a diet or GuppyScreen) comes later.

## What is in this repo
See `docs/PORTING.md`: the Pi installer of WM_Ultra_Vanilla_Klipper is the base (KlipperScreen option removed), with copies of the Fluidd/ACE panel and the load cell tools under `vendor/`.

## Use
```
./install.sh --check      # look only
./install.sh --dry-run    # show the plan, change nothing
./install.sh              # install (asks once)
./snapshot.sh status|verify|usb
./restore.sh --factory [--from DIR] [--yes] [--reboot]
```
Options: `--webcam on|off`, `--model ultra|ultra-s`, `--swap auto|zram|off`, `-- EXTRA ARGS`.

## Requirements before a real run
- The main MCU USB cable must be on this board (it shows as `can0`). Without it the install warns and Klipper cannot reach the printer.
- Printer idle. The Pi host must not run Klipper at the same time.

## Tests
`bash tests/test_install.sh` and `bash tests/test_snapshot.sh` (fake board files and fake commands, no hardware). The ported installer suite is `tests/run_tests.sh`.

See `docs/FINDINGS-01-board-survey.md` for what the board has and the open tests.

## USB rescue
`install.sh` also arms a boot check: an empty file `WM-FACTORY` on a USB stick plus a reboot runs `restore.sh --factory`; `WM-RESCUE` only writes a status report to the stick. See `usb_flags/README.md`. Not tested on hardware yet.

## More
- `./installer.sh --extruder-setup` finds the dock order of the four tool heads and writes it into the thr0..thr3 files.
- USB flag files: [usb_flags/](usb_flags/). Dev box tools: `tools/devbox/` (see README-DEVBOX.md).
