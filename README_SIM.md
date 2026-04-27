# OpenSoC Tier-1 — Simulation Environment Setup

> This document covers QuestaSim tool setup and environment variables.
> For test execution commands, see `README_ECLASS.md` and `scripts/eclass_sim.py`.

---

## Quick Start

```bash
# 1. Build firmware (once)
make -C sw

# 2. Run any test (QuestaSim) — firmware rebuilt automatically if stale
python scripts/eclass_sim.py gpio_l1
python scripts/eclass_sim.py gpio_l2
python scripts/eclass_sim.py uart_l1
python scripts/eclass_sim.py uart_l2
python scripts/eclass_sim.py cov_l1 --coverage
python scripts/eclass_sim.py cov_l2 --coverage

# 3. Run with Verilator (open-source, no licence needed, requires >= 5.0)
make verilator_gpio_l1
make verilator_uart_l1
make verilator_regression    # all four L1+L2 ISS tests
```

---

## Simulation Result

```
vlog: Errors: 0, Warnings: 165
[TB] Reset released — ISS booting from 0x80000000
[TB] TOHOST written after 1532 cycles: 0x00000001
[TB] PASS -- all checks passed [L1]
```

---

## QuestaSim Setup

### Set QUESTA_HOME

```powershell
# Set for this session
$env:QUESTA_HOME = "C:\intelFPGA_pro\23.1\questa_fse"

# Set permanently (User scope)
[System.Environment]::SetEnvironmentVariable("QUESTA_HOME",
    "C:\intelFPGA_pro\23.1\questa_fse", "User")
```

`eclass_sim.py` auto-detects QuestaSim from these locations (in order):

| Priority | Path |
|----------|------|
| 1 | `$QUESTA_HOME` |
| 2 | `C:\intelFPGA_pro\23.1\questa_fse` |
| 3 | `C:\intelFPGA_pro\22.4\questa_fse` |
| 4 | `C:\modeltech64_2023.3` |
| 5 | `C:\questasim64_2023.3` |
| 6 | `/opt/questasim` (Linux) |
| 7 | `vsim` on PATH |

---

## Simulation Flow

`eclass_sim.py` runs three QuestaSim steps:

```
1. vlog  -sv -mfcu
         +define+SIM +define+USE_ISS
         [+define+LEVEL2 +define+TEST_LEVEL2]   # _l2 tests
         [+cover=bcesfx]                         # cov_l2
         +incdir+<repo_root>                     # for verif/include/tb_level.svh
         rtl/questa_src_eclass.f
         [verif/coverage/t1_l2_func_cov.sv]
         verif/tb/<top>.sv

2. vopt  +acc -o <top>_opt  <top>
         [+cover=bcesfx]

3. vsim  -batch -t 1ps
         +HEX_FILE=<path>
         [-coverage -coverstore build/eclass_<test>/coverage]
         [-wlf build/eclass_<test>/<test>.wlf]
         <top>_opt
         -do "run -all; quit -f"
```

---

## Suppressed Warnings

| ID | Reason |
|----|--------|
| `2583` | `always_comb` sensitivity list auto-generated — normal in SV |
| `2718` | Implicit wire declarations in OpenTitan vendor IP |
| `8386` | Missing `timescale` in some vendor files — harmless with `-mfcu` |

---

## Build Artifacts

| Path | Contents |
|------|----------|
| `build/eclass_<test>/compile.log` | vlog output |
| `build/eclass_<test>/vopt.log` | vopt output |
| `build/eclass_<test>/sim.log` | vsim transcript — PASS/FAIL markers |
| `build/eclass_<test>/<test>.wlf` | Waveform database (if `--waves`) |
| `build/eclass_<test>/coverage_html/index.html` | Coverage report (if `--coverage`) |

---

## SoC Architecture

```
t1_soc_top_eclass
├── rv32i_iss            ← RV32IM instruction-set simulator (USE_ISS)
├── t1_xbar_32           ← 2-master × 3-slave 32-bit AXI4 crossbar (Level-2)
│   ├── t1_boot_rom_32   ← 0x0001_0000 – 0x0001_FFFF  (Boot ROM, 3 instructions)
│   ├── t1_sram_top_32   ← 0x8000_0000 – 0x8001_FFFF  (128 KB SRAM)
│   └── t1_periph_ss_32  ← 0x9000_0000 – 0x9000_002B  (UART + GPIO + SPI)
└── t1_bus_l1            ← 2-master × 2-slave (Level-1 only)
    ├── t1_sram_top_32   ← 0x8000_0000 – 0x8000_0FFF  (4 KB SRAM)
    └── t1_periph_ss_l1  ← 0x9000_0000 – 0x9000_1FFF  (UART + 16-bit GPIO)
```

Level selected by `+define+LEVEL2` at compile time. Default is Level-1.

---

## Known Non-Fatal Warnings

| Warning | Impact |
|---------|--------|
| PMP `allow_o` assertion at time 0 | Before reset; simulation completes PASS |
| ISS reading uninitialized addresses | Before hex loaded; no effect on test result |
| vopt-2732 for `FPGA_EN` (if present) | Harmless parameter warning |

---

## Troubleshooting

### QuestaSim not found
```powershell
Get-ChildItem "C:\intelFPGA_pro" -Filter "vsim.exe" -Recurse 2>$null
$env:QUESTA_HOME = "C:\intelFPGA_pro\23.1\questa_fse"
```

### `tb_level.svh` not found
`eclass_sim.py` adds `+incdir+<repo_root>` automatically. If compiling
manually, add `+incdir+.` from the repo root.

### UART / GPIO test times out
1. Check hex file exists: `sw/tests/uart_test_l2.hex`
2. Build it: `make -C sw uart_l2`
3. Verify `+define+LEVEL2` is set for L2 tests

### Work library error
```bash
python scripts/eclass_sim.py gpio_l2 --clean
```
