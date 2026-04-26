# =============================================================================
# OpenSoC Tier-1 -- QuestaSim Makefile  (Shakti E-class SoC -- Level-1)
# =============================================================================
# Usage (from project root):
#
#   make eclass_regression      -- E-class structural regression (default)
#   make <test>                 -- compile + simulate a single E-class TB
#   make t1_eclass_cpu_tb       -- build C + run L1 CPU boot test
#   make t1_eclass_gpio_tb      -- GPIO register + pin test L1 (USE_ISS + C test)
#   make t1_gpio_cpu_tb         -- alias for t1_eclass_gpio_tb
#   make t1_eclass_uart_tb      -- UART loopback test L1 (USE_ISS + C test)
#   make t1_uart_cpu_tb         -- alias for t1_eclass_uart_tb
#   make l1_coverage            -- build + run functional coverage (USE_ISS)
#   make cov_report_l1          -- generate HTML coverage report from UCDB
#   make clean                  -- delete build artefacts
#   make help                   -- print this help
#
# E-class structural tests (no USE_ISS):
#   t1_eclass_tb_top  t1_eclass_smoke_tb  t1_eclass_reset_tb
#   t1_eclass_uart_idle_tb  t1_eclass_spi_idle_tb  t1_eclass_uart_txrx_tb
# E-class CPU/ISS tests (USE_ISS + C binary required):
#   t1_eclass_gpio_tb  t1_eclass_uart_tb  t1_eclass_cpu_tb
# =============================================================================

# -- Tool settings -------------------------------------------------------------
VLOG  := vlog
VSIM  := vsim
VOPT  := vopt

# -- RISC-V toolchain (for CPU boot tests) ------------------------------------
RISCV_PREFIX  ?= riscv32-unknown-elf-
RISCV_CC      := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
PYTHON        ?= python3

# -- Library & build directories -----------------------------------------------
WORK_ECLASS       := work_eclass
WORK_ECLASS_ISS   := work_eclass_iss
BUILD_DIR         := build
LOG_DIR           := $(BUILD_DIR)/logs
COV_DIR           := $(BUILD_DIR)/coverage

# -- Software source + build paths ---------------------------------------------
SW_DIR   := sw
SW_BUILD := $(BUILD_DIR)/sw

# -- Bare-metal CFLAGS ---------------------------------------------------------
CFLAGS_RV32 := -march=rv32im -mabi=ilp32 -Os -g \
               -nostdlib -nostartfiles -ffreestanding \
               -Wall -Wno-unused-function

# -- Source file lists ---------------------------------------------------------
SRC_F_ECLASS := rtl/questa_src_eclass.f
TB_DIR       := verif/tb

# -- Include path for tb_level.svh ---------------------------------------------
TB_INC := +incdir+verif/include

# -- Common vlog flags ---------------------------------------------------------
VLOG_FLAGS_ECLASS := -work $(WORK_ECLASS) -sv \
                      +acc \
                     $(TB_INC) \
                     -suppress 2732 \
                     -suppress 2583 \
                     -suppress 8386

# -- Common vsim flags ---------------------------------------------------------
VSIM_FLAGS_ECLASS := -work $(WORK_ECLASS) -c \
                     -suppress 8386

VSIM_FLAGS_ECLASS_ISS := -work $(WORK_ECLASS_ISS) -c \
                         -suppress 8386 \
                         -voptargs="+acc"

# -- E-class structural tests --------------------------------------------------
TESTS_ECLASS := t1_eclass_tb_top \
                t1_eclass_smoke_tb \
                t1_eclass_reset_tb \
                t1_eclass_uart_idle_tb \
                t1_eclass_spi_idle_tb \
                t1_eclass_uart_txrx_tb

# =============================================================================
# PRIMARY TARGETS
# =============================================================================

.PHONY: all compile_eclass compile_eclass_iss compile_eclass_iss_cov \
        eclass_regression l1_coverage cov_report_l1 clean help \
        $(TESTS_ECLASS)

## Default target
all: eclass_regression

## Compile E-class RTL (separate work library)
compile_eclass: $(WORK_ECLASS)/_INFO

$(WORK_ECLASS)/_INFO: $(SRC_F_ECLASS)
	@echo ""
	@echo "=========================================="
	@echo "  Compiling Shakti E-class RTL [L1]"
	@echo "=========================================="
	$(VLOG) $(VLOG_FLAGS_ECLASS) -f $(SRC_F_ECLASS)
	@mkdir -p $(LOG_DIR)
	@touch $(WORK_ECLASS)/_INFO
	@echo "  E-class RTL compile complete."

## Compile E-class RTL with USE_ISS — selects rv32i_iss inside t1_soc_top_eclass.
## Separate library (work_eclass_iss) avoids clobbering work_eclass.
compile_eclass_iss: $(WORK_ECLASS_ISS)/_INFO_ISS

$(WORK_ECLASS_ISS)/_INFO_ISS: $(SRC_F_ECLASS)
	@echo ""
	@echo "=========================================="
	@echo "  Compiling E-class RTL [ISS, L1]"
	@echo "=========================================="
	$(VLOG) -work $(WORK_ECLASS_ISS) -sv \
	    $(TB_INC) \
	    +define+USE_ISS \
	    -suppress 2732 \
	    -suppress 2583 \
	    -suppress 8386 \
	    -f $(SRC_F_ECLASS)
	@mkdir -p $(LOG_DIR)
	@touch $(WORK_ECLASS_ISS)/_INFO_ISS
	@echo "  E-class RTL (ISS) compile complete."

## Compile E-class RTL with USE_ISS + coverage instrumentation
compile_eclass_iss_cov: $(WORK_ECLASS_ISS)/_INFO_ISS_COV

$(WORK_ECLASS_ISS)/_INFO_ISS_COV: $(SRC_F_ECLASS)
	@echo ""
	@echo "=========================================="
	@echo "  Compiling E-class RTL [ISS+COV, L1]"
	@echo "=========================================="
	$(VLOG) -work $(WORK_ECLASS_ISS) -sv \
	    $(TB_INC) \
	    +define+USE_ISS \
	    +cover=bcesfx \
	    +acc=all \
	    -suppress 2732 \
	    -suppress 2583 \
	    -suppress 8386 \
	    -f $(SRC_F_ECLASS)
	@mkdir -p $(LOG_DIR)
	@touch $(WORK_ECLASS_ISS)/_INFO_ISS_COV
	@echo "  E-class RTL (ISS+COV) compile complete."

## E-class test macro (uses WORK_ECLASS library)
define RUN_TEST_ECLASS
.PHONY: $(1)
$(1): compile_eclass
	@echo ""
	@echo "------------------------------------------"
	@echo "  E-CLASS TEST: $(1)"
	@echo "------------------------------------------"
	@mkdir -p $(LOG_DIR)
	$(VLOG) $(VLOG_FLAGS_ECLASS) $(TB_DIR)/$(1).sv 2>&1 | tee $(LOG_DIR)/$(1)_compile.log
	$(VSIM) $(VSIM_FLAGS_ECLASS) $(1) \
	    -do "log -r /*; run -all; quit -f" \
	    2>&1 | tee $(LOG_DIR)/$(1)_sim.log
	@grep -E "\[TB\]|\[PASS\]|\[FAIL\]|\[OK\]|\[INFO\]|PASS|FAIL|TIMEOUT" \
	    $(LOG_DIR)/$(1)_sim.log || true
	@echo "  Log: $(LOG_DIR)/$(1)_sim.log"
endef

$(foreach t,$(TESTS_ECLASS),$(eval $(call RUN_TEST_ECLASS,$(t))))

## E-class structural regression
eclass_regression: compile_eclass
	@echo ""
	@echo "=========================================="
	@echo "  E-CLASS REGRESSION [L1]"
	@echo "=========================================="
	@mkdir -p $(LOG_DIR)
	@PASS=0; FAIL=0; \
	for t in $(TESTS_ECLASS); do \
	    echo ""; \
	    echo "--- $$t ---"; \
	    $(VLOG) $(VLOG_FLAGS_ECLASS) $(TB_DIR)/$$t.sv \
	        > $(LOG_DIR)/$$t_compile.log 2>&1; \
	    if [ $$? -ne 0 ]; then \
	        echo "  [COMPILE FAIL] $$t"; \
	        FAIL=$$((FAIL+1)); \
	        continue; \
	    fi; \
	    $(VSIM) $(VSIM_FLAGS_ECLASS) $$t \
	        -do "run -all; quit -f" \
	        > $(LOG_DIR)/$$t_sim.log 2>&1; \
	    grep -E "\[TB\]|\[OK\]|\[FAIL\]|PASS|FAIL|TIMEOUT" \
	        $(LOG_DIR)/$$t_sim.log || true; \
	    if grep -q "PASS" $(LOG_DIR)/$$t_sim.log && \
	       ! grep -q "\[FAIL\]" $(LOG_DIR)/$$t_sim.log; then \
	        echo "  + PASS: $$t"; \
	        PASS=$$((PASS+1)); \
	    else \
	        echo "  x FAIL: $$t"; \
	        FAIL=$$((FAIL+1)); \
	    fi; \
	done; \
	TOTAL=$$((PASS+FAIL)); \
	echo ""; \
	echo "=========================================="; \
	echo "  E-CLASS REGRESSION SUMMARY [L1]"; \
	echo "  Total : $$TOTAL"; \
	echo "  PASS  : $$PASS"; \
	echo "  FAIL  : $$FAIL"; \
	echo "=========================================="; \
	if [ $$FAIL -ne 0 ]; then exit 1; fi

# =============================================================================
# CPU BOOT TESTS  (require riscv32-unknown-elf-gcc and python3)
# =============================================================================

## Build bare-metal ELF + hex for Level 1
$(SW_BUILD)/eclass_cpu_test_l1.elf: $(SW_DIR)/tests/eclass_cpu_test.c \
                                     $(SW_DIR)/boot/crt0.S \
                                     $(SW_DIR)/boot/eclass.ld
	@mkdir -p $(SW_BUILD)
	$(RISCV_CC) $(CFLAGS_RV32) \
	    -T $(SW_DIR)/boot/eclass.ld \
	    $(SW_DIR)/boot/crt0.S \
	    $(SW_DIR)/tests/eclass_cpu_test.c \
	    -o $@
	@echo "  Built L1 ELF: $@"

$(SW_BUILD)/eclass_cpu_test_l1.hex: $(SW_BUILD)/eclass_cpu_test_l1.elf
	$(RISCV_OBJCOPY) -O binary $< $(SW_BUILD)/eclass_cpu_test_l1.bin
	$(PYTHON) scripts/bin2hex.py $(SW_BUILD)/eclass_cpu_test_l1.bin $@

.PHONY: build_sw_l1 build_sw
build_sw_l1: $(SW_BUILD)/eclass_cpu_test_l1.hex
build_sw: build_sw_l1

## CPU boot test -- Level 1 (arith + shift + branch + word mem)
.PHONY: t1_eclass_cpu_tb
t1_eclass_cpu_tb: compile_eclass_iss build_sw_l1
	@echo ""
	@echo "------------------------------------------"
	@echo "  CPU BOOT TEST [L1]: t1_eclass_cpu_tb"
	@echo "------------------------------------------"
	@mkdir -p $(LOG_DIR)
	$(VLOG) -work $(WORK_ECLASS_ISS) -sv \
	    $(TB_INC) \
	    +define+USE_ISS \
	    -suppress 2732 -suppress 2583 -suppress 8386 \
	    $(TB_DIR)/t1_eclass_cpu_tb.sv \
	    2>&1 | tee $(LOG_DIR)/t1_eclass_cpu_tb_compile.log
	$(VSIM) $(VSIM_FLAGS_ECLASS_ISS) t1_eclass_cpu_tb \
	    +HEX_FILE=$(SW_BUILD)/eclass_cpu_test_l1.hex \
	    -do "log -r /*; run -all; quit -f" \
	    2>&1 | tee $(LOG_DIR)/t1_eclass_cpu_tb_l1_sim.log
	@grep -E "\[TB\]|\[PASS\]|\[FAIL\]|\[OK\]|\[INFO\]|PASS|FAIL|TIMEOUT" \
	    $(LOG_DIR)/t1_eclass_cpu_tb_l1_sim.log || true
	@echo "  Log: $(LOG_DIR)/t1_eclass_cpu_tb_l1_sim.log"

# =============================================================================
# GPIO CPU TESTS  (require riscv32-unknown-elf-gcc and python3)
# =============================================================================

$(SW_BUILD)/gpio_test_l1.elf: $(SW_DIR)/tests/gpio_test.c \
                               $(SW_DIR)/boot/crt0.S \
                               $(SW_DIR)/boot/eclass.ld
	@mkdir -p $(SW_BUILD)
	$(RISCV_CC) $(CFLAGS_RV32) \
	    -T $(SW_DIR)/boot/eclass.ld \
	    $(SW_DIR)/boot/crt0.S \
	    $(SW_DIR)/tests/gpio_test.c \
	    -o $@
	@echo "  Built GPIO L1 ELF: $@"

$(SW_BUILD)/gpio_test_l1.hex: $(SW_BUILD)/gpio_test_l1.elf
	$(RISCV_OBJCOPY) -O binary $< $(SW_BUILD)/gpio_test_l1.bin
	$(PYTHON) scripts/bin2hex.py $(SW_BUILD)/gpio_test_l1.bin $@

.PHONY: build_gpio_l1 build_gpio
build_gpio_l1: $(SW_BUILD)/gpio_test_l1.hex
build_gpio: build_gpio_l1

## GPIO register + pin-level test -- Level 1 (USE_ISS, C-driven via gpio_test.c)
## Alias: t1_gpio_cpu_tb -> t1_eclass_gpio_tb for consistency.
.PHONY: t1_eclass_gpio_tb t1_gpio_cpu_tb
t1_eclass_gpio_tb: compile_eclass_iss build_gpio_l1
	@echo ""
	@echo "------------------------------------------"
	@echo "  GPIO CPU TEST [L1]: t1_eclass_gpio_tb"
	@echo "------------------------------------------"
	@mkdir -p $(LOG_DIR)
	$(VLOG) -work $(WORK_ECLASS_ISS) -sv \
	    $(TB_INC) \
	    +define+USE_ISS \
	    -suppress 2732 -suppress 2583 -suppress 8386 \
	    $(TB_DIR)/t1_eclass_gpio_tb.sv \
	    2>&1 | tee $(LOG_DIR)/t1_eclass_gpio_tb_compile.log
	$(VSIM) $(VSIM_FLAGS_ECLASS_ISS) t1_eclass_gpio_tb \
	    +HEX_FILE=$(SW_BUILD)/gpio_test_l1.hex \
	    -do "log -r /*; run -all; quit -f" \
	    2>&1 | tee $(LOG_DIR)/t1_eclass_gpio_tb_l1_sim.log
	@grep -E "\[TB\]|\[PASS\]|\[FAIL\]|\[OK\]|\[INFO\]|PASS|FAIL|TIMEOUT" \
	    $(LOG_DIR)/t1_eclass_gpio_tb_l1_sim.log || true
	@echo "  Log: $(LOG_DIR)/t1_eclass_gpio_tb_l1_sim.log"

t1_gpio_cpu_tb: t1_eclass_gpio_tb

# =============================================================================
# UART CPU TESTS  (require riscv32-unknown-elf-gcc and python3)
# =============================================================================

$(SW_BUILD)/uart_test_l1.elf: $(SW_DIR)/tests/uart_test.c \
                               $(SW_DIR)/boot/crt0.S \
                               $(SW_DIR)/boot/eclass.ld
	@mkdir -p $(SW_BUILD)
	$(RISCV_CC) $(CFLAGS_RV32) \
	    -T $(SW_DIR)/boot/eclass.ld \
	    $(SW_DIR)/boot/crt0.S \
	    $(SW_DIR)/tests/uart_test.c \
	    -o $@
	@echo "  Built UART L1 ELF: $@"

$(SW_BUILD)/uart_test_l1.hex: $(SW_BUILD)/uart_test_l1.elf
	$(RISCV_OBJCOPY) -O binary $< $(SW_BUILD)/uart_test_l1.bin
	$(PYTHON) scripts/bin2hex.py $(SW_BUILD)/uart_test_l1.bin $@

.PHONY: build_uart_l1 build_uart
build_uart_l1: $(SW_BUILD)/uart_test_l1.hex
build_uart: build_uart_l1

## UART CPU test -- Level 1 (USE_ISS + uart_test.c via t1_eclass_uart_tb.sv)
## Alias: t1_uart_cpu_tb -> t1_eclass_uart_tb for consistency.
.PHONY: t1_eclass_uart_tb t1_uart_cpu_tb
t1_eclass_uart_tb: compile_eclass_iss build_uart_l1
	@echo ""
	@echo "------------------------------------------"
	@echo "  UART CPU TEST [L1]: t1_eclass_uart_tb"
	@echo "------------------------------------------"
	@mkdir -p $(LOG_DIR)
	$(VLOG) -work $(WORK_ECLASS_ISS) -sv \
	    $(TB_INC) \
	    +define+USE_ISS \
	    -suppress 2732 -suppress 2583 -suppress 8386 \
	    $(TB_DIR)/t1_eclass_uart_tb.sv \
	    2>&1 | tee $(LOG_DIR)/t1_eclass_uart_tb_compile.log
	$(VSIM) $(VSIM_FLAGS_ECLASS_ISS) t1_eclass_uart_tb \
	    +HEX_FILE=$(SW_BUILD)/uart_test_l1.hex \
	    -do "log -r /*; run -all; quit -f" \
	    2>&1 | tee $(LOG_DIR)/t1_eclass_uart_tb_l1_sim.log
	@grep -E "\[TB\]|\[PASS\]|\[FAIL\]|\[OK\]|\[INFO\]|PASS|FAIL|TIMEOUT" \
	    $(LOG_DIR)/t1_eclass_uart_tb_l1_sim.log || true
	@echo "  Log: $(LOG_DIR)/t1_eclass_uart_tb_l1_sim.log"

t1_uart_cpu_tb: t1_eclass_uart_tb

# =============================================================================
# L1 FUNCTIONAL COVERAGE  (requires USE_ISS + l1_cov_test.c)
# =============================================================================
# Build flow:
#   1. compile_eclass_iss_cov   -- RTL + USE_ISS + +cover=bcesfx
#   2. build_l1_cov             -- compile l1_cov_test.c -> hex
#   3. t1_l1_cov_tb             -- compile TB, simulate with -coverage, save UCDB
#   4. cov_report_l1            -- vcover report -html -> build/coverage/l1_html/
# =============================================================================

$(SW_BUILD)/l1_cov_test.elf: $(SW_DIR)/tests/l1_cov_test.c \
                              $(SW_DIR)/boot/crt0.S \
                              $(SW_DIR)/boot/eclass.ld
	@mkdir -p $(SW_BUILD)
	$(RISCV_CC) $(CFLAGS_RV32) \
	    -T $(SW_DIR)/boot/eclass.ld \
	    $(SW_DIR)/boot/crt0.S \
	    $(SW_DIR)/tests/l1_cov_test.c \
	    -o $@
	@echo "  Built l1_cov_test ELF: $@"

$(SW_BUILD)/l1_cov_test.hex: $(SW_BUILD)/l1_cov_test.elf
	$(RISCV_OBJCOPY) -O binary $< $(SW_BUILD)/l1_cov_test.bin
	$(PYTHON) scripts/bin2hex.py $(SW_BUILD)/l1_cov_test.bin $@

.PHONY: build_l1_cov
build_l1_cov: $(SW_BUILD)/l1_cov_test.hex

## Coverage simulation -- compile TB + run with -coverage, save UCDB
.PHONY: t1_l1_cov_tb
t1_l1_cov_tb: compile_eclass_iss_cov build_l1_cov
	@echo ""
	@echo "------------------------------------------"
	@echo "  L1 COVERAGE TB: t1_l1_cov_tb"
	@echo "------------------------------------------"
	@mkdir -p $(LOG_DIR) $(COV_DIR)
	$(VLOG) -work $(WORK_ECLASS_ISS) -sv \
	    $(TB_INC) \
	    +define+USE_ISS \
	    +cover=bcesfx \
	    +acc=all \
	    -suppress 2732 -suppress 2583 -suppress 8386 \
	    verif/coverage/t1_l1_func_cov.sv \
	    $(TB_DIR)/t1_l1_cov_tb.sv \
	    2>&1 | tee $(LOG_DIR)/t1_l1_cov_tb_compile.log
	$(VSIM) $(VSIM_FLAGS_ECLASS_ISS) t1_l1_cov_tb \
	    +HEX_FILE=$(SW_BUILD)/l1_cov_test.hex \
	    -coverage \
	    -do "coverage save -onexit $(COV_DIR)/l1_cov.ucdb; log -r /*; run -all; quit -f" \
	    2>&1 | tee $(LOG_DIR)/t1_l1_cov_tb_sim.log
	@grep -E "\[COV\]|\[TB\]|\[PASS\]|\[FAIL\]|PASS|FAIL|TIMEOUT" \
	    $(LOG_DIR)/t1_l1_cov_tb_sim.log || true
	@echo "  UCDB: $(COV_DIR)/l1_cov.ucdb"
	@echo "  Log:  $(LOG_DIR)/t1_l1_cov_tb_sim.log"

## Generate HTML coverage report from UCDB
.PHONY: cov_report_l1
cov_report_l1: $(COV_DIR)/l1_cov.ucdb
	@mkdir -p $(COV_DIR)/l1_html
	vcover report -html \
	    -output $(COV_DIR)/l1_html \
	    -details \
	    $(COV_DIR)/l1_cov.ucdb
	@echo "  HTML report: $(COV_DIR)/l1_html/index.html"

## Full coverage flow: build + simulate + report
.PHONY: l1_coverage
l1_coverage: t1_l1_cov_tb cov_report_l1
	@echo ""
	@echo "=========================================="
	@echo "  L1 COVERAGE COMPLETE"
	@echo "  Report: $(COV_DIR)/l1_html/index.html"
	@echo "=========================================="

# =============================================================================
# UTILITY
# =============================================================================

## Delete all build artefacts
clean:
	@echo "Cleaning build artefacts..."
	rm -rf $(WORK_ECLASS) $(WORK_ECLASS_ISS) $(BUILD_DIR) transcript vsim.wlf *.log *.vcd *.fst
	@echo "Clean complete."

## Print help
help:
	@echo ""
	@echo "OpenSoC Tier-1 -- QuestaSim Makefile (Shakti E-class SoC, Level-1)"
	@echo "==================================================================="
	@echo ""
	@echo "Targets:"
	@echo "  make compile_eclass            Compile E-class RTL (work_eclass/)"
	@echo "  make compile_eclass_iss        Compile E-class RTL with USE_ISS"
	@echo "  make compile_eclass_iss_cov    Compile E-class RTL with USE_ISS + coverage"
	@echo "  make eclass_regression         Run all E-class structural tests [default]"
	@echo "  make <test>                    Run a single E-class structural test"
	@echo "  make t1_eclass_cpu_tb          CPU boot test L1"
	@echo "  make t1_eclass_gpio_tb         GPIO register+pin test L1 (USE_ISS)"
	@echo "  make t1_gpio_cpu_tb            alias for t1_eclass_gpio_tb"
	@echo "  make t1_eclass_uart_tb         UART loopback test L1 (USE_ISS)"
	@echo "  make t1_uart_cpu_tb            alias for t1_eclass_uart_tb"
	@echo "  make l1_coverage               Full coverage flow (build+sim+report)"
	@echo "  make t1_l1_cov_tb              Run coverage simulation only"
	@echo "  make cov_report_l1             Generate HTML report from UCDB"
	@echo "  make clean                     Delete work_eclass/ work_eclass_iss/ and logs"
	@echo "  make help                      Show this message"
	@echo ""
	@echo "E-class structural tests:"
	@for t in $(TESTS_ECLASS); do echo "  $$t"; done
	@echo ""
	@echo "Examples:"
	@echo "  make eclass_regression"
	@echo "  make t1_eclass_gpio_tb"
	@echo "  make t1_eclass_cpu_tb"
	@echo "  make l1_coverage"
	@echo ""
