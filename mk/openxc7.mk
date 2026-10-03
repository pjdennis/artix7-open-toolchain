# openXC7 build + openFPGALoader programming rules.
# Inputs: TOP, RTL (synthesis sources), XDC, and a board file (boards/*.mk) providing
#         PART, FAMILY, CHIPDB_DIE, BOARD, CLK_MHZ, FLASH_BYTES and optionally OSCFSEL.
# prog/flash use the compact bitstream ($(TOP).fast.bit); pass LOAD_BIT=build/$(TOP).bit for the full one.
# fast.bit also guards against the JTAG/flash race (see scripts/xc7bit.py): its flash boot waits
# BOOT_DELAY_MS before writing anything, and a JTAG load of it redoes startup if a flash design got there first.
include $(dir $(lastword $(MAKEFILE_LIST)))tools.mk

BUILD  ?= build
CHIPDB ?= $(OPENXC7_ROOT)/chipdb/chipdb-$(CHIPDB_DIE).bin
DB     := $(PRJXRAY_DB)/$(FAMILY)
BIT    := $(BUILD)/$(TOP).bit
BOOT_DELAY_MS ?= 100
FAST_BIT := $(BUILD)/$(TOP).fast.bit
LOAD_BIT ?= $(FAST_BIT)
PART_YAML := $(DB)/$(PART)/part.yaml
BITREAD := bitread --part_file $(PART_YAML) -C -z
LOADER := openFPGALoader -b $(BOARD)

# The first flash write on a machine saves whatever was there before (e.g. a Vivado design).
# Backups are per user, not per repository, since any design may be the first to write flash.
BACKUP_DIR ?= $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/fpga-flash-backups
BACKUPS    := $(BACKUP_DIR)/$(BOARD)-first.bin

.PHONY: bit prog flash backup-flash detect reset clean
bit: $(BIT) $(FAST_BIT)

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
	xc7frames2bit --part_file $(PART_YAML) --part_name $(PART) --frm_file $< --output_file $@
	@{ echo "kit $$(git -C $(KIT_ROOT) describe --always --dirty --abbrev=12 2>/dev/null || echo unknown) ($(KIT_ROOT))"; \
	   cat $(KIT_ROOT)/TOOLCHAIN_VERSIONS; } > $(BUILD)/KIT_VERSION

# Only the frames that carry data (see scripts/xc7bit.py), checked by decoding both bitstreams.
$(FAST_BIT): $(BIT)
	$(BITREAD) -o $(BIT).frames $< > /dev/null
	python3 $(KIT_ROOT)/scripts/xc7bit.py compact $< $(BIT).frames $@ $(if $(OSCFSEL),--oscfsel $(OSCFSEL)) \
	  --restart --boot-delay-ms $(BOOT_DELAY_MS)
	$(BITREAD) -o $@.frames $@ > /dev/null
	@cmp -s $(BIT).frames $@.frames || { rm -f $@; echo "*** $@ decodes to different frames than $<"; exit 1; }

detect:
	$(LOADER) --detect

prog: $(LOAD_BIT)           # load into FPGA SRAM (lost on power-off)
	$(LOADER) $(LOAD_BIT)

flash: $(LOAD_BIT) | $(BACKUPS)  # write QSPI flash; FPGA loads it at power-up
	$(LOADER) -f --verify $(LOAD_BIT)
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
