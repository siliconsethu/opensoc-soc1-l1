# ==============================================================================
# exceptions.sdc  —  Timing Exceptions
#                    OpenSoC Tier-1 Shakti E-class SoC
#
# Applied AFTER t1_soc_top_eclass.sdc in both Genus and Vivado flows.
#
# CONTENTS
#   1. Asynchronous reset false paths
#   2. JTAG false paths  (all JTAG ports are tied off in L1/L2 stub)
#   3. SPI / I2C false paths  (tied off in L1)
#   4. halt_o false path  (quasi-static signal)
#   5. UART baud-rate generator multicycle paths
#   6. GPIO input synchroniser false path
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Asynchronous reset
#    rst_ni is an asynchronous input.  Flops use it as async reset/preset, so
#    there is no combinatorial path from the port through logic to a setup check.
#    Set false path from the port itself.
# ------------------------------------------------------------------------------
set_false_path -from [get_ports rst_ni]

# ------------------------------------------------------------------------------
# 2. JTAG ports
#    shakti_eclass_wrapper ties jtag_tdo_o=0, jtag_tdo_oe_o=0.
#    All JTAG inputs are unused constants.  No timing paths exist.
# ------------------------------------------------------------------------------
set_false_path -from [get_ports jtag_tck_i]
set_false_path -from [get_ports jtag_tms_i]
set_false_path -from [get_ports jtag_trst_ni]
set_false_path -from [get_ports jtag_tdi_i]
set_false_path -to   [get_ports jtag_tdo_o]
set_false_path -to   [get_ports jtag_tdo_oe_o]

# ------------------------------------------------------------------------------
# 3. SPI interface  (Level-1: spi_sck_o=0, spi_csb_o=1, spi_sd_o=0)
#    Outputs are tied-off constants, input is ignored.
# ------------------------------------------------------------------------------
set_false_path -from [get_ports spi_sd_i]
set_false_path -to   [get_ports spi_sck_o]
set_false_path -to   [get_ports spi_csb_o]
set_false_path -to   [get_ports spi_sd_o]

# ------------------------------------------------------------------------------
# 4. I2C interface  (Level-1: scl_o=1, sda_o=1 = bus idle)
#    Open-drain outputs held high; inputs ignored.
# ------------------------------------------------------------------------------
set_false_path -from [get_ports i2c_scl_i]
set_false_path -from [get_ports i2c_sda_i]
set_false_path -to   [get_ports i2c_scl_o]
set_false_path -to   [get_ports i2c_sda_o]

# ------------------------------------------------------------------------------
# 5. halt_o
#    Asserted only on CPU halt (ECALL/EBREAK).  Quasi-static; no timing.
# ------------------------------------------------------------------------------
set_false_path -to [get_ports halt_o]

# ------------------------------------------------------------------------------
# 6. UART baud-rate generator — multicycle paths
#
#    The UART NCO accumulator (nco_q in uart.sv) increments each clock and
#    fires a tick when it wraps.  At 25 MHz / 115200 baud, baud_div ≈ 217:
#      tick period = 217 clock cycles >> 1 clock period
#
#    Paths from the NCO tick to the TX shift register and RX sampler are
#    static for hundreds of cycles between ticks.  A 4-cycle MCP is
#    conservative; actual slack is ~217 cycles.
#
#    Pattern match: uart.sv uses registers named nco_q, tx_*, rx_*
#    Adjust -through/-from/-to if the synthesised instance path differs.
# ------------------------------------------------------------------------------
set_multicycle_path 4 -setup \
    -from [get_cells -hierarchical -filter {NAME =~ *nco_q*}]
set_multicycle_path 3 -hold  \
    -from [get_cells -hierarchical -filter {NAME =~ *nco_q*}]

# TX serialiser data path (driven once per baud tick)
set_multicycle_path 4 -setup \
    -from [get_cells -hierarchical -filter {NAME =~ *tx_state*}] \
    -to   [get_cells -hierarchical -filter {NAME =~ *tx_data*}]
set_multicycle_path 3 -hold  \
    -from [get_cells -hierarchical -filter {NAME =~ *tx_state*}] \
    -to   [get_cells -hierarchical -filter {NAME =~ *tx_data*}]

# RX sample path (oversampled at 16× baud; still >> 1 cycle)
set_multicycle_path 4 -setup \
    -from [get_cells -hierarchical -filter {NAME =~ *rx_state*}]
set_multicycle_path 3 -hold  \
    -from [get_cells -hierarchical -filter {NAME =~ *rx_state*}]

# ------------------------------------------------------------------------------
# 7. GPIO input — external asynchronous stimulus
#    gpio_in_i[15:0] is a combinatorial input from the system environment.
#    In L1 there is no input synchroniser in the RTL (added by user if needed).
#    Mark as false path to suppress unconstrained input warnings.
# ------------------------------------------------------------------------------
set_false_path -from [get_ports {gpio_in_i[*]}]

# ------------------------------------------------------------------------------
# 8. GPIO output / output-enable — quasi-static, driven by register writes
#    AXI register write → gpio_out_o / gpio_oe_o: relaxed to 2 cycles.
# ------------------------------------------------------------------------------
# (No special exception needed; output_delay in SDC covers these.)
