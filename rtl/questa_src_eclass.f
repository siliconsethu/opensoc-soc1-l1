// OpenSoC Tier-1 — QuestaSim source file list (Shakti E-class variant)
// Paths are relative to project root.
//
// Compilation order: packages → TLUL infra → vendor IPs → project RTL → top
//
// L1 (no +define+LEVEL2): rv_uart + gpio vendor IPs via t1_periph_ss_l1
// L2 (+define+LEVEL2):     self-contained t1_periph_ss_32 (no vendor deps)

// ── Base stub packages (no inter-dependencies) ────────────────────────────────
rtl/include/lc_ctrl_pkg.sv
rtl/include/prim_alert_pkg.sv
rtl/include/prim_ram_1p_pkg.sv
rtl/include/spi_device_pkg.sv
rtl/include/prim_mubi_pkg.sv
rtl/include/prim_subreg_pkg.sv
rtl/include/prim_util_pkg.sv

// ── TL-UL bus parameters (must precede tlul_pkg and tlul_stubs) ──────────────
rtl/include/top_pkg.sv
rtl/include/prim_secded_pkg.sv

// ── TL-UL package (depends on top_pkg, prim_mubi_pkg, prim_secded_pkg) ───────
rtl/peripherals/tlul_pkg.sv

// ── Vendor IP: OpenTitan UART (L1 only; depends on tlul_pkg, prim_alert_pkg) ─
rtl/vendor/rv_uart/uart.sv

// ── Vendor IP: OpenTitan GPIO (L1 only; depends on tlul_pkg, prim_alert_pkg) ─
rtl/vendor/gpio/gpio.sv

// ── E-class CPU wrapper (behavioural stub) ────────────────────────────────────
rtl/cpu/shakti_eclass_wrapper.sv

// ── RV32IM ISS (executable CPU model for CPU boot tests) ─────────────────────
rtl/cpu/rv32i_iss.sv

// ── 32-bit crossbar (L2) and L1 bus ──────────────────────────────────────────
rtl/interconnect/t1_xbar_32.sv
rtl/interconnect/t1_bus_l1.sv

// ── L1 peripheral subsystem (UART + GPIO via vendor IPs + TLUL bridge) ───────
rtl/peripherals/t1_periph_ss_l1.sv

// ── 32-bit memory subsystem ───────────────────────────────────────────────────
rtl/memory/t1_boot_rom_32.sv
rtl/memory/t1_sram_top_32.sv

// ── L2 peripheral subsystem (self-contained; no vendor deps) ─────────────────
rtl/peripherals/t1_periph_ss_32.sv

// ── E-class SoC top-level ─────────────────────────────────────────────────────
rtl/top/t1_soc_top_eclass.sv
