# OpenSoC Tier-1 — Windows + QuestaSim Quickstart

Complete commands from a fresh Windows 11 machine to a running simulation.

---

## Prerequisites

- Windows 10 (2004+) or Windows 11
- QuestaSim installed (Intel FPGA Pro or Mentor/Siemens standalone)
- Python 3.8+ on PATH
- RISC-V GCC toolchain (for firmware build)

---

## Step 0 — Clone the repo

Open **PowerShell**:

```powershell
git clone https://github.com/your-org/opensoc-tier1.git
cd opensoc-tier1\soc1.1
```

---

## Step 1 — Set QUESTA_HOME

```powershell
# Set for this session:
$env:QUESTA_HOME = "C:\intelFPGA_pro\23.1\questa_fse"

# Set permanently (User scope):
[System.Environment]::SetEnvironmentVariable("QUESTA_HOME",
    "C:\intelFPGA_pro\23.1\questa_fse", "User")
```

QuestaSim is also auto-detected from common install paths if `QUESTA_HOME` is not set.

---

## Step 2 — Install RISC-V GCC (for firmware)

### Option A: xpack toolchain (recommended for Windows)

Download from https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
and extract to e.g. `C:\tools\xpack-riscv-none-elf-14.2.0`.

```powershell
$env:RISCV = "C:\tools\xpack-riscv-none-elf-14.2.0"
```

### Option B: WSL2 Ubuntu

```bash
sudo apt install gcc-riscv64-unknown-elf
```

---

## Step 3 — Build firmware

```bash
# From repo root — Git Bash, WSL2, or any shell with make
make -C sw           # build all 4 hex files
```

Or build one at a time:

```bash
make -C sw gpio_l2
make -C sw uart_l2
```

Hex files land in `sw/tests/`.

---

## Step 4 — Run simulation

### Python (cross-platform, recommended)

```bash
# GPIO tests
python scripts/eclass_sim.py gpio_l1
python scripts/eclass_sim.py gpio_l2

# UART loopback tests
python scripts/eclass_sim.py uart_l1
python scripts/eclass_sim.py uart_l2

# L2 functional coverage
python scripts/eclass_sim.py cov_l2 --coverage

# Options
python scripts/eclass_sim.py gpio_l2 --gui --waves   # QuestaSim GUI
python scripts/eclass_sim.py uart_l2 --clean         # wipe build dir first
python scripts/eclass_sim.py uart_l2 --no-build      # skip firmware auto-build
python scripts/eclass_sim.py uart_l2 --hex path/to/custom.hex
```

> `eclass_sim.py` auto-builds firmware via `make -C sw` if hex files are missing or stale.

### Makefile approach (WSL2 / Git Bash)

```bash
# E-class tests (firmware must already be built)
make -f verif/scripts/Makefile.questa eclass_gpio_l1
make -f verif/scripts/Makefile.questa eclass_gpio_l2
make -f verif/scripts/Makefile.questa eclass_uart_l1
make -f verif/scripts/Makefile.questa eclass_uart_l2
make -f verif/scripts/Makefile.questa eclass_regression
make -f verif/scripts/Makefile.questa eclass_regression_l2
```

---

## Simulation flow

`eclass_sim.py` runs three QuestaSim steps:

```
1. vlog  -sv -mfcu +define+USE_ISS [+define+LEVEL2 +define+TEST_LEVEL2]
         rtl/questa_src_eclass.f  verif/tb/<top>.sv

2. vopt  +acc -o <top>_opt <top>

3. vsim  -batch -t 1ps +HEX_FILE=<path>  <top>_opt
         -do "run -all; quit -f"
```

Build output goes to `build/eclass_<test>/`:
- `compile.log`, `vopt.log`, `sim.log`
- `<test>.wlf` (if `--waves`)
- `coverage/` + `coverage_html/` (if `--coverage`)

---

## Troubleshooting

### "QUESTA_HOME not set" / QuestaSim not found
```powershell
Get-ChildItem "C:\intelFPGA_pro" -Filter "vsim.exe" -Recurse 2>$null
$env:QUESTA_HOME = "C:\intelFPGA_pro\23.1\questa_fse"
```

### `tb_level.svh` not found
`eclass_sim.py` adds `+incdir+<repo_root>` automatically. If compiling manually,
add `+incdir+.` from the repo root.

### UART / GPIO test times out (TOHOST never written)
1. Check firmware hex exists: `sw/tests/uart_test_l2.hex`
2. Build it: `make -C sw uart_l2`
3. Verify level: L2 test must be compiled with `+define+LEVEL2`

### SPI / I2C port connection errors on L1
SPI and I2C ports are absent in Level-1 builds (`` `ifdef LEVEL2 `` in RTL and
all TBs). Do not connect them when compiling without `+define+LEVEL2`.

### Work library error
```bash
python scripts/eclass_sim.py gpio_l2 --clean
```

### RISC-V GCC not found for firmware build
```bash
# WSL2 Ubuntu
sudo apt install gcc-riscv64-unknown-elf

# Or set xpack path (Windows)
$env:RISCV = "C:\path\to\xpack-riscv-none-elf-14.2.0"
```
