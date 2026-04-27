# OpenSoC Tier-1 — Simulation Scripts Reference

## Overview

| Interface | File | Best for |
|---|---|---|
| **Python script** | `scripts/eclass_sim.py` | All L1 tests, any OS, auto-builds firmware |
| **Shell wrapper** | `eclass_sim` | Wraps eclass_sim.py, auto-detects Python on RHEL |
| **Firmware make** | `sw/Makefile` | Building RISC-V hex files |
| **Root Makefile** | `Makefile` | QuestaSim + Verilator targets, Linux / Git Bash |
| **Questa Makefile** | `verif/scripts/Makefile.questa` | Standalone QuestaSim wrapper |

---

## E-class Simulation -- Python (recommended)

Works on Windows, Linux, and macOS. Automatically builds firmware before simulating.

```bash
python scripts/eclass_sim.py gpio_l1
python scripts/eclass_sim.py uart_l1
python scripts/eclass_sim.py cov_l1 --coverage
```

Options:

| Flag | Effect |
|------|--------|
| `--hex <path>` | Override firmware hex file path |
| `--gui` | Open QuestaSim GUI |
| `--waves` | Log waveforms to .wlf |
| `--coverage` | Enable functional coverage collection |
| `--clean` | Wipe build directory before run |
| `--no-build` | Skip firmware auto-build |
| `--verbose` | Print all tool commands |

Build artefacts: `build/eclass_<test>/compile.log`, `vopt.log`, `sim.log`, `<test>.wlf`

---

## Firmware Build -- sw/Makefile

```bash
# From repo root
make -C sw           # build all hex files
make -C sw gpio_l1
make -C sw uart_l1
make -C sw clean

# Override toolchain
make -C sw CROSS=riscv64-unknown-elf-
```

Hex outputs: `sw/tests/gpio_test_l1.hex`, `sw/tests/uart_test_l1.hex`

Toolchain search order: `riscv32-unknown-elf-gcc` -> `riscv-none-elf-gcc` -> `riscv64-unknown-elf-gcc`.

---

## Makefile.questa -- WSL2 / Linux / Git Bash

Located at `verif/scripts/Makefile.questa`. Run from the repo root:

```bash
make -f verif/scripts/Makefile.questa eclass_gpio_l1
make -f verif/scripts/Makefile.questa eclass_uart_l1
make -f verif/scripts/Makefile.questa eclass_regression      # gpio_l1 + uart_l1
make -f verif/scripts/Makefile.questa clean
```

### Makefile variables

| Variable | Default | Description |
|---|---|---|
| `SEED` | `42` | Random seed |
| `QUESTA_HOME` | auto-detect | QuestaSim install root |

> Firmware hex files must be built first (`make -C sw`).
> `eclass_sim.py` does this automatically; Makefile.questa does not.

---

## Simulation Flow Details

```
vlog  -sv -mfcu -suppress 2583,2718,8386
      +define+SIM +define+USE_ISS
      +incdir+<repo_root>                     # for verif/include/tb_level.svh
      rtl/questa_src_eclass.f
      verif/tb/<top>.sv

vopt  +acc -o <top>_opt  <top>

vsim  -batch -t 1ps
      +HEX_FILE=<path>
      <top>_opt
      -do "run -all; quit -f"
```

---

## Suppressed Warnings

| ID | Reason |
|----|--------|
| `2583` | `always_comb` sensitivity list auto-generated -- normal in SV |
| `2718` | Implicit wire declarations in OpenTitan vendor IP |
| `8386` | Missing `timescale` in some vendor files -- harmless with `-mfcu` |

---

## Log Files

| Path | Contents |
|------|----------|
| `build/eclass_<test>/compile.log` | vlog output |
| `build/eclass_<test>/vopt.log` | vopt output |
| `build/eclass_<test>/sim.log` | vsim transcript -- PASS/FAIL markers |
| `build/eclass_<test>/<test>.wlf` | Waveform database (if `--waves`) |
| `build/eclass_<test>/coverage_html/index.html` | Coverage report (if `--coverage`) |

---

## Root Makefile -- QuestaSim targets

```bash
# Structural regression (default)
make eclass_regression

# Single CPU/ISS tests
make t1_eclass_gpio_tb       # GPIO L1
make t1_eclass_uart_tb       # UART L1

# L1 functional coverage
make l1_coverage             # build + sim + HTML report

# Clean all artefacts
make clean
```

---

## Verilator Simulation -- open-source, no licence required

Requires **Verilator >= 5.0** (for `--timing` support).

### Install Verilator

**Ubuntu / Debian:**
```bash
sudo apt install verilator
verilator --version          # verify >= 5.0
```

**RHEL / CentOS (build from source):**
```bash
sudo yum install -y git autoconf flex bison make gcc-c++ python39

# Bypass VCO python3 wrapper
mkdir -p ~/bin
ln -sf /usr/bin/python3.9 ~/bin/python3
export PATH=~/bin:/usr/local/bin:$PATH

git clone https://github.com/verilator/verilator.git
cd verilator
autoconf
./configure --prefix=/usr/local
touch verilator_gantt.1      # skip missing help2man
make -j`nproc`
sudo env PATH=$PATH make install

export PATH=/usr/local/bin:$PATH
verilator --version
```

**macOS:**
```bash
brew install verilator
```

### Verilator make targets

```bash
# Build firmware first (if not already done)
make -C sw

# Lint only -- fast check, no simulation binary built
make verilator_lint_l1

# Compile RTL + TB, then simulate
make verilator_gpio_l1
make verilator_uart_l1

# Both ISS tests in sequence
make verilator_regression

# With VCD waveform (open in GTKWave)
make verilator_gpio_l1 WAVES=1
# Waveform: build/verilator/gpio_l1/sim.vcd

# Clean Verilator build dirs only
make verilator_clean
```

### Verilator variables

| Variable | Default | Description |
|---|---|---|
| `VERILATOR` | `verilator` | Path to Verilator binary |
| `WAVES` | `0` | Set to `1` to emit VCD waveform via `--trace` |

### Build artefacts

| Path | Contents |
|------|----------|
| `build/verilator/<test>/build.log` | Verilator compile output |
| `build/verilator/<test>/sim.log` | Simulation transcript -- PASS/FAIL |
| `build/verilator/<test>/sim.vcd` | Waveform (if `WAVES=1`) |

### Verilator flow

```
verilator --binary --sv --timing
          +define+SIM +define+USE_ISS
          +incdir+verif/include +incdir+.
          -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC ...
          --Mdir build/verilator/<test>
          --top-module <tb_module>
          -f rtl/questa_src_eclass.f
          verif/tb/<top>.sv
          -o <test>

# Run
build/verilator/<test>/<test> +HEX_FILE=sw/tests/<test>.hex [+trace]
```

---

## Adding a New E-class Test

1. Create `sw/tests/mytest.c` (write TOHOST=1 on pass, non-zero on fail)
2. Add build rule to `sw/Makefile`
3. Create (or reuse) a testbench in `verif/tb/`
4. Add entry to `TESTS` dict in `scripts/eclass_sim.py`
5. Run: `python scripts/eclass_sim.py mytest`
