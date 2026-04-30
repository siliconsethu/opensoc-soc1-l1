##############################################################################
# genus_run.tcl  —  Cadence Genus Synthesis Flow
#                   OpenSoC Tier-1 Shakti E-class SoC (Level-1)
#                   Technology: SkyWater sky130 (sky130_fd_sc_hd, 130 nm)
#
# USAGE
#   genus -no_gui -execute synth/scripts/genus/genus_run.tcl
#   OR:
#   make -f synth/Makefile genus_l1
#
# ENVIRONMENT VARIABLES (set before invoking, or edit defaults below)
#   PDK_ROOT     Root of sky130A PDK installation
#                Default: /opt/pdk/sky130A
#                         (OpenLane default; Skywater PDK default: /usr/share/pdk)
#   DESIGN_ROOT  Root of this repository
#                Default: current working directory
#   WORK_DIR     Synthesis output directory
#                Default: synth/out/genus
#   LEVEL        1 or 2 (L1=4KB SRAM, L2=128KB SRAM+Boot ROM)
#                Default: 1
#
# GF180MCU ALTERNATIVE
#   Set PDK_ROOT to the GF180MCU PDK root and replace library names:
#     sky130_fd_sc_hd__tt_025C_1v80.lib  →  gf180mcu_fd_sc_mcu7t5v0__tt_025C_3v30.lib
#     sky130_sram_1rw1r_32x1024_8.lib    →  gf180mcu_sram equivalent
##############################################################################

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
proc getenv_default {var default} {
  if {[info exists ::env($var)]} { return $::env($var) } else { return $default }
}

set design_root [getenv_default DESIGN_ROOT [pwd]]
set pdk_root    [getenv_default PDK_ROOT    /opt/pdk/sky130A]
set work_dir    [getenv_default WORK_DIR    synth/out/genus]
set level       [getenv_default LEVEL       1]

file mkdir $work_dir/reports
file mkdir $work_dir/db
file mkdir $work_dir/netlists

puts "=== Genus synthesis: LEVEL=$level  PDK=$pdk_root ==="

# ---------------------------------------------------------------------------
# Library Setup — sky130_fd_sc_hd (High-Density standard cells)
# ---------------------------------------------------------------------------
# TT corner: typical-typical, 25°C, 1.8 V
# For sign-off:
#   read additional SS corner: sky130_fd_sc_hd__ss_100C_1v60.lib
#   read additional FF corner: sky130_fd_sc_hd__ff_n40C_1v95.lib
# ---------------------------------------------------------------------------
set_db init_lib_search_path [list \
    $pdk_root/libs.ref/sky130_fd_sc_hd/lib \
]

set sram_lib "$design_root/synth/libs/sky130_sram_1kbyte_1rw1r_8x1024_8_TT_1p8V_25C.lib"
read_libs [list \
    $pdk_root/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
    $sram_lib \
]

# sky130 OpenRAM SRAM macro Liberty model
# Obtain from: https://github.com/efabless/sky130_sram_macros
# or generate:  openram synth/libs/sky130_sram_1rw1r_32x1024_8.cfg
# Place the generated sky130_sram_1rw1r_32x1024_8.lib in synth/libs/
if {[file exists $sram_lib]} {
    #read_libs $sram_lib
    puts "INFO: Loaded SRAM macro Liberty: $sram_lib"
} else {
    puts "WARNING: $sram_lib not found."
    puts "         sky130_sram_1rw1r_32x1024_8 will be a black box."
    puts "         Run: make -f synth/Makefile gen_sram_lib  to generate it."
}

# ---------------------------------------------------------------------------
# RTL Read
# ---------------------------------------------------------------------------
# Include paths (for `include directives)
set_db hdl_search_path [list \
    $design_root/rtl/include \
    $design_root/rtl/peripherals \
    $design_root/synth/rtl \
]

# SV packages — must be read before modules that use them
read_hdl -sv [list \
    $design_root/rtl/include/lc_ctrl_pkg.sv        \
    $design_root/rtl/include/prim_alert_pkg.sv      \
    $design_root/rtl/include/prim_ram_1p_pkg.sv     \
    $design_root/rtl/include/spi_device_pkg.sv      \
    $design_root/rtl/include/prim_mubi_pkg.sv       \
    $design_root/rtl/include/prim_subreg_pkg.sv     \
    $design_root/rtl/include/prim_util_pkg.sv       \
    $design_root/rtl/include/top_pkg.sv             \
    $design_root/rtl/include/prim_secded_pkg.sv     \
    $design_root/rtl/peripherals/tlul_pkg.sv        \
]

# Design RTL — Level-1 configuration (no USE_ISS, no LEVEL2)
# t1_sram_sky130_wrap.sv is read BEFORE rtl/memory/t1_sram_top_32.sv
# so Genus uses the sky130 macro version of the SRAM.
# The original t1_sram_top_32.sv behavioral mem[] is NOT read here.

read_hdl -sv -define {SYNTHESIS} [list \
    $design_root/synth/rtl/t1_sram_sky130_wrap.sv   \
    $design_root/synth/rtl/t1_sram_top_32_asic.sv   \
    $design_root/rtl/vendor/rv_uart/uart.sv          \
    $design_root/rtl/vendor/gpio/gpio.sv             \
    $design_root/rtl/cpu/shakti_eclass_wrapper.sv    \
    $design_root/rtl/interconnect/t1_bus_l1.sv       \
    $design_root/rtl/peripherals/t1_periph_ss_l1.sv  \
    $design_root/rtl/top/t1_soc_top_eclass.sv        \
]

# Level-2 adds boot ROM + full peripheral subsystem (t1_periph_ss_32.sv)
if {$level == 2} {
    read_hdl -sv -define {SYNTHESIS LEVEL2} [list \
        $design_root/rtl/memory/t1_boot_rom_32.sv       \
        $design_root/rtl/interconnect/t1_xbar_32.sv     \
        $design_root/rtl/peripherals/t1_periph_ss_32.sv \
    ]
}

# ---------------------------------------------------------------------------
# Elaboration
# ---------------------------------------------------------------------------
#elaborate t1_soc_top_eclass

# Set Level-1 SRAM size (1024 words = 4 KB)
# For Level-2: 32768 words = 128 KB
if {$level == 1} {
elaborate t1_soc_top_eclass -parameters { {SramNumWords 1024} }
#    elaborate t1_soc_top_eclass -parameters { SramNumWords 1024 }

} else {
elaborate t1_soc_top_eclass -parameters { {SramNumWords 32768} }
#elaborate t1_soc_top_eclass -parameters { SramNumWords 32768 }
}

# Mark SRAM macro black-box boundary (Genus will not try to synthesise inside)
set_db [get_cells -hier -filter {is_black_box==true}] .preserve true

# CPU stub: shakti_eclass_wrapper outputs are all 0/constant.
# Genus will propagate constants and remove dead logic automatically.

# ---------------------------------------------------------------------------
# RAM Inference (for any inferred RAMs not covered by black-box SRAM macro)
# ---------------------------------------------------------------------------
# If Genus infers a RAM from RTL (e.g., Boot ROM), map it to sky130 SRAM.
# Uncomment and adjust when using Level-2 with additional memories.
#
# define_memory_model -name sky130_sram_1rw1r_32x1024_8 \
#     -read_ports 2 -write_ports 1                        \
#     -addr_width 10 -data_width 32                       \
#     -byte_enable_width 4

# ---------------------------------------------------------------------------
# Timing Constraints
# ---------------------------------------------------------------------------
read_sdc $design_root/synth/constraints/t1_soc_top_eclass.sdc
read_sdc $design_root/synth/constraints/exceptions.sdc

# Verify no unconstrained paths
check_timing_intent

# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------
# Generic: technology-independent optimisation (gate-level IR)
syn_generic -effort medium

# Map: map to sky130_fd_sc_hd library cells
syn_map -effort medium

# Optimise: post-mapping timing and area cleanup
syn_opt -effort medium

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
report_timing  -max_paths 20               > $work_dir/reports/timing_setup.rpt
#report_timing  -max_paths 20 -late         > $work_dir/reports/timing_hold.rpt
report_area                                > $work_dir/reports/area.rpt
report_power   -depth 3                    > $work_dir/reports/power.rpt
report_gates                               > $work_dir/reports/gates.rpt
report_messages                            > $work_dir/reports/messages.rpt
report_constraint -all_violators           > $work_dir/reports/violations.rpt

# ---------------------------------------------------------------------------
# Write Outputs
# ---------------------------------------------------------------------------
# Gate-level netlist (Verilog)
#write_hdl -mapped > $work_dir/netlists/t1_soc_top_eclass_netlist.v
write_hdl > $work_dir/netlists/t1_soc_top_eclass_netlist.v

# Back-annotated SDC for APR (Innovus / OpenROAD)
write_sdc > $work_dir/netlists/t1_soc_top_eclass_mapped.sdc

# Genus database (for ECO / incremental synthesis)
write_db $work_dir/db/t1_soc_top_eclass.db

# SPEF stub (physical parasitics placeholder for pre-layout timing)
# write_spef $work_dir/netlists/t1_soc_top_eclass_prelay.spef
# QoR summary
puts "\n=== Synthesis QoR Summary ==="
puts "  WNS  : [get_db [get_timing_paths -max_paths 1 -path_type max] .slack] ns"
puts "  Area : [get_db [get_designs t1_soc_top_eclass] .area] um2"


puts "\n=== Genus synthesis complete ==="
puts "  Netlist : $work_dir/netlists/t1_soc_top_eclass_netlist.v"
puts "  SDC     : $work_dir/netlists/t1_soc_top_eclass_mapped.sdc"
puts "  Reports : $work_dir/reports/"
