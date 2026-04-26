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

SW_DIR   := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TEST_DIR := $(SW_DIR)tests
BOOT_DIR := $(SW_DIR)boot

ifdef RISCV
  GCC := $(RISCV)/bin/riscv32-unknown-elf-gcc
  ifeq ($(wildcard $(GCC)),)
    GCC := $(RISCV)/bin/riscv-none-elf-gcc
  endif
else
  GCC := $(shell which riscv32-unknown-elf-gcc 2>/dev/null)
  ifeq ($(GCC),)
    GCC := $(shell which riscv-none-elf-gcc 2>/dev/null)
    ifeq ($(GCC),)
      GCC := $(shell which riscv64-unknown-elf-gcc 2>/dev/null)
    endif
  endif
endif

ifeq ($(GCC),)
  $(error No RISC-V GCC found. Set RISCV=/path/to/xpack or install riscv64-unknown-elf-gcc)
endif

CFLAGS := -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -Os \
          -T $(BOOT_DIR)/eclass.ld

OBJCOPY_CANDIDATES := riscv32-unknown-elf-objcopy riscv-none-elf-objcopy riscv64-unknown-elf-objcopy
OBJCOPY := $(firstword $(foreach c,$(OBJCOPY_CANDIDATES),$(shell which $(c) 2>/dev/null)))

BIN2HEX := python3 $(SW_DIR)/../scripts/bin2hex.py

.PHONY: all gpio_l1 uart_l1 clean

all: gpio_l1 uart_l1

gpio_l1:
	$(GCC) $(CFLAGS) $(BOOT_DIR)/crt0.S $(TEST_DIR)/gpio_test.c \
	  -o $(TEST_DIR)/gpio_test_l1.elf
	$(OBJCOPY) -O binary $(TEST_DIR)/gpio_test_l1.elf $(TEST_DIR)/gpio_test_l1.bin
	$(BIN2HEX) $(TEST_DIR)/gpio_test_l1.bin $(TEST_DIR)/gpio_test_l1.hex
	@echo "[HEX] gpio_test_l1.hex"

uart_l1:
	$(GCC) $(CFLAGS) $(BOOT_DIR)/crt0.S $(TEST_DIR)/uart_test.c \
	  -o $(TEST_DIR)/uart_test_l1.elf
	$(OBJCOPY) -O binary $(TEST_DIR)/uart_test_l1.elf $(TEST_DIR)/uart_test_l1.bin
	$(BIN2HEX) $(TEST_DIR)/uart_test_l1.bin $(TEST_DIR)/uart_test_l1.hex
	@echo "[HEX] uart_test_l1.hex"

clean:
	rm -f $(TEST_DIR)/*.elf $(TEST_DIR)/*.bin $(TEST_DIR)/*.hex
	@echo "[CLEAN] done"
