# USB flag files (rescue by USB stick)

Put ONE of these empty files in the top folder of a USB stick (FAT32/ext4/exFAT), plug it into the screen board and reboot it.
The check is installed by `install.sh` (`usb_rescue/`, service `wm-factory-usb`) and removed again by `restore.sh --factory`.

| File | What the board does |
|---|---|
| `WM-FACTORY` | runs `restore.sh --factory --yes` and reboots: deletes the vanilla install, puts the factory files back, resets the settings (the printer must be calibrated again) |
| `WM-RESCUE` | changes nothing: writes a status report (memory, disk, services, snapshot check) to the stick |

Snapshot used: `wm-factory-snapshot/` on the stick if it passes its checksum (copy it there with `./snapshot.sh usb`), otherwise the one on the board.
If neither is good, nothing is changed and the reason is written to the stick.
Do not put both flags on one stick: `WM-FACTORY` wins.

After use the flag is renamed to `.done` (before anything runs, so it can never loop) and the report `WM-FACTORY-LOG.txt` is written to the stick.
Not tested on hardware yet: the offline tests (`tests/test_usb_flag.sh`) use a folder in place of the stick.
