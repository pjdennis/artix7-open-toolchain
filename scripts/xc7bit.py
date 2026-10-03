#!/usr/bin/env python3
"""Post-processes Xilinx 7-series .bit files from xc7frames2bit (stdlib only).

  xc7bit.py compact IN.bit FRAMES.txt OUT.bit [--oscfsel N] [--restart] [--boot-delay-ms MS]
      Writes only the configuration frames that carry data (FRAMES.txt is `bitread -C -z -o`
      output for IN.bit) instead of every frame of the device. Configuration memory is cleared
      before every load, so the skipped all-zero frames are already correct. Optionally sets
      COR0.OSCFSEL, the master-SPI flash clock (CCLK) used when booting from flash, and guards
      against the JTAG/flash race (add_restart, add_boot_delay).
  xc7bit.py info IN.bit
      Prints the configuration packet sequence.
"""
import argparse
import re
import struct
import sys

FRAME_WORDS = 101
SYNC = b"\xaa\x99\x55\x66"
NOOP = 0x20000000
REG_FAR, REG_FDRI, REG_CMD, REG_COR0, REG_IDCODE = 1, 2, 4, 9, 12
CMD_WCFG, CMD_LFRM, CMD_START, CMD_RCRC, CMD_AGHIGH, CMD_GRESTORE, CMD_SHUTDOWN, CMD_DESYNC = 1, 3, 5, 7, 8, 10, 11, 13
OSCFSEL_SHIFT, OSCFSEL_MASK = 17, 0x3F
DEFAULT_CCLK_HZ = 3.3e6  # the flash clock before COR0 is read; nominally 3 MHz, 3.3 MHz measured on a Cmod A7

REG_NAMES = {0: "CRC", 1: "FAR", 2: "FDRI", 4: "CMD", 5: "CTL0", 6: "MASK", 9: "COR0", 12: "IDCODE",
             14: "COR1", 16: "WBSTAR", 17: "TIMER", 24: "CTL1"}
CMD_NAMES = {0: "NULL", 1: "WCFG", 3: "LFRM", 5: "START", 7: "RCRC", 8: "AGHIGH", 9: "SWITCH", 10: "GRESTORE",
             11: "SHUTDOWN", 13: "DESYNC"}


def type1_write(reg, count):
    return 0x30000000 | (reg << 13) | count


def type2_write(count):
    return 0x50000000 | count


class BitFile:
    """A .bit file: header fields, pre-sync bytes, then configuration packets as (header, payload)."""

    @classmethod
    def parse(cls, raw):
        bf = cls()
        pos = 13  # fixed 13-byte preamble: 0x0009, 9 bytes, 0x0001
        while raw[pos:pos + 1] != b"e":
            pos += 3 + struct.unpack(">H", raw[pos + 1:pos + 3])[0]
        bf.fields = raw[:pos]
        (length,) = struct.unpack(">I", raw[pos + 1:pos + 5])
        body = raw[pos + 5:pos + 5 + length]
        sync = body.index(SYNC) + len(SYNC)
        bf.preamble = body[:sync]
        nwords = (len(body) - sync) // 4
        words = struct.unpack(f">{nwords}I", body[sync:sync + 4 * nwords])
        bf.tail = body[sync + 4 * nwords:]
        bf.packets = []
        i = 0
        while i < len(words):
            hdr = words[i]
            kind, op = hdr >> 29, (hdr >> 27) & 3
            count = (hdr & 0x7FF if kind == 1 else hdr & 0x7FFFFFF if kind == 2 else 0) if op == 2 else 0
            bf.packets.append((hdr, list(words[i + 1:i + 1 + count])))
            i += 1 + count
        return bf

    def serialize(self):
        words = [w for hdr, payload in self.packets for w in (hdr, *payload)]
        body = self.preamble + struct.pack(f">{len(words)}I", *words) + self.tail
        return self.fields + b"e" + struct.pack(">I", len(body)) + body


def parse_frame_dump(text):
    """Parses `bitread -o` output: '.frame 0xFAR' followed by the frame's words in hex."""
    frames = {}
    for far, words in re.findall(r"\.frame (0x[0-9a-fA-F]+)\s+([0-9a-fA-F\s]*)", text):
        frames[int(far, 16)] = [int(w, 16) for w in words.split()]
    return frames


def frame_runs(frames):
    """Groups frames into runs of consecutive frame addresses."""
    runs = []
    for far in sorted(f for f, words in frames.items() if any(words)):
        if runs and far == runs[-1][0] + len(runs[-1][1]):
            runs[-1][1].append(frames[far])
        else:
            runs.append((far, [frames[far]]))
    return runs


def compact(bf, frames):
    """Replaces the single full-device FAR/WCFG/FDRI burst with one burst per run of data frames.
    Each burst ends with a pad frame, which flushes the frame buffer and is itself never written."""
    bursts = [i for i, (hdr, _) in enumerate(bf.packets) if hdr >> 29 == 2]
    if len(bursts) != 1 or bf.packets[bursts[0] - 1][0] != type1_write(REG_FDRI, 0):
        raise ValueError("expected exactly one type-2 FDRI burst")
    start = max(i for i in range(bursts[0]) if bf.packets[i][0] == type1_write(REG_FAR, 1))
    writes = []
    for far, run in frame_runs(frames):
        data = [w for f in run for w in f] + [0] * FRAME_WORDS
        writes += [(type1_write(REG_FAR, 1), [far]), (type1_write(REG_CMD, 1), [CMD_WCFG]), (NOOP, []),
                   (type1_write(REG_FDRI, 0), []), (type2_write(len(data)), data)]
    bf.packets[start:bursts[0] + 1] = writes


def set_oscfsel(bf, value):
    """Sets COR0.OSCFSEL: the CCLK frequency the FPGA uses to read its configuration flash."""
    if not 0 <= value <= OSCFSEL_MASK:
        raise ValueError(f"OSCFSEL must be 0..{OSCFSEL_MASK}")
    hits = [i for i, (hdr, _) in enumerate(bf.packets) if hdr == type1_write(REG_COR0, 1)]
    if not hits:
        raise ValueError("no COR0 write in bitstream")
    for i in hits:
        (cor0,) = bf.packets[i][1]
        bf.packets[i] = (bf.packets[i][0], [(cor0 & ~(OSCFSEL_MASK << OSCFSEL_SHIFT)) | (value << OSCFSEL_SHIFT)])


# The JTAG/flash race. A JTAG load (JPROGRAM) clears the FPGA and makes it start booting from its flash, as
# at power-up, while the JTAG data is still on its way. If that boot finishes first, the JTAG design is
# written over a started design: register initial values are not applied, and the started design's frames
# that the JTAG bitstream skips are left behind. add_boot_delay keeps a flash image from writing anything in
# that time; add_restart makes a JTAG load redo the startup if a flash design (made elsewhere) got there first.

def _command(cmd):
    return (type1_write(REG_CMD, 1), [cmd])


def add_restart(bf):
    """After the first CRC reset: SHUTDOWN (leave a started state), then AGHIGH (interconnect off while the
    frames change). The bitstream's own GRESTORE, LFRM and START then run a full startup. On a freshly
    cleared FPGA these do nothing."""
    first = next((i for i, p in enumerate(bf.packets) if p == _command(CMD_RCRC)), None)
    if first is None:
        raise ValueError("no CRC reset command in bitstream")
    bf.packets[first + 1:first + 1] = ([_command(CMD_SHUTDOWN)] + [(NOOP, [])] * 100 +  # shutdown takes cycles
                                       [_command(CMD_RCRC)] + [(NOOP, [])] * 2 + [_command(CMD_AGHIGH)])


def add_boot_delay(bf, ms):
    """NOOPs before the COR0 write, which the FPGA reads at its slow default clock when booting from flash:
    the boot then writes no frames for about `ms` (100 ms covers openFPGALoader's ~20 ms lead even if the
    clock runs 50% fast). Over JTAG they cost 32 TCK each."""
    cor0 = next((i for i, (hdr, _) in enumerate(bf.packets) if hdr == type1_write(REG_COR0, 1)), None)
    if cor0 is None:
        raise ValueError("no COR0 write in bitstream")
    bf.packets[cor0:cor0] = [(NOOP, [])] * round(ms / 1000 * DEFAULT_CCLK_HZ / 32)


def describe(bf):
    out, noops = [], 0
    for hdr, payload in bf.packets + [(None, [])]:
        if hdr == NOOP:
            noops += 1
            continue
        if noops:
            out.append(f"NOOP x{noops}")
            noops = 0
        if hdr is None:
            break
        reg = (hdr >> 13) & 0x3FFF
        if hdr >> 29 == 2:
            out.append(f"  FDRI burst: {len(payload)} words ({len(payload) / FRAME_WORDS:.0f} frames)")
        elif reg == REG_CMD and payload:
            out.append("CMD " + ",".join(CMD_NAMES.get(v, hex(v)) for v in payload))
        else:
            out.append(f"{REG_NAMES.get(reg, reg)} = {' '.join(f'0x{v:08x}' for v in payload)}")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("compact")
    c.add_argument("bit")
    c.add_argument("frames")
    c.add_argument("out")
    c.add_argument("--oscfsel", type=lambda s: int(s, 0))
    c.add_argument("--restart", action="store_true", help="redo startup if a flash design started first")
    c.add_argument("--boot-delay-ms", type=float, default=0, help="delay before a flash boot writes frames")
    i = sub.add_parser("info")
    i.add_argument("bit")
    args = ap.parse_args()

    with open(args.bit, "rb") as f:
        bf = BitFile.parse(f.read())
    if args.cmd == "info":
        print(describe(bf))
        return
    before = len(bf.serialize())
    with open(args.frames) as f:
        compact(bf, parse_frame_dump(f.read()))
    if args.oscfsel is not None:
        set_oscfsel(bf, args.oscfsel)
    if args.boot_delay_ms:
        add_boot_delay(bf, args.boot_delay_ms)
    if args.restart:
        add_restart(bf)
    out = bf.serialize()
    with open(args.out, "wb") as f:
        f.write(out)
    print(f"{args.out}: {len(out)} bytes ({before / len(out):.0f}x smaller)", file=sys.stderr)


if __name__ == "__main__":
    main()
