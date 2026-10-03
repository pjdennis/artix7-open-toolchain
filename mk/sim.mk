# Self-checking Icarus Verilog testbenches.
# Inputs: TB_DIR (holds tb_*.v), RTL (sources under test). `make test` runs every testbench;
# a testbench passes only if vvp exits 0 and its last line is "PASS" (see lib/sim/tb_util.vh).
include $(dir $(lastword $(MAKEFILE_LIST)))tools.mk

SIM_BUILD ?= build/sim
TBS       := $(wildcard $(TB_DIR)/tb_*.v)
TB_PASS   := $(patsubst $(TB_DIR)/%.v,$(SIM_BUILD)/%.pass,$(TBS))
IVERILOG  := iverilog -g2012 -Wall -I $(REPO_ROOT)/lib/sim

.PHONY: test
test: $(TB_PASS)

$(SIM_BUILD)/%.pass: $(TB_DIR)/%.v $(RTL) $(REPO_ROOT)/lib/sim/tb_util.vh
	@mkdir -p $(SIM_BUILD)
	$(IVERILOG) -s $* -o $(SIM_BUILD)/$*.vvp $< $(RTL)
	@cd $(SIM_BUILD) && vvp -n $*.vvp > $*.log 2>&1; rc=$$?; cat $*.log; \
	  [ $$rc -eq 0 ] && [ "$$(tail -n1 $*.log)" = PASS ] || { echo "*** $* FAILED"; exit 1; }
	@touch $@
