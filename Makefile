# ------------------------------------------------------------------
# Makefile – self-checking Verilator testbenches + ULX3S bitstream
# ------------------------------------------------------------------
# Targets:
#   make / make test     – build & run every testbench
#   make test-<name>     – one testbench (tbs/tb_<name>.sv), e.g. make test-tmds
#   make test-<name> WAVES=1  – also dump build/tb_<name>.vcd
#   make wave T=<name>   – open build/tb_<name>.vcd in gtkwave
#   make coverage        – run every testbench with Verilator coverage and pack
#                          build/coverage/coverview.zip (needs info-process)
#   make coverage-html   – standalone Coverview dashboard build/coverage/index.html
#                          (also needs git, node/npm)
#   make clean
# Every testbench exits non-zero on the first failed check.
# ------------------------------------------------------------------

VERILATOR   = verilator
VFLAGS      = --binary --timing --timescale 1ns/1ps -Wall -Wno-fatal \
              --trace -j 0 -Itbs -CFLAGS "-std=c++17"

BUILD       = build
# Compiler temporaries go under build/ instead of a possibly full /tmp.
BUILD_TMP   = $(CURDIR)/$(BUILD)/tmp

TESTS       = tmds serial10b differential bram display_signal pattern pll \
              hdmi steer top

# Simulation-only models of the Lattice ECP5 primitives and shared TB code.
ODDR_MODEL  = tbs/models/ODDRX1F.v
PLL_MODEL   = tbs/models/EHXPLLL.v
TMDS_REF    = tbs/tmds_ref.sv
TMDS_RX     = tbs/tmds_rx.sv

SRCS_tmds           = $(TMDS_REF) rtl/tmds.sv
SRCS_serial10b      = $(ODDR_MODEL) rtl/serial10b.sv
SRCS_differential   = rtl/differential.sv
SRCS_bram           = rtl/bram.sv
SRCS_display_signal = rtl/display_signal.sv
SRCS_pattern        = rtl/pattern.sv
SRCS_pll            = $(PLL_MODEL) rtl/pll.sv
SRCS_hdmi           = $(TMDS_REF) $(TMDS_RX) $(ODDR_MODEL) rtl/tmds.sv \
                      rtl/serial10b.sv rtl/differential.sv rtl/hdmi.sv
SRCS_steer          = $(SRCS_hdmi) $(PLL_MODEL) rtl/pll.sv \
                      rtl/display_signal.sv rtl/pattern.sv rtl/steer.sv
SRCS_top            = $(SRCS_steer) rtl/top.sv

# Extra prerequisites that are not compiled (e.g. $readmemh images).
DATA_bram           = tbs/data/bram_init.hex

.PHONY: all test $(addprefix test-,$(TESTS)) coverage coverage-html wave clean \
        bitstream prog fpga-clean

all: test

test: $(addprefix test-,$(TESTS))
	@echo ""
	@echo "=== All tests passed ==="

define TEST_template
$(BUILD)/tb_$(1)/Vtb_$(1): $$(SRCS_$(1)) tbs/tb_$(1).sv $$(DATA_$(1))
	@mkdir -p $$(@D) $(BUILD_TMP)
	TMPDIR=$(BUILD_TMP) $$(VERILATOR) $$(VFLAGS) --top-module tb_$(1) \
	    --Mdir $$(@D) $$(SRCS_$(1)) tbs/tb_$(1).sv

test-$(1): $(BUILD)/tb_$(1)/Vtb_$(1)
	@echo "=== tb_$(1) ==="
	./$$< $$(if $$(WAVES),+waves)
endef

$(foreach t,$(TESTS),$(eval $(call TEST_template,$(t))))

# ------------------------------------------------------------------
# Coverage: Verilator line/branch/toggle/expression coverage of rtl/,
# merged per type with info-process and packed for Coverview.
# https://github.com/antmicro/coverview
# https://github.com/antmicro/info-process
# ------------------------------------------------------------------
VERILATOR_COVERAGE = verilator_coverage
INFO_PROCESS       = info-process

COV_DIR      = $(BUILD)/cov
COV_OUT      = $(BUILD)/coverage
COV_TYPES    = line branch toggle expr
COV_DATASET  = verilator
COV_DATS     = $(foreach t,$(TESTS),$(COV_DIR)/dat/tb_$(t).dat)
COV_PACK     = $(COV_DIR)/pack

# Dashboard metadata; GitHub Actions variables take precedence over git.
COV_REPO    ?= $(or $(GITHUB_REPOSITORY),$(notdir $(CURDIR)))
COV_BRANCH  ?= $(or $(GITHUB_HEAD_REF),$(GITHUB_REF_NAME),$(shell git rev-parse --abbrev-ref HEAD 2>/dev/null),local)
COV_COMMIT  ?= $(or $(GITHUB_SHA),$(shell git rev-parse HEAD 2>/dev/null),unknown)

COVERVIEW_REPO = https://github.com/antmicro/coverview.git
COVERVIEW_REF  = cb550b9f2198d8307774c0106c8ef882145a606a
COVERVIEW_DIR  = $(BUILD)/coverview

define COV_template
$(COV_DIR)/tb_$(1)/Vtb_$(1): $$(SRCS_$(1)) tbs/tb_$(1).sv $$(DATA_$(1))
	@mkdir -p $$(@D) $(BUILD_TMP)
	TMPDIR=$(BUILD_TMP) $$(VERILATOR) $$(VFLAGS) --coverage --top-module tb_$(1) \
	    --Mdir $$(@D) $$(SRCS_$(1)) tbs/tb_$(1).sv

$(COV_DIR)/dat/tb_$(1).dat: $(COV_DIR)/tb_$(1)/Vtb_$(1)
	@mkdir -p $$(@D)
	@echo "=== tb_$(1) (coverage) ==="
	./$$< +verilator+coverage+file+$$@.tmp
	mv $$@.tmp $$@
endef

$(foreach t,$(TESTS),$(eval $(call COV_template,$(t))))

coverage: $(COV_OUT)/coverview.zip
	@cat $(COV_OUT)/summary.md

# One .info per testbench and coverage type, restricted to rtl/, then merged
# per type into coverage_<type>_<dataset>.info plus a tests_<type>_<dataset>.desc
# listing the testbenches that hit each line (names Coverview expects). Toggle
# entries are re-numbered so each signal's 0->1 / 1->0 pair forms one block.
$(COV_OUT)/coverview.zip: $(COV_DATS)
	rm -rf $(COV_DIR)/info $(COV_PACK)
	@mkdir -p $(COV_PACK) $(COV_OUT)
	@set -e; for type in $(COV_TYPES); do \
	    mkdir -p $(COV_DIR)/info/$$type; \
	    for dat in $(COV_DATS); do \
	        info=$(COV_DIR)/info/$$type/$$(basename $$dat .dat).info; \
	        $(VERILATOR_COVERAGE) --filter-type $$type --write-info $$info $$dat; \
	        $(INFO_PROCESS) transform --filter '^rtl/' $$info; \
	    done; \
	    $(INFO_PROCESS) merge \
	        --test-list $(COV_PACK)/tests_$${type}_$(COV_DATASET).desc \
	        --output $(COV_PACK)/coverage_$${type}_$(COV_DATASET).info \
	        $(COV_DIR)/info/$$type/*.info; \
	done
	$(INFO_PROCESS) transform --set-block-ids --set-block-ids-step 2 \
	    $(COV_PACK)/coverage_toggle_$(COV_DATASET).info
	printf '{\n  "title": "%s",\n  "repo": "%s",\n  "branch": "%s",\n  "commit": "%s",\n  "timestamp": "%s",\n  "tests_as_total": true\n}\n' \
	    "RTL coverage" "$(COV_REPO)" "$(COV_BRANCH)" "$(COV_COMMIT)" \
	    "$$(date -u +%Y-%m-%dT%H:%M:%S.000+0000)" > $(COV_DIR)/config.json
	$(INFO_PROCESS) pack --output $@ --config $(COV_DIR)/config.json \
	    --coverage-files $(COV_PACK)/*.info --description-files $(COV_PACK)/*.desc
	$(INFO_PROCESS) report --file-summary-only --output $(COV_DIR)/report.json $@
	python3 tbs/coverage_summary.py $(COV_DIR)/report.json > $(COV_OUT)/summary.md

# Standalone dashboard: Coverview production build with the archive embedded.
$(COVERVIEW_DIR)/dist/index.html:
	rm -rf $(COVERVIEW_DIR)
	git clone --quiet $(COVERVIEW_REPO) $(COVERVIEW_DIR)
	git -C $(COVERVIEW_DIR) checkout --quiet $(COVERVIEW_REF)
	cd $(COVERVIEW_DIR) && npm ci && npm run build

coverage-html: $(COV_OUT)/coverview.zip $(COVERVIEW_DIR)/dist/index.html
	cd $(COVERVIEW_DIR) && python3 embed.py --inject-data $(abspath $(COV_OUT)/coverview.zip)
	cp $(COVERVIEW_DIR)/dist/index.html $(COV_OUT)/index.html
	@cat $(COV_OUT)/summary.md

wave:
	@gtkwave $(BUILD)/tb_$(T).vcd &

clean:
	rm -f *.vcd *.fst $(FPGA_JSON) $(FPGA_CONFIG) $(FPGA_BIT)
	rm -rf $(BUILD)


# ------------------------------------------------------------------
# ULX3S FPGA bitstream build
# ------------------------------------------------------------------
FPGA_TOP   ?= top
FPGA_SRCS  := rtl/*.sv 

FPGA_JSON  := ulx3s.json
FPGA_CONFIG := ulx3s_out.config
FPGA_BIT   := ulx3s.bit
FPGA_LPF   := ulx3s_v20.lpf

YOSYS       ?= yosys
NEXTPNR     ?= nextpnr-ecp5
ECPPACK     ?= ecppack
FUJPROG     ?= fujprog

# ULX3S with LFE5U-85F FPGA
FPGA_DEVICE  ?= --85k
FPGA_PACKAGE ?= CABGA381
FPGA_SPEED   ?= 6

# ------------------------------------------------------------------
# ULX3S synthesis, place-and-route, and bitstream
# ------------------------------------------------------------------

bitstream: $(FPGA_BIT)

$(FPGA_JSON): $(FPGA_SRCS)
	$(YOSYS) -p 'read_verilog -sv $(FPGA_SRCS); synth_ecp5 -top $(FPGA_TOP) -json $@'

$(FPGA_CONFIG): $(FPGA_JSON) $(FPGA_LPF)
	$(NEXTPNR) $(FPGA_DEVICE) \
	    --package $(FPGA_PACKAGE) \
	    --speed $(FPGA_SPEED) \
	    --json $(FPGA_JSON) \
	    --lpf $(FPGA_LPF) \
	    --textcfg $@

$(FPGA_BIT): $(FPGA_CONFIG)
	$(ECPPACK) $< $@

# Program the connected ULX3S board
prog: $(FPGA_BIT)
	$(FUJPROG) $(FPGA_BIT)

# Remove FPGA build artifacts only
fpga-clean:
	rm -f $(FPGA_JSON) $(FPGA_CONFIG) $(FPGA_BIT)
