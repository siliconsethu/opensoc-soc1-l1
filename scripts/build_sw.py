#!/usr/bin/env python3
"""
build_sw.py  —  Compile OpenSoC Tier-1 E-class firmware to Verilog hex files.
Works on Windows, Linux, and macOS with any riscv32/riscv64 GNU toolchain.

Output hex files (Verilog $readmemh format, one 32-bit word per line):
  sw/tests/gpio_test_l1.hex   — L1 GPIO test  (OpenTitan gpio.sv, 16-bit)
  sw/tests/gpio_test_l2.hex   — L2 GPIO test  (t1_periph_ss_32, 32-bit)
  build/sw/uart_test_l1.hex   — L1 UART test  (OpenTitan uart.sv, NCO)
  build/sw/uart_test_l2.hex   — L2 UART test  (t1_periph_ss_32, baud_div)

Usage:
  python scripts/build_sw.py              # build all
  python scripts/build_sw.py --test gpio_l1
  python scripts/build_sw.py --verbose
"""

import argparse
import os
import platform
import shutil
import struct
import subprocess
import sys
from pathlib import Path

COLOURS = sys.stdout.isatty()
def _c(code, t): return f"\033[{code}m{t}\033[0m" if COLOURS else t
def log(m):  print(_c("36", f"\n==> {m}"))
def ok(m):   print(_c("32", f"  [OK]  {m}"))
def warn(m): print(_c("33", f"  [WARN] {m}"))
def fail(m): print(_c("31", f"\n  [FAIL] {m}")); sys.exit(1)

# ── Locate RISC-V toolchain ────────────────────────────────────────────────────
def find_riscv_gcc():
    """
    Return (gcc_path, objcopy_path).
    Search order:
      1. $RISCV env var (xpack toolchain root set by 01_install_tools.ps1)
      2. riscv32-unknown-elf-gcc on PATH
      3. riscv64-unknown-elf-gcc on PATH (works for rv32 with -march/-mabi flags)
    """
    riscv_root = os.environ.get("RISCV", "")
    exe = ".exe" if platform.system() == "Windows" else ""

    if riscv_root:
        for name in ("riscv32-unknown-elf-gcc", "riscv-none-elf-gcc",
                     "riscv64-unknown-elf-gcc"):
            gcc = Path(riscv_root) / "bin" / f"{name}{exe}"
            if gcc.exists():
                objcopy = gcc.parent / f"{name.replace('gcc','objcopy')}{exe}"
                return gcc, objcopy

    for name in ("riscv32-unknown-elf-gcc", "riscv-none-elf-gcc",
                 "riscv64-unknown-elf-gcc"):
        gcc = shutil.which(f"{name}{exe}") or shutil.which(name)
        if gcc:
            objcopy = shutil.which(f"{name.replace('gcc','objcopy')}{exe}") \
                   or shutil.which(name.replace("gcc", "objcopy"))
            return Path(gcc), Path(objcopy) if objcopy else None

    return None, None

# ── ELF → Verilog hex ─────────────────────────────────────────────────────────
def elf_to_verilog_hex(objcopy, elf_path, hex_path, verbose=False):
    """
    Convert ELF to flat binary with objcopy, then write a Verilog $readmemh
    hex file: one 32-bit word per line, little-endian byte order preserved.
    """
    bin_path = elf_path.with_suffix(".bin")

    cmd = [str(objcopy), "-O", "binary", "--gap-fill", "0x00",
           str(elf_path), str(bin_path)]
    if verbose:
        print("  $", " ".join(cmd))
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        fail(f"objcopy failed:\n{r.stderr}")

    data = bin_path.read_bytes()
    # Pad to multiple of 4
    while len(data) % 4:
        data += b"\x00"

    hex_path.parent.mkdir(parents=True, exist_ok=True)
    with hex_path.open("w") as f:
        for i in range(0, len(data), 4):
            word = struct.unpack_from("<I", data, i)[0]   # little-endian → uint32
            f.write(f"{word:08x}\n")

    bin_path.unlink(missing_ok=True)
    ok(f"→ {hex_path}  ({len(data)//4} words, {len(data)} bytes)")

# ── Compile one test ───────────────────────────────────────────────────────────
def build(gcc, objcopy, repo, srcs, out_name, out_dir, verbose=False):
    """
    Compile srcs (list of Path) with crt0.S, link with eclass.ld,
    produce <out_dir>/<out_name>.hex.
    """
    log(f"Building {out_name}")
    build_tmp = repo / "build" / "sw_obj" / out_name
    build_tmp.mkdir(parents=True, exist_ok=True)

    elf_path = build_tmp / f"{out_name}.elf"
    ld_script = repo / "sw" / "boot" / "eclass.ld"
    crt0 = repo / "sw" / "boot" / "crt0.S"

    flags = [
        "-march=rv32im", "-mabi=ilp32",
        "-nostdlib", "-nostartfiles", "-ffreestanding",
        "-Os", "-g",
        f"-T{ld_script}",
        f"-I{repo / 'sw' / 'include'}",   # optional include dir (may not exist)
    ]

    cmd = [str(gcc)] + flags + [str(crt0)] + [str(s) for s in srcs] + ["-o", str(elf_path)]
    if verbose:
        print("  $", " ".join(cmd))

    r = subprocess.run(cmd, capture_output=True, text=True)
    if verbose and r.stdout:
        print(r.stdout)
    if r.returncode:
        fail(f"Compile failed for {out_name}:\n{r.stderr}")
    if r.stderr.strip():
        warn(f"Compile warnings for {out_name}:\n{r.stderr.strip()}")

    out_dir_path = repo / out_dir
    hex_path = out_dir_path / f"{out_name}.hex"
    elf_to_verilog_hex(objcopy, elf_path, hex_path, verbose)

# ── Test catalogue ────────────────────────────────────────────────────────────
def get_tests(repo):
    return {
        "gpio_l1": dict(
            srcs=[repo / "sw" / "tests" / "gpio_test.c"],
            out_name="gpio_test_l1",
            out_dir="sw/tests",
        ),
        "gpio_l2": dict(
            srcs=[repo / "sw" / "tests" / "gpio_test_l2.c"],
            out_name="gpio_test_l2",
            out_dir="sw/tests",
        ),
        "uart_l1": dict(
            srcs=[repo / "sw" / "tests" / "uart_test.c"],
            out_name="uart_test_l1",
            out_dir="build/sw",
        ),
        "uart_l2": dict(
            srcs=[repo / "sw" / "tests" / "uart_test_l2.c"],
            out_name="uart_test_l2",
            out_dir="build/sw",
        ),
    }

# ── Main ───────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Build E-class firmware hex files")
    ap.add_argument("--test", choices=["gpio_l1","gpio_l2","uart_l1","uart_l2"],
                    help="Build one specific test (default: all)")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    repo = Path(__file__).resolve().parent.parent

    log("Locating RISC-V toolchain")
    gcc, objcopy = find_riscv_gcc()
    if not gcc:
        fail(
            "RISC-V GCC not found.\n"
            "  Option 1: Set $RISCV to xpack toolchain root.\n"
            "  Option 2: Install riscv32-unknown-elf-gcc and add to PATH.\n"
            "  Option 3: In WSL2: sudo apt install gcc-riscv64-linux-gnu"
        )
    if not objcopy or not objcopy.exists():
        # Try sibling objcopy next to gcc
        objcopy = gcc.parent / gcc.name.replace("gcc", "objcopy")
    if not objcopy.exists():
        fail(f"riscv objcopy not found next to {gcc}")
    ok(f"GCC     : {gcc}")
    ok(f"objcopy : {objcopy}")

    tests = get_tests(repo)
    to_build = [args.test] if args.test else list(tests.keys())

    for name in to_build:
        cfg = tests[name]
        build(gcc, objcopy, repo,
              cfg["srcs"], cfg["out_name"], cfg["out_dir"],
              verbose=args.verbose)

    print()
    ok("All done — hex files ready for simulation")
    print()
    print("  Now run:")
    print("    python scripts/eclass_sim.py uart_l1")
    print("    python scripts/eclass_sim.py uart_l2")
    print("    python scripts/eclass_sim.py gpio_l1")
    print("    python scripts/eclass_sim.py gpio_l2")

if __name__ == "__main__":
    main()
