#!/usr/bin/env python3
"""Checks the bram_check design over the Cmod A7's USB-UART (stdlib only).

  bram_check.py check [--banks N]   scan all block RAM; exit 0 if every word holds its preloaded value
  bram_check.py selftest            corrupt one word ('x') and require exactly that error to be reported
"""
import argparse
import re
import sys

from uart_check import Serial, find_port, query

REPORT_RE = re.compile(rb"BRAM N=([0-9A-F]{2}) ERR=([0-9A-F]{4}) AT=([0-9A-F]{2}):([0-9A-F]{3})\r?\n?$")


def parse_report(line):
    m = REPORT_RE.search(line)
    return dict(zip(("banks", "errors", "bank", "addr"), (int(g, 16) for g in m.groups()))) if m else None


def scan(ser, timeout=1.0):
    return query(ser, timeout, parse=parse_report)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["check", "selftest"])
    ap.add_argument("--banks", type=int, help="expected number of RAM banks")
    ap.add_argument("--port", help="serial device (default: auto-detect Digilent UART)")
    args = ap.parse_args()
    with Serial(args.port or find_port()) as ser:
        try:
            rep = scan(ser)
            if args.mode == "selftest":
                ser.write(b"x")
                rep = scan(ser)
                ok = rep["errors"] == 1 and (rep["bank"], rep["addr"]) == (0, 5)
            else:
                ok = rep["errors"] == 0 and args.banks in (None, rep["banks"])
        except TimeoutError as e:
            sys.exit(f"FAIL: {e}")
    print(f"{'ok' if ok else 'FAIL'}: {rep}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
