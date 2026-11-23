# Finding 01 - survey of the factory screen board (read-only)

Date: 2026-11-23. Nothing was changed on any board.

## Screen board (TM-T1)
| Item | Value |
|---|---|
| SoC | Rockchip RK3308B, 4 cores, ~1.1 GHz, 46 C idle |
| OS | Debian 11 (bullseye) aarch64, kernel 5.10.160, Python 3.9.2 |
| RAM | 487 MB total, ~341 MB available, no swap |
| Storage | 7.2 GB eMMC, root 7.0 GB, 2.2 GB free (68 % used) |
| Display | fb0 800x480, DRI card0, one input device |
| USB | host ports through a 2.0 hub (no device plugged in now), plus a dwc2 gadget |
| Network | eth0 and wlan0 |
| CAN | `can0` is configured (1 Mbit) as allow-hotplug. The kernel has the `gs_usb` driver. No can0 now because no USB-CAN device is plugged in. No serial port to the main MCU |
| Running now | KlipperScreen (python ~110 MB, Xorg ~56 MB), wm-chamber-light-http, usbdevice |

## Factory stack already on the board (installed, services disabled)
klipper, moonraker, nginx, fluidd, crowsnest, klipper-mcu, klippy-env, moonraker-env, mcu_update (factory MCU images KLP_IMG_WM_ZRU_V1.0.26), printer_data/config with the full ZRU config (all CAN uuids). So this board was designed to be the host.

## Pi 4 host (.35) for comparison, idle, klippy ready
klippy 77 MB, moonraker 73 MB, camera-streamer 33 MB. Pi has 1.8 GB RAM. Main MCU is a gs_usb CAN bridge on the Pi USB (1d50:606f).

## Budget on the screen board
available 341 MB - klippy 77 - moonraker 73 = ~190 MB left for the UI, nginx and the system. KlipperScreen + Xorg now use ~165 MB, so it is tight but not impossible. Peak klippy memory during a print is not measured yet.

## Open tests
1. klippy/moonraker peak RSS during a real print on the Pi.
2. Plug the main MCU USB into the screen board hub (printer off, Pi unplugged) and check lsusb and can0.
3. Touch UI: KlipperScreen on a diet vs GuppyScreen (800x480, touch, four toolheads, action:prompt windows).
4. Add zram or a swap file and measure.
