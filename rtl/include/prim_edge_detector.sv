// OpenSoC Tier-1 — prim_edge_detector stub
// Detects rising/falling edges of a multi-bit signal
module prim_edge_detector #(
  parameter int unsigned Width      = 1,
  parameter logic [Width-1:0] ResetValue = '0,
  parameter logic             EnSync = 1'b0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [Width-1:0] d_i,
  output logic [Width-1:0] q_sync_o,
  output logic [Width-1:0] q_posedge_pulse_o,
  output logic [Width-1:0] q_negedge_pulse_o
);
  logic [Width-1:0] q_prev;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) q_prev <= ResetValue;
    else         q_prev <= d_i;
  end
  assign q_sync_o          = d_i;
  assign q_posedge_pulse_o = d_i & ~q_prev;
  assign q_negedge_pulse_o = ~d_i & q_prev;
endmodule
