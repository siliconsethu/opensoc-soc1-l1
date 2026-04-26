#!/usr/bin/env python3
"""
eclass_sim.py — Shakti E-class standalone simulation runner
Works on Windows, Linux, and macOS wherever QuestaSim is installed.

Automatically builds firmware via  make -C sw  (or build_sw.py fallback)
before running simulation — no manual hex compilation needed.

Tests:
  gpio_l1   GPIO testbench, Level-1 (16-bit, OpenTitan gpio.sv)
  gpio_l2   GPIO testbench, Level-2 (32-bit, t1_periph_ss_32)
  uart_l1   UART loopback testbench, Level-1 (OpenTitan uart.sv)
  uart_l2   UART loopback testbench, Level-2 (t1_periph_ss_32)
  cov_l2    L2 functional coverage testbench

Usage:
  python scripts/eclass_sim.py gpio_l2
  python scripts/eclass_sim.py uart_l2
  python scripts/eclass_sim.py cov_l2 --coverage
  python scripts/eclass_sim.py gpio_l2 --gui --waves
  python scripts/eclass_sim.py gpio_l2 --clean
  python scripts/eclass_sim.py uart_l1 --no-build   # skip auto-build
"""

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

# ── Colour helpers ─────────────────────────────────────────────────────────────
COLOURS = sys.stdout.isatty()
def _c(code, t): return f"\033[{code}m{t}\033[0m" if COLOURS else t
def log(m):  print(_c("36", f"\n==> {m}"))
def ok(m):   print(_c("32", f"  [OK]  {m}"))
def warn(m): print(_c("33", f"  [WARN] {m}"))
def fail(m): print(_c("31", f"\n  [FAIL] {m}")); sys.exit(1)

# ── QuestaSim search ───────────────────────────────────────────────────────────
QUESTA_SEARCH = [
    os.environ.get("QUESTA_HOME", ""),
    r"C:\intelFPGA_pro\23.1\questa_fse",
    r"C:\intelFPGA_pro\22.4\questa_fse",
    r"C:\modeltech64_2023.3",
    r"C:\modeltech64_2022.4",
    r"C:\questasim64_2023.3",
    r"C:\questasim64_10.7c",
    "/opt/questasim",
    "/opt/modelsim",
    "/tools/questa",
]

def find_questa():
    for root in QUESTA_SEARCH:
        if not root:
            continue
        for sub in ("win64", "bin", "linux_x86_64"):
            vsim = Path(root) / sub / ("vsim.exe" if platform.system() == "Windows" else "vsim")
            if vsim.exists():
                return Path(root) / sub
    vsim = shutil.which("vsim")
    if vsim:
        return Path(vsim).parent
    return None

# ── Test configuration ─────────────────────────────────────────────────────────
# All hex files are now in sw/tests/ (built by sw/Makefile)
TESTS = {
    "gpio_l1": dict(top="t1_eclass_gpio_tb", tb="verif/tb/t1_eclass_gpio_tb.sv",
                    hex="sw/tests/gpio_test_l1.hex", level2=False, cov_tb=False),
    "gpio_l2": dict(top="t1_eclass_gpio_tb", tb="verif/tb/t1_eclass_gpio_tb.sv",
                    hex="sw/tests/gpio_test_l2.hex", level2=True,  cov_tb=False),
    "uart_l1": dict(top="t1_eclass_uart_tb", tb="verif/tb/t1_eclass_uart_tb.sv",
                    hex="sw/tests/uart_test_l1.hex", level2=False, cov_tb=False),
    "uart_l2": dict(top="t1_eclass_uart_tb", tb="verif/tb/t1_eclass_uart_tb.sv",
                    hex="sw/tests/uart_test_l2.hex", level2=True,  cov_tb=False),
    "cov_l2":  dict(top="t1_l2_cov_tb",      tb="verif/tb/t1_l2_cov_tb.sv",
                    hex="sw/tests/gpio_test_l2.hex", level2=True,  cov_tb=True),
}

# Maps test name → make target in sw/Makefile
MAKE_TARGET = {
    "gpio_l1": "gpio_l1",
    "gpio_l2": "gpio_l2",
    "uart_l1": "uart_l1",
    "uart_l2": "uart_l2",
    "cov_l2":  "gpio_l2",
}

# ── Firmware auto-build ────────────────────────────────────────────────────────
def _sources_newer(hex_path, sw_dir):
    """True if any source file in sw/ is newer than hex_path."""
    if not hex_path.exists():
        return True
    hex_mtime = hex_path.stat().st_mtime
    for p in sw_dir.rglob("*"):
        if p.suffix in (".c", ".S", ".ld") and p.stat().st_mtime > hex_mtime:
            return True
    return False

def ensure_firmware(test, hex_path, repo, verbose):
    """
    Build firmware using  make -C sw <target>  if the hex is missing or stale.
    Falls back to build_sw.py if make is not available.
    """
    sw_dir = repo / "sw"
    if not _sources_newer(hex_path, sw_dir):
        ok(f"Firmware up-to-date: {hex_path.name}")
        return

    log(f"Building firmware: {hex_path.name}")

    make_target = MAKE_TARGET[test]
    make_cmd = None

    # Try make / gmake
    for m in ("make", "gmake", "mingw32-make"):
        if shutil.which(m):
            make_cmd = m
            break

    if make_cmd:
        cmd = [make_cmd, "-C", str(sw_dir), make_target]
        if verbose:
            print("  $", " ".join(cmd))
        r = subprocess.run(cmd)
        if r.returncode == 0 and hex_path.exists():
            ok(f"Built: {hex_path}")
            return
        warn(f"make failed (rc={r.returncode}), trying build_sw.py…")

    # Fallback: build_sw.py
    py_build = repo / "scripts" / "build_sw.py"
    if py_build.exists():
        # Map test name to build_sw.py --test argument
        build_test = {"gpio_l1":"gpio_l1","gpio_l2":"gpio_l2",
                      "uart_l1":"uart_l1","uart_l2":"uart_l2",
                      "cov_l2":"gpio_l2"}[test]
        cmd = [sys.executable, str(py_build), "--test", build_test]
        if verbose:
            print("  $", " ".join(cmd))
        r = subprocess.run(cmd)
        if r.returncode == 0 and hex_path.exists():
            ok(f"Built: {hex_path}")
            return
        fail(f"Firmware build failed. Check sw/Makefile or scripts/build_sw.py")
    else:
        fail(
            f"Hex file missing: {hex_path}\n"
            f"  Run:  make -C sw {make_target}\n"
            f"  Needs riscv32-unknown-elf-gcc or riscv64-unknown-elf-gcc on PATH"
        )

# ── F-file readers ─────────────────────────────────────────────────────────────
def read_incdirs(path, repo):
    dirs = []
    for raw in Path(path).read_text().splitlines():
        m = re.match(r"^\+incdir\+(.+)", raw.strip())
        if m:
            d = Path(m.group(1).replace("/", os.sep))
            if not d.is_absolute():
                d = repo / d
            dirs.append(f"+incdir+{d}")
    return dirs

def read_srcs(path, repo):
    srcs = []
    for raw in Path(path).read_text().splitlines():
        line = raw.strip()
        if line and not line.startswith("//") and line.endswith(".sv"):
            p = Path(line.replace("/", os.sep))
            if not p.is_absolute():
                p = repo / p
            if p.exists():
                srcs.append(p)
            else:
                warn(f"Source not found: {p}")
    return srcs

# ── Run helper ─────────────────────────────────────────────────────────────────
def run(cmd, log_path, cwd):
    print("  $", " ".join(str(c) for c in cmd))
    with Path(log_path).open("w") as lf:
        proc = subprocess.Popen([str(c) for c in cmd], stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, cwd=str(cwd))
        lines = []
        for raw in proc.stdout:
            line = raw.decode(errors="replace")
            sys.stdout.write(line)
            lf.write(line)
            lines.append(line)
        proc.wait()
        return "".join(lines), proc.returncode

# ── Main ───────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(
        description="Run Shakti E-class testbenches (auto-builds firmware)"
    )
    ap.add_argument("test", choices=list(TESTS))
    ap.add_argument("--hex",      default="", help="Override hex firmware path")
    ap.add_argument("--gui",      action="store_true")
    ap.add_argument("--waves",    action="store_true")
    ap.add_argument("--coverage", action="store_true")
    ap.add_argument("--clean",    action="store_true", help="Wipe sim build dir")
    ap.add_argument("--no-build", action="store_true", help="Skip firmware auto-build")
    ap.add_argument("--verbose",  "-v", action="store_true")
    args = ap.parse_args()

    cfg    = TESTS[args.test]
    is_l2  = cfg["level2"]
    do_cov = args.coverage or cfg["cov_tb"]

    repo      = Path(__file__).resolve().parent.parent
    build_dir = repo / "build" / f"eclass_{args.test}"

    # Resolve hex path
    hex_path = Path(args.hex) if args.hex else repo / cfg["hex"]
    if not hex_path.is_absolute():
        hex_path = repo / hex_path

    log(f"E-class sim: {args.test}  top={cfg['top']}")
    print(f"  Level   : {'2 (LEVEL2)' if is_l2 else '1'}")
    print(f"  HexFile : {hex_path}")

    # ── Auto-build firmware ────────────────────────────────────────────────────
    if not args.no_build and not args.hex:
        ensure_firmware(args.test, hex_path, repo, args.verbose)

    if not hex_path.exists():
        fail(f"Hex file not found: {hex_path}")

    # ── Find QuestaSim ─────────────────────────────────────────────────────────
    log("Locating QuestaSim")
    bin_dir = find_questa()
    if not bin_dir:
        fail("QuestaSim not found. Set QUESTA_HOME env var.")

    exe = ".exe" if platform.system() == "Windows" else ""
    VLIB  = bin_dir / f"vlib{exe}"
    VLOG  = bin_dir / f"vlog{exe}"
    VOPT  = bin_dir / f"vopt{exe}"
    VSIM  = bin_dir / f"vsim{exe}"
    VCOVER= bin_dir / f"vcover{exe}"
    ok(f"QuestaSim: {bin_dir}")

    # ── Build directory ────────────────────────────────────────────────────────
    log(f"Build dir: {build_dir}")
    if args.clean and build_dir.exists():
        shutil.rmtree(build_dir)
        ok("Cleaned")
    build_dir.mkdir(parents=True, exist_ok=True)

    # ── Work library ──────────────────────────────────────────────────────────
    if not (build_dir / "work").exists():
        subprocess.run([str(VLIB), "work"], cwd=str(build_dir), check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        ok("Created work library")
    else:
        ok("Reusing work library")

    # ── Sources ────────────────────────────────────────────────────────────────
    inc_f = repo / "rtl" / "questa_inc.f"
    src_f = repo / "rtl" / "questa_src_eclass.f"
    if not src_f.exists():
        fail(f"Missing {src_f}  — run 03_stitch_ips.ps1 first")

    incdirs = read_incdirs(inc_f, repo) if inc_f.exists() else []
    incdirs += [f"+incdir+{repo}"]        # resolves `include "verif/include/tb_level.svh"
    rtl_srcs = read_srcs(src_f, repo)

    if cfg["cov_tb"]:
        cov_sv = repo / "verif" / "coverage" / "t1_l2_func_cov.sv"
        if cov_sv.exists():
            rtl_srcs.append(cov_sv)
        else:
            warn(f"Coverage module not found: {cov_sv}")

    tb_sv = repo / cfg["tb"]
    if not tb_sv.exists():
        fail(f"Testbench not found: {tb_sv}")

    # ── Defines ────────────────────────────────────────────────────────────────
    defines = ["+define+SIM", "+define+USE_ISS"]
    if is_l2:
        defines += ["+define+LEVEL2", "+define+TEST_LEVEL2"]
    if do_cov:
        defines += ["+cover=bcesfx"]

    # ── Compile ───────────────────────────────────────────────────────────────
    log(f"Compiling {len(rtl_srcs)} RTL files + TB")
    vlog_cmd = (
        [VLOG, "-work", "work", "-sv",
         "-suppress", "2583", "-suppress", "2718", "-suppress", "8386",
         "-mfcu", "-cuname", "eclass_work"]
        + defines + incdirs + rtl_srcs + [tb_sv]
    )
    out, rc = run(vlog_cmd, build_dir / "compile.log", build_dir)
    errs = len(re.findall(r"^\*\* Error", out, re.MULTILINE))
    if errs or rc != 0:
        fail(f"Compilation failed ({errs} errors) — see {build_dir / 'compile.log'}")
    ok(f"Compiled OK")

    # ── vopt ──────────────────────────────────────────────────────────────────
    top_opt = f"{cfg['top']}_opt"
    log(f"Optimising → {top_opt}")
    vopt_cmd = [VOPT, "-work", "work", "+acc", "-o", top_opt, cfg["top"]]
    if do_cov:
        vopt_cmd += ["+cover=bcesfx"]
    out_v, rc_v = run(vopt_cmd, build_dir / "vopt.log", build_dir)
    if rc_v != 0 or re.search(r"^\*\* Error", out_v, re.MULTILINE):
        fail(f"vopt failed — see {build_dir / 'vopt.log'}")
    ok(f"vopt OK → {top_opt}")

    # ── vsim ──────────────────────────────────────────────────────────────────
    log(f"Simulating: {top_opt}")
    sim_log   = build_dir / "sim.log"
    wave_file = build_dir / f"{args.test}.wlf"

    vsim_cmd = [
        VSIM, "-work", "work", "-t", "1ps", "-batch",
        f"+HEX_FILE={hex_path}",
    ]
    if do_cov:
        vsim_cmd += ["-coverage", "-coverstore", str(build_dir / "coverage")]
    if args.waves or args.gui:
        vsim_cmd += ["-wlf", str(wave_file)]

    if args.gui:
        vsim_cmd = [c for c in vsim_cmd if c != "-batch"]
        do_file = build_dir / f"waves_{args.test}.do"
        do_file.write_text(f"add wave -r /{cfg['top']}/*\nrun -all\n")
        vsim_cmd += ["-do", str(do_file), top_opt]
        subprocess.Popen([str(c) for c in vsim_cmd], cwd=str(build_dir))
        ok(f"GUI launched — wlf: {wave_file}")
        return

    vsim_cmd += ["-do", "run -all; quit -f", top_opt]
    t0 = time.time()
    out, _ = run(vsim_cmd, sim_log, build_dir)
    elapsed = time.time() - t0

    # ── Results ───────────────────────────────────────────────────────────────
    pass_n  = len(re.findall(r"\[TB\] PASS",           out))
    fail_n  = len(re.findall(r"\[TB\] FAIL|\[FAIL\]",  out))
    timeout = len(re.findall(r"\[TB\] TIMEOUT|TIMEOUT after", out))
    questa  = len(re.findall(r"^\*\* Error", out, re.MULTILINE))

    print()
    print(_c("36", "─── Simulation Summary " + "─"*52))
    print(f"  Test     : {args.test}  ({'Level-2' if is_l2 else 'Level-1'})")
    print(f"  Duration : {elapsed:.1f}s")
    print(f"  PASS     : {_c('32',str(pass_n)) if pass_n else _c('33','0')}")
    print(f"  FAIL     : {_c('31',str(fail_n)) if fail_n else _c('32','0')}")
    print(f"  Timeouts : {_c('31',str(timeout)) if timeout else _c('32','0')}")
    print(f"  QstErrors: {_c('31',str(questa))  if questa  else _c('32','0')}")
    print(_c("36", "─"*75))

    print("\n  Key TB output:")
    for line in out.splitlines():
        if re.search(r"\[TB\]|\[FAIL\]|\[PASS\]", line):
            print(f"    {line}")

    # ── Coverage report ───────────────────────────────────────────────────────
    cov_store = build_dir / "coverage"
    if do_cov and cov_store.exists():
        log("Coverage report")
        ucdb_files = list(cov_store.rglob("*.ucdb"))
        if ucdb_files:
            merged  = build_dir / "merged.ucdb"
            cov_html = build_dir / "coverage_html"
            cov_html.mkdir(exist_ok=True)
            subprocess.run([str(VCOVER), "merge", str(merged)] + [str(u) for u in ucdb_files],
                           cwd=str(build_dir))
            subprocess.run([str(VCOVER), "report", "-html", "-output", str(cov_html), str(merged)],
                           cwd=str(build_dir))
            ok(f"Coverage HTML: {cov_html / 'index.html'}")

    # ── Verdict ───────────────────────────────────────────────────────────────
    print()
    if fail_n or timeout or questa:
        fail(f"TEST FAILED: {args.test}  (fails={fail_n} timeouts={timeout} questa={questa})")
    elif pass_n:
        ok(f"TEST PASSED: {args.test}")
    else:
        warn(f"No PASS/FAIL found — check {sim_log}")

    print(f"\n  Log: {sim_log}")
    if args.waves:
        print(f"  WLF: {wave_file}")

if __name__ == "__main__":
    main()
