import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
import xc7bit  # noqa: E402

FRAME_WORDS = xc7bit.FRAME_WORDS
NOOP = 0x20000000
SYNC = 0xAA995566


def t1(reg, *vals):
    """Type-1 write packet."""
    return [0x30000000 | (reg << 13) | len(vals), *vals]


def t2(n):
    return [0x50000000 | n]


def frame(seed):
    return [(seed * 1000 + i) & 0xFFFFFFFF for i in range(FRAME_WORDS)]


def bit_file(words, design=b"top.v;UserID=0XFFFFFFFF\0"):
    """Minimal .bit: Xilinx header fields a-e, then dummy/bus-width words, sync and packets."""
    body = struct.pack(">8I", *[0xFFFFFFFF] * 8) + struct.pack(">4I", 0x000000BB, 0x11220044, 0xFFFFFFFF, 0xFFFFFFFF)
    body += struct.pack(">I", SYNC) + struct.pack(f">{len(words)}I", *words)
    hdr = bytes.fromhex("0009 0ff00ff00ff00ff000 0001".replace(" ", ""))
    for key, val in ((b"a", design), (b"b", b"7a35tcpg236\0"), (b"c", b"2026/10/02\0"), (b"d", b"12:00:00\0")):
        hdr += key + struct.pack(">H", len(val)) + val
    return hdr + b"e" + struct.pack(">I", len(body)) + body


PREFIX = [NOOP, *t1(xc7bit.REG_CMD, xc7bit.CMD_RCRC), NOOP, NOOP,
          *t1(xc7bit.REG_COR0, 0x02003FE5), *t1(xc7bit.REG_IDCODE, 0x0362D093), NOOP]
TRAILER = [*t1(xc7bit.REG_CMD, xc7bit.CMD_RCRC), NOOP, NOOP, *t1(xc7bit.REG_CMD, xc7bit.CMD_GRESTORE), NOOP,
           *t1(xc7bit.REG_CMD, xc7bit.CMD_START), *t1(xc7bit.REG_CMD, xc7bit.CMD_DESYNC), NOOP, NOOP]


def full_bitstream(frames_in_order):
    """Like xc7frames2bit: FAR=0, WCFG, one FDRI burst with every frame (zeros included), then a pad frame."""
    data = [w for f in frames_in_order for w in f] + [0] * FRAME_WORDS
    return bit_file(PREFIX + t1(xc7bit.REG_FAR, 0) + t1(xc7bit.REG_CMD, xc7bit.CMD_WCFG) + [NOOP]
                    + t1(xc7bit.REG_FDRI) + t2(len(data)) + data + TRAILER)


class BitFileTest(unittest.TestCase):
    def test_round_trip_and_length_field(self):
        raw = full_bitstream([frame(1)])
        bf = xc7bit.BitFile.parse(raw)
        self.assertEqual(bf.serialize(), raw)
        self.assertEqual(bf.packets[0], (NOOP, []))
        bf.packets = bf.packets[:3]  # shrink: the 'e' length field must follow
        out = bf.serialize()
        e = len(bf.fields)
        self.assertEqual(out[e:e + 5], b"e" + struct.pack(">I", len(out) - e - 5))
        self.assertEqual(xc7bit.BitFile.parse(out).packets, bf.packets)


class FrameDumpTest(unittest.TestCase):
    def test_parse_bitread_output(self):
        words = frame(3)
        lines = [" ".join(f"{w:08x}" for w in words[i:i + 6]) for i in range(0, FRAME_WORDS, 6)]
        text = ".frame 0x00000081\n" + "\n".join(lines) + "\n\n.frame 0x00420003\n" + "\n".join(lines) + "\n"
        self.assertEqual(xc7bit.parse_frame_dump(text), {0x81: words, 0x420003: words})


class CompactTest(unittest.TestCase):
    FRAMES = {0x81: frame(1), 0x82: frame(2), 0x200: frame(3)}

    def compact(self):
        bf = xc7bit.BitFile.parse(full_bitstream([frame(9)] * 4))
        xc7bit.compact(bf, self.FRAMES)
        return bf

    def test_writes_each_run_of_consecutive_frames_with_one_pad_frame(self):
        words = [w for hdr, payload in self.compact().packets for w in [hdr, *payload]]
        pad = [0] * FRAME_WORDS
        expected = (PREFIX
                    + t1(xc7bit.REG_FAR, 0x81) + t1(xc7bit.REG_CMD, xc7bit.CMD_WCFG) + [NOOP]
                    + t1(xc7bit.REG_FDRI) + t2(3 * FRAME_WORDS) + frame(1) + frame(2) + pad
                    + t1(xc7bit.REG_FAR, 0x200) + t1(xc7bit.REG_CMD, xc7bit.CMD_WCFG) + [NOOP]
                    + t1(xc7bit.REG_FDRI) + t2(2 * FRAME_WORDS) + frame(3) + pad
                    + TRAILER)
        self.assertEqual(words, expected)

    def test_output_is_much_smaller_and_reparses(self):
        bf = xc7bit.BitFile.parse(full_bitstream([frame(9)] * 200))
        before = len(bf.serialize())
        xc7bit.compact(bf, self.FRAMES)
        out = bf.serialize()
        self.assertLess(len(out), before / 20)
        self.assertEqual(xc7bit.BitFile.parse(out).packets, bf.packets)

    def test_rejects_bitstream_without_single_fdri_burst(self):
        bf = xc7bit.BitFile.parse(bit_file(PREFIX + TRAILER))
        with self.assertRaises(ValueError):
            xc7bit.compact(bf, self.FRAMES)


class ConfigRateTest(unittest.TestCase):
    def test_sets_oscfsel_only(self):
        bf = xc7bit.BitFile.parse(full_bitstream([frame(1)]))
        xc7bit.set_oscfsel(bf, 0x2B)
        cor0 = [p for h, p in bf.packets if h == t1(xc7bit.REG_COR0, 0)[0]]
        self.assertEqual(cor0, [[(0x02003FE5 & ~(0x3F << 17)) | (0x2B << 17)]])

    def test_rejects_out_of_range(self):
        bf = xc7bit.BitFile.parse(full_bitstream([frame(1)]))
        with self.assertRaises(ValueError):
            xc7bit.set_oscfsel(bf, 64)


if __name__ == "__main__":
    unittest.main()
