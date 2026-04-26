// OpenSoC Tier-1 — TLUL simulation stubs
// Provides minimal behavioural models for OpenTitan TLUL infrastructure modules.

// ---------------------------------------------------------------------------
// tlul_cmd_intg_chk — integrity checker (stub: never signals error)
// ---------------------------------------------------------------------------
module tlul_cmd_intg_chk (
  input  tlul_pkg::tl_h2d_t tl_i,
  output logic               err_o
);
  assign err_o = 1'b0;
endmodule

// ---------------------------------------------------------------------------
// tlul_rsp_intg_gen — integrity generator (stub: pass-through)
// ---------------------------------------------------------------------------
module tlul_rsp_intg_gen #(
  parameter int EnableRspIntgGen  = 1,
  parameter int EnableDataIntgGen = 1
) (
  input  tlul_pkg::tl_d2h_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o
);
  assign tl_o = tl_i;
endmodule

// ---------------------------------------------------------------------------
// tlul_adapter_reg — TL-UL to register bus adapter (stub)
// Drives we=0, re=0 so registers keep reset values; rvalid mirrors re.
// ---------------------------------------------------------------------------
module tlul_adapter_reg #(
  parameter int RegAw              = 8,
  parameter int RegDw              = 32,
  parameter int EnableDataIntgGen  = 0,
  parameter int AccessLatency      = 0
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  input  tlul_pkg::tl_h2d_t  tl_i,
  output tlul_pkg::tl_d2h_t  tl_o,

  input  prim_mubi_pkg::mubi4_t en_ifetch_i,
  output logic                  intg_error_o,

  output logic                  we_o,
  output logic                  re_o,
  output logic [RegAw-1:0]      addr_o,
  output logic [RegDw-1:0]      wdata_o,
  output logic [RegDw/8-1:0]    be_o,
  input  logic                  busy_i,
  input  logic [RegDw-1:0]      rdata_i,
  input  logic                  error_i
);
  assign we_o        = 1'b0;
  assign re_o        = 1'b0;
  assign addr_o      = '0;
  assign wdata_o     = '0;
  assign be_o        = '0;
  assign intg_error_o= 1'b0;

  // Return zero data with d_valid whenever a_valid
  always_comb begin
    tl_o           = '0;
    tl_o.d_valid   = tl_i.a_valid;
    tl_o.d_opcode  = tlul_pkg::AccessAckData;
    tl_o.d_source  = tl_i.a_source;
    tl_o.d_data    = rdata_i;
    tl_o.a_ready   = 1'b1;
  end
endmodule

// ---------------------------------------------------------------------------
// tlul_adapter_sram — TL-UL to SRAM adapter (stub: tie off)
// ---------------------------------------------------------------------------
module tlul_adapter_sram #(
  parameter int SramAw              = 12,
  parameter int SramDw              = 32,
  parameter int Outstanding         = 1,
  parameter int ByteAccess          = 1,
  parameter int ErrOnWrite          = 0,
  parameter int ErrOnRead           = 0,
  parameter int CmdIntgCheck        = 0,
  parameter int EnableRspIntgGen    = 0,
  parameter int EnableDataIntgGen   = 0,
  parameter int SecureRsp           = 0,
  parameter int EnableReadback      = 0,
  parameter int EnableReadbackCheck = 0,
  parameter int EnableDataIntgPt    = 0,
  parameter int DataXorAddr         = 0
) (
  input  logic                clk_i,
  input  logic                rst_ni,
  input  tlul_pkg::tl_h2d_t  tl_i,
  output tlul_pkg::tl_d2h_t  tl_o,
  input  prim_mubi_pkg::mubi4_t en_ifetch_i,
  // SRAM interface
  output logic                req_o,
  output logic                req_type_o,
  input  logic                gnt_i,
  output logic                we_o,
  output logic [SramAw-1:0]   addr_o,
  output logic [SramDw-1:0]   wdata_o,
  output logic [SramDw-1:0]   wmask_o,
  output logic                intg_error_o,
  input  logic [SramDw-1:0]   rdata_i,
  input  logic                rvalid_i,
  input  logic [1:0]          rerror_i,
  output logic                compound_txn_in_progress_o,
  input  prim_mubi_pkg::mubi4_t readback_en_i,
  output logic                readback_error_o,
  input  logic                wr_collision_i,
  input  logic                write_pending_i
);
  assign req_o                      = 1'b0;
  assign req_type_o                 = 1'b0;
  assign we_o                       = 1'b0;
  assign addr_o                     = '0;
  assign wdata_o                    = '0;
  assign wmask_o                    = '0;
  assign intg_error_o               = 1'b0;
  assign compound_txn_in_progress_o = 1'b0;
  assign readback_error_o           = 1'b0;
  always_comb begin
    tl_o         = '0;
    tl_o.a_ready = 1'b1;
    tl_o.d_valid = 1'b0;
  end
endmodule

// ---------------------------------------------------------------------------
// tlul_socket_1n — 1-to-N TLUL socket (stub: tie off all slave channels)
// ---------------------------------------------------------------------------
module tlul_socket_1n #(
  parameter int N             = 4,
  parameter int HReqPass      = 1,
  parameter int HRspPass      = 1,
  parameter int DReqPass      = {N{1'b1}},
  parameter int DRspPass      = {N{1'b1}},
  parameter int HReqDepth     = 4,
  parameter int HRspDepth     = 4,
  parameter int DReqDepth     = {N{4'b0100}},
  parameter int DRspDepth     = {N{4'b0100}},
  parameter int ExplicitErrs  = 0
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  tlul_pkg::tl_h2d_t      tl_h_i,
  output tlul_pkg::tl_d2h_t      tl_h_o,
  output tlul_pkg::tl_h2d_t      tl_d_o [N],
  input  tlul_pkg::tl_d2h_t      tl_d_i [N],
  input  logic [top_pkg::TL_AIW-1:0] dev_select_i
);
  always_comb begin
    tl_h_o = '0;
    tl_h_o.a_ready = 1'b1;
    for (int i = 0; i < N; i++) begin
      tl_d_o[i] = '0;
    end
  end
endmodule
