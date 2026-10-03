ifndef TOOLS_MK_INCLUDED
TOOLS_MK_INCLUDED := 1
# Toolchain locations (see scripts/install-toolchain.sh). Lets `make` work without sourcing env.sh.
KIT_ROOT    := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
FPGA_PREFIX  ?= $(HOME)/opt/fpga
OPENXC7_ROOT ?= $(FPGA_PREFIX)/openxc7
PRJXRAY_DB   ?= $(OPENXC7_ROOT)/share/nextpnr/external/prjxray-db
export PATH  := $(PATH):$(OPENXC7_ROOT)/bin:$(FPGA_PREFIX)/oss-cad-suite/bin
endif
