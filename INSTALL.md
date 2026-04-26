# OpenSoC Tier-1 — Installation Guide

Complete step-by-step setup for a new user on **Windows 10/11** or **WSL2 Ubuntu**.
Follow every step in order; each section includes a verification command so you
know it worked before moving on.

---

## System Requirements

| Item | Minimum | Recommended |
|------|---------|-------------|
| OS | Windows 10 (2004+) | Windows 11 22H2+ |
| RAM | 8 GB | 16 GB |
| Disk | 5 GB free | 20 GB free |
| CPU | Any x86-64 | Any x86-64 |
| QuestaSim | 2020.4+ | 2023.1 / 2024.1 |
| Python | 3.8+ | 3.11+ |
| RISC-V GCC | any riscv32 or riscv64 elf | xpack 14.2.0 |

> **Linux / WSL2**: All steps work identically. Substitute `$env:` PowerShell
> syntax with `export` bash syntax where noted.

---

## Step 1 — Get the Repository

Open **PowerShell** (Windows) or **bash** (WSL2 / Linux):

```powershell
# Windows PowerShell
cd C:\Users\YourName\Projects
git clone https://github.com/your-org/opensoc-tier1.git
cd opensoc-tier1\soc1.1
```

```bash
# WSL2 / Linux bash
cd ~/projects
git clone https://github.com/your-org/opensoc-tier1.git
cd opensoc-tier1/soc1.1
```

If you received a zip archive instead:

```powershell
Expand-Archive opensoc-tier1.zip .
cd opensoc-tier1\soc1.1
```

**Verify:** `dir` (Windows) or `ls` (bash) should show:
```
CLAUDE.md   INSTALL.md   README_ECLASS.md   rtl/   verif/   sw/   scripts/
```

---

## Step 2 — Install QuestaSim

### Option A: Intel FPGA / Quartus (most common)

Download **Intel Quartus Prime Pro** from the Intel FPGA Download Center.
During installation, select **QuestaSim-Intel FPGA Pro Edition** (also called
`questa_fse`).

Default install paths:

| Version | Path |
|---------|------|
| 23.1 | `C:\intelFPGA_pro\23.1\questa_fse` |
| 22.4 | `C:\intelFPGA_pro\22.4\questa_fse` |
| 21.1 | `C:\intelFPGA_pro\21.1\questa_fse` |

### Option B: Siemens / Mentor Standalone

Install QuestaSim standalone. Typical path: `C:\questasim64_2023.3`

### Verify QuestaSim

Open a new PowerShell window after installation:

```powershell
& "C:\intelFPGA_pro\23.1\questa_fse\win64\vsim.exe" -version
```

Expected output (version number will vary):
```
QuestaSim-64 vsim 2023.1 Compiler 2023.01 Jan 27 2023
```

---

## Step 3 — Set QUESTA_HOME

`eclass_sim.py` auto-detects QuestaSim from several common paths, but setting
`QUESTA_HOME` is the most reliable approach.

### Windows — set for current session

```powershell
$env:QUESTA_HOME = "C:\intelFPGA_pro\23.1\questa_fse"
```

### Windows — set permanently (survives reboot)

```powershell
[System.Environment]::SetEnvironmentVariable(
    "QUESTA_HOME",
    "C:\intelFPGA_pro\23.1\questa_fse",
    "User"
)
```

Then open a **new** PowerShell window and verify:

```powershell
echo $env:QUESTA_HOME
# Expected: C:\intelFPGA_pro\23.1\questa_fse

Test-Path "$env:QUESTA_HOME\win64\vsim.exe"
# Expected: True
```

### WSL2 / Linux

```bash
export QUESTA_HOME="/opt/questasim"          # adjust to your install path
echo 'export QUESTA_HOME="/opt/questasim"' >> ~/.bashrc
```

> **Tip**: If you don't set `QUESTA_HOME`, `eclass_sim.py` searches these paths
> automatically (in priority order):
> `C:\intelFPGA_pro\23.1\questa_fse` →
> `C:\intelFPGA_pro\22.4\questa_fse` →
> `C:\modeltech64_2023.3` →
> `C:\questasim64_2023.3` →
> `/opt/questasim` →
> `vsim` on PATH

---

## Step 4 — Install RISC-V GCC Toolchain

The firmware (`sw/`) must be compiled to a Verilog hex file before simulation.
Choose **one** of the three options below.

### Option A: xpack RISC-V GCC (recommended for Windows)

1. Download from the xpack GitHub releases page:
   `https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases`
   — choose the latest `win32-x64` zip (e.g. `xpack-riscv-none-elf-gcc-14.2.0-...`)

2. Extract to a permanent location, e.g. `C:\tools\xpack-riscv-none-elf-14.2.0`

3. Set the `RISCV` environment variable:

```powershell
# Session only
$env:RISCV = "C:\tools\xpack-riscv-none-elf-14.2.0"

# Permanent
[System.Environment]::SetEnvironmentVariable("RISCV",
    "C:\tools\xpack-riscv-none-elf-14.2.0", "User")
```

4. Verify (open a new PowerShell window if you set it permanently):

```powershell
& "$env:RISCV\bin\riscv-none-elf-gcc.exe" --version
```

Expected:
```
riscv-none-elf-gcc (xPack GNU RISC-V Embedded GCC x86_64) 14.2.0
```

### Option B: WSL2 Ubuntu (apt package)

```bash
sudo apt update
sudo apt install -y gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
riscv64-unknown-elf-gcc --version
```

Expected:
```
riscv64-unknown-elf-gcc (Ubuntu ...) 12.2.0
```

The `sw/Makefile` automatically falls back to `riscv64-unknown-elf-gcc` if the
preferred `riscv32-unknown-elf-gcc` is not found — this toolchain works fine.

### Option C: riscv32-unknown-elf-gcc (crosstool-ng)

If you have a custom toolchain built with crosstool-ng, set:

```bash
export RISCV=/path/to/your/toolchain   # must contain bin/riscv32-unknown-elf-gcc
```

### Toolchain search order (sw/Makefile)

| Priority | Binary |
|----------|--------|
| 1 | `riscv32-unknown-elf-gcc` |
| 2 | `riscv-none-elf-gcc` |
| 3 | `riscv64-unknown-elf-gcc` |

All three produce correct RV32IM bare-metal binaries.

---

## Step 5 — Install Python 3.8+

### Windows

Download the installer from `https://www.python.org/downloads/` and run it.
**Check "Add Python to PATH"** during installation.

Verify:

```powershell
python --version
# Expected: Python 3.x.x  (3.8 or later)

python -c "import docx; print('python-docx OK')"
```

If `python-docx` is missing (needed only for doc generation, not simulation):

```powershell
pip install python-docx
```

### WSL2 / Ubuntu

```bash
sudo apt install -y python3 python3-pip
pip3 install python-docx
python3 --version
```

---

## Step 6 — Verify All Tools

Run this quick checklist before building firmware:

```powershell
# 1. Python
python --version

# 2. QuestaSim
& "$env:QUESTA_HOME\win64\vsim.exe" -version

# 3. RISC-V GCC (xpack)
& "$env:RISCV\bin\riscv-none-elf-gcc.exe" --version

# 4. make (needed for firmware build)
make --version
```

> **make on Windows**: Use **Git Bash** (`C:\Program Files\Git\bin\bash.exe`)
> which ships with `make`, or install MSYS2 and add its `usr\bin` to PATH.
> Alternatively, `python scripts/build_sw.py` is a pure-Python fallback that
> does not need `make`.

Expected `make` output:
```
GNU Make 4.x.x
```

---

## Step 7 — Build Firmware

Firmware must be compiled once (and rebuilt automatically if sources change):

```bash
# From the repo root — Git Bash, WSL2, or any shell with make
make -C sw

# Or build individual targets
make -C sw gpio_l1
make -C sw gpio_l2
make -C sw uart_l1
make -C sw uart_l2
```

Expected output:
```
[CC]  gpio_test.c → gpio_test_l1.elf
[HEX] gpio_test_l1.elf → sw/tests/gpio_test_l1.hex
[CC]  gpio_test_l2.c → gpio_test_l2.elf
[HEX] gpio_test_l2.elf → sw/tests/gpio_test_l2.hex
[CC]  uart_test.c → uart_test_l1.elf
[HEX] uart_test_l1.elf → sw/tests/uart_test_l1.hex
[CC]  uart_test_l2.c → uart_test_l2.elf
[HEX] uart_test_l2.elf → sw/tests/uart_test_l2.hex
```

Verify hex files were created:

```bash
ls sw/tests/
# gpio_test_l1.hex  gpio_test_l2.hex  uart_test_l1.hex  uart_test_l2.hex
```

### If make is not available (Windows without Git Bash)

```powershell
python scripts/build_sw.py --test gpio_l1
python scripts/build_sw.py --test gpio_l2
python scripts/build_sw.py --test uart_l1
python scripts/build_sw.py --test uart_l2
```

---

## Step 8 — Run Your First Simulation

`eclass_sim.py` handles the complete flow (vlog → vopt → vsim) and
auto-rebuilds firmware if any hex file is missing or stale:

```bash
python scripts/eclass_sim.py gpio_l2
```

Expected transcript (abbreviated):

```
[SIM] Building firmware: make -C sw gpio_l2
[SIM] vlog  → build/eclass_gpio_l2/compile.log
[SIM] vopt  → build/eclass_gpio_l2/vopt.log
[SIM] vsim  → build/eclass_gpio_l2/sim.log

# vsim transcript:
[TB] Reset released — ISS booting from 0x00010000
[TB] PC = 0x00010000  (Boot ROM entry)
[TB] PC = 0x80000000  (SRAM entry, after boot jump)
[TB] GPIO walk-1 pattern: 32 iterations PASS
[TB] GPIO walk-0 pattern: 32 iterations PASS
[TB] GPIO_IN OR-accumulation PASS
[TB] TOHOST written after 230 cycles: 0x00000001
[TB] PASS -- all checks passed [L2]

[SIM] PASS  (gpio_l2)
```

A `[TB] PASS` line and exit code 0 confirm the simulation passed.

---

## Step 9 — Run Full Regression

```bash
# Level-1 regression (quick, ~2 minutes)
python scripts/eclass_sim.py gpio_l1
python scripts/eclass_sim.py uart_l1

# Level-2 regression (full, ~5 minutes)
python scripts/eclass_sim.py gpio_l2
python scripts/eclass_sim.py uart_l2
python scripts/eclass_sim.py cov_l2 --coverage
```

Or using the Makefile (WSL2 / Git Bash):

```bash
make -f verif/scripts/Makefile.questa eclass_regression       # L1
make -f verif/scripts/Makefile.questa eclass_regression_l2    # L2
```

Expected final line for each test:
```
GPIO L2: PASS
UART L2: PASS
[COV] Run complete — ucdb in build/eclass_cov_l2/coverage/
```

---

## Step 10 — Optional: Open QuestaSim GUI / Waves

```bash
# Open GUI with waveform window
python scripts/eclass_sim.py gpio_l2 --gui --waves

# View coverage report in browser
python scripts/eclass_sim.py cov_l2 --coverage
# then open: build/eclass_cov_l2/coverage_html/index.html
```

---

## Build Artifacts

After a successful run, `build/eclass_<test>/` contains:

| File | Contents |
|------|----------|
| `compile.log` | vlog output — check for errors |
| `vopt.log` | vopt output — elaboration messages |
| `sim.log` | vsim transcript — look for `[TB] PASS` |
| `<test>.wlf` | Waveform database (`--waves` only) |
| `coverage/` | UCDB coverage database (`--coverage` only) |
| `coverage_html/index.html` | HTML coverage report |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `QUESTA_HOME not set` or `vsim not found` | QuestaSim not on PATH and env var not set | Set `$env:QUESTA_HOME` — see Step 3 |
| `vsim.exe: command not found` | Wrong QUESTA_HOME path | Run `Test-Path "$env:QUESTA_HOME\win64\vsim.exe"` to verify |
| `riscv-none-elf-gcc: not found` | RISCV env var not set or wrong path | Set `$env:RISCV` — see Step 4 |
| `No rule to make target 'gpio_l1'` | make not finding sw/Makefile | Run from repo root: `make -C sw gpio_l1` |
| `Hex file not found: sw/tests/gpio_test_l2.hex` | Firmware not built | Run `make -C sw` or `python scripts/build_sw.py` |
| `** Error: vlog-2902` — file not found | questa_src_eclass.f path wrong | Run `eclass_sim.py` from the repo root directory |
| `** Error: vopt-2912` — port not found | Stale vendor IP | Check `README_VENDOR_CHANGES.md` — vendor files need patching |
| `tb_level.svh: No such file` | Missing `+incdir` | `eclass_sim.py` adds it automatically; for manual compile add `+incdir+.` |
| Test times out, no TOHOST | Wrong hex level | L2 test compiled without `+define+LEVEL2`; use `eclass_sim.py` which sets this automatically |
| `** Error: (vsim-19)` — work library missing | Build dir corrupted | Run `python scripts/eclass_sim.py <test> --clean` |
| `python-docx not found` | Missing pip package | `pip install python-docx` (only needed for doc generation) |
| `make: *** missing separator` | Makefile edited with wrong editor | Re-clone; ensure tabs (not spaces) in Makefile recipes |
| `Errors: N` in compile.log | RTL compile error | Read compile.log; common cause: missing vendor file — check `rtl/questa_src_eclass.f` paths |
| `[TB] FAIL` in sim.log | Firmware test logic failed | Read sim.log for the specific assertion; check firmware hex matches test level |

---

## Environment Variables Reference

| Variable | Purpose | Example |
|----------|---------|---------|
| `QUESTA_HOME` | QuestaSim install root | `C:\intelFPGA_pro\23.1\questa_fse` |
| `RISCV` | xpack toolchain root | `C:\tools\xpack-riscv-none-elf-14.2.0` |

---

## What Each Script Does

| Command | Description |
|---------|-------------|
| `python scripts/eclass_sim.py <test>` | Full simulation: auto-builds firmware, compiles RTL, runs vsim |
| `python scripts/eclass_sim.py <test> --clean` | Wipe build dir first, then simulate |
| `python scripts/eclass_sim.py <test> --gui --waves` | Open QuestaSim GUI with waveforms |
| `python scripts/eclass_sim.py <test> --no-build` | Skip firmware rebuild |
| `python scripts/eclass_sim.py <test> --verbose` | Print vlog/vsim output to console |
| `python scripts/build_sw.py --test <name>` | Build firmware only (no make needed) |
| `make -C sw` | Build all 4 hex files |
| `make -f verif/scripts/Makefile.questa <target>` | WSL2/Git Bash Makefile approach |

Available test names: `gpio_l1`, `gpio_l2`, `uart_l1`, `uart_l2`, `cov_l2`

---

## Next Steps

| Document | Read for |
|----------|----------|
| `README_ECLASS.md` | SoC architecture, address maps, register descriptions |
| `README_SIM.md` | Detailed simulation flow, suppressed warnings, artifacts |
| `README_MAKEFILE.md` | All Makefile targets and options |
| `docs/OpenSoC_Tier1_SWI.docx` | Register bit-field reference, hardware programming guide |
| `docs/OpenSoC_Tier1_FileInventory.docx` | Every source file with purpose description |
