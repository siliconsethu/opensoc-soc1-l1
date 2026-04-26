// ============================================================================
// t1_periph_ss_l1.sv
// Level-1 Peripheral Subsystem
// AXI4-32 slave → TLUL bridge → OpenTitan UART + GPIO (16-bit)
//
// Address map (base 0x9000_0000):
//   UART  0x9000_0000 – 0x9000_0FFF   (bit[12]=0)
//   GPIO  0x9000_1000 – 0x9000_1FFF   (bit[12]=1)
//
// Differences vs Level-2 (t1_periph_ss.sv):
//   - 32-bit AXI4 (flat ports, not struct types)
//   - No AXI data downsize — AXI and TLUL are both 32-bit
//   - 2 devices only: UART + GPIO (no SPI, I2C, timers, PLIC)
//   - GPIO is 16-bit (upper 16 bits of OpenTitan 32-bit GPIO IP are tied)
// ============================================================================

`timescale 1ns/1ps

module t1_periph_ss_l1 #(
  parameter int unsigned AxiAddrWidth = 32,
  parameter int unsigned AxiDataWidth = 32,
  parameter int unsigned AxiIdWidth   = 4
) (
  input  logic clk_i,
  input  logic rst_ni,

  // ── AXI4 slave (flat 32-bit ports) ───────────────────────────────────────
  input  logic                        awvalid_i,
  output logic                        awready_o,
  input  logic [AxiIdWidth-1:0]       awid_i,
  input  logic [AxiAddrWidth-1:0]     awaddr_i,
  input  logic [7:0]                  awlen_i,
  input  logic [2:0]                  awsize_i,
  input  logic [1:0]                  awburst_i,

  input  logic                        wvalid_i,
  output logic                        wready_o,
  input  logic [AxiDataWidth-1:0]     wdata_i,
  input  logic [(AxiDataWidth/8)-1:0] wstrb_i,
  input  logic                        wlast_i,

  output logic                        bvalid_o,
  input  logic                        bready_i,
  output logic [AxiIdWidth-1:0]       bid_o,
  output logic [1:0]                  bresp_o,

  input  logic                        arvalid_i,
  output logic                        arready_o,
  input  logic [AxiIdWidth-1:0]       arid_i,
  input  logic [AxiAddrWidth-1:0]     araddr_i,
  input  logic [7:0]                  arlen_i,
  input  logic [2:0]                  arsize_i,
  input  logic [1:0]                  arburst_i,

  output logic                        rvalid_o,
  input  logic                        rready_i,
  output logic [AxiIdWidth-1:0]       rid_o,
  output logic [AxiDataWidth-1:0]     rdata_o,
  output logic [1:0]                  rresp_o,
  output logic                        rlast_o,

  // ── UART I/O ──────────────────────────────────────────────────────────────
  input  logic        uart_rx_i,
  output logic        uart_tx_o,

  // ── GPIO I/O (16-bit) ─────────────────────────────────────────────────────
  input  logic [15:0] gpio_in_i,
  output logic [15:0] gpio_out_o,
  output logic [15:0] gpio_oe_o,

  // ── Interrupt to CPU ──────────────────────────────────────────────────────
  output logic        uart_irq_o
);

  // ==========================================================================
  // AXI → TLUL bridge (32-bit data, single outstanding transaction)
  // No downsize needed: AXI data width == TLUL data width (both 32-bit)
  // ==========================================================================
  // ST_AW_WAIT_W: AW accepted but W not yet seen (ISS sends AW and W in
  // separate clock cycles — awvalid in S_ST_AW, wvalid in S_ST_W).
  typedef enum logic [2:0] {
    ST_IDLE, ST_AW_WAIT_W, ST_TLUL_RD, ST_TLUL_WR, ST_AXI_R, ST_AXI_B
  } axi_st_e;

  axi_st_e             st_q;
  logic [AxiIdWidth-1:0] txn_id_q;
  logic [31:0]           txn_addr_q;
  logic [31:0]           txn_wdata_q;
  logic [3:0]            txn_wmask_q;
  logic                  txn_wr_q;
  logic [31:0]           rdata_q;
  logic                  rerr_q;

  // TLUL bus to/from device mux
  tlul_pkg::tl_h2d_t tl_out;
  tlul_pkg::tl_d2h_t tl_in;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q        <= ST_IDLE;
      txn_id_q    <= '0;
      txn_addr_q  <= '0;
      txn_wdata_q <= '0;
      txn_wmask_q <= '0;
      txn_wr_q    <= 1'b0;
      rdata_q     <= '0;
      rerr_q      <= 1'b0;
    end else unique case (st_q)
      ST_IDLE: begin
        if (arvalid_i) begin
          txn_id_q   <= arid_i;
          txn_addr_q <= araddr_i;
          txn_wr_q   <= 1'b0;
          st_q       <= ST_TLUL_RD;
        end else if (awvalid_i && !arvalid_i) begin
          // Accept AW immediately; W may or may not be simultaneously valid.
          txn_id_q   <= awid_i;
          txn_addr_q <= awaddr_i;
          txn_wr_q   <= 1'b1;
          if (wvalid_i) begin
            txn_wdata_q <= wdata_i;
            txn_wmask_q <= wstrb_i;
            st_q        <= ST_TLUL_WR;
          end else begin
            st_q <= ST_AW_WAIT_W;  // W arrives in a later cycle
          end
        end
      end
      // Wait for the W beat after AW was already accepted.
      ST_AW_WAIT_W: begin
        if (wvalid_i) begin
          txn_wdata_q <= wdata_i;
          txn_wmask_q <= wstrb_i;
          st_q        <= ST_TLUL_WR;
        end
      end
      ST_TLUL_RD: if (tl_in.d_valid) begin
        rdata_q <= tl_in.d_data;
        rerr_q  <= tl_in.d_error;
        st_q    <= ST_AXI_R;
      end
      ST_TLUL_WR: if (tl_in.d_valid) begin
        rerr_q  <= tl_in.d_error;
        st_q    <= ST_AXI_B;
      end
      ST_AXI_R: if (rready_i)  st_q <= ST_IDLE;
      ST_AXI_B: if (bready_i)  st_q <= ST_IDLE;
    endcase
  end

  // TLUL request output
  assign tl_out.a_valid   = (st_q == ST_TLUL_RD || st_q == ST_TLUL_WR) && !tl_in.d_valid;
  assign tl_out.a_opcode  = txn_wr_q ? tlul_pkg::PutFullData : tlul_pkg::Get;
  assign tl_out.a_param   = 3'h0;
  assign tl_out.a_size    = 2;        // 4 bytes
  assign tl_out.a_source  = 8'h0;
  assign tl_out.a_address = txn_addr_q;
  assign tl_out.a_mask    = txn_wmask_q;
  assign tl_out.a_data    = txn_wdata_q;
  assign tl_out.a_user    = '0;
  assign tl_out.d_ready   = 1'b1;

  // AXI slave responses
  // awready: accept AW whenever idle and no read pending (W handled separately)
  // wready:  accept W simultaneously with AW (in IDLE) or after AW (in ST_AW_WAIT_W)
  assign arready_o = (st_q == ST_IDLE) && !awvalid_i;
  assign awready_o = (st_q == ST_IDLE) && !arvalid_i;
  assign wready_o  = (st_q == ST_IDLE && awvalid_i && !arvalid_i) ||
                     (st_q == ST_AW_WAIT_W);
  assign rvalid_o  = (st_q == ST_AXI_R);
  assign rid_o     = txn_id_q;
  assign rdata_o   = rdata_q;
  assign rresp_o   = rerr_q ? 2'b10 : 2'b00;
  assign rlast_o   = 1'b1;
  assign bvalid_o  = (st_q == ST_AXI_B);
  assign bid_o     = txn_id_q;
  assign bresp_o   = rerr_q ? 2'b10 : 2'b00;

  // ==========================================================================
  // Address decode → 2 TLUL devices
  //   dev 0: UART  (txn_addr_q[12] == 0)
  //   dev 1: GPIO  (txn_addr_q[12] == 1)
  // ==========================================================================
  localparam int unsigned N_DEV = 2;
  tlul_pkg::tl_h2d_t dev_tl_h2d [N_DEV];
  tlul_pkg::tl_d2h_t dev_tl_d2h [N_DEV];

  logic dev_sel;
  assign dev_sel = txn_addr_q[12];   // 0 = UART, 1 = GPIO

  for (genvar i = 0; i < N_DEV; i++) begin : g_dev_mux
    always_comb begin
      dev_tl_h2d[i]         = tl_out;
      dev_tl_h2d[i].a_valid = tl_out.a_valid && (dev_sel == logic'(i));
    end
  end
  assign tl_in = dev_tl_d2h[dev_sel];

  // ==========================================================================
  // Device 0: UART (OpenTitan)
  // ==========================================================================
  logic uart_intr_tx_watermark, uart_intr_rx_watermark;
  logic uart_intr_tx_empty,     uart_intr_rx_overflow;
  logic uart_intr_rx_frame_err, uart_intr_rx_break_err;
  logic uart_intr_rx_timeout,   uart_intr_tx_done;

  uart u_uart (
    .clk_i,
    .rst_ni,
    .tl_i                ( dev_tl_h2d[0]            ),
    .tl_o                ( dev_tl_d2h[0]            ),
    .alert_rx_i          ( '{default: prim_alert_pkg::ALERT_RX_DEFAULT} ),
    .alert_tx_o          (                            ),
    .cio_rx_i            ( uart_rx_i                 ),
    .cio_tx_o            ( uart_tx_o                 ),
    .cio_tx_en_o         (                            ),
    .intr_tx_watermark_o ( uart_intr_tx_watermark    ),
    .intr_rx_watermark_o ( uart_intr_rx_watermark    ),
    .intr_tx_empty_o     ( uart_intr_tx_empty        ),
    .intr_rx_overflow_o  ( uart_intr_rx_overflow     ),
    .intr_rx_frame_err_o ( uart_intr_rx_frame_err    ),
    .intr_rx_break_err_o ( uart_intr_rx_break_err    ),
    .intr_rx_timeout_o   ( uart_intr_rx_timeout      ),
    .intr_tx_done_o      ( uart_intr_tx_done         )
  );

  // OR-reduce UART interrupts into a single line to the CPU
  assign uart_irq_o = uart_intr_tx_watermark | uart_intr_rx_watermark |
                      uart_intr_tx_empty     | uart_intr_rx_overflow;

  // ==========================================================================
  // Device 1: GPIO (OpenTitan, 32-bit IP — only lower 16 wired externally)
  // ==========================================================================
  logic [31:0] gpio_out_32;
  logic [31:0] gpio_oe_32;

  gpio u_gpio (
    .clk_i,
    .rst_ni,
    .tl_i          ( dev_tl_h2d[1]           ),
    .tl_o          ( dev_tl_d2h[1]           ),
    .alert_rx_i    ( '{default: prim_alert_pkg::ALERT_RX_DEFAULT} ),
    .alert_tx_o    (                           ),
    .cio_gpio_i    ( {16'h0, gpio_in_i}       ),
    .cio_gpio_o    ( gpio_out_32              ),
    .cio_gpio_en_o ( gpio_oe_32              ),
    .intr_gpio_o   (                          )
  );

  assign gpio_out_o = gpio_out_32[15:0];
  assign gpio_oe_o  = gpio_oe_32[15:0];

endmodule
