import os
import sys
import threading
import tty
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
import uart_check  # noqa: E402


def status(b0, b1, c):
    return f"CMODA7 OK B0={b0} B1={b1} C={c}\r\n".encode()


class FakeBoard:
    """Plays the FPGA side of the serial link on a pty."""

    def __init__(self, on_query=None, events=()):
        self.master, self.slave = os.openpty()  # slave held open so master reads don't hit EIO
        self.port = os.ttyname(self.slave)
        tty.setraw(self.slave)  # raw before events are written, as a real serial port would be
        self.on_query = on_query
        self.events = list(events)
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        for ev in self.events:
            os.write(self.master, ev)
        while self.on_query:
            try:
                data = os.read(self.master, 64)
            except OSError:
                return
            if b"?" in data:
                os.write(self.master, self.on_query)

    def close(self):
        os.close(self.master)
        os.close(self.slave)


class ParseStatusTest(unittest.TestCase):
    def test_valid_line(self):
        self.assertEqual(uart_check.parse_status(b"CMODA7 OK B0=1 B1=0 C=3\r\n"),
                         {"B0": 1, "B1": 0, "C": 3})

    def test_rejects_garbage(self):
        for line in (b"", b"hello\r\n", b"CMODA7 OK B0=2 B1=0 C=0\r\n", b"CMODA7 OK B0=1 B1=0 C=5\r\n"):
            with self.subTest(line=line):
                self.assertIsNone(uart_check.parse_status(line))


class QueryTest(unittest.TestCase):
    def test_query_returns_status(self):
        board = FakeBoard(on_query=status(0, 1, 2))
        with uart_check.Serial(board.port) as ser:
            self.assertEqual(uart_check.query(ser), {"B0": 0, "B1": 1, "C": 2})
        board.close()

    def test_query_skips_stale_and_junk_lines(self):
        board = FakeBoard(on_query=b"\x00junk\r\n" + status(1, 0, 4))
        with uart_check.Serial(board.port) as ser:
            self.assertEqual(uart_check.query(ser), {"B0": 1, "B1": 0, "C": 4})
        board.close()

    def test_query_times_out_when_silent(self):
        board = FakeBoard()
        with uart_check.Serial(board.port) as ser:
            with self.assertRaises(TimeoutError):
                uart_check.query(ser, timeout=0.3)
        board.close()


class WaitForTest(unittest.TestCase):
    def test_wait_for_condition_across_events(self):
        board = FakeBoard(events=[status(1, 0, 0), status(0, 0, 0), status(0, 1, 1)])
        with uart_check.Serial(board.port) as ser:
            st = uart_check.wait_for(ser, lambda s: s["C"] == 1, timeout=2)
        self.assertEqual(st, {"B0": 0, "B1": 1, "C": 1})
        board.close()

    def test_wait_for_without_timeout(self):
        board = FakeBoard(events=[status(1, 0, 0)])
        with uart_check.Serial(board.port) as ser:
            self.assertEqual(uart_check.wait_for(ser, lambda s: True, timeout=None), {"B0": 1, "B1": 0, "C": 0})
        board.close()

    def test_readline_returns_unparseable_lines_for_watch(self):
        board = FakeBoard(events=[b"CMODA7 OK B0=0 B1=0 C=7\r\n"])
        with uart_check.Serial(board.port) as ser:
            self.assertEqual(ser.readline(deadline=None), b"CMODA7 OK B0=0 B1=0 C=7\r\n")
        board.close()

    def test_wait_for_times_out(self):
        board = FakeBoard(events=[status(1, 0, 0)])
        with uart_check.Serial(board.port) as ser:
            with self.assertRaises(TimeoutError):
                uart_check.wait_for(ser, lambda s: s["B1"] == 1, timeout=0.3)
        board.close()


if __name__ == "__main__":
    unittest.main()
