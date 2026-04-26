# ==============================================================================
# t1_soc_top_eclass.sdc  —  SDC Timing Constraints
#                            OpenSoC Tier-1 Shakti E-class SoC
#
# VALID FOR: Cadence Genus (sky130 ASIC) and Xilinx Vivado (FPGA).
#            Vivado-specific overrides are in constraints/vivado/t1_soc_top_eclass.xdc
#
# CLOCK STRATEGY
#   Primary clock  : clk_i  (system clock, all synchronous logic)
#   JTAG clock     : jtag_tck_i (tied off; defined to prevent unconstrained warnings)
#   No generated clocks (no PLL in t1_clkrst.sv for this variant).
#
# TARGET FREQUENCY
#   sky130 ASIC : 25 MHz  (40 ns)  — achievable with sky130_fd_sc_hd TT corner
#                                     Raise to 50 MHz after sign-off with SS corner.
#   FPGA        : 100 MHz (10 ns)  — override in Vivado XDC (see constraints/vivado/)
#
# UART NOTE
#   At 25 MHz the UART baud divisor for 115200 baud = 25e6/115200 ≈ 217.
#   Update NCO_SIM or baud_div in uart_test.c / uart.sv if the target clock changes.
# ==============================================================================

# ------------------------------------------------------------------------------
# Primary clock
# ------------------------------------------------------------------------------
create_clock -name clk_i -period 40.0 [get_ports clk_i]

# Waveform: rise at 0, fall at 20 ns (50% duty cycle)
set_clock_uncertainty 0.5 [get_clocks clk_i]

# ------------------------------------------------------------------------------
# JTAG clock (jtag_tck_i is driven 1'b0 in synthesis; define to avoid warnings)
# ------------------------------------------------------------------------------
create_clock -name jtag_tck -period 100.0 [get_ports jtag_tck_i]
set_clock_groups -asynchronous -group {clk_i} -group {jtag_tck}

# ------------------------------------------------------------------------------
# Input delays  (external combinatorial delay before clk_i edge)
# Assume PCB + package = 2 ns, setup margin = 3 ns  → input delay = 5 ns
# ------------------------------------------------------------------------------
set all_in_ex_clk [remove_from_collection [all_inputs] [get_ports {clk_i jtag_tck_i}]]
set_input_delay -clock clk_i -max 5.0 $all_in_ex_clk
set_input_delay -clock clk_i -min 1.0 $all_in_ex_clk

# ------------------------------------------------------------------------------
# Output delays
# Assume external register setup = 3 ns, PCB = 2 ns  → output delay = 5 ns
# ------------------------------------------------------------------------------
set_output_delay -clock clk_i -max 5.0 [all_outputs]
set_output_delay -clock clk_i -min 1.0 [all_outputs]

# ------------------------------------------------------------------------------
# Driving cell for inputs (sky130_fd_sc_hd__buf_4 at 25 MHz)
# Comment out if not using sky130 Liberty (Vivado ignores this gracefully)
# ------------------------------------------------------------------------------
# set_driving_cell -lib_cell sky130_fd_sc_hd__buf_4 -pin X [all_inputs]
# set_load 0.05 [all_outputs]  ;# 50 fF estimated PCB + pad capacitance

# ------------------------------------------------------------------------------
# Don't touch memory macros (Genus: prevents optimization across macro boundary)
# ------------------------------------------------------------------------------
# set_dont_touch [get_cells -hier *u_sram*]

# ------------------------------------------------------------------------------
# Maximum fanout / transition (sky130 HD library limits)
# ------------------------------------------------------------------------------
set_max_fanout 16 [current_design]
set_max_transition 2.0 [current_design]
