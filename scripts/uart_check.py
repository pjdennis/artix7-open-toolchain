#!/usr/bin/env python3
"""Checks the cmod_a7_demo design over the Cmod A7's USB-UART (stdlib only).

  uart_check.py query     ask for a status line ('?'); exit 0 if the design answers
  uart_check.py buttons   guided test: prompts you to press each button and verifies the reports
  uart_check.py watch     print status lines as they arrive (Ctrl-C to stop)
"""
import argparse
import glob
import os
import re
import select
import sys
import termios
import time

STATUS_RE = re.compile(rb"CMODA7 OK B0=([01]) B1=([01]) C=([0-4])\r?\n?$")


def parse_status(line):
    m = STATUS_RE.search(line)
    return {"B0": int(m[1]), "B1": int(m[2]), "C": int(m[3])} if m else None


def find_port():
    ports = sorted(glob.glob("/dev/serial/by-id/*Digilent*-if01-port0"))
    if not ports:
        sys.exit("No Digilent UART found (run scripts/attach-board.sh; is ftdi_sio loaded?)")
    return ports[0]


class Serial:
    """Minimal raw 8N1 serial port."""

    def __init__(self, path, baud=termios.B115200):
        self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0                                               # iflag: raw
        attrs[1] = 0                                               # oflag: raw
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL    # cflag: 8N1
        attrs[3] = 0                                               # lflag: no echo/canonical
        attrs[4] = attrs[5] = baud
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        self.buf = b""

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        os.close(self.fd)

    def flush_input(self):
        termios.tcflush(self.fd, termios.TCIFLUSH)
        self.buf = b""

    def write(self, data):
        os.write(self.fd, data)

    def readline(self, deadline):
        """Returns the next line; deadline is a time.monotonic() value, or None to wait forever."""
        while b"\n" not in self.buf:
            remaining = None if deadline is None else deadline - time.monotonic()
            if remaining is not None and remaining <= 0 or not select.select([self.fd], [], [], remaining)[0]:
                raise TimeoutError("no response from board")
            self.buf += os.read(self.fd, 256)
        line, _, self.buf = self.buf.partition(b"\n")
        return line + b"\n"


def wait_for(ser, predicate, timeout):
    """Returns the first status line satisfying predicate; ignores anything else. timeout=None waits forever."""
    deadline = None if timeout is None else time.monotonic() + timeout
    while True:
        st = parse_status(ser.readline(deadline))
        if st and predicate(st):
            return st


def query(ser, timeout=1.0):
    ser.flush_input()
    ser.write(b"?")
    return wait_for(ser, lambda st: True, timeout)


def guided_buttons(ser, timeout=60):
    color = query(ser)["C"]
    steps = [
        ("Press and hold BTN0 (LD2 should light)", lambda s: s["B0"] == 1),
        ("Release BTN0", lambda s: s["B0"] == 0),
        ("Press BTN1 (RGB LED should change colour)", lambda s: s["B1"] == 1 and s["C"] == (color + 1) % 5),
        ("Release BTN1", lambda s: s["B1"] == 0),
    ]
    for prompt, pred in steps:
        print(f"  {prompt} ...", flush=True)
        print(f"    ok: {wait_for(ser, pred, timeout)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["query", "buttons", "watch"], nargs="?", default="query")
    ap.add_argument("--port", help="serial device (default: auto-detect Digilent UART)")
    args = ap.parse_args()
    port = args.port or find_port()
    try:
        with Serial(port) as ser:
            if args.mode == "query":
                print(f"{port}: {query(ser)}")
            elif args.mode == "buttons":
                guided_buttons(ser)
                print("Button test passed.")
            else:
                while True:  # raw lines, so malformed or out-of-range reports stay visible
                    print(ser.readline(deadline=None).decode(errors="replace").rstrip(), flush=True)
    except TimeoutError as e:
        sys.exit(f"FAIL: {e}")
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
