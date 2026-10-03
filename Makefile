# `make` runs the shared library testbenches, the host-script tests and every design's tests.
TB_DIR  := lib/sim
RTL     := $(wildcard lib/rtl/*.v)
DESIGNS := $(patsubst %/Makefile,%,$(wildcard designs/*/Makefile))

include mk/sim.mk

.PHONY: test-all test-py clean $(DESIGNS)
.DEFAULT_GOAL := test-all
test-all: test test-py $(DESIGNS)
test-py:
	python3 -m unittest discover -s tests
$(DESIGNS):
	$(MAKE) -C $@ test

clean:
	rm -rf build
	for d in $(DESIGNS); do $(MAKE) -C $$d clean; done
