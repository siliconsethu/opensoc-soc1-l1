// ============================================================================
// t1_sram_top_32_asic.sv  —  ASIC synthesis wrapper for t1_sram_top_32
//                             Replaces behavioral mem[] with sky130 SRAM macro
//                             OpenSoC Tier-1 (Level-1, sky130, 4 KB)
//
// DROP-IN REPLACEMENT
//   Module name is t1_sram_top_32 — identical to rtl/memory/t1_sram_top_32.sv.
//   Genus reads THIS file instead of the original so the 1024-word SRAM is
//   mapped to the sky130_sram_1rw1r_32x1024_8 OpenRAM macro rather than being
//   inferred as ~32 K flip-flops.
//
// DIFFERENCES FROM THE BEHAVIORAL VERSION
//   1. No mem[] array — storage is inside the sky130 SRAM macro.
//   2. No simulation-only initial block.
//   3. No rdata_q register — the macro's registered Port-1 output feeds rdata_o.
//   4. Burst reads: each beat requires a RD_WAIT cycle (1 extra cycle/beat vs.
//      the behavioral pre-fetch trick) because the macro has 1-cycle latency.
//   5. TOHOST monitoring via hierarchical mem[] is not possible; testbenches
//      must use AXI reads or a dedicated status register for synthesis verification.
//
// SRAM MACRO PORT MAPPING
//   Port 0 (RW)  →  write path  (csb0=~wr_en, web0=0, wmask0=wstrb)
//   Port 1 (R)   →  read path   (csb1=~rd_en, dout1→rdata_o)
//   Simultaneous reads and writes to DIFFERENT addresses are supported.
//   Read-during-write to the SAME address is undefined; avoid in software.
//
// READ LATENCY
//   Cycle N   : RD_WAIT — rd_en_i=1, rd_addr_i presented to macro at posedge
//   Cycle N+1 : RD_DATA — macro dout1 (registered) is valid; rvalid=1
//   Identical to the behavioral model's RD_WAIT → RD_DATA sequencing.
// ============================================================================

`timescale 1ns/1ps

module t1_sram_top_32 #(
  parameter int unsigned AxiAddrWidth = 32,
  parameter int unsigned AxiDataWidth = 32,
  parameter int unsigned AxiIdWidth   = 4,
  parameter int unsigned AxiUserWidth = 1,
  parameter int unsigned NumWords     = 1024    // L1 = 4 KB  (use 1024 for sky130 macro)
) (
  input  logic clk_i,
  input  logic rst_ni,

  // AXI4 Write address (AW)
  input  logic                        awvalid_i,
  output logic                        awready_o,
  input  logic [AxiIdWidth-1:0]       awid_i,
  input  logic [AxiAddrWidth-1:0]     awaddr_i,
  input  logic [7:0]                  awlen_i,
  input  logic [2:0]                  awsize_i,
  input  logic [1:0]                  awburst_i,

  // AXI4 Write data (W)
  input  logic                        wvalid_i,
  output logic                        wready_o,
  input  logic [AxiDataWidth-1:0]     wdata_i,
  input  logic [(AxiDataWidth/8)-1:0] wstrb_i,
  input  logic                        wlast_i,

  // AXI4 Write response (B)
  output logic                        bvalid_o,
  input  logic                        bready_i,
  output logic [AxiIdWidth-1:0]       bid_o,
  output logic [1:0]                  bresp_o,

  // AXI4 Read address (AR)
  input  logic                    arvalid_i,
  output logic                    arready_o,
  input  logic [AxiIdWidth-1:0]   arid_i,
  input  logic [AxiAddrWidth-1:0] araddr_i,
  input  logic [7:0]              arlen_i,
  input  logic [2:0]              arsize_i,
  input  logic [1:0]              arburst_i,

  // AXI4 Read data (R)
  output logic                    rvalid_o,
  input  logic                    rready_i,
  output logic [AxiIdWidth-1:0]   rid_o,
  output logic [AxiDataWidth-1:0] rdata_o,
  output logic [1:0]              rresp_o,
  output logic                    rlast_o
);

  localparam int unsigned AW = $clog2(NumWords);

  // ==========================================================================
  // Write state machine
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
  // Read state machine
  // ==========================================================================
  //
  // RD_IDLE  — accept AR; capture address → RD_WAIT
  // RD_WAIT  — assert rd_en to SRAM (macro latches addr on posedge) → RD_DATA
  // RD_DATA  — rvalid=1; macro dout1 is the registered read data.
  //            Last beat  → RD_IDLE
  //            Burst beat → increment raddr_q / rbeat_q → RD_WAIT (re-fetch)
  //
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

      // SRAM address is presented this cycle (via rd_en/rd_addr assigns below).
      // Registered output (dout1) is valid at the start of the next cycle.
      RD_WAIT: rd_state_q <= RD_DATA;

      RD_DATA: if (rready_i) begin
        if (rbeat_q == rlen_q) begin
          rd_state_q <= RD_IDLE;
        end else begin
          rbeat_q    <= rbeat_q + 1;
          raddr_q    <= raddr_q + 1;
          rd_state_q <= RD_WAIT;   // re-fetch next beat through SRAM latency
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
  // SRAM macro interface signals
  // ==========================================================================
  logic                 sram_wr_en;
  logic [3:0]           sram_wr_be;
  logic [AW-1:0]        sram_wr_addr;
  logic [AxiDataWidth-1:0] sram_wr_data;
  logic                 sram_rd_en;
  logic [AW-1:0]        sram_rd_addr;
  logic [AxiDataWidth-1:0] sram_rd_data;

  assign sram_wr_en   = (wr_state_q == WR_DATA) && wvalid_i;
  assign sram_wr_be   = wstrb_i;
  assign sram_wr_addr = waddr_q;
  assign sram_wr_data = wdata_i;

  assign sram_rd_en   = (rd_state_q == RD_WAIT);
  assign sram_rd_addr = raddr_q;

  assign rdata_o = sram_rd_data;

  // ==========================================================================
  // SRAM macro instantiation
  // ==========================================================================
  t1_sram_sky130_wrap #(
    .NumWords  (NumWords),
    .DataWidth (AxiDataWidth)
  ) u_sram (
    .clk_i     (clk_i),
    .wr_en_i   (sram_wr_en),
    .wr_be_i   (sram_wr_be),
    .wr_addr_i (sram_wr_addr),
    .wr_data_i (sram_wr_data),
    .rd_en_i   (sram_rd_en),
    .rd_addr_i (sram_rd_addr),
    .rd_data_o (sram_rd_data)
  );

endmodule
