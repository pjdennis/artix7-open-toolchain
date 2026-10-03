#!/usr/bin/env bash
# One-time root setup so the Cmod A7's FTDI FT2232H (0403:6010) is usable without sudo in WSL.
# Run once: sudo bash scripts/setup-usb-root.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }

cat > /etc/udev/rules.d/99-digilent-ftdi.rules <<'EOF'
# Digilent boards (FTDI FT2232H): channel A = JTAG (libftdi), channel B = UART (/dev/ttyUSBn)
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666", GROUP="dialout"
EOF

printf 'vhci_hcd\nftdi_sio\n' > /etc/modules-load.d/fpga-usb.conf
modprobe vhci_hcd
modprobe ftdi_sio

udevadm control --reload-rules
udevadm trigger
echo "USB setup complete."
