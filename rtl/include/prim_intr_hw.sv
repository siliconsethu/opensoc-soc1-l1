// OpenSoC Tier-1 — prim_intr_hw stub
module prim_intr_hw #(
  parameter int unsigned Width    = 1,
  parameter string       IntrT    = "Event",
  parameter bit          FlopEn   = 0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             event_intr_i,
  input  logic [Width-1:0] reg2hw_intr_enable_q_i,
  input  logic [Width-1:0] reg2hw_intr_test_q_i,
  input  logic             reg2hw_intr_test_qe_i,
  input  logic [Width-1:0] reg2hw_intr_state_q_i,
  input  logic             reg2hw_intr_state_de_i,
  output logic [Width-1:0] hw2reg_intr_state_de_o,
  output logic [Width-1:0] hw2reg_intr_state_d_o,
  output logic             intr_o
);
  logic [Width-1:0] state_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= '0;
    else if (reg2hw_intr_test_qe_i) state_q <= state_q | reg2hw_intr_test_q_i;
    else if (reg2hw_intr_state_de_i) state_q <= reg2hw_intr_state_q_i & ~reg2hw_intr_state_q_i;
    else if (event_intr_i) state_q <= state_q | Width'(1'b1);
  end
  assign hw2reg_intr_state_de_o = state_q;
  assign hw2reg_intr_state_d_o  = state_q;
  assign intr_o                 = |(state_q & reg2hw_intr_enable_q_i);
endmodule
