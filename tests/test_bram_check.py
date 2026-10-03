import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
sys.path.insert(0, os.path.dirname(__file__))
import bram_check  # noqa: E402
import uart_check  # noqa: E402
from test_uart_check import FakeBoard  # noqa: E402


class ParseTest(unittest.TestCase):
    def test_valid_report(self):
        self.assertEqual(bram_check.parse_report(b"BRAM N=20 ERR=0001 AT=1F:3FF\r\n"),
                         {"banks": 32, "errors": 1, "bank": 31, "addr": 1023})

    def test_rejects_other_lines(self):
        for line in (b"", b"CMODA7 OK B0=0 B1=0 C=0\r\n", b"BRAM N=20 ERR=00G1 AT=00:000\r\n"):
            with self.subTest(line=line):
                self.assertIsNone(bram_check.parse_report(line))


class QueryTest(unittest.TestCase):
    def test_scan_returns_report(self):
        board = FakeBoard(on_query=b"BRAM N=20 ERR=0000 AT=00:000\r\n")
        with uart_check.Serial(board.port) as ser:
            self.assertEqual(bram_check.scan(ser), {"banks": 32, "errors": 0, "bank": 0, "addr": 0})
        board.close()

    def test_scan_times_out_on_other_designs(self):
        board = FakeBoard(on_query=b"CMODA7 OK B0=0 B1=0 C=0\r\n")
        with uart_check.Serial(board.port) as ser:
            with self.assertRaises(TimeoutError):
                bram_check.scan(ser, timeout=0.3)
        board.close()


if __name__ == "__main__":
    unittest.main()
