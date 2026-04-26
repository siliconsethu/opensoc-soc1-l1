# OpenSoC Tier-1 — Shakti E-class Integration

## Overview

This directory contains a second SoC variant that replaces the CVA6 (RV64GC, 64-bit)
with the **Shakti E-class** (RV32IM, 3-stage, 32-bit) RISC-V processor.
The design supports two compile-time levels selected by `+define+LEVEL2`:

| | Level-1 | Level-2 |
|---|---|---|
| SRAM | 4 KB | 128 KB |
| Boot ROM | — | 256 × 32-bit |
| Bus | `t1_bus_l1` (2-slave) | `t1_xbar_32` (3-slave) |
| Peripherals | `t1_periph_ss_l1` (UART + 16-bit GPIO) | `t1_periph_ss_32` (UART + 32-bit GPIO + SPI + I2C) |
| SPI / I2C ports | **Absent** | Present |
| Boot address | `0x8000_0000` (SRAM direct) | `0x0001_0000` (Boot ROM) |

> **SPI and I2C ports** are conditionally compiled via `` `ifdef LEVEL2 `` in
> `t1_soc_top_eclass.sv` and all testbenches. L1 builds have no SPI/I2C
> top-level ports.

---

## Quick Start — Simulation

```bash
# 1. Build firmware (once; auto-rebuilt when sources change)
make -C sw           # needs riscv32-unknown-elf-gcc or riscv64-unknown-elf-gcc

# 2. Run any test (cross-platform Python runner)
python scripts/eclass_sim.py gpio_l1
python scripts/eclass_sim.py gpio_l2
python scripts/eclass_sim.py uart_l1
python scripts/eclass_sim.py uart_l2
python scripts/eclass_sim.py cov_l2 --coverage

# Options
python scripts/eclass_sim.py uart_l2 --gui --waves   # open QuestaSim GUI
python scripts/eclass_sim.py gpio_l2 --clean         # wipe build dir first
python scripts/eclass_sim.py uart_l2 --no-build      # skip firmware auto-build
```

> `eclass_sim.py` automatically calls `make -C sw` if any hex file is missing or
> its source is newer than the last build. QuestaSim must be on PATH or
> `QUESTA_HOME` set.

---

## Firmware Build

```bash
# Build all hex files
make -C sw

# Build one target
make -C sw gpio_l1
make -C sw gpio_l2
make -C sw uart_l1
make -C sw uart_l2

# Clean firmware outputs
make -C sw clean
```

Toolchain search order (set `RISCV=/path/to/xpack` or install one of these):

| Preference | Toolchain | Install |
|---|---|---|
| 1 | `riscv32-unknown-elf-gcc` | xpack / `$RISCV` |
| 2 | `riscv-none-elf-gcc` | xpack newer |
| 3 | `riscv64-unknown-elf-gcc` | `apt install gcc-riscv64-unknown-elf` (WSL2/Ubuntu) |

Hex files are written to `sw/tests/`:

| File | Firmware |
|---|---|
| `sw/tests/gpio_test_l1.hex` | L1 GPIO — OpenTitan gpio.sv, 16-bit |
| `sw/tests/gpio_test_l2.hex` | L2 GPIO — t1_periph_ss_32, 32-bit |
| `sw/tests/uart_test_l1.hex` | L1 UART — OpenTitan uart.sv, NCO baud |
| `sw/tests/uart_test_l2.hex` | L2 UART — t1_periph_ss_32, baud_div=10 |

---

## Simulation Flow

`eclass_sim.py` runs: **vlog → vopt +acc → vsim -batch**

```
vlog  -sv -mfcu +define+USE_ISS [+define+LEVEL2 +define+TEST_LEVEL2]
      questa_src_eclass.f  [t1_l2_func_cov.sv]  verif/tb/<top>.sv

vopt  +acc -o <top>_opt  <top>

vsim  -batch -t 1ps  +HEX_FILE=<path>  [-coverage]  <top>_opt
      -do "run -all; quit -f"
```

Build artefacts go to `build/eclass_<test>/` (separate dir per test).

---

## RTL Files

| File | Description |
|------|-------------|
| `rtl/cpu/shakti_eclass_wrapper.sv` | CPU wrapper — AXI4 behavioural stub; replace body with `mkE_Class` BSV output |
| `rtl/cpu/rv32i_iss.sv` | Behavioural RV32IM instruction-set simulator (USE_ISS) |
| `rtl/interconnect/t1_xbar_32.sv` | 2-master × 3-slave 32-bit AXI crossbar (Level-2) |
| `rtl/interconnect/t1_bus_l1.sv` | 2-master × 2-slave 32-bit AXI bus (Level-1) |
| `rtl/memory/t1_boot_rom_32.sv` | 3-instruction bootstrap ROM (Level-2 only) |
| `rtl/memory/t1_sram_top_32.sv` | Behavioural SRAM — 4 KB (L1) / 128 KB (L2) |
| `rtl/peripherals/t1_periph_ss_l1.sv` | L1 peripherals: OpenTitan UART + 16-bit GPIO via TLUL |
| `rtl/peripherals/t1_periph_ss_32.sv` | L2 peripherals: UART, 32-bit GPIO, SPI, I2C (self-contained, no vendor deps) |
| `rtl/top/t1_soc_top_eclass.sv` | Unified SoC top — SPI/I2C ports present only under `+define+LEVEL2` |
| `rtl/questa_src_eclass.f` | QuestaSim source file list |

---

## Testbench Files

| File | Level | Description |
|------|-------|-------------|
| `verif/tb/t1_eclass_gpio_tb.sv` | L1 + L2 | CPU-driven GPIO: walk-1/0, patterns, DATA_IN OR-accumulation |
| `verif/tb/t1_eclass_uart_tb.sv` | L1 + L2 | CPU-driven UART loopback: 4 bytes (0x55/0xAA/0x00/0xFF) |
| `verif/tb/t1_l2_cov_tb.sv` | L2 only | Functional coverage TB — stimulus for all 26 covergroups |
| `verif/coverage/t1_l2_func_cov.sv` | L2 only | 26-covergroup functional coverage module |
| `verif/include/tb_level.svh` | Both | Shared macros: `TBL_GPIO_CPU_TIMEOUT`, `TBL_UART_CPU_TIMEOUT`, etc. |

---

## Firmware Source Files

| File | Description |
|------|-------------|
| `sw/boot/crt0.S` | Minimal startup: stack, BSS zero, call main, spin |
| `sw/boot/eclass.ld` | Linker script: SRAM at `0x8000_0000`, 128 KB |
| `sw/tests/gpio_test.c` | L1 GPIO firmware (OpenTitan gpio.sv register map) |
| `sw/tests/gpio_test_l2.c` | L2 GPIO firmware (t1_periph_ss_32 register map, 32-bit) |
| `sw/tests/uart_test.c` | L1 UART firmware (OpenTitan uart.sv, NCO baud) |
| `sw/tests/uart_test_l2.c` | L2 UART firmware (t1_periph_ss_32, baud_div=10) |
| `sw/tests/spi_test.c` | SPI firmware |
| `sw/tests/i2c_test.c` | I2C firmware |
| `sw/Makefile` | Firmware build: compiles C → ELF → Verilog hex ($readmemh format) |

---

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/eclass_sim.py` | Cross-platform simulation runner (Windows/Linux/macOS); auto-builds firmware |
| `scripts/build_sw.py` | Standalone firmware builder (fallback if make unavailable) |

---

## Address Map

### Level-2
| Region | Base | End | Size |
|--------|------|-----|------|
| Boot ROM | `0x0001_0000` | `0x0001_FFFF` | 1 KB |
| SRAM | `0x8000_0000` | `0x801F_FFFF` | 128 KB |
| Peripheral SS | `0x9000_0000` | `0x901F_FFFF` | 2 MB |

### Level-1
| Region | Base | End | Size |
|--------|------|-----|------|
| SRAM | `0x8000_0000` | `0x8000_0FFF` | 4 KB |
| Peripheral SS | `0x9000_0000` | `0x9000_1FFF` | 8 KB |

### L2 Peripheral Register Map (`t1_periph_ss_32`, base `0x9000_0000`)
| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| `0x00` | UART_CTRL | R/W | [15:0]=baud_div, [16]=uart_en, [17]=parity_en |
| `0x04` | UART_STAT | R | [0]=tx_empty, [1]=tx_full, [2]=rx_valid |
| `0x08` | UART_TX | W | [7:0] byte to transmit |
| `0x0C` | UART_RX | R | [7:0] received byte (read clears rx_valid) |
| `0x10` | GPIO_OUT | R/W | 32-bit output data |
| `0x14` | GPIO_OE | R/W | 32-bit output enable |
| `0x18` | GPIO_IN | R | 32-bit synchronised input |

### TOHOST Convention
CPU writes test result to `0x8000_0FF0` (SRAM word index 1020):
- `0x0000_0001` = PASS
- Any other non-zero value = FAIL (upper 16 bits = group, lower 16 bits = sub-error)

---

## Replacing the CPU Stub with Real BSV Output

```systemverilog
// In shakti_eclass_wrapper.sv, replace the stub body with:
mkE_Class u_eclass (
  .CLK             (clk_i),
  .RST_N           (rst_ni),
  .ext_interrupt   (irq_m_ext_i),
  .timer_interrupt (irq_m_timer_i),
  .soft_interrupt  (irq_m_soft_i),
  // ... map AXI ports to imem_*/dmem_* signals
);
```

Compile without `+define+USE_ISS`. Port names follow BSV-compiled Verilog
convention (`CLK`, `RST_N`). Refer to `e-class/src/core/mkE_Class.v` for
the exact port list after BSV compilation.

---

## Known Limitations

- `t1_periph_ss_32` SPI and I2C are behavioural models — no real clock-accurate
  shift register or I2C state machine timing beyond baud-period granularity.
- No JTAG debug in this integration. JTAG ports on `t1_soc_top_eclass` are
  permanently tied off.
- L1 firmware must be leaf functions only (no sub-calls) — L1 SRAM is 4 KB but
  `crt0.S` sets `sp = 0x8001_0000`; any stack push accesses unmapped memory.
