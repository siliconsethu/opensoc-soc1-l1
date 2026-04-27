# OpenSoC Tier-1 -- Firmware Makefile (Level-1 public release)
# Builds firmware hex files for the E-class Level-1 SoC.
#
# Usage (from repo root):
#   make -C sw gpio_l1
#   make -C sw uart_l1
#   make -C sw all
#   make -C sw clean
#
# Toolchain search order:
#   1. riscv32-unknown-elf-gcc  (xpack or crosstool-ng)
#   2. riscv-none-elf-gcc       (xpack newer naming)
#   3. riscv64-unknown-elf-gcc  (Ubuntu apt gcc-riscv64-unknown-elf)
# Set RISCV=/path/to/xpack to override.
#
# Python auto-detected (python3.12 .. python3 tried in order).
# Override with: make -C sw PY=/usr/bin/python3.9
#
# Note: all paths are relative so this Makefile is safe on paths with spaces.

TEST_DIR := tests
BOOT_DIR := boot
SCRIPTS  := ../scripts

# Auto-detect Python: try versioned binaries first to bypass site wrappers
# (some RHEL/corporate systems wrap python3 with a VCO/module guard)
PY ?= $(firstword $(foreach v,python3.12 python3.11 python3.10 python3.9 python3.8 python3,\
        $(shell command -v $(v) 2>/dev/null)))
ifeq ($(PY),)
  $(error Python 3 not found. Install python3 or set PY=/path/to/python3)
endif

ifdef RISCV
  GCC := $(RISCV)/bin/riscv32-unknown-elf-gcc
  ifeq ($(wildcard $(GCC)),)
    GCC := $(RISCV)/bin/riscv-none-elf-gcc
  endif
else
  GCC := $(shell command -v riscv32-unknown-elf-gcc 2>/dev/null)
  ifeq ($(GCC),)
    GCC := $(shell command -v riscv-none-elf-gcc 2>/dev/null)
    ifeq ($(GCC),)
      GCC := $(shell command -v riscv64-unknown-elf-gcc 2>/dev/null)
    endif
  endif
endif

ifeq ($(GCC),)
  $(error No RISC-V GCC found. Set RISCV=/path/to/xpack or install riscv64-unknown-elf-gcc)
endif

CFLAGS := -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -Os \
          -T $(BOOT_DIR)/eclass.ld

OBJCOPY_CANDIDATES := riscv32-unknown-elf-objcopy riscv-none-elf-objcopy riscv64-unknown-elf-objcopy
OBJCOPY := $(firstword $(foreach c,$(OBJCOPY_CANDIDATES),$(shell command -v $(c) 2>/dev/null)))

.PHONY: all gpio_l1 uart_l1 clean

all: gpio_l1 uart_l1

gpio_l1:
	$(GCC) $(CFLAGS) $(BOOT_DIR)/crt0.S $(TEST_DIR)/gpio_test.c \
	  -o $(TEST_DIR)/gpio_test_l1.elf
	$(OBJCOPY) -O binary $(TEST_DIR)/gpio_test_l1.elf $(TEST_DIR)/gpio_test_l1.bin
	$(PY) $(SCRIPTS)/bin2hex.py $(TEST_DIR)/gpio_test_l1.bin $(TEST_DIR)/gpio_test_l1.hex
	@echo "[HEX] gpio_test_l1.hex"

uart_l1:
	$(GCC) $(CFLAGS) $(BOOT_DIR)/crt0.S $(TEST_DIR)/uart_test.c \
	  -o $(TEST_DIR)/uart_test_l1.elf
	$(OBJCOPY) -O binary $(TEST_DIR)/uart_test_l1.elf $(TEST_DIR)/uart_test_l1.bin
	$(PY) $(SCRIPTS)/bin2hex.py $(TEST_DIR)/uart_test_l1.bin $(TEST_DIR)/uart_test_l1.hex
	@echo "[HEX] uart_test_l1.hex"

clean:
	rm -f $(TEST_DIR)/*.elf $(TEST_DIR)/*.bin $(TEST_DIR)/*.hex
	@echo "[CLEAN] done"
