# OpenSoC Tier-1 — Shakti E-class Level-1 SoC

[![L1 Regression](https://img.shields.io/badge/L1_regression-PASS-brightgreen)]()
[![QuestaSim](https://img.shields.io/badge/simulator-QuestaSim_2024.1-blue)]()
[![RV32IM](https://img.shields.io/badge/ISA-RV32IM-orange)]()

Educational RISC-V SoC from **IIITDM Chennai** — OpenSoC programme.
Level-1 public release: RTL, testbenches, firmware, and simulation scripts.

---

## SoC Overview

| Parameter | Value |
|-----------|-------|
| CPU | Shakti E-class (RV32IM, 3-stage in-order) |
| Bus | `t1_bus_l1` — 2-master x 2-slave 32-bit AXI4 |
| SRAM | 4 KB at `0x8000_0000` |
| Peripherals | OpenTitan UART + 16-bit GPIO via TL-UL |
| Boot address | `0x8000_0000` (direct SRAM boot) |
| Simulator | QuestaSim 2020.4+ |

In simulation the CPU is replaced by `rv32i_iss`, a behavioural RV32IM ISS
that loads compiled firmware from a hex file over AXI4.

---

## Quick Start

```bash
# 1. Build firmware (needs RISC-V GCC)
make -C sw

# 2. Run simulation (auto-builds firmware if missing)
python scripts/eclass_sim.py gpio_l1
python scripts/eclass_sim.py uart_l1

# 3. GUI with waveforms
python scripts/eclass_sim.py gpio_l1 --gui --waves
```

See [INSTALL.md](INSTALL.md) for full tool setup.

---

## Repository Structure

```
.
+-- rtl/
|   +-- cpu/            rv32i_iss (ISS), shakti_eclass_wrapper (stub)
|   +-- interconnect/   t1_bus_l1 (2Mx2S AXI4 bus)
|   +-- memory/         t1_sram_top_32 (4 KB)
|   +-- peripherals/    t1_periph_ss_l1 (OpenTitan UART + 16-bit GPIO)
|   +-- top/            t1_soc_top_eclass
|   +-- include/        OpenTitan primitives and packages
|   +-- vendor/         OpenTitan vendor IP (uart, gpio)
|   +-- questa_src_eclass.f
+-- verif/
|   +-- tb/             t1_eclass_gpio_tb.sv, t1_eclass_uart_tb.sv
|   +-- include/        tb_level.svh
|   +-- scripts/        Makefile.questa
+-- sw/
|   +-- boot/           crt0.S, eclass.ld
|   +-- tests/          gpio_test.c, uart_test.c
|   +-- Makefile
+-- synth/
|   +-- constraints/    Genus SDC, Vivado XDC
|   +-- libs/           SKY130 SRAM macro config
|   +-- rtl/            ASIC / FPGA SRAM top variants
|   +-- scripts/        genus_run.tcl, vivado_run.tcl
+-- scripts/            eclass_sim.py, build_sw.py, bin2hex.py
+-- docs/               Word format documentation
+-- INSTALL.md
```

---

## Tests

| Test | Command | Verifies |
|------|---------|---------|
| GPIO L1 | `python scripts/eclass_sim.py gpio_l1` | Walk-1/walk-0 on 16 GPIO pins |
| UART L1 | `python scripts/eclass_sim.py uart_l1` | TX/RX loopback 0x55/0xAA/0x00/0xFF |

Expected output:
```
[TB] TOHOST written after NNN cycles: 0x00000001
[TB] PASS -- all checks passed [LEVEL-1 (Quick)]
```

---

## Address Map

| Region | Base | End | Size |
|--------|------|-----|------|
| SRAM | `0x8000_0000` | `0x8000_0FFF` | 4 KB |
| Peripheral SS | `0x9000_0000` | `0x9000_1FFF` | 8 KB |

### TOHOST Convention

Firmware signals test completion by writing to SRAM word 1020 (`0x8000_0FF0`):
- `0x0000_0001` = **PASS**
- Any other non-zero = **FAIL** (upper 16 bits = error group, lower = sub-error)

---

## Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| QuestaSim | 2020.4+ | RTL simulation |
| Python | 3.8+ | Simulation runner |
| RISC-V GCC | riscv32/64-elf | Firmware compilation |

---

## Licence

Educational use — IIITDM Chennai.
OpenTitan vendor IP: Apache 2.0 (lowRISC).
Shakti E-class: BSD (IIT-Madras).

## Contact

OpenSoC Programme · IIITDM Chennai · github.com/siliconsethu
