# `make test` runs the shared library testbenches and every design's tests.
TB_DIR  := lib/sim
RTL     := $(wildcard lib/rtl/*.v)
DESIGNS := $(patsubst %/Makefile,%,$(wildcard designs/*/Makefile))

include mk/sim.mk

.PHONY: test-all clean $(DESIGNS)
.DEFAULT_GOAL := test-all
test-all: test $(DESIGNS)
$(DESIGNS):
	$(MAKE) -C $@ test

clean:
	rm -rf build
	for d in $(DESIGNS); do $(MAKE) -C $$d clean; done
