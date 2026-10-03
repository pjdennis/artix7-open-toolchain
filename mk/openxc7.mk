# openXC7 build + openFPGALoader programming rules.
# Inputs: TOP, RTL (synthesis sources), XDC, and a board file (boards/*.mk) providing
#         PART, FAMILY, CHIPDB_DIE, BOARD, CLK_MHZ, FLASH_BYTES.
include $(dir $(lastword $(MAKEFILE_LIST)))tools.mk

BUILD  ?= build
CHIPDB ?= $(OPENXC7_ROOT)/chipdb/chipdb-$(CHIPDB_DIE).bin
DB     := $(PRJXRAY_DB)/$(FAMILY)
BIT    := $(BUILD)/$(TOP).bit
LOADER := openFPGALoader -b $(BOARD)

# The first flash write on a machine saves whatever was there before (e.g. a Vivado design).
BACKUP_DIR := $(REPO_ROOT)/flash-backups
BACKUPS    := $(BACKUP_DIR)/$(BOARD)-first.bin

.PHONY: bit prog flash backup-flash detect reset clean
bit: $(BIT)

$(BUILD)/$(TOP).json: $(RTL)
	@mkdir -p $(BUILD)
	yosys -q -l $(BUILD)/yosys.log -p 'synth_xilinx -flatten -abc9 -arch xc7 -top $(TOP); write_json $@' $(RTL)

$(BUILD)/$(TOP).fasm: $(BUILD)/$(TOP).json $(XDC)
	nextpnr-xilinx -q -l $(BUILD)/nextpnr.log --chipdb $(CHIPDB) --device $(PART) --freq $(CLK_MHZ) \
	  -o xdc=$(XDC) -o fasm=$@ --json $< --report $(BUILD)/report.json
	@grep "Max frequency" $(BUILD)/nextpnr.log | tail -n1

$(BUILD)/$(TOP).frames: $(BUILD)/$(TOP).fasm
	fasm2frames --part $(PART) --db-root $(DB) $< > $@

$(BIT): $(BUILD)/$(TOP).frames
	xc7frames2bit --part_file $(DB)/$(PART)/part.yaml --part_name $(PART) --frm_file $< --output_file $@

detect:
	$(LOADER) --detect

prog: $(BIT)                # load into FPGA SRAM (lost on power-off)
	$(LOADER) $(BIT)

flash: $(BIT) | $(BACKUPS)  # write QSPI flash; FPGA loads it at power-up
	$(LOADER) -f --verify $(BIT)
$(BACKUPS):
	@mkdir -p $(BACKUP_DIR)
	$(LOADER) --dump-flash --file-size $(FLASH_BYTES) $@.tmp && mv $@.tmp $@

backup-flash:               # timestamped copy of the current flash contents
	@mkdir -p $(BACKUP_DIR)
	$(LOADER) --dump-flash --file-size $(FLASH_BYTES) $(BACKUP_DIR)/$(BOARD)-$$(date +%Y%m%d-%H%M%S).bin

reset:                      # reconfigure the FPGA from flash
	$(LOADER) -r

clean:
	rm -rf $(BUILD)
