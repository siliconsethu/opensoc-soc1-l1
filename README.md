# OpenSoC Tier-1 — Shakti E-class Level-1 SoC

[![Level-1 Regression](https://img.shields.io/badge/L1_regression-PASS-brightgreen)]()
[![QuestaSim](https://img.shields.io/badge/simulator-QuestaSim-blue)]()
[![RV32IM](https://img.shields.io/badge/ISA-RV32IM-orange)]()

Educational RISC-V SoC from **IIITDM Chennai** — OpenSoC programme.

This is the **Level-1 public release** of the Shakti E-class Tier-1 SoC.
It contains the complete RTL, testbenches, firmware, and simulation scripts
for the Level-1 configuration.

---

## SoC Overview

| Parameter | Value |
|-----------|-------|
| CPU | Shakti E-class (RV32IM, 3-stage) |
| Bus | `t1_bus_l1` — 2-master × 2-slave 32-bit AXI4 |
| SRAM | 4 KB at `0x8000_0000` |
| Peripherals | OpenTitan UART + 16-bit GPIO via TLUL |
| Boot address | `0x8000_0000` (direct SRAM boot) |
| Simulator | QuestaSim 2020.4+ (vlog → vopt → vsim) |

In simulation the CPU is replaced by `rv32i_iss`, a behavioural RV32IM
instruction-set simulator that loads a compiled firmware hex file.

---

## Quick Start

```bash
# 1. Build firmware (needs RISC-V GCC)
make -C sw

# 2. Run simulation (auto-builds firmware if missing)
python scripts/eclass_sim.py gpio_l1
python scripts/eclass_sim.py uart_l1

# 3. Open GUI with waveforms
python scripts/eclass_sim.py gpio_l1 --gui --waves
```

See [INSTALL.md](INSTALL.md) for full tool setup instructions.

---

## Repository Structure

```
├── rtl/
│   ├── cpu/            ← rv32i_iss (RV32IM ISS), shakti_eclass_wrapper
│   ├── interconnect/   ← t1_bus_l1 (2M×2S AXI4 bus)
│   ├── memory/         ← t1_sram_top_32 (4 KB)
│   ├── peripherals/    ← t1_periph_ss_l1 (OpenTitan UART + 16-bit GPIO)
│   ├── top/            ← t1_soc_top_eclass (SoC top)
│   ├── include/        ← OpenTitan primitives and packages
│   ├── vendor/         ← OpenTitan vendor IP (uart, gpio, plic)
│   └── questa_src_eclass.f
├── verif/
│   ├── tb/             ← t1_eclass_gpio_tb.sv, t1_eclass_uart_tb.sv
│   ├── include/        ← tb_level.svh
│   └── scripts/        ← Makefile.questa
├── sw/
│   ├── boot/           ← crt0.S, eclass.ld
│   └── tests/          ← gpio_test.c, uart_test.c
├── scripts/            ← eclass_sim.py, build_sw.py, bin2hex.py
└── INSTALL.md
```

---

## Tests

| Test | Command | What It Verifies |
|------|---------|-----------------|
| GPIO L1 | `python scripts/eclass_sim.py gpio_l1` | CPU walks a 1-bit through 16-bit GPIO_OUT; reads GPIO_IN |
| UART L1 | `python scripts/eclass_sim.py uart_l1` | CPU sends 4-byte loopback (0x55/0xAA/0x00/0xFF) via UART |

Expected output (both tests):
```
[TB] TOHOST written after NNN cycles: 0x00000001
[TB] PASS -- all checks passed [L1]
```

---

## Address Map

| Region | Base | End | Size |
|--------|------|-----|------|
| SRAM | `0x8000_0000` | `0x8000_0FFF` | 4 KB |
| Peripheral SS | `0x9000_0000` | `0x9000_1FFF` | 8 KB |

### Peripheral Register Map (`t1_periph_ss_l1`, OpenTitan base addresses)

| Block | Base | Description |
|-------|------|-------------|
| UART | `0x9000_0000` | OpenTitan uart.sv (NCO baud) |
| GPIO | `0x9000_1000` | OpenTitan gpio.sv (16-bit) |

---

## Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| QuestaSim | 2020.4+ | RTL simulation |
| Python | 3.8+ | Simulation runner |
| RISC-V GCC | any riscv32/64-elf | Firmware compilation |

See [INSTALL.md](INSTALL.md) for detailed setup instructions.

---

## TOHOST Convention

The CPU firmware signals test completion by writing to SRAM address `0x8000_0FF0`:
- `0x0000_0001` = **PASS**
- Any other non-zero value = **FAIL** (upper 16 bits = group, lower = sub-error)

---

## Licence

Educational use — IIITDM Chennai.  OpenTitan vendor IP under Apache 2.0.

---

## Contact

OpenSoC Programme · IIITDM Chennai · github.com/siliconsethu
