// ============================================================================
// t1_sram_sky130_wrap.sv  —  SkyWater sky130 OpenRAM SRAM macro wrapper
//                             OpenSoC Tier-1, L1 (1024 × 32 = 4 KB)
//
// TECHNOLOGY NOTE
//   "sky 180" in the project refers to the SkyWater open-source PDK family.
//   The available node is sky130A (130 nm).  For GlobalFoundries 180 nm use
//   gf180mcu_fd_ip_sram__sram512x8m8wm1 or equivalent GF180MCU macro.
//
// MACRO
//   sky130_sram_1rw1r_32x1024_8  (OpenRAM-generated, efabless/sky130_sram_macros)
//   — 1024 words × 32 bits = 4 KB  (matches L1 SRAM_WORDS = 1024)
//   — 1 read/write port (Port 0) + 1 read-only port (Port 1)
//   — 1-cycle registered read output on both ports
//   — Byte-granular write enable wmask0[3:0] on Port 0
//
// USAGE
//   Port 0  →  writes only (web0=0 when wr_en_i=1, csb0 = ~wr_en_i)
//   Port 1  →  reads only  (csb1 = ~rd_en_i)
//   Simultaneous read + write to different addresses: fully supported.
//   Read-during-write to the SAME address: undefined (avoid in software).
//
// READ TIMING
//   Cycle N  : rd_en_i=1, rd_addr_i=A presented at posedge clk_i
//   Cycle N+1: rd_data_o holds mem[A]  (SRAM registered output)
//   This matches the RD_WAIT → RD_DATA latency in t1_sram_top_32.sv.
//
// OBTAINING THE MACRO
//   Option A (pre-generated):
//     git clone https://github.com/efabless/sky130_sram_macros
//     Copy sky130_sram_1rw1r_32x1024_8.v + .lib + .lef into synth/libs/
//   Option B (OpenRAM):
//     pip install openram
//     openram synth/libs/sky130_sram_1rw1r_32x1024_8.cfg
//
// GF180MCU ALTERNATIVE
//   Replace the macro instantiation below with:
//     gf180mcu_fd_ip_sram__sram512x8m8wm1   (512 × 8, 4 ports → tile 8×)
//   or use GF OpenRAM-generated macro for 1024×32.
// ============================================================================
`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// Black-box stub for the sky130 OpenRAM macro.
// Remove (or guard with `ifndef) when the real Verilog model is in scope.
// Genus / Vivado will use the Liberty (.lib) model for timing; the Verilog
// stub is only needed for elaboration.
// ----------------------------------------------------------------------------
/**
(* keep_hierarchy = "yes" *)
module sky130_sram_1rw1r_8x1024_8 (
  // Port 0: read/write
  input         clk0,
  input         csb0,       // chip select, active low
  input         web0,       // write enable, active low
  input    wmask0,     // byte write mask (1 = write byte)
  input  [9:0]  addr0,
  input  [7:0] din0,
  output [7:0] dout0,
  // Port 1: read-only
  input         clk1,
  input         csb1,       // chip select, active low
  input  [9:0]  addr1,
  output [7:0] dout1
);
  // Synthesis black-box: no body.
  // Timing driven by sky130_sram_1rw1r_32x1024_8.lib (read by Genus/Vivado).
endmodule
**/
// ----------------------------------------------------------------------------
// t1_sram_sky130_wrap — clean synchronous interface around the macro
// ----------------------------------------------------------------------------
module t1_sram_sky130_wrap #(
  parameter int NumWords  = 1024,   // fixed for this macro
  parameter int DataWidth = 32      // fixed for this macro
) (
  input  logic clk_i,

  // Write port (maps to Port 0)
  input  logic                        wr_en_i,
  input  logic [3:0]                  wr_be_i,    // byte enables, active high
  input  logic [$clog2(NumWords)-1:0] wr_addr_i,
  input  logic [DataWidth-1:0]        wr_data_i,

  // Read port (maps to Port 1 — registered output, 1-cycle latency)
  input  logic                        rd_en_i,
  input  logic [$clog2(NumWords)-1:0] rd_addr_i,
  output logic [DataWidth-1:0]        rd_data_o
);

  sky130_sram_1rw1r_8x1024_8 u_macro0 (
    // Port 0: write
    .clk0   ( clk_i    ),
    .csb0   ( ~wr_en_i ),   // active low: enabled when writing
    .web0   ( 1'b0     ),   // always write-mode when Port 0 selected
    .wmask0 ( wr_be_i[0]  ),
    .addr0  ( wr_addr_i ),
    .din0   ( wr_data_i[7:0] ),
    .dout0  (           ),  // Port 0 readback unused (use Port 1)

    // Port 1: read
    .clk1   ( clk_i    ),
    .csb1   ( ~rd_en_i ),   // active low: enabled when reading
    .addr1  ( rd_addr_i ),
    .dout1  ( rd_data_o[7:0] )   // 1-cycle registered output
  );

  sky130_sram_1rw1r_8x1024_8 u_macro1 (
    // Port 0: write
    .clk0   ( clk_i    ),
    .csb0   ( ~wr_en_i ),   // active low: enabled when writing
    .web0   ( 1'b0     ),   // always write-mode when Port 0 selected
    .wmask0 ( wr_be_i[1]  ),
    .addr0  ( wr_addr_i ),
    .din0   ( wr_data_i[15:8] ),
    .dout0  (           ),  // Port 0 readback unused (use Port 1)

    // Port 1: read
    .clk1   ( clk_i    ),
    .csb1   ( ~rd_en_i ),   // active low: enabled when reading
    .addr1  ( rd_addr_i ),
    .dout1  ( rd_data_o[15:8] )   // 1-cycle registered output
  );

  sky130_sram_1rw1r_8x1024_8 u_macro2 (
    // Port 0: write
    .clk0   ( clk_i    ),
    .csb0   ( ~wr_en_i ),   // active low: enabled when writing
    .web0   ( 1'b0     ),   // always write-mode when Port 0 selected
    .wmask0 ( wr_be_i[2]  ),
    .addr0  ( wr_addr_i ),
    .din0   ( wr_data_i[23:16] ),
    .dout0  (           ),  // Port 0 readback unused (use Port 1)

    // Port 1: read
    .clk1   ( clk_i    ),
    .csb1   ( ~rd_en_i ),   // active low: enabled when reading
    .addr1  ( rd_addr_i ),
    .dout1  ( rd_data_o[23:16] )   // 1-cycle registered output
  );


  sky130_sram_1rw1r_8x1024_8 u_macro3 (
    // Port 0: write
    .clk0   ( clk_i    ),
    .csb0   ( ~wr_en_i ),   // active low: enabled when writing
    .web0   ( 1'b0     ),   // always write-mode when Port 0 selected
    .wmask0 ( wr_be_i[3]  ),
    .addr0  ( wr_addr_i ),
    .din0   ( wr_data_i[31:24] ),
    .dout0  (           ),  // Port 0 readback unused (use Port 1)

    // Port 1: read
    .clk1   ( clk_i    ),
    .csb1   ( ~rd_en_i ),   // active low: enabled when reading
    .addr1  ( rd_addr_i ),
    .dout1  ( rd_data_o[31:24] )   // 1-cycle registered output
  );

endmodule
