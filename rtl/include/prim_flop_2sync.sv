// OpenSoC Tier-1 — prim_flop_2sync stub (2-stage synchronizer)
module prim_flop_2sync #(
  parameter int unsigned Width      = 16,
  parameter logic [Width-1:0] ResetValue = '0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [Width-1:0] d_i,
  output logic [Width-1:0] q_o
);
  logic [Width-1:0] sync1_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin sync1_q <= ResetValue; q_o <= ResetValue; end
    else         begin sync1_q <= d_i;        q_o <= sync1_q;   end
  end
endmodule
