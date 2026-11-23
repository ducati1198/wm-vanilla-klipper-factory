#!/usr/bin/env python3
# Replace the bootloader of the WonderMaker load cell board (CELL) in SOFTWARE, through the running Klipper
# application, over CAN (Klipper debug_read / debug_write commands). No SWD probe, no soldering.
#
#   cell_bl_soft.py UUID probe                 read only. Last line: "BOOTLOADER: new|factory|unknown"
#   cell_bl_soft.py UUID trial                 erase/program/erase one empty page at the end of the flash
#   cell_bl_soft.py UUID write BOOTLOADER.bin  replace the bootloader at 0x08000000   (add --force to skip the checks)
#
# Klipper must be stopped (this tool talks to the board itself; it uses the klippy code of ~/klipper).
# NEVER reset or power off the printer while it writes (1 to 4 seconds).
import sys, os, time, hashlib, logging
logging.disable(logging.WARNING)
KDIR = os.environ.get("KLIPPER_DIR", os.path.expanduser("~/klipper"))
sys.path.insert(0, os.path.join(KDIR, "klippy"))
import reactor, serialhdl  # noqa

FLASH = 0x40022000
KEYR, SR, CR, AR = FLASH + 0x04, FLASH + 0x0C, FLASH + 0x10, FLASH + 0x14
PG, PER, STRT, LOCK = 1, 2, 0x40, 0x80
BSY, PGERR, WRPRTERR, EOP = 1, 4, 0x10, 0x20
BASE = 0x08000000
APP = 0x08002000

# what this tool was tested with
KNOWN_APPS = ("KLP_CELL_WM_ZRU_20251223_162212", "KLP_CELL_WM_ZRU_RPI_V2_20261117")
NEW_BL_MD5 = "49340e49d8fec9a74f76a8dce60eb6b0"      # KLP_CELL_WM_ZRU_20251223_162212_new_bootloader.bin (3798 bytes)
OLD_BL_MD5 = "7251e472575b1ff1028d25d4478a7050"      # ..._original_bootloader.bin (3154 bytes)
BL_FILES = {NEW_BL_MD5: 3798, OLD_BL_MD5: 3154}
DEV_ID = 0x414


class Stop(Exception):
    pass


class Tool:
    def __init__(self, uuid, mode, path, force):
        self.uuid, self.mode, self.path, self.force = uuid, mode, path, force
        self.rc = 1
        self.r = reactor.Reactor()
        self.ser = serialhdl.SerialReader(self.r)
        self.r.register_callback(self.main)
        self.r.run()

    def say(self, m):
        sys.stdout.write(m + "\n"); sys.stdout.flush()

    # --- low level
    def rd(self, addr, order=2):
        return self.ser.send_with_response("debug_read order=%d addr=%d" % (order, addr), "debug_result")["val"]

    def wr(self, addr, val, order=2):
        self.ser.send("debug_write order=%d addr=%d val=%d" % (order, addr, val))

    def wait(self):
        t = time.time()
        while True:
            s = self.rd(SR)
            if not s & BSY:
                return s
            if time.time() - t > 5:
                raise Stop("flash stays busy, SR=%#x" % s)

    def unlock(self):
        if self.rd(CR) & LOCK:
            self.wr(KEYR, 0x45670123); self.wr(KEYR, 0xCDEF89AB)
        if self.rd(CR) & LOCK:
            raise Stop("flash controller did not unlock")
        self.wr(SR, PGERR | WRPRTERR | EOP)

    def lock(self):
        self.wr(CR, LOCK); self.rd(CR)

    def erase(self, addr):
        self.wr(CR, PER); self.wr(AR, addr); self.wr(CR, PER | STRT)
        s = self.wait(); self.wr(CR, 0)
        if s & (PGERR | WRPRTERR):
            raise Stop("erase error at %#x SR=%#x" % (addr, s))
        self.wr(SR, EOP)

    def program(self, addr, data):
        if len(data) & 1:
            data += b"\xff"
        self.wr(CR, PG)
        for i in range(0, len(data), 2):
            self.wr(addr + i, data[i] | (data[i + 1] << 8), 1)
            if (i & 0x7e) == 0x7e:
                s = self.wait()
                if s & (PGERR | WRPRTERR):
                    self.wr(CR, 0); raise Stop("program error near %#x SR=%#x" % (addr + i, s))
        s = self.wait(); self.wr(CR, 0)
        if s & (PGERR | WRPRTERR):
            raise Stop("program error SR=%#x" % s)
        self.wr(SR, EOP)

    def read(self, addr, n):
        out = bytearray()
        for a in range(addr, addr + n, 4):
            out += self.rd(a).to_bytes(4, "little")
        return bytes(out[:n])

    def page_size(self):
        # program one halfword in each 1K half of the trial area, erase the first: if both are gone, pages are 2K
        T = self.trial
        self.erase(T); self.erase(T + 0x400)
        self.program(T + 0x10, b"\x34\x12"); self.program(T + 0x410, b"\x78\x56")
        a, b = self.rd(T + 0x10, 1), self.rd(T + 0x410, 1)
        if (a, b) != (0x1234, 0x5678):
            self.erase(T); self.erase(T + 0x400)
            raise Stop("the flash trial failed (read %#x %#x): this chip does not behave like the tested one" % (a, b))
        self.erase(T)
        a, b = self.rd(T + 0x10, 1), self.rd(T + 0x410, 1)
        self.erase(T + 0x400)
        if a != 0xffff:
            raise Stop("the trial erase failed")
        return 0x800 if b == 0xffff else 0x400

    # --- modes
    def main(self, eventtime):
        try:
            self.ser.connect_canbus(self.uuid, 64, "can0")
            self.mp = self.ser.get_msgparser()
            self.app = self.mp.get_version_info()[0]
            self.say("connected, application: %s" % (self.app,))
            getattr(self, "do_" + self.mode)()
            self.rc = 0
        except Stop as e:
            self.say("STOP: %s" % (e,)); self.rc = 3
        except Exception as e:
            self.say("ERROR: %s" % (e,))
        finally:
            try:
                self.ser.disconnect()
            except Exception:
                pass
            self.r.end()

    def info(self):
        self.kb = self.rd(0x1FFFF7E0) & 0xffff
        self.devid = self.rd(0xE0042000) & 0xfff
        self.hsi = self.rd(0x40021000) & 1
        self.trial = BASE + self.kb * 1024 - 0x1000
        self.say("chip: DEV_ID %#x, flash %d K, HSI on %d, FLASH_CR %#x" % (self.devid, self.kb, self.hsi, self.rd(CR)))
        bl = self.read(BASE, 0x1000)
        self.kind = "unknown"
        for md5, n in BL_FILES.items():
            if hashlib.md5(bl[:n]).hexdigest() == md5 and bl[n:] == b"\xff" * (0x1000 - n):
                self.kind = "new" if md5 == NEW_BL_MD5 else "factory"
        self.say("bootloader on the board: %d bytes used, vectors %s" % (len(bl.rstrip(b"\xff")), bl[:8].hex()))
        return bl

    def checks(self):
        problems = []
        if self.app not in KNOWN_APPS:
            problems.append("application %s is not one this tool was tested with" % self.app)
        if self.devid != DEV_ID:
            problems.append("chip DEV_ID %#x is not %#x" % (self.devid, DEV_ID))
        if not 64 <= self.kb <= 1024:
            problems.append("flash size %d K looks wrong" % self.kb)
        if not self.hsi:
            problems.append("the HSI clock is off")
        if self.kind == "unknown":
            problems.append("the bootloader on the board is neither the factory one nor the new one")
        if not problems and self.read(self.trial, 0x800) != b"\xff" * 0x800:
            problems.append("the trial area at %#x is not empty" % self.trial)
        if problems and not self.force:
            raise Stop("not safe to write on this board: " + "; ".join(problems) + ". Nothing was changed.")
        for p in problems:
            self.say("WARNING (forced): " + p)

    def do_probe(self):
        self.info()
        self.say("BOOTLOADER: " + self.kind)

    def do_trial(self):
        self.info(); self.checks()
        self.unlock()
        try:
            ps = self.page_size()
            self.say("flash page size: %d bytes" % ps)
            blob = bytes((i * 7 + 3) & 0xff for i in range(256))
            self.program(self.trial, blob)
            ok = self.read(self.trial, 256) == blob
            self.erase(self.trial)
            self.say("trial program: %s, area empty again: %s" % ("OK" if ok else "MISMATCH", self.read(self.trial, 0x800) == b"\xff" * 0x800))
            if not ok:
                raise Stop("trial mismatch")
        finally:
            self.lock()

    def do_write(self):
        new = open(self.path, "rb").read()
        md5 = hashlib.md5(new).hexdigest()
        if not (1000 < len(new) <= 0x1000) or new[3] != 0x20 or new[7] != 0x08:
            raise Stop("that file does not look like a bootloader for this board")
        if md5 not in BL_FILES and not self.force:
            raise Stop("that file is not one of the two known bootloaders (md5 %s)" % md5)
        old = self.info()
        if old[:len(new)] == new and old[len(new):] == b"\xff" * (0x1000 - len(new)):
            self.say("this bootloader is already on the board, nothing to do"); return
        self.checks()
        bdir = os.path.expanduser("~/wm-load-cell-mcu-backups"); os.makedirs(bdir, exist_ok=True)
        bk = os.path.join(bdir, "cell-bootloader-before-%s.bin" % time.strftime("%Y%m%d-%H%M%S"))
        open(bk, "wb").write(self.read(BASE, 0x2000)); self.say("backup of the old bootloader area: " + bk)
        self.unlock()
        try:
            ps = self.page_size()
            self.say("flash page size: %d bytes. Writing now: do NOT power off." % ps)
            new_p = new + b"\xff" * (-len(new) % 0x1000)
            for attempt in (1, 2, 3):
                t = time.time()
                for off in range(0, len(new_p), ps):
                    self.erase(BASE + off)
                    self.program(BASE + off, new_p[off:off + ps])
                back = self.read(BASE, len(new_p))
                if back == new_p:
                    self.say("attempt %d: written and read back identical (%d bytes, %.1f s)" % (attempt, len(new), time.time() - t))
                    break
                self.say("attempt %d: %d bytes differ, writing again (do NOT power off)" % (attempt, sum(1 for x, y in zip(back, new_p) if x != y)))
            else:
                raise Stop("the bootloader could not be written correctly. DO NOT power off or reset the printer: run this again")
        finally:
            self.lock()
        self.say("BOOTLOADER WRITTEN OK (md5 %s). The application was not touched." % hashlib.md5(self.read(BASE, len(new))).hexdigest())


if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if x != "--force"]
    if len(a) < 2 or a[1] not in ("probe", "trial", "write") or (a[1] == "write" and len(a) < 3):
        sys.stdout.write("usage: cell_bl_soft.py UUID probe | trial | write BOOTLOADER.bin [--force]\n"); sys.exit(2)
    sys.exit(Tool(a[0], a[1], a[2] if len(a) > 2 else None, "--force" in sys.argv).rc)
