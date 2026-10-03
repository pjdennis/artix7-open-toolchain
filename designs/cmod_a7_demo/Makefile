# Cmod A7-35T demo: heartbeat LED, button-driven LEDs, UART status reporting.
#   make test     run simulations        make bit     build bitstream
#   make prog     load into FPGA SRAM    make flash   write to QSPI flash
#   make hwcheck  verify the running design over the UART
#   make buttons  guided button test (you press, the script verifies)
TOP    := top
LIB    := ../../lib/rtl
RTL    := rtl/top.v $(LIB)/debounce.v $(LIB)/uart_tx.v $(LIB)/uart_rx.v $(LIB)/uart_line_tx.v
XDC    := constr/cmod_a7.xdc
TB_DIR := sim

include ../../boards/cmod_a7_35t.mk
include ../../mk/sim.mk
include ../../mk/openxc7.mk

.DEFAULT_GOAL := all
.PHONY: all hwcheck buttons
all: test bit

hwcheck:
	python3 $(REPO_ROOT)/scripts/uart_check.py query

buttons:
	python3 $(REPO_ROOT)/scripts/uart_check.py buttons
