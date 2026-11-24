# Window model: making the other windows work like the e-step window (proposal, nothing changed yet)

Status: PROPOSAL. No macro was changed for this. The e-step window is 33 macros in `rpi-cfg/rpi_nozzle.cfg`
(`_WM_ESTEP*`); it was only ever tested offline (`tests/estep_render.py`) and on a printer one window at a time.
The other windows are about 7000 lines in `rpi-cfg/*.cfg`. Converting them all untested is how a printer gets stuck
with a window it cannot close, so this is split in small steps, each testable alone.

## The model (what the e-step window does)
1. One page per step, one job per page.
2. A waiting page (heating) reopens itself every 3 s until done, then goes to the next page.
3. A page with no buttons during a blocking move.
4. Back always goes to the right page; Retry never moves the printer.
5. Checks before any move: no print, temperature, amount moved, new value within a range of the old one.
6. Automatic end: park, motors off, heater off, restart only if the config changed.
7. Pictures and texts in one place.

## Shared parts to build first (new macros, used by e-step first, so the e-step window proves them)
| Part | What it does | Exists today as |
|---|---|---|
| `_WM_WIN_GUARD` | refuse to open during a print, require nozzle safe, homed if a move follows | `_WM_ESTEP_GUARD` |
| `_WM_WIN_WAIT page=X` | "please wait" page, no buttons | `_WM_ESTEP_WAIT` |
| `_WM_WIN_HEAT temp=T next=X` | self-refreshing heat page | `_WM_ESTEP_HEAT`, `_WM_ESTEP_HEATWIN` |
| `_WM_WIN_END` | park, motors off, heater off, optional restart | `_WM_ESTEP_FINISH`, `_WM_ESTEP_WIPEPARK` |
| `_WM_WIN_FAIL` | on any error: close the window, heater off, show the reason | `_WM_FAIL` (closes only in some places) |

## Order of conversion (one per release, each tested on the printer before the next)
1. Pull the shared parts out of e-step; e-step must behave exactly as now (`tests/estep_render.py` unchanged and green).
2. `WM_NOZZLE_GROWTH_CAL` and `WM_OFFSETS_Z_HOT` (they heat and wait: closest to e-step).
3. `WM_LIVE_Z_MENU`, `WM_Z_TRIM_MENU` (menus that write a value).
4. `WM_BED_SOAK_MENU`, `WM_LOAD_MENU`, `WM_UNLOAD_MENU`, `WM_PURGE_MENU`.
5. Long flows last: `WM_FIRST_RUN_CAL`, `WM_FULL_OFFSET_CAL`, `WM_OFFSETS_RAPID`.

## Questions that need the owner (the answers change the design)
- Screens that count: ANSWERED by the owner (2026-11-24): the touch screen matters the most. Fluidd still has to work, but every page is designed for the touch screen first: 800x480, big buttons, few words, one job per page, no scrolling.
- Does every window write a value, or are some read-only?
- One shared engine (list of steps per tool) or macro by macro like e-step? Proposal: macro by macro, shared helpers only.

## Rules for every conversion
- Test offline first with a render test like `tests/estep_render.py`, then one window on the printer.
- A window must close itself on any error. No redirect to a macro that no longer exists: grep every caller.
- Windows refuse to open during a print.

## Consequence of "the touch screen matters the most"
- Which touch UI runs on this board is still undecided (KlipperScreen on a diet, GuppyScreen, or the factory app). The windows are Klipper prompts (`RESPOND TYPE=command`), so each UI must be checked: how it draws a prompt, how many buttons fit, whether a prompt can be redrawn in place (the heating page relies on this), and whether pictures show.
- Before converting any window: test the e-step window on that touch UI on the real board and write down what works. The conversion order above then follows what the touch UI can do.
- Design limits to use now: at most 3-4 buttons per page, texts under about 60 characters per line, no tables.
