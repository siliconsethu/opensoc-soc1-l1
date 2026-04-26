// ============================================================================
// t1_bus_l1.sv
// Level-1 SoC simple bus: 2 masters (IMEM, DMEM) × 2 slaves (SRAM, Periph)
//
// Masters (slave ports of the bus):
//   IMEM — Shakti E-class instruction fetch (read-only)
//   DMEM — Shakti E-class data access (read/write)
//
// Slaves (master ports of the bus):
//   0 – SRAM        0x8000_0000 – 0x8000_0FFF  (4 KB)
//   1 – Peripheral  0x9000_0000 – 0x9000_1FFF  (UART + GPIO)
//
// No Boot ROM: Level-1 boots directly from SRAM (BootAddr = 0x8000_0000).
// Arbitration: DMEM has priority over IMEM when both target the same slave.
//
// Used via `ifdef LEVEL2 macro: compiled in both modes, instantiated only
// when LEVEL2 is NOT defined.
// ============================================================================

`timescale 1ns/1ps

module t1_bus_l1 #(
  parameter int unsigned AxiAddrWidth = 32,
  parameter int unsigned AxiDataWidth = 32,
  parameter int unsigned AxiIdWidth   = 4
) (
  input  logic clk_i,
  input  logic rst_ni,

  // ── IMEM master (read-only) ──────────────────────────────────────────────
  input  logic                    imem_arvalid_i,
  output logic                    imem_arready_o,
  input  logic [AxiIdWidth-1:0]   imem_arid_i,
  input  logic [AxiAddrWidth-1:0] imem_araddr_i,
  input  logic [7:0]              imem_arlen_i,
  input  logic [2:0]              imem_arsize_i,
  input  logic [1:0]              imem_arburst_i,
  output logic                    imem_rvalid_o,
  input  logic                    imem_rready_i,
  output logic [AxiIdWidth-1:0]   imem_rid_o,
  output logic [AxiDataWidth-1:0] imem_rdata_o,
  output logic [1:0]              imem_rresp_o,
  output logic                    imem_rlast_o,

  // ── DMEM master (read/write) ─────────────────────────────────────────────
  input  logic                        dmem_awvalid_i,
  output logic                        dmem_awready_o,
  input  logic [AxiIdWidth-1:0]       dmem_awid_i,
  input  logic [AxiAddrWidth-1:0]     dmem_awaddr_i,
  input  logic [7:0]                  dmem_awlen_i,
  input  logic [2:0]                  dmem_awsize_i,
  input  logic [1:0]                  dmem_awburst_i,
  input  logic                        dmem_wvalid_i,
  output logic                        dmem_wready_o,
  input  logic [AxiDataWidth-1:0]     dmem_wdata_i,
  input  logic [(AxiDataWidth/8)-1:0] dmem_wstrb_i,
  input  logic                        dmem_wlast_i,
  output logic                        dmem_bvalid_o,
  input  logic                        dmem_bready_i,
  output logic [AxiIdWidth-1:0]       dmem_bid_o,
  output logic [1:0]                  dmem_bresp_o,
  input  logic                        dmem_arvalid_i,
  output logic                        dmem_arready_o,
  input  logic [AxiIdWidth-1:0]       dmem_arid_i,
  input  logic [AxiAddrWidth-1:0]     dmem_araddr_i,
  input  logic [7:0]                  dmem_arlen_i,
  input  logic [2:0]                  dmem_arsize_i,
  input  logic [1:0]                  dmem_arburst_i,
  output logic                        dmem_rvalid_o,
  input  logic                        dmem_rready_i,
  output logic [AxiIdWidth-1:0]       dmem_rid_o,
  output logic [AxiDataWidth-1:0]     dmem_rdata_o,
  output logic [1:0]                  dmem_rresp_o,
  output logic                        dmem_rlast_o,

  // ── SRAM slave (0x8000_0000 – 0x8000_0FFF, 4 KB) ────────────────────────
  output logic                        sram_awvalid_o,
  input  logic                        sram_awready_i,
  output logic [AxiIdWidth-1:0]       sram_awid_o,
  output logic [AxiAddrWidth-1:0]     sram_awaddr_o,
  output logic [7:0]                  sram_awlen_o,
  output logic [2:0]                  sram_awsize_o,
  output logic [1:0]                  sram_awburst_o,
  output logic                        sram_wvalid_o,
  input  logic                        sram_wready_i,
  output logic [AxiDataWidth-1:0]     sram_wdata_o,
  output logic [(AxiDataWidth/8)-1:0] sram_wstrb_o,
  output logic                        sram_wlast_o,
  input  logic                        sram_bvalid_i,
  output logic                        sram_bready_o,
  input  logic [AxiIdWidth-1:0]       sram_bid_i,
  input  logic [1:0]                  sram_bresp_i,
  output logic                        sram_arvalid_o,
  input  logic                        sram_arready_i,
  output logic [AxiIdWidth-1:0]       sram_arid_o,
  output logic [AxiAddrWidth-1:0]     sram_araddr_o,
  output logic [7:0]                  sram_arlen_o,
  output logic [2:0]                  sram_arsize_o,
  output logic [1:0]                  sram_arburst_o,
  input  logic                        sram_rvalid_i,
  output logic                        sram_rready_o,
  input  logic [AxiIdWidth-1:0]       sram_rid_i,
  input  logic [AxiDataWidth-1:0]     sram_rdata_i,
  input  logic [1:0]                  sram_rresp_i,
  input  logic                        sram_rlast_i,

  // ── Peripheral slave (0x9000_0000 – 0x9000_1FFF) ────────────────────────
  output logic                        periph_awvalid_o,
  input  logic                        periph_awready_i,
  output logic [AxiIdWidth-1:0]       periph_awid_o,
  output logic [AxiAddrWidth-1:0]     periph_awaddr_o,
  output logic [7:0]                  periph_awlen_o,
  output logic [2:0]                  periph_awsize_o,
  output logic [1:0]                  periph_awburst_o,
  output logic                        periph_wvalid_o,
  input  logic                        periph_wready_i,
  output logic [AxiDataWidth-1:0]     periph_wdata_o,
  output logic [(AxiDataWidth/8)-1:0] periph_wstrb_o,
  output logic                        periph_wlast_o,
  input  logic                        periph_bvalid_i,
  output logic                        periph_bready_o,
  input  logic [AxiIdWidth-1:0]       periph_bid_i,
  input  logic [1:0]                  periph_bresp_i,
  output logic                        periph_arvalid_o,
  input  logic                        periph_arready_i,
  output logic [AxiIdWidth-1:0]       periph_arid_o,
  output logic [AxiAddrWidth-1:0]     periph_araddr_o,
  output logic [7:0]                  periph_arlen_o,
  output logic [2:0]                  periph_arsize_o,
  output logic [1:0]                  periph_arburst_o,
  input  logic                        periph_rvalid_i,
  output logic                        periph_rready_o,
  input  logic [AxiIdWidth-1:0]       periph_rid_i,
  input  logic [AxiDataWidth-1:0]     periph_rdata_i,
  input  logic [1:0]                  periph_rresp_i,
  input  logic                        periph_rlast_i
);

  // ==========================================================================
  // Address decode — 1'b0 = SRAM, 1'b1 = Peripheral
  // ==========================================================================
  function automatic logic decode_slave(input logic [AxiAddrWidth-1:0] addr);
    if (addr >= 32'h8000_0000 && addr <= 32'h8000_0FFF)
      decode_slave = 1'b0;   // SRAM (4 KB window)
    else
      decode_slave = 1'b1;   // Peripheral (default)
  endfunction

  // ==========================================================================
  // Read arbitration — DMEM priority per slave
  // ==========================================================================

  // ── SRAM read owner ───────────────────────────────────────────────────────
  typedef enum logic [1:0] {SRAM_R_IDLE, SRAM_R_IMEM, SRAM_R_DMEM} sram_rowner_e;
  sram_rowner_e sram_rowner_q;

  wire imem_to_sram   = imem_arvalid_i && !decode_slave(imem_araddr_i);
  wire dmem_to_sram   = dmem_arvalid_i && !decode_slave(dmem_araddr_i);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) sram_rowner_q <= SRAM_R_IDLE;
    else case (sram_rowner_q)
      SRAM_R_IDLE: begin
        if      (dmem_to_sram && sram_arready_i) sram_rowner_q <= SRAM_R_DMEM;
        else if (imem_to_sram && sram_arready_i) sram_rowner_q <= SRAM_R_IMEM;
      end
      SRAM_R_IMEM: if (sram_rvalid_i && imem_rready_i && sram_rlast_i) sram_rowner_q <= SRAM_R_IDLE;
      SRAM_R_DMEM: if (sram_rvalid_i && dmem_rready_i && sram_rlast_i) sram_rowner_q <= SRAM_R_IDLE;
      default:     sram_rowner_q <= SRAM_R_IDLE;
    endcase
  end

  // ── Peripheral read owner ─────────────────────────────────────────────────
  typedef enum logic [1:0] {PER_R_IDLE, PER_R_IMEM, PER_R_DMEM} per_rowner_e;
  per_rowner_e per_rowner_q;

  wire imem_to_periph = imem_arvalid_i && decode_slave(imem_araddr_i);
  wire dmem_to_periph = dmem_arvalid_i && decode_slave(dmem_araddr_i);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) per_rowner_q <= PER_R_IDLE;
    else case (per_rowner_q)
      PER_R_IDLE: begin
        if      (dmem_to_periph && periph_arready_i) per_rowner_q <= PER_R_DMEM;
        else if (imem_to_periph && periph_arready_i) per_rowner_q <= PER_R_IMEM;
      end
      PER_R_IMEM: if (periph_rvalid_i && imem_rready_i && periph_rlast_i) per_rowner_q <= PER_R_IDLE;
      PER_R_DMEM: if (periph_rvalid_i && dmem_rready_i && periph_rlast_i) per_rowner_q <= PER_R_IDLE;
      default:    per_rowner_q <= PER_R_IDLE;
    endcase
  end

  // ==========================================================================
  // SRAM AR channel (DMEM priority)
  // ==========================================================================
  assign sram_arvalid_o = (sram_rowner_q == SRAM_R_IDLE) ?
                          (dmem_to_sram ? 1'b1 : imem_to_sram) : 1'b0;
  assign sram_arid_o    = (sram_rowner_q == SRAM_R_IDLE && dmem_to_sram) ? dmem_arid_i   : imem_arid_i;
  assign sram_araddr_o  = (sram_rowner_q == SRAM_R_IDLE && dmem_to_sram) ? dmem_araddr_i : imem_araddr_i;
  assign sram_arlen_o   = (sram_rowner_q == SRAM_R_IDLE && dmem_to_sram) ? dmem_arlen_i  : imem_arlen_i;
  assign sram_arsize_o  = (sram_rowner_q == SRAM_R_IDLE && dmem_to_sram) ? dmem_arsize_i : imem_arsize_i;
  assign sram_arburst_o = (sram_rowner_q == SRAM_R_IDLE && dmem_to_sram) ? dmem_arburst_i: imem_arburst_i;
  assign sram_rready_o  = (sram_rowner_q == SRAM_R_IMEM) ? imem_rready_i :
                          (sram_rowner_q == SRAM_R_DMEM) ? dmem_rready_i : 1'b0;

  // Master AR ready signals
  assign imem_arready_o = imem_to_sram   ? (sram_rowner_q == SRAM_R_IDLE && !dmem_to_sram   && sram_arready_i)   :
                          imem_to_periph ? (per_rowner_q  == PER_R_IDLE  && !dmem_to_periph && periph_arready_i) :
                          1'b0;
  assign dmem_arready_o = dmem_to_sram   ? (sram_rowner_q == SRAM_R_IDLE && sram_arready_i)   :
                          dmem_to_periph ? (per_rowner_q  == PER_R_IDLE  && periph_arready_i) :
                          1'b0;

  // ==========================================================================
  // Peripheral AR channel (DMEM priority)
  // ==========================================================================
  assign periph_arvalid_o = (per_rowner_q == PER_R_IDLE) ?
                            (dmem_to_periph ? 1'b1 : imem_to_periph) : 1'b0;
  assign periph_arid_o    = (per_rowner_q == PER_R_IDLE && dmem_to_periph) ? dmem_arid_i   : imem_arid_i;
  assign periph_araddr_o  = (per_rowner_q == PER_R_IDLE && dmem_to_periph) ? dmem_araddr_i : imem_araddr_i;
  assign periph_arlen_o   = (per_rowner_q == PER_R_IDLE && dmem_to_periph) ? dmem_arlen_i  : imem_arlen_i;
  assign periph_arsize_o  = (per_rowner_q == PER_R_IDLE && dmem_to_periph) ? dmem_arsize_i : imem_arsize_i;
  assign periph_arburst_o = (per_rowner_q == PER_R_IDLE && dmem_to_periph) ? dmem_arburst_i: imem_arburst_i;
  assign periph_rready_o  = (per_rowner_q == PER_R_IMEM) ? imem_rready_i :
                            (per_rowner_q == PER_R_DMEM) ? dmem_rready_i : 1'b0;

  // ==========================================================================
  // R demux → back to correct master
  // ==========================================================================
  assign imem_rvalid_o = (sram_rowner_q == SRAM_R_IMEM && sram_rvalid_i)    ? 1'b1 :
                         (per_rowner_q  == PER_R_IMEM  && periph_rvalid_i)  ? 1'b1 : 1'b0;
  assign imem_rid_o    = (sram_rowner_q == SRAM_R_IMEM) ? sram_rid_i   : periph_rid_i;
  assign imem_rdata_o  = (sram_rowner_q == SRAM_R_IMEM) ? sram_rdata_i : periph_rdata_i;
  assign imem_rresp_o  = (sram_rowner_q == SRAM_R_IMEM) ? sram_rresp_i : periph_rresp_i;
  assign imem_rlast_o  = (sram_rowner_q == SRAM_R_IMEM) ? sram_rlast_i : periph_rlast_i;

  assign dmem_rvalid_o = (sram_rowner_q == SRAM_R_DMEM && sram_rvalid_i)    ? 1'b1 :
                         (per_rowner_q  == PER_R_DMEM  && periph_rvalid_i)  ? 1'b1 : 1'b0;
  assign dmem_rid_o    = (sram_rowner_q == SRAM_R_DMEM) ? sram_rid_i   : periph_rid_i;
  assign dmem_rdata_o  = (sram_rowner_q == SRAM_R_DMEM) ? sram_rdata_i : periph_rdata_i;
  assign dmem_rresp_o  = (sram_rowner_q == SRAM_R_DMEM) ? sram_rresp_i : periph_rresp_i;
  assign dmem_rlast_o  = (sram_rowner_q == SRAM_R_DMEM) ? sram_rlast_i : periph_rlast_i;

  // ==========================================================================
  // Write channels — DMEM only (IMEM never writes)
  // ==========================================================================
  wire dmem_aw_to_sram   = dmem_awvalid_i && !decode_slave(dmem_awaddr_i);
  wire dmem_aw_to_periph = dmem_awvalid_i &&  decode_slave(dmem_awaddr_i);

  typedef enum logic [1:0] {WR_IDLE, WR_SRAM, WR_PERIPH} wr_state_e;
  wr_state_e wr_state_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) wr_state_q <= WR_IDLE;
    else case (wr_state_q)
      WR_IDLE: begin
        if      (dmem_aw_to_sram   && sram_awready_i)   wr_state_q <= WR_SRAM;
        else if (dmem_aw_to_periph && periph_awready_i) wr_state_q <= WR_PERIPH;
      end
      WR_SRAM:   if (sram_bvalid_i   && dmem_bready_i) wr_state_q <= WR_IDLE;
      WR_PERIPH: if (periph_bvalid_i && dmem_bready_i) wr_state_q <= WR_IDLE;
      default:   wr_state_q <= WR_IDLE;
    endcase
  end

  // AW channels
  assign sram_awvalid_o   = (wr_state_q == WR_IDLE) && dmem_aw_to_sram;
  assign sram_awid_o      = dmem_awid_i;
  assign sram_awaddr_o    = dmem_awaddr_i;
  assign sram_awlen_o     = dmem_awlen_i;
  assign sram_awsize_o    = dmem_awsize_i;
  assign sram_awburst_o   = dmem_awburst_i;

  assign periph_awvalid_o = (wr_state_q == WR_IDLE) && dmem_aw_to_periph;
  assign periph_awid_o    = dmem_awid_i;
  assign periph_awaddr_o  = dmem_awaddr_i;
  assign periph_awlen_o   = dmem_awlen_i;
  assign periph_awsize_o  = dmem_awsize_i;
  assign periph_awburst_o = dmem_awburst_i;

  assign dmem_awready_o   = (wr_state_q == WR_IDLE) ?
                            (dmem_aw_to_sram ? sram_awready_i : periph_awready_i) : 1'b0;

  // W channels
  assign sram_wvalid_o   = (wr_state_q == WR_SRAM)   ? dmem_wvalid_i : 1'b0;
  assign sram_wdata_o    = dmem_wdata_i;
  assign sram_wstrb_o    = dmem_wstrb_i;
  assign sram_wlast_o    = dmem_wlast_i;
  assign periph_wvalid_o = (wr_state_q == WR_PERIPH) ? dmem_wvalid_i : 1'b0;
  assign periph_wdata_o  = dmem_wdata_i;
  assign periph_wstrb_o  = dmem_wstrb_i;
  assign periph_wlast_o  = dmem_wlast_i;
  assign dmem_wready_o   = (wr_state_q == WR_SRAM)   ? sram_wready_i   :
                           (wr_state_q == WR_PERIPH)  ? periph_wready_i : 1'b0;

  // B channels
  assign dmem_bvalid_o   = (wr_state_q == WR_SRAM)   ? sram_bvalid_i   :
                           (wr_state_q == WR_PERIPH)  ? periph_bvalid_i : 1'b0;
  assign dmem_bid_o      = (wr_state_q == WR_SRAM)   ? sram_bid_i   : periph_bid_i;
  assign dmem_bresp_o    = (wr_state_q == WR_SRAM)   ? sram_bresp_i : periph_bresp_i;
  assign sram_bready_o   = (wr_state_q == WR_SRAM)   ? dmem_bready_i : 1'b0;
  assign periph_bready_o = (wr_state_q == WR_PERIPH) ? dmem_bready_i : 1'b0;

endmodule
