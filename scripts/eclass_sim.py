"""
eclass_sim.py  --  OpenSoC Tier-1 E-class simulation runner (Level-1)
Compiles RTL with QuestaSim, builds firmware if needed, and runs the sim.

Tests available:
  gpio_l1   GPIO testbench, Level-1 (16-bit, OpenTitan gpio.sv)
  uart_l1   UART loopback testbench, Level-1 (OpenTitan uart.sv)

Usage:
  python scripts/eclass_sim.py gpio_l1
  python scripts/eclass_sim.py uart_l1
  python scripts/eclass_sim.py gpio_l1 --gui --waves
  python scripts/eclass_sim.py gpio_l1 --clean
  python scripts/eclass_sim.py uart_l1 --no-build   # skip auto-build
"""

import os
import re
import sys
import shutil
import argparse
import subprocess
from pathlib import Path

TESTS = {
    "gpio_l1": dict(top="t1_eclass_gpio_tb", tb="verif/tb/t1_eclass_gpio_tb.sv",
                    hex="sw/tests/gpio_test_l1.hex", level2=False, cov_tb=False),
    "uart_l1": dict(top="t1_eclass_uart_tb", tb="verif/tb/t1_eclass_uart_tb.sv",
                    hex="sw/tests/uart_test_l1.hex", level2=False, cov_tb=False),
}

SW_BUILDS = {
    "gpio_l1": "gpio_l1",
    "uart_l1": "uart_l1",
}


def find_repo_root():
    here = Path(__file__).resolve().parent
    for candidate in [here.parent, here, Path.cwd()]:
        if (candidate / "rtl").is_dir() and (candidate / "verif").is_dir():
            return candidate
    raise RuntimeError("Cannot find repo root. Run from repo root or scripts/.")


def find_questa():
    questa_home = os.environ.get("QUESTA_HOME", "")
    if questa_home:
        for sub in ["bin", "linux_x86_64", ""]:
            p = Path(questa_home) / sub / "vsim"
            if p.exists():
                return Path(questa_home) / sub
        p = Path(questa_home) / "win64"
        if (p / "vsim.exe").exists():
            return p
    for name in ["vsim", "vsim.exe"]:
        result = shutil.which(name)
        if result:
            return Path(result).parent
    return None


def run(cmd, cwd=None, capture=False):
    print("  $", " ".join(str(c) for c in cmd))
    if capture:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        return r.stdout + r.stderr
    else:
        subprocess.run(cmd, cwd=cwd, check=True)
        return ""


def build_firmware(repo, test, verbose=False):
    sw_build = SW_BUILDS.get(test)
    if not sw_build:
        return
    hex_path = repo / TESTS[test]["hex"]
    if hex_path.exists():
        return
    print(f"[FW] Building firmware for {test} ...")
    py = sys.executable
    build_script = repo / "scripts" / "build_sw.py"
    if build_script.exists():
        subprocess.run([py, str(build_script), sw_build], cwd=repo, check=True)
    else:
        subprocess.run(["make", "-C", str(repo / "sw"), sw_build], check=True)


def main():
    parser = argparse.ArgumentParser(
        description="OpenSoC Tier-1 E-class simulation runner (Level-1)")
    parser.add_argument("test", choices=list(TESTS.keys()),
                        help="Test to run")
    parser.add_argument("--gui",       action="store_true",
                        help="Open QuestaSim GUI")
    parser.add_argument("--waves",     action="store_true",
                        help="Log all signals to waveform database")
    parser.add_argument("--no-build",  action="store_true",
                        help="Skip firmware auto-build")
    parser.add_argument("--clean",     action="store_true",
                        help="Delete build directory before running")
    parser.add_argument("--verbose",   action="store_true",
                        help="Show full tool output")
    args = parser.parse_args()

    repo   = find_repo_root()
    questa = find_questa()
    if questa is None:
        print("[ERROR] QuestaSim not found. Set QUESTA_HOME or add vsim to PATH.")
        sys.exit(1)

    cfg   = TESTS[args.test]
    build = repo / "build" / f"eclass_{args.test}"

    print()
    print("=" * 56)
    print(f"  OpenSoC Tier-1 E-class sim  --  {args.test}")
    print(f"  Repo    : {repo}")
    print(f"  Questa  : {questa}")
    print(f"  Build   : {build}")
    print(f"  Level   : 1")
    print("=" * 56)

    if args.clean and build.exists():
        shutil.rmtree(build)
        print(f"[CLEAN] Removed {build}")

    if not args.no_build:
        build_firmware(repo, args.test, args.verbose)

    hex_path = repo / cfg["hex"]
    if not hex_path.exists():
        print(f"[ERROR] Hex file not found: {hex_path}")
        print(f"        Build it:  make -C sw {SW_BUILDS[args.test]}")
        sys.exit(1)

    build.mkdir(parents=True, exist_ok=True)

    vlib = questa / "vlib"
    vlog = questa / "vlog"
    vopt = questa / "vopt"
    vsim = questa / "vsim"

    vlib_dir = build / "work"
    if not vlib_dir.exists():
        run([vlib, "work"], cwd=build)

    defines = ["+define+SIM", "+define+USE_ISS"]
    suppress = ["-suppress", "2583", "-suppress", "2718", "-suppress", "8386"]

    work_lib = str(build / "work")
    compile_cmd = [
        vlog, "-work", work_lib, "-sv", "-mfcu",
        *defines, *suppress,
        f"+incdir+{repo}",
        "-f", str(repo / "rtl" / "questa_src_eclass.f"),
        str(repo / cfg["tb"]),
    ]
    run(compile_cmd, cwd=repo)

    opt_top = cfg["top"] + "_opt"
    vopt_cmd = [vopt, "-work", work_lib, "+acc", "-o", opt_top, cfg["top"]]
    run(vopt_cmd, cwd=build)

    if args.gui:
        do_str = "log -r /*; " if args.waves else ""
        do_str += "run -all"
        vsim_cmd = [
            vsim, "-work", work_lib, "-t", "1ps",
            f"+HEX_FILE={hex_path}",
            "-do", do_str,
            opt_top,
        ]
    else:
        vsim_cmd = [
            vsim, "-work", work_lib, "-t", "1ps", "-batch",
            f"+HEX_FILE={hex_path}",
            "-do", "run -all; quit -f",
            opt_top,
        ]

    log_path = build / "sim.log"
    if not args.gui:
        out = run(vsim_cmd, cwd=build, capture=True)
        log_path.write_text(out, encoding="utf-8")
        print(out)
        passed = "[TB] PASS" in out
        print()
        print("=" * 56)
        print(f"  Result : {'PASS' if passed else 'FAIL'}")
        print(f"  Log    : {log_path}")
        print("=" * 56)
        sys.exit(0 if passed else 1)
    else:
        run(vsim_cmd, cwd=build)


if __name__ == "__main__":
    main()
