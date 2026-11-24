# Porting log: what came from where (branch testing)

Base: the Raspberry Pi installer of WM_Ultra_Vanilla_Klipper v2.25.2 (`installer.sh`).

## Copied
| From | To | Notes |
|---|---|---|
| WM_Ultra_Vanilla_Klipper | `installer.sh`, `config/`, `rpi-cfg/`, `scripts/`, `tools/`, `tests/`, `zr_tools/`, `usb_flags/`, `chamber_test/`, `first-layer-stl/`, `docs/from-vanilla/` | unchanged except the edits below |
| wm-ultra-fluidd-acepro-panel | `vendor/acepro-panel/` | installer, config, Fluidd build (zip + patch), extras, scripts, tests. Left out: `old_backup/`, `orca_plugin/`, `docs/` |
| wm-load-cell-mcu | `vendor/load-cell-mcu/` | whole project (flash tools, firmware, docs) |
| WM_Ultra_Vanilla_Klipper `factory/` (460 MB) | **not copied** (see open decision) | `.gitignore` keeps it out of commits |
| `screen_board_bundle/`, `screen_rescue/` | not copied | files for the screen board as a screen, not as a host |

## Removed from installer.sh (KlipperScreen on a Pi, and the RAM-heavy add-ons)
- No question "Add a touchscreen (KlipperScreen ...)": the install always sets up only the ZR Tools macros.
- `--screen-layout`, `--screen-backend`, `--screen-test`, `--screen-remove` now stop with a message. `--screen` accepts only `off` or `macros`.
- Add-on menu now lists: webcam, timelapse, shell-command, shaketune, spoolman, acepro, zr-tools. Gone from the menu: Touchscreen, NetworkManager, Obico, OctoApp, OctoEverywhere. (The `--obico`, `--octoapp`, `--octoeverywhere`, `--network-manager` flags still exist in the code and default to off.)
- Test suite: KlipperScreen tests and NetworkManager tests removed (22 checks).
The KlipperScreen code is removed from installer.sh too (screen test/layout/remove, panel copy, doctor and update blocks, `--screen-layout/-backend/-test/-remove` now stop with a message). Only the ZR Tools macros step stays. Removed tests: 2 KlipperScreen-removal checks, 2 Pi-to-screen-board update checks. `screen python tests` needs the `cairo` module (not in the build container): not run here.

## Test status (copy of the repo with factory/ committed, in a temp folder)
Original repo in this container: 993 passed, 7 failed.
This branch: **951 passed, 17 failed**. The 2 sets of checks removed with the screen/NetworkManager options are gone from the count.
Failures and why:
- Same as the original (7): `screen python tests`, 5x `macro patches` (and similar), environment of this container.
- Need a git remote or files not copied (6): `doctor ... behind`, `--check-updates`, README/header lists `--extruder-setup`, `docs/HOST_MCU.md`, host MCU printer.cfg check, dev box README, `usb_flags` README.
- Only because the temp test copy is re-committed (2): "every file in SHA256SUMS is tracked by git" (the bundled Klipper `.gitignore` hides `*.so`).
- Caused by this port (2): `--version names this project, VERSION is 2.x` (this project is 0.1.0-testing) and `menu: Add-ons, Webcam ... offers setting up the cameras again` (the menu numbers moved after five entries were removed).
Next: fix those 2 tests, copy the missing docs, drop checks for things this project does not ship.

## Open decisions
1. **factory/** (231 MB per model). The installer checks it against git (`git status -- factory`, `git checkout -- factory`), so it must be committed in the repo it runs from. Options: (a) commit only `factory/ultra-s` (231 MB), (b) keep the installer pulling a pinned clone of WM_Ultra_Vanilla_Klipper and use its `factory/`, (c) git submodule.
2. DONE: the installer copies `vendor/acepro-panel` (Fluidd zip checked against its .sha256) and `vendor/load-cell-mcu` instead of cloning GitHub. The ACE Pro folder in `~` is now a plain copy (no .git): Fluidd's update button for it is not added.
3. DONE: `install.sh` runs this folder's `installer.sh`; it stops with a message if `factory/` is missing (open decision 1).
4. DONE: `WM-FACTORY` / `WM-RESCUE` USB flags: `usb_rescue/` (boot service `wm-factory-usb`, installed by `install.sh`, removed by `restore.sh --factory`), `tests/test_usb_flag.sh` (12 checks). NOT tested on hardware: the tests use a folder in place of the stick.

## Factory snapshot and restore (added on top of the port)
- `snapshot.sh`, `lib/snapshot.sh`, `restore.sh --factory`, tests in `tests/test_snapshot.sh` (21 checks, fake home and system root).
- Factory reset: the factory app keeps clean copies in `TM_T1/factory_settings/` and a script `TM_T1/scripts/restore_factory_settings.sh` that copies the config files back. That script does NOT copy `printer.cfg`, `saved_variables.cfg` or `tmt1.ini` (they hold the calibration), so `restore.sh` copies those three from `factory_settings/` too: the calibration values go back to the factory defaults (offsets 0.0).
- NOT KNOWN YET: how the factory app decides the printer must be calibrated again. It is not in the saved values I compared. Test on a spare board: after restore, does the app force calibration? If not, find the flag.
- NOT TESTED: USB stick detection on the real board (an earlier test in the vanilla repo did not see a stick).
