# Block RAM initialisation check: BANKS RAMs are preloaded with a location-unique pattern by the
# bitstream; '?' makes the FPGA verify every word and report over the UART (see rtl/top.v).
#   make test     run simulations        make bit      build bitstreams
#   make hwtest   load the compact and full bitstreams over JTAG, then boot from flash, and check each
TOP    := top
LIB    := ../../lib/rtl
RTL    := rtl/top.v rtl/pattern_ram.v $(LIB)/uart_tx.v $(LIB)/uart_rx.v $(LIB)/uart_line_tx.v
XDC    := constr/cmod_a7.xdc
TB_DIR := sim

include ../../boards/cmod_a7_35t.mk
include ../../mk/sim.mk
include ../../mk/openxc7.mk

.DEFAULT_GOAL := all
.PHONY: all hwtest
all: test bit

CHECK := python3 $(KIT_ROOT)/scripts/bram_check.py
hwtest: $(FAST_BIT) $(BIT)
	@for b in $(FAST_BIT) $(BIT); do \
	  echo "== JTAG load: $$b"; $(LOADER) $$b > /dev/null 2>&1 && $(CHECK) check && $(CHECK) selftest || exit 1; \
	done
	@echo "== Flash boot: $(FAST_BIT)"
	@$(LOADER) -f --verify $(FAST_BIT) > /dev/null 2>&1 && $(LOADER) -r > /dev/null 2>&1 && sleep 0.5 && $(CHECK) check && $(CHECK) selftest
