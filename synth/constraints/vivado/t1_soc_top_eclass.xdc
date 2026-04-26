# ==============================================================================
# t1_soc_top_eclass.xdc  —  Vivado XDC Constraints
#                            OpenSoC Tier-1 Shakti E-class SoC
#
# TARGET BOARD  : Digilent Basys3  (xc7a35tcpg236-1)
#
# TO USE WITH ARTY A7-35:  uncomment ARTY pin assignments, comment Basys3.
# TO USE WITH NEXYS A7  :  update accordingly (see Digilent master XDC files).
#
# TOP-LEVEL PORTS:
#   clk_i         system clock
#   rst_ni        active-low reset (button, inverted externally or in RTL)
#   uart_tx_o     UART transmit to PC
#   uart_rx_i     UART receive from PC
#   gpio_out_o    driven to LEDs  [15:0]
#   gpio_in_i     driven from switches [15:0]
#   gpio_oe_o     ignored on FPGA (all GPIO outputs always driven)
#   halt_o        driven to single LED (CPU halt indicator)
# ==============================================================================

# ==============================================================================
# BASYS3  (xc7a35tcpg236-1)
# ==============================================================================

# -- Clock (100 MHz on-board oscillator, pin W5) --------------------------------
set_property PACKAGE_PIN W5      [get_ports clk_i]
set_property IOSTANDARD  LVCMOS33 [get_ports clk_i]
create_clock -period 10.000 -name clk_i -waveform {0.000 5.000} [get_ports clk_i]

# -- Reset (centre button BTNC = U18, active high → invert for rst_ni) ---------
# The design expects active-LOW rst_ni.
# Wire BTNC through an IBUF; invert in RTL top wrapper or in XDC with set_property.
# Option A: invert in your RTL wrapper (recommended).
# Option B: add an LUT1 inverter between the button and rst_ni.
set_property PACKAGE_PIN U18      [get_ports rst_ni]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_ni]
# BTNU=T18 can serve as a second reset button if needed.

# -- UART (USB-UART bridge on Basys3) -------------------------------------------
# PC TX → FPGA RX : pin A18 (UART_RXD_OUT on board)
set_property PACKAGE_PIN A18      [get_ports uart_rx_i]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_rx_i]
# FPGA TX → PC RX : pin B18 (UART_TXD_IN on board)
set_property PACKAGE_PIN B18      [get_ports uart_tx_o]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx_o]

# -- LEDs (gpio_out_o[15:0]) ---------------------------------------------------
set_property PACKAGE_PIN U16      [get_ports {gpio_out_o[0]}]
set_property PACKAGE_PIN E19      [get_ports {gpio_out_o[1]}]
set_property PACKAGE_PIN U19      [get_ports {gpio_out_o[2]}]
set_property PACKAGE_PIN V19      [get_ports {gpio_out_o[3]}]
set_property PACKAGE_PIN W18      [get_ports {gpio_out_o[4]}]
set_property PACKAGE_PIN U15      [get_ports {gpio_out_o[5]}]
set_property PACKAGE_PIN U14      [get_ports {gpio_out_o[6]}]
set_property PACKAGE_PIN V14      [get_ports {gpio_out_o[7]}]
set_property PACKAGE_PIN V13      [get_ports {gpio_out_o[8]}]
set_property PACKAGE_PIN V3       [get_ports {gpio_out_o[9]}]
set_property PACKAGE_PIN W3       [get_ports {gpio_out_o[10]}]
set_property PACKAGE_PIN U3       [get_ports {gpio_out_o[11]}]
set_property PACKAGE_PIN P3       [get_ports {gpio_out_o[12]}]
set_property PACKAGE_PIN N3       [get_ports {gpio_out_o[13]}]
set_property PACKAGE_PIN P1       [get_ports {gpio_out_o[14]}]
set_property PACKAGE_PIN L1       [get_ports {gpio_out_o[15]}]
set_property IOSTANDARD LVCMOS33  [get_ports {gpio_out_o[*]}]

# gpio_out_o[31:16] tied to 0 in L1; no pin assignment needed.

# -- Switches (gpio_in_i[15:0]) -----------------------------------------------
set_property PACKAGE_PIN V17      [get_ports {gpio_in_i[0]}]
set_property PACKAGE_PIN V16      [get_ports {gpio_in_i[1]}]
set_property PACKAGE_PIN W16      [get_ports {gpio_in_i[2]}]
set_property PACKAGE_PIN W17      [get_ports {gpio_in_i[3]}]
set_property PACKAGE_PIN W15      [get_ports {gpio_in_i[4]}]
set_property PACKAGE_PIN V15      [get_ports {gpio_in_i[5]}]
set_property PACKAGE_PIN W14      [get_ports {gpio_in_i[6]}]
set_property PACKAGE_PIN W13      [get_ports {gpio_in_i[7]}]
set_property PACKAGE_PIN V2       [get_ports {gpio_in_i[8]}]
set_property PACKAGE_PIN T3       [get_ports {gpio_in_i[9]}]
set_property PACKAGE_PIN T2       [get_ports {gpio_in_i[10]}]
set_property PACKAGE_PIN R3       [get_ports {gpio_in_i[11]}]
set_property PACKAGE_PIN W2       [get_ports {gpio_in_i[12]}]
set_property PACKAGE_PIN U1       [get_ports {gpio_in_i[13]}]
set_property PACKAGE_PIN T1       [get_ports {gpio_in_i[14]}]
set_property PACKAGE_PIN R2       [get_ports {gpio_in_i[15]}]
set_property IOSTANDARD LVCMOS33  [get_ports {gpio_in_i[*]}]

# gpio_in_i[31:16] = '0 (L1 uses only lower 16 bits)
# If the top-level port is declared [31:0], tie upper bits in a wrapper module.

# -- gpio_oe_o: not connected on FPGA (all outputs always driven) --------------
# tie off internally or leave unconnected in wrapper

# -- halt_o: wire to LED LD16 (rightmost LED on 7-seg digit select area) ------
# Basys3 does not have LD16; use an unused LED or 7-seg segment.
# Example: use DP segment of rightmost digit (N19).
set_property PACKAGE_PIN N19      [get_ports halt_o]
set_property IOSTANDARD LVCMOS33  [get_ports halt_o]

# ==============================================================================
# ARTY A7-35  (xc7a35tcsg324-1)  — uncomment and comment Basys3 section above
# ==============================================================================
# set_property PACKAGE_PIN E3      [get_ports clk_i]       ;# 100 MHz
# set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
# create_clock -period 10.000 -name clk_i [get_ports clk_i]
# set_property PACKAGE_PIN C2      [get_ports rst_ni]       ;# BTN0
# set_property IOSTANDARD LVCMOS33 [get_ports rst_ni]
# set_property PACKAGE_PIN A9      [get_ports uart_rx_i]
# set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]
# set_property PACKAGE_PIN D10     [get_ports uart_tx_o]
# set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]
# -- Arty LEDs LD0-LD3 (green) and RGB (use as status / gpio_out nibble) ------
# For full gpio_out[15:0] mapping add PMOD JA/JB/JC/JD pins.

# ==============================================================================
# Timing exceptions (supplement t1_soc_top_eclass.sdc)
# ==============================================================================

# False path on async reset (active-low, asynchronous)
set_false_path -from [get_ports rst_ni]

# JTAG ports are constant (0/1)
set_false_path -from [get_ports jtag_tck_i]
set_false_path -from [get_ports jtag_tms_i]
set_false_path -from [get_ports jtag_trst_ni]
set_false_path -from [get_ports jtag_tdi_i]
set_false_path -to   [get_ports jtag_tdo_o]
set_false_path -to   [get_ports jtag_tdo_oe_o]

# SPI and I2C tied off in L1
set_false_path -from [get_ports spi_sd_i]
set_false_path -to   [get_ports {spi_sck_o spi_csb_o spi_sd_o}]
set_false_path -from [get_ports {i2c_scl_i i2c_sda_i}]
set_false_path -to   [get_ports {i2c_scl_o i2c_sda_o}]

# halt_o quasi-static
set_false_path -to   [get_ports halt_o]

# GPIO inputs are asynchronous (no synchroniser in L1 RTL)
set_false_path -from [get_ports {gpio_in_i[*]}]

# ==============================================================================
# Bitstream configuration
# ==============================================================================
set_property BITSTREAM.GENERAL.COMPRESS TRUE     [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33      [current_design]
set_property CONFIG_VOLTAGE 3.3                  [current_design]
set_property CFGBVS VCCO                         [current_design]
