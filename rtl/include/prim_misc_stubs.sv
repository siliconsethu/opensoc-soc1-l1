// OpenSoC Tier-1 — miscellaneous prim_* simulation stubs

// ---------------------------------------------------------------------------
// prim_filter_ctr — digital filter with counter (stub: pass-through)
// ---------------------------------------------------------------------------
module prim_filter_ctr #(
  parameter bit          AsyncOn  = 1'b0,
  parameter int unsigned CntWidth = 2
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic enable_i,
  input  logic filter_i,
  input  logic [CntWidth-1:0] thresh_i,
  output logic filter_o
);
  assign filter_o = filter_i;
endmodule

// ---------------------------------------------------------------------------
// prim_fifo_sync_cnt — FIFO with separate count output (stub)
// ---------------------------------------------------------------------------
module prim_fifo_sync_cnt #(
  parameter int unsigned Depth  = 4,
  parameter bit          Secure = 1'b0,
  // derived
  parameter int unsigned CntW = $clog2(Depth+1)
) (
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            clr_i,
  input  logic            incr_wptr_i,
  input  logic            incr_rptr_i,
  output logic [CntW-1:0] wptr_o,
  output logic [CntW-1:0] rptr_o,
  output logic            full_o,
  output logic            empty_o,
  output logic [CntW-1:0] depth_o,
  output logic            err_o
);
  logic [CntW-1:0] wptr_q, rptr_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || clr_i) begin
      wptr_q <= '0;
      rptr_q <= '0;
    end else begin
      if (incr_wptr_i && !full_o)  wptr_q <= wptr_q + 1'b1;
      if (incr_rptr_i && !empty_o) rptr_q <= rptr_q + 1'b1;
    end
  end
  assign wptr_o  = wptr_q;
  assign rptr_o  = rptr_q;
  assign depth_o = wptr_q - rptr_q;
  assign full_o  = (depth_o == CntW'(Depth));
  assign empty_o = (depth_o == '0);
  assign err_o   = 1'b0;
endmodule

// ---------------------------------------------------------------------------
// prim_arbiter_tree — round-robin tree arbiter (stub: grant first valid)
// ---------------------------------------------------------------------------
module prim_arbiter_tree #(
  parameter int unsigned N         = 2,
  parameter int unsigned DW        = 32,
  parameter bit          EnDataPort = 1'b1,
  parameter bit          ExtPrio    = 1'b0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             req_chk_i,
  input  logic [N-1:0]     req_i,
  input  logic [DW-1:0]   data_i [N],
  output logic [N-1:0]     gnt_o,
  output logic [$clog2(N)-1:0] idx_o,
  output logic             valid_o,
  output logic [DW-1:0]    data_o,
  input  logic             ready_i
);
  logic found;
  always_comb begin
    gnt_o  = '0;
    idx_o  = '0;
    data_o = '0;
    valid_o= 1'b0;
    found  = 1'b0;
    for (int i = 0; i < N; i++) begin
      if (req_i[i] && !found) begin
        gnt_o[i] = ready_i;
        idx_o    = i[$clog2(N)-1:0];
        data_o   = data_i[int'(i)];
        valid_o  = 1'b1;
        found    = 1'b1;
      end
    end
  end
endmodule

// ---------------------------------------------------------------------------
// prim_ram_1p_adv — single-port RAM with advanced features (stub)
// ---------------------------------------------------------------------------
module prim_ram_1p_adv #(
  parameter int unsigned Depth               = 128,
  parameter int unsigned Width               = 32,
  parameter int unsigned DataBitsPerMask     = 1,
  parameter bit          EnableECC           = 1'b0,
  parameter bit          EnableParity        = 1'b0,
  parameter bit          EnableInputPipeline = 1'b0,
  parameter bit          EnableOutputPipeline= 1'b0
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic                          req_i,
  input  logic                          write_i,
  input  logic [$clog2(Depth)-1:0]      addr_i,
  input  logic [Width-1:0]              wdata_i,
  input  logic [Width-1:0]              wmask_i,
  output logic [Width-1:0]              rdata_o,
  output logic                          rvalid_o,
  output logic [1:0]                    rerror_o,
  input  logic                          cfg_i,
  output prim_alert_pkg::alert_tx_t     alert_o
);
  logic [Width-1:0] mem [Depth];
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid_o <= 1'b0;
      rdata_o  <= '0;
    end else begin
      rvalid_o <= req_i & ~write_i;
      if (req_i) begin
        if (write_i) begin
          mem[addr_i] <= (wdata_i & wmask_i) | (mem[addr_i] & ~wmask_i);
        end else begin
          rdata_o <= mem[addr_i];
        end
      end
    end
  end
  assign rerror_o = 2'b00;
  assign alert_o  = prim_alert_pkg::ALERT_TX_DEFAULT;
endmodule

// ---------------------------------------------------------------------------
// prim_packer_fifo — packer FIFO (converts InW to OutW) — stub
// ---------------------------------------------------------------------------
module prim_packer_fifo #(
  parameter int InW  = 8,
  parameter int OutW = 8
) (
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            clr_i,
  input  logic [InW-1:0]  wdata_i,
  input  logic            wvalid_i,
  output logic            wready_o,
  output logic [OutW-1:0] rdata_o,
  output logic            rvalid_o,
  input  logic            rready_i,
  output logic [$clog2(OutW)-1:0] depth_o
);
  // Stub: accept and immediately discard data; outputs always 0/invalid
  assign wready_o = 1'b1;
  assign rdata_o  = '0;
  assign rvalid_o = 1'b0;
  assign depth_o  = '0;
endmodule

// ---------------------------------------------------------------------------
// prim_flop_en — flip-flop with clock enable
// ---------------------------------------------------------------------------
module prim_flop_en #(
  parameter int Width = 1,
  parameter logic [Width-1:0] ResetValue = '0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             en_i,
  input  logic [Width-1:0] d_i,
  output logic [Width-1:0] q_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) q_o <= ResetValue;
    else if (en_i) q_o <= d_i;
  end
endmodule
