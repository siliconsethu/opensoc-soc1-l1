# OpenSoC Tier-1 — Simulation Scripts Reference

## Overview

| Interface | File | Best for |
|---|---|---|
| **Python script** | `scripts/eclass_sim.py` | All E-class tests, any OS, auto-builds firmware |
| **Firmware make** | `sw/Makefile` | Building RISC-V hex files |
| **Makefile** | `verif/scripts/Makefile.questa` | WSL2 / Linux / Git Bash |

---

## E-class Simulation — Python (recommended)

Works on Windows, Linux, and macOS. Automatically builds firmware before simulating.

```bash
python scripts/eclass_sim.py gpio_l1
python scripts/eclass_sim.py gpio_l2
python scripts/eclass_sim.py uart_l1
python scripts/eclass_sim.py uart_l2
python scripts/eclass_sim.py cov_l2 --coverage
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

## Firmware Build — sw/Makefile

```bash
# From repo root
make -C sw           # build all 4 hex files
make -C sw gpio_l1
make -C sw gpio_l2
make -C sw uart_l1
make -C sw uart_l2
make -C sw clean

# Override toolchain
make -C sw CROSS=riscv64-unknown-elf-
```

Hex outputs: `sw/tests/gpio_test_l1.hex`, `sw/tests/gpio_test_l2.hex`,
`sw/tests/uart_test_l1.hex`, `sw/tests/uart_test_l2.hex`

Toolchain search order: `riscv32-unknown-elf-gcc` → `riscv-none-elf-gcc` → `riscv64-unknown-elf-gcc`.

---

## Makefile.questa — WSL2 / Linux / Git Bash

Located at `verif/scripts/Makefile.questa`. Run from the repo root:

```bash
make -f verif/scripts/Makefile.questa eclass_gpio_l1
make -f verif/scripts/Makefile.questa eclass_gpio_l2
make -f verif/scripts/Makefile.questa eclass_uart_l1
make -f verif/scripts/Makefile.questa eclass_uart_l2
make -f verif/scripts/Makefile.questa eclass_cov_l2
make -f verif/scripts/Makefile.questa eclass_regression      # gpio_l1 + uart_l1
make -f verif/scripts/Makefile.questa eclass_regression_l2   # gpio_l2 + uart_l2 + cov_l2
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
      [+define+LEVEL2 +define+TEST_LEVEL2]   # for _l2 tests
      [+cover=bcesfx]                         # for cov_l2
      +incdir+<repo_root>                     # for verif/include/tb_level.svh
      rtl/questa_src_eclass.f
      [verif/coverage/t1_l2_func_cov.sv]
      verif/tb/<top>.sv

vopt  +acc -o <top>_opt  <top>
      [+cover=bcesfx]

vsim  -batch -t 1ps
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

## Log Files

| Path | Contents |
|------|----------|
| `build/eclass_<test>/compile.log` | vlog output |
| `build/eclass_<test>/vopt.log` | vopt output |
| `build/eclass_<test>/sim.log` | vsim transcript — PASS/FAIL markers |
| `build/eclass_<test>/<test>.wlf` | Waveform database (if `--waves`) |
| `build/eclass_<test>/coverage_html/index.html` | Coverage report (if `--coverage`) |

---

## Adding a New E-class Test

1. Create `sw/tests/mytest.c` (write TOHOST=1 on pass, non-zero on fail)
2. Add build rule to `sw/Makefile`
3. Create (or reuse) a testbench in `verif/tb/`
4. Add entry to `TESTS` dict in `scripts/eclass_sim.py`
5. Run: `python scripts/eclass_sim.py mytest`
