# Open-source FPGA toolchain for the Digilent Cmod A7-35T (WSL2)

Yosys → nextpnr-xilinx → Project X-Ray → openFPGALoader, no Vivado. Tested on Ubuntu 22.04 / WSL2
with usbipd-win 5.2, OSS CAD Suite 2026-10-02 and openXC7 2026-09-30 (see `TOOLCHAIN_VERSIONS`).

## Setup (once)

```sh
scripts/install-toolchain.sh             # ~840 MB download into ~/opt/fpga, no root needed
sudo bash scripts/setup-usb-root.sh      # udev rule for the FTDI chip + ftdi_sio/vhci_hcd modules
scripts/attach-board.sh                  # share (one Windows UAC prompt) and attach the board to WSL
```

`scripts/attach-board.sh --auto` keeps re-attaching in the background, so unplug/replug just works.
The attachment is lost when WSL restarts; re-run the script.

`make` finds the tools itself; `source env.sh` puts them on your shell's PATH for interactive use.

## Daily use

```sh
make                                     # all simulations + host-script tests
cd designs/cmod_a7_demo
make            # simulate, then build build/top.bit and build/top.fast.bit (~12 s)
make prog       # load into FPGA SRAM in ~0.25 s (lost at power-off)
make hwcheck    # ask the running design for its status over the USB-UART
make buttons    # guided test: you press BTN0/BTN1, the script verifies the reports
make flash      # write QSPI flash (~7 s incl. verify); boots from flash in ~30 ms
make reset      # reconfigure the FPGA from flash
make detect     # show the JTAG chain (expect IDCODE 0x0362D093)
make backup-flash   # timestamped dump of the 4 MiB flash into flash-backups/
```

The first `make flash` on a machine dumps whatever was in flash to `flash-backups/<board>-first.bin`.

## Fast loading

`prog` and `flash` use `build/top.fast.bit`, made by `scripts/xc7bit.py` from the full bitstream:

- **Only data-carrying frames.** xc7frames2bit writes every configuration frame of the device
  (2.1 MB), but configuration memory is cleared before every load, so all-zero frames can be
  skipped. The demo uses 189 of 5,408 frames, giving a 97 KB file, 23x smaller. The build
  decodes both bitstreams with `bitread` and fails if their frames differ.
- **Faster flash clock.** `OSCFSEL` in the board file sets the clock the FPGA uses to read flash
  at boot (Vivado's ConfigRate). The encoding isn't documented; these values were measured on
  this board: 0 = 3.3 MHz (default), 4 = 23 MHz, 6 = ~31 MHz (used), 8 = ~37 MHz.

| | Full bitstream, default clock | Fast |
|---|---|---|
| `make prog` | 3.35 s | 0.25 s |
| `make flash` | ~2 min | ~7 s |
| Flash boot (reconfigure until the design answers) | ~4 s | ~30 ms |

Hardware check: `make -C designs/bram_check hwtest` preloads 32 block RAMs (1,024 content frames
across both chip halves and both clock-region rows) with a location-unique pattern. It then has
the FPGA verify every word after a compact JTAG load, a full JTAG load and a compact flash boot,
and runs a self-test that a corrupted word is detected. All pass. Designs dominated by RAM
contents shrink less (this one is 1.05 MB, 2x smaller).

To use the full bitstream, pass `LOAD_BIT=build/top.bit`, e.g. `make prog LOAD_BIT=build/top.bit`.
`python3 scripts/xc7bit.py info <file.bit>` prints a bitstream's configuration commands.

## Demo design (`designs/cmod_a7_demo`)

| | Behaviour |
|---|---|
| LD1 | 1 Hz heartbeat |
| LD2 | lit while BTN0 is held |
| RGB LED | BTN1 cycles off → red → green → blue → white (dimmed, active-low pins) |
| UART 115200 8N1 | `?` → `CMODA7 OK B0=b B1=b C=c`; also sent on every button press/release |

`scripts/uart_check.py {query,buttons,watch}` speaks this protocol using only the Python stdlib.

## Layout

```
boards/cmod_a7_35t.mk    part, chipdb die, openFPGALoader board, clock, flash size
mk/openxc7.mk            synth / place-and-route / bitstream / program rules
mk/sim.mk                self-checking iverilog testbenches (must print PASS last)
lib/rtl, lib/sim         reusable debounce + UART modules and their testbenches
designs/<name>/          rtl/, sim/, constr/*.xdc, Makefile (copy cmod_a7_demo to start)
designs/bram_check/      block RAM initialisation check (`make hwtest`), see Fast loading
scripts/                 installer, USB setup/attach, UART checker
tests/                   tests for the host scripts
```

## Gotchas found while setting this up

- **XDC syntax:** nextpnr-xilinx crashes on Digilent's `[get_ports { name }]`. Write `{name}`
  with no spaces inside the braces.
- **Chip database:** the openXC7 release keeps chipdbs in `openxc7/chipdb/`, not where
  nextpnr looks by default, so the build passes `--chipdb`. An xc7a35t uses the xc7a50t die file,
  so nextpnr's utilisation percentages are against the 50T. Stay within the 35T's 20,800 LUTs.
- **Register initial values after JTAG loads:** while the flash still held a Vivado-built
  design, every `make prog` came up with register initial values ignored (e.g. `reg [2:0] c = 0`
  powered up as 7). Booting the same bitstream from flash was correct. After the flash was
  rewritten with an openXC7 design, JTAG loads were correct too, and have stayed correct.
  The likely cause is the old flash image's boot interfering with the JTAG load, but this
  wasn't confirmed. If initial values look wrong after `make prog`, run `make flash` once.
- **Startup glitches:** don't rely on button or UART state in the first few milliseconds after
  configuration.
- **`bit2fasm` in the openXC7 release** calls `bitread` through a `/nix/store/.../sh` path that
  doesn't exist. Run `bitread` yourself and feed the `.bits` file to the disassembler instead.
- **Flash read width:** flash boot still reads one bit at a time. Four-bit (quad) mode would need
  bus-width detection words in the bitstream and the flash's quad-enable bit set, and at ~30 ms
  per boot it isn't worth it.
