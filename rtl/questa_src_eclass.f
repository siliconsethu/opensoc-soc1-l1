// OpenSoC Tier-1 — QuestaSim source file list (E-class Level-1 public)
// Paths are relative to the repository root.
//
// Compilation order: packages -> TLUL infra -> vendor IPs -> RTL -> top
//
// Level-1 configuration (no +define+LEVEL2):
//   CPU  : rv32i_iss (ISS) or shakti_eclass_wrapper (FPGA/ASIC stub)
//   Bus  : t1_bus_l1  (2-master x 2-slave 32-bit AXI4)
//   SRAM : 4 KB at 0x8000_0000
//   Periph: t1_periph_ss_l1 (OpenTitan UART + 16-bit GPIO via TLUL)

// -- Base stub packages (no inter-dependencies) ------------------------------
rtl/include/lc_ctrl_pkg.sv
rtl/include/prim_alert_pkg.sv
rtl/include/prim_ram_1p_pkg.sv
rtl/include/spi_device_pkg.sv
rtl/include/prim_mubi_pkg.sv
rtl/include/prim_subreg_pkg.sv
rtl/include/prim_util_pkg.sv

// -- TL-UL bus parameters (must precede tlul_pkg) ----------------------------
rtl/include/top_pkg.sv
rtl/include/prim_secded_pkg.sv

// -- TL-UL package (depends on top_pkg, prim_mubi_pkg, prim_secded_pkg) -----
rtl/peripherals/tlul_pkg.sv

// -- Vendor IP: OpenTitan UART (depends on tlul_pkg, prim_alert_pkg) ---------
rtl/vendor/rv_uart/uart.sv

// -- Vendor IP: OpenTitan GPIO (depends on tlul_pkg, prim_alert_pkg) ---------
rtl/vendor/gpio/gpio.sv

// -- E-class CPU wrapper (behavioural stub; replace with BSV mkE_Class.v) ----
rtl/cpu/shakti_eclass_wrapper.sv

// -- RV32IM ISS (executable CPU model for simulation) ------------------------
rtl/cpu/rv32i_iss.sv

// -- Level-1 bus (2-master x 2-slave AXI4 shared bus) -----------------------
rtl/interconnect/t1_bus_l1.sv

// -- Level-1 peripheral subsystem (UART + GPIO via vendor IPs + TLUL) --------
rtl/peripherals/t1_periph_ss_l1.sv

// -- 32-bit SRAM (4 KB for Level-1, NumWords=1024) ---------------------------
rtl/memory/t1_sram_top_32.sv

// -- E-class SoC top-level ---------------------------------------------------
rtl/top/t1_soc_top_eclass.sv
