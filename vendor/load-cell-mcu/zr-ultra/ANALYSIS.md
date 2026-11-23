# CELL board firmware KLP_CELL_WM_ZRU_20251223_162212 - analysis 2026-11-17 (static, on the dump; nothing flashed)

## What the firmware is
- NOT the code of src/sensor_cs1237.c in the factory Klipper tree (2026, new protocol: config_cs1237 with config=, attach_trigger_analog, status bits, error codes). The board runs an OLDER WonderMaker driver (commands cs1237_setup_home, query_cs1237_zero, query_cs1237_read ...). The host module that matches it is the compiled cs1237.cpython-39 .so; cs1237.py next to it belongs to the newer firmware (20260902, not shipped).
- Command table at 0x0800ce28 (16 bytes per entry). Handlers: config_cs1237 0x08007880, query_cs1237 0x08007498, cs1237_setup_home 0x080071b8, query_cs1237_zero 0x08008908, query_cs1237_read 0x080088b8, query_cs1237_begin 0x08007bf0.
- Timer 0x08006d3c: every 36000 ticks (0.5 ms, fixed; the host's rest_ticks is only on/off). DOUT low on two reads -> sample pending -> task.
- Bit reader 0x0800776c: 24 data clocks + 3 more; SCLK high 32 ticks (444 ns), DOUT sampled, SCLK low, 32 ticks; interrupts off only while SCLK is high for the 24 data bits.
- Sample read 0x08008800: reads when DOUT is low; a result 0 or 0xFFFFFF is read again (up to 4 tries); 0x800000 -> shutdown code 0x29 (unless flag 0x20000009 is set); anything else is taken as a good sample. NO other plausibility check, NO status bit check.
- Task 0x08009d28 (while probing): raw -> mV (x 0.0193359375 ...) -> crude smoothing (state kept as one byte) -> |value - zero| > threshold -> trsync trigger AT ONCE on ONE sample.
- query_cs1237_zero (zero before every probe): 10 reads straight from the command, not synchronised to the timer; the LAST stored read becomes the zero.
- Chip config read back by the host at start: 0x2c = 640 samples per second, gain 128, channel A.

## What this means for B-049
- A broken read (true top bits, then a single 1, then zeros: 0x50000, 0x60000, 0x80000, 0x100000, 0x200000, 0x400000) passes every check in the firmware.
- During a probe move one such sample triggers the probe at once (threshold 0.05 mV, broken reads are +0.046 to +9 mV).
- In the zero step one such sample as the last of the 10 reads gives a wrong zero, and the move then triggers with no travel at all (seen in B-049: "no travel at all").
- The 1-in-90 rate of the noise test was measured through the debug read (reads at any time, not when the chip says ready) and the zero step reads the same way. The timer path used during the move reads within 0.5 ms of "ready" (the chip gives a new sample every 1.56 ms), so it should hit a broken read far less often. Likely mechanism: the read runs into the moment the chip puts out its next sample. NOT proven (no logic analyser trace).

## Patch candidate klipper_CELL_patched_v1.bin (NOT flashed)
- 6 bytes changed at 0x08008822 (b.w to a stub) + 18 bytes of new code after the application at 0x0800d68c:
    cmp.w r0,#0x800000 ; beq.w 0x08008892   (unchanged behaviour for 0x800000)
    lsls r1,r0,#18     ; bne.w 0x08008828   (low 14 bits not all zero -> good sample, as before)
    movs r0,#0 ; pop {r3,r4,r5,pc}          (low 14 bits all zero -> "no sample", same as the existing "not ready" return)
- Effect: a broken read is dropped everywhere (probe move, zero step, debug read). A real sample with 14 zero low bits (1 in 16384, about one per 25 s) is skipped, the previous sample stays: harmless.
- Emulated (unicorn) original against patched: good values identical; the broken values are stored by the original and dropped by the patched one; 0, 0xFFFFFF and 0x800000 behave the same.
- md5: original app e1e4fbc247a306d7854640f22cb6409d, patched 8266049d5db7d8b84311426b41189103 (46750 bytes).
- Way back: klipper_CELL_app_from_board.bin over CAN (CanBoot) or cell_512k.bin over SWD (Pico).

## 2026-11-17 15:15-15:30: v1 flashed, did not help; real cause PROVEN; v2 built
- v1 (drop reads with 14 zero low bits) flashed over SWD. First try failed half way ("flash write algorithm aborted", the running firmware's watchdog reset the chip while halted); bootloader stayed intact; second try from "reset halt" wrote and verified. LESSON: always "reset halt" before a flash write on this board.
- Noise test on v1: broken reads still there (18, 22, 26 in 1900). So the assumed signature was wrong.
- Ground truth, read from the board's RAM over SWD while the host ran debug reads (struct at 0x2000031c, sample at +0x3a): broken samples are 0x1fffe0, 0x3fffc1, 0x7fff82, 0x04ffff, 0xffff02, 0x7fff81 (good: 0x04ba24). Pattern: the real top bits, then SIXTEEN ones, then the first bits of the NEXT sample (000001...). The earlier "single 1 then zeros" values were the host's rounded print.
- This proves the mechanism: the read ran into the moment the CS1237 puts out its next sample. The chip holds DOUT high for about 26 us (16 clocks at the firmware's clock rate), then starts shifting the new sample. The read after such a collision is garbage too (it gets the rest of the half-read sample).
- When does the firmware read without knowing how old the sample is: (1) the debug read, (2) the first read of each round of the zero step, (3) the FIRST sample after the sample timer is started (query_cs1237) - the sample waiting there can be any age. (3) fits the false touches with no travel.
- v2 = original firmware + a resync step (klipper_CELL_patched_v2.bin, md5 583f254423bfb39d5c101bbc48154f05, 46814 bytes, build_v2.py):
    syncF at 0x0800d68c: wait until DOUT is high (the chip's update pulse, or no sample pending), then until DOUT is low (a brand-new sample), then read at once. Each wait gives up after 3 ms and reads as the original did.
    hooks (12 bytes changed in the original code): query_cs1237 start 0x080074d2 (resync, read and drop one sample before the timer starts), debug read 0x080088da, zero step 0x08008938.
    v1's filter is NOT in v2.
- Emulated with a simulated chip: stale sample + pulse -> read starts 0.4 us after the pulse ends; no sample -> read when it comes; stuck low -> reads after 3 ms; stuck high -> "no sample" after 3 ms.
- Not covered by v2: a collision in the middle of a probe move when the board's main loop is late by more than 1 ms (should be very rare).
