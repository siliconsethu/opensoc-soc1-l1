// OpenSoC Tier-1 — prim_flop stub
// Parameterised D flip-flop with synchronous reset
module prim_flop #(
  parameter int unsigned Width      = 1,
  parameter logic [Width-1:0] ResetValue = '0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [Width-1:0] d_i,
  output logic [Width-1:0] q_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) q_o <= ResetValue;
    else         q_o <= d_i;
  end
endmodule
