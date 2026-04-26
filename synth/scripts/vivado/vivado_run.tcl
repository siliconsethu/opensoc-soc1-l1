##############################################################################
# vivado_run.tcl  —  Xilinx Vivado Synthesis + Implementation Flow
#                    OpenSoC Tier-1 Shakti E-class SoC
#
# USAGE
#   vivado -mode batch -source synth/scripts/vivado/vivado_run.tcl
#   OR:
#   make -f synth/Makefile vivado_bit
#
# ENVIRONMENT VARIABLES
#   DESIGN_ROOT  Repository root  (default: [pwd])
#   WORK_DIR     Output directory (default: synth/out/vivado)
#   LEVEL        1 or 2          (default: 1)
#   PART         Xilinx part     (default: xc7a35tcpg236-1  = Basys3)
#                Arty A7-35:  xc7a35tcsg324-1
#                Nexys A7-50: xc7a50tcsg324-1
#
# FLOW
#   1. Create in-memory project
#   2. Add RTL sources (FPGA SRAM override replaces behavioral mem[])
#   3. Add XDC constraints
#   4. Synthesis  (synth_design)
#   5. Opt + Place + Route  (opt_design / place_design / route_design)
#   6. Timing reports + DRC
#   7. Write bitstream
##############################################################################

# ---------------------------------------------------------------------------
# Environment helpers
# ---------------------------------------------------------------------------
proc getenv_default {var default} {
  if {[info exists ::env($var)]} { return $::env($var) } else { return $default }
}

set design_root [getenv_default DESIGN_ROOT [pwd]]
set work_dir    [getenv_default WORK_DIR    synth/out/vivado]
set level       [getenv_default LEVEL       1]
set part        [getenv_default PART        xc7a35tcpg236-1]

file mkdir $work_dir/reports
file mkdir $work_dir/bitstream
file mkdir $work_dir/checkpoints

puts "=== Vivado flow: LEVEL=$level  PART=$part ==="

# ---------------------------------------------------------------------------
# Create in-memory project
# ---------------------------------------------------------------------------
create_project -in_memory -part $part

# Enable XPM libraries (required for xpm_memory_sdpram in t1_sram_top_32_fpga.sv)
set_property -name "xpm_libraries" -value "XPM_MEMORY XPM_FIFO" \
    -objects [current_project]

# ---------------------------------------------------------------------------
# Add RTL sources
# ---------------------------------------------------------------------------
# Packages first
add_files -norecurse [list \
    $design_root/rtl/include/lc_ctrl_pkg.sv         \
    $design_root/rtl/include/prim_alert_pkg.sv       \
    $design_root/rtl/include/prim_ram_1p_pkg.sv      \
    $design_root/rtl/include/spi_device_pkg.sv       \
    $design_root/rtl/include/prim_mubi_pkg.sv        \
    $design_root/rtl/include/prim_subreg_pkg.sv      \
    $design_root/rtl/include/prim_util_pkg.sv        \
    $design_root/rtl/include/top_pkg.sv              \
    $design_root/rtl/include/prim_secded_pkg.sv      \
    $design_root/rtl/peripherals/tlul_pkg.sv         \
]

# Design RTL — common (L1 + L2)
# NOTE: t1_sram_top_32_fpga.sv is added INSTEAD OF rtl/memory/t1_sram_top_32.sv
#       It has the same module name (t1_sram_top_32) and uses XPM BRAM.
add_files -norecurse [list \
    $design_root/rtl/vendor/rv_uart/uart.sv          \
    $design_root/rtl/vendor/gpio/gpio.sv             \
    $design_root/rtl/cpu/shakti_eclass_wrapper.sv    \
    $design_root/rtl/interconnect/t1_bus_l1.sv       \
    $design_root/rtl/peripherals/t1_periph_ss_l1.sv  \
    $design_root/synth/rtl/t1_sram_top_32_fpga.sv    \
    $design_root/rtl/top/t1_soc_top_eclass.sv        \
]

# Level-2 additional files
if {$level == 2} {
    add_files -norecurse [list \
        $design_root/rtl/memory/t1_boot_rom_32.sv        \
        $design_root/rtl/interconnect/t1_xbar_32.sv      \
        $design_root/rtl/peripherals/t1_periph_ss_32.sv  \
    ]
}

# Include directories for `include
set_property include_dirs [list \
    $design_root/rtl/include \
    $design_root/rtl/peripherals \
] [current_fileset]

# Set all files as SystemVerilog
set_property file_type {SystemVerilog} [get_files *.sv]

# Top module
set_property top t1_soc_top_eclass [current_fileset]

# ---------------------------------------------------------------------------
# Generics / Parameters
# ---------------------------------------------------------------------------
if {$level == 1} {
    set sram_words 1024
} else {
    set sram_words 32768
}
set_property generic "SramNumWords=$sram_words" [current_fileset]

# ---------------------------------------------------------------------------
# Constraints (XDC)
# ---------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse \
    $design_root/synth/constraints/vivado/t1_soc_top_eclass.xdc

# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------
puts "=== Running synthesis ==="
synth_design \
    -top       t1_soc_top_eclass \
    -part      $part \
    -flatten_hierarchy rebuilt \
    -directive PerformanceOptimized \
    -verilog_define {SYNTHESIS=1}

write_checkpoint -force $work_dir/checkpoints/post_synth.dcp

# Synthesis reports
report_timing_summary -max_paths 20 \
    -file $work_dir/reports/post_synth_timing.rpt
report_utilization \
    -file $work_dir/reports/post_synth_util.rpt
report_clock_interaction \
    -file $work_dir/reports/post_synth_clk_interact.rpt

# ---------------------------------------------------------------------------
# Implementation: Opt + Place + Route
# ---------------------------------------------------------------------------
puts "=== Running opt_design ==="
opt_design

puts "=== Running place_design ==="
place_design -directive Explore

# Post-placement physical optimisation
phys_opt_design -directive AggressiveExplore

write_checkpoint -force $work_dir/checkpoints/post_place.dcp
report_timing_summary -max_paths 20 \
    -file $work_dir/reports/post_place_timing.rpt

puts "=== Running route_design ==="
route_design -directive Explore

write_checkpoint -force $work_dir/checkpoints/post_route.dcp

# ---------------------------------------------------------------------------
# Post-Route Reports
# ---------------------------------------------------------------------------
report_timing_summary -max_paths 20 \
    -file $work_dir/reports/post_route_timing.rpt
report_utilization \
    -file $work_dir/reports/post_route_util.rpt
report_power \
    -file $work_dir/reports/post_route_power.rpt
report_drc \
    -file $work_dir/reports/post_route_drc.rpt
report_methodology \
    -file $work_dir/reports/post_route_methodology.rpt
report_io \
    -file $work_dir/reports/io_placement.rpt

# Check timing met
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
if {$wns < 0} {
    puts "WARNING: Timing NOT met! WNS = $wns ns"
} else {
    puts "INFO: Timing met. WNS = $wns ns"
}

# ---------------------------------------------------------------------------
# Write Bitstream
# ---------------------------------------------------------------------------
puts "=== Writing bitstream ==="
write_bitstream -force \
    $work_dir/bitstream/t1_soc_top_eclass_l${level}.bit

# Optionally write MCS for SPI flash programming
# write_cfgmem -force -format MCS -size 128 -interface SPIx4 \
#     -loadbit "up 0x00000000 $work_dir/bitstream/t1_soc_top_eclass_l${level}.bit" \
#     $work_dir/bitstream/t1_soc_top_eclass_l${level}.mcs

puts "\n=== Vivado flow complete ==="
puts "  Bitstream : $work_dir/bitstream/t1_soc_top_eclass_l${level}.bit"
puts "  Reports   : $work_dir/reports/"
puts "  DCP       : $work_dir/checkpoints/post_route.dcp"
