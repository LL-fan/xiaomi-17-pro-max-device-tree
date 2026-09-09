# Xiaomi 17 Pro Max (popsicle / canoe / Qualcomm SM8850) device tree
#
#   make            Build all DTB/DTBO artifacts from dts/ into build/
#   make verify     Rebuild and compare against the shipped stock blobs
#   make clean      Remove build output
#
# Requirements: device-tree-compiler (dtc >= 1.6), python3. No kernel tree is
# required to rebuild these DTS because the decompiled constants are inlined.
DTC       ?= dtc
PYTHON    ?= python3
PAGE_SIZE ?= 4096
OUT       := build

.PHONY: all dtb verify clean help

all: dtb

dtb:
	@DTC="$(DTC)" PAGE_SIZE="$(PAGE_SIZE)" bash scripts/build-dtb.sh

verify:
	@bash scripts/verify-stock.sh

clean:
	rm -rf "$(OUT)"

help:
	@echo "make / make dtb   compile dts/*.dts(.dtsi) and overlays into $(OUT)/"
	@echo "make verify       rebuild and diff model/compatible against original/"
	@echo "make clean        remove $(OUT)/"
