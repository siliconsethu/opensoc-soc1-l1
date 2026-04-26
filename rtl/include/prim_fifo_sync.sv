// OpenSoC Tier-1 — prim_fifo_sync stub (functional single-clock FIFO)
module prim_fifo_sync #(
  parameter int unsigned Width      = 16,
  parameter bit          Pass       = 1'b1,
  parameter int unsigned Depth      = 4,
  parameter bit          OutputZeroIfEmpty = 1'b0,
  parameter bit          Secure     = 1'b0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             clr_i,
  input  logic             wvalid_i,
  output logic             wready_o,
  input  logic [Width-1:0] wdata_i,
  output logic             rvalid_o,
  input  logic             rready_i,
  output logic [Width-1:0] rdata_o,
  output logic [$clog2(Depth+1)-1:0] depth_o,
  output logic             full_o,
  output logic             err_o
);
  localparam int unsigned AW = (Depth > 1) ? $clog2(Depth) : 1;
  logic [Width-1:0] mem [0:Depth-1];
  logic [AW-1:0]   wr_ptr_q, rd_ptr_q;
  logic [$clog2(Depth+1)-1:0] count_q;

  assign full_o    = (count_q == Depth[($clog2(Depth+1)-1):0]);
  assign rvalid_o  = (count_q != '0);
  assign wready_o  = !full_o;
  assign depth_o   = count_q;
  assign err_o     = 1'b0;
  assign rdata_o   = (OutputZeroIfEmpty && !rvalid_o) ? '0 : mem[rd_ptr_q];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || clr_i) begin
      wr_ptr_q <= '0; rd_ptr_q <= '0; count_q <= '0;
    end else begin
      if (wvalid_i && wready_o) begin
        mem[wr_ptr_q] <= wdata_i;
        wr_ptr_q <= (wr_ptr_q == AW'(Depth-1)) ? '0 : wr_ptr_q + 1;
        count_q  <= count_q + 1;
      end
      if (rvalid_o && rready_i) begin
        rd_ptr_q <= (rd_ptr_q == AW'(Depth-1)) ? '0 : rd_ptr_q + 1;
        count_q  <= count_q - 1;
      end
      if (wvalid_i && wready_o && rvalid_o && rready_i)
        count_q <= count_q;
    end
  end
endmodule
