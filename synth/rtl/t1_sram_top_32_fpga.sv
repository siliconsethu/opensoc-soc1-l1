// ============================================================================
// t1_sram_top_32_fpga.sv  —  FPGA (Vivado/XPM) version of t1_sram_top_32
//                             Module name matches original for drop-in use.
//                             OpenSoC Tier-1 FPGA synthesis target.
//
// DIFFERENCES FROM rtl/memory/t1_sram_top_32.sv
//   1. mem[] replaced by Xilinx XPM Simple Dual-Port BRAM (xpm_memory_sdpram).
//      Port A = write (from AXI WR_DATA state).
//      Port B = read  (from AXI RD_WAIT state, 1-cycle registered output).
//   2. rdata_q removed — XPM Port B output IS the registered data.
//   3. Burst reads: transitions through RD_WAIT between beats (adds 1 cycle
//      per beat vs. original).  Not observable for L1 (ARLEN always 0).
//   4. synthesis translate_off / initial block removed (not needed for FPGA).
//
// FPGA TARGET
//   Xilinx 7-Series / UltraScale.  xpm_memory_sdpram with MEMORY_PRIMITIVE
//   "block" infers RAMB36E1 / RAMB36E2.
//   For L1 (1024 × 32 = 4 KB) → 1× RAMB36 (36 Kb capacity, 4-bit parity unused).
//   For L2 (32768 × 32 = 128 KB) → 32× RAMB36.
//
// VIVADO COMPILE:
//   Set library xpm in project, or add:
//     set_property -name "xpm_libraries" -value "XPM_MEMORY" ...
// ============================================================================
`timescale 1ns/1ps

module t1_sram_top_32 #(
  parameter int unsigned AxiAddrWidth = 32,
  parameter int unsigned AxiDataWidth = 32,
  parameter int unsigned AxiIdWidth   = 4,
  parameter int unsigned AxiUserWidth = 1,
  parameter int unsigned NumWords     = 32768
) (
  input  logic clk_i,
  input  logic rst_ni,

  // AXI Write Address (AW)
  input  logic                        awvalid_i,
  output logic                        awready_o,
  input  logic [AxiIdWidth-1:0]       awid_i,
  input  logic [AxiAddrWidth-1:0]     awaddr_i,
  input  logic [7:0]                  awlen_i,
  input  logic [2:0]                  awsize_i,
  input  logic [1:0]                  awburst_i,

  // AXI Write Data (W)
  input  logic                        wvalid_i,
  output logic                        wready_o,
  input  logic [AxiDataWidth-1:0]     wdata_i,
  input  logic [(AxiDataWidth/8)-1:0] wstrb_i,
  input  logic                        wlast_i,

  // AXI Write Response (B)
  output logic                        bvalid_o,
  input  logic                        bready_i,
  output logic [AxiIdWidth-1:0]       bid_o,
  output logic [1:0]                  bresp_o,

  // AXI Read Address (AR)
  input  logic                    arvalid_i,
  output logic                    arready_o,
  input  logic [AxiIdWidth-1:0]   arid_i,
  input  logic [AxiAddrWidth-1:0] araddr_i,
  input  logic [7:0]              arlen_i,
  input  logic [2:0]              arsize_i,
  input  logic [1:0]              arburst_i,

  // AXI Read Data (R)
  output logic                    rvalid_o,
  input  logic                    rready_i,
  output logic [AxiIdWidth-1:0]   rid_o,
  output logic [AxiDataWidth-1:0] rdata_o,
  output logic [1:0]              rresp_o,
  output logic                    rlast_o
);

  localparam int unsigned AW = $clog2(NumWords);

  // ==========================================================================
  // Write state machine  (WR_IDLE → WR_DATA → WR_RESP)
  // ==========================================================================
  typedef enum logic [1:0] {WR_IDLE, WR_DATA, WR_RESP} wr_state_e;
  wr_state_e             wr_state_q;
  logic [AxiIdWidth-1:0] wid_q;
  logic [AW-1:0]         waddr_q;
  logic [7:0]            wlen_q;
  logic [7:0]            wbeat_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_state_q <= WR_IDLE;
      wid_q      <= '0;
      waddr_q    <= '0;
      wlen_q     <= '0;
      wbeat_q    <= '0;
    end else case (wr_state_q)
      WR_IDLE: if (awvalid_i) begin
        wr_state_q <= WR_DATA;
        wid_q      <= awid_i;
        waddr_q    <= AW'(awaddr_i[AW+1:2]);
        wlen_q     <= awlen_i;
        wbeat_q    <= '0;
      end
      WR_DATA: if (wvalid_i) begin
        if (wbeat_q == wlen_q) wr_state_q <= WR_RESP;
        else begin wbeat_q <= wbeat_q + 1; waddr_q <= waddr_q + 1; end
      end
      WR_RESP: if (bready_i) wr_state_q <= WR_IDLE;
      default: wr_state_q <= WR_IDLE;
    endcase
  end

  assign awready_o = (wr_state_q == WR_IDLE);
  assign wready_o  = (wr_state_q == WR_DATA);
  assign bvalid_o  = (wr_state_q == WR_RESP);
  assign bid_o     = wid_q;
  assign bresp_o   = 2'b00;

  // ==========================================================================
  // Read state machine  (RD_IDLE → RD_WAIT → RD_DATA)
  // FPGA NOTE: no pre-fetch between burst beats; each beat goes back through
  //            RD_WAIT to absorb the 1-cycle XPM BRAM output latency.
  //            This adds 1 cycle/beat for bursts — not observable in L1.
  // ==========================================================================
  typedef enum logic [1:0] {RD_IDLE, RD_WAIT, RD_DATA} rd_state_e;
  rd_state_e             rd_state_q;
  logic [AxiIdWidth-1:0] rid_q;
  logic [AW-1:0]         raddr_q;
  logic [7:0]            rlen_q;
  logic [7:0]            rbeat_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_state_q <= RD_IDLE;
      rid_q      <= '0;
      raddr_q    <= '0;
      rlen_q     <= '0;
      rbeat_q    <= '0;
    end else case (rd_state_q)
      RD_IDLE: if (arvalid_i) begin
        rd_state_q <= RD_WAIT;
        rid_q      <= arid_i;
        raddr_q    <= AW'(araddr_i[AW+1:2]);
        rlen_q     <= arlen_i;
        rbeat_q    <= '0;
      end
      RD_WAIT: begin
        // Address is held on XPM port B; output is registered and valid next cycle.
        rd_state_q <= RD_DATA;
      end
      RD_DATA: if (rready_i) begin
        if (rbeat_q == rlen_q) begin
          rd_state_q <= RD_IDLE;
        end else begin
          rbeat_q    <= rbeat_q + 1;
          raddr_q    <= raddr_q + 1;
          rd_state_q <= RD_WAIT;   // re-absorb BRAM latency for next beat
        end
      end
      default: rd_state_q <= RD_IDLE;
    endcase
  end

  assign arready_o = (rd_state_q == RD_IDLE);
  assign rvalid_o  = (rd_state_q == RD_DATA);
  assign rid_o     = rid_q;
  assign rresp_o   = 2'b00;
  assign rlast_o   = (rd_state_q == RD_DATA) && (rbeat_q == rlen_q);

  // ==========================================================================
  // XPM Simple Dual-Port Block RAM
  //   Port A = write  (driven from WR_DATA state)
  //   Port B = read   (driven from RD_WAIT state, 1-cycle registered output)
  // ==========================================================================
  logic bram_rd_en;
  assign bram_rd_en = (rd_state_q == RD_WAIT);

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A         ( AW             ),
    .ADDR_WIDTH_B         ( AW             ),
    .BYTE_WRITE_WIDTH_A   ( 8              ),  // byte-granular write enables
    .WRITE_DATA_WIDTH_A   ( AxiDataWidth   ),
    .READ_DATA_WIDTH_B    ( AxiDataWidth   ),
    .MEMORY_SIZE          ( NumWords * AxiDataWidth ),
    .MEMORY_PRIMITIVE     ( "block"        ),  // force BRAM (not LUT RAM)
    .READ_LATENCY_B       ( 1              ),  // 1-cycle output register
    .WRITE_MODE_B         ( "no_change"    ),  // doutb unchanged during write
    .USE_EMBEDDED_CONSTRAINT ( 0           ),
    .MEMORY_INIT_FILE     ( "none"         ),
    .MEMORY_INIT_PARAM    ( "0"            ),
    .ECC_MODE             ( "no_ecc"       ),
    .AUTO_SLEEP_TIME      ( 0              ),
    .MESSAGE_CONTROL      ( 0              )
  ) u_bram (
    // Port A: write
    .clka    ( clk_i                          ),
    .ena     ( (wr_state_q == WR_DATA) && wvalid_i ),
    .wea     ( wstrb_i                        ),   // 4-bit byte enables
    .addra   ( waddr_q                        ),
    .dina    ( wdata_i                        ),

    // Port B: read
    .clkb    ( clk_i                          ),
    .enb     ( bram_rd_en                     ),
    .addrb   ( raddr_q                        ),
    .doutb   ( rdata_o                        ),   // registered, 1-cycle latency
    .rstb    ( ~rst_ni                        ),
    .regceb  ( 1'b1                           ),

    // ECC/error injection: unused
    .injectdbiterra ( 1'b0 ),
    .injectsbiterra ( 1'b0 ),
    .dbiterrb (             ),
    .sbiterrb (             ),
    .sleep    ( 1'b0        )
  );

endmodule
