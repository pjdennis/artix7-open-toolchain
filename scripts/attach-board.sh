#!/usr/bin/env bash
# Attaches the Cmod A7 (FTDI 0403:6010) from Windows to this WSL distro via usbipd-win.
# First run triggers one Windows UAC prompt to "bind" (share) the device; Windows remembers it.
#   scripts/attach-board.sh          attach once
#   scripts/attach-board.sh --auto   also keep re-attaching in the background after replug
set -euo pipefail

HWID="${HWID:-0403:6010}"
USBIPD="${USBIPD:-/mnt/c/Program Files/usbipd-win/usbipd.exe}"

device_line() { "$USBIPD" list | tr -d '\r' | sed -n '/^Connected:/,/^$/p' | grep -i " $HWID " || true; }
in_wsl()      { lsusb -d "$HWID" >/dev/null 2>&1; }

if in_wsl && [[ "${1:-}" != --auto ]]; then echo "Board already attached to WSL."; exit 0; fi

line=$(device_line)
[[ -n "$line" ]] || { echo "No $HWID device connected to Windows. Is the board plugged in?" >&2; exit 1; }
echo "Windows sees: $line"

if [[ "$line" == *"Not shared"* ]]; then
  echo "Sharing device with WSL (approve the Windows admin prompt)..."
  powershell.exe -NoProfile -Command \
    "Start-Process -FilePath '$(wslpath -w "$USBIPD")' -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList 'bind','--hardware-id','$HWID'"
  [[ "$(device_line)" != *"Not shared"* ]] || { echo "Bind failed or was declined." >&2; exit 1; }
fi

if [[ "${1:-}" == --auto ]]; then
  nohup "$USBIPD" attach --wsl --auto-attach --hardware-id "$HWID" > "${TMPDIR:-/tmp}/usbipd-auto-attach.log" 2>&1 &
  echo "Auto-attach running in background (pid $!)."
elif ! in_wsl; then
  "$USBIPD" attach --wsl --hardware-id "$HWID"
fi

for _ in $(seq 30); do in_wsl && break; sleep 0.5; done
in_wsl || { echo "Device did not appear in WSL." >&2; exit 1; }
lsusb -d "$HWID"
for _ in $(seq 20); do compgen -G "/dev/serial/by-id/*Digilent*-if01-*" >/dev/null && break; sleep 0.5; done
ls -l /dev/serial/by-id/ 2>/dev/null | grep -i digilent || echo "Note: no UART tty yet (is ftdi_sio loaded? run scripts/setup-usb-root.sh)"
