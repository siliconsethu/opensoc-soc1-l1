// ============================================================================
// gpio.sv — OpenTitan-compatible GPIO peripheral
// OpenSoC Tier-1 vendor IP (gpio)
//
// Implements the OpenTitan GPIO register interface over TL-UL.
// Used by t1_periph_ss_l1 (L1, 32-bit with upper 16 tied externally)
// and t1_periph_ss_l2 (L2, full 32-bit).
//
// Register map (byte offsets from base):
//   0x00  INTR_STATE         R/W1C  [31:0] per-pin interrupt state
//   0x04  INTR_ENABLE        R/W    [31:0] per-pin interrupt enable
//   0x08  INTR_TEST          W/O    [31:0] SW interrupt test
//   0x10  DATA_IN            RO     [31:0] cio_gpio_i sampled value
//   0x14  DIRECT_OUT         R/W    [31:0] direct output data
//   0x18  MASKED_OUT_LOWER   W/O    [31:16]=mask [15:0]=data (lower 16 pins)
//   0x1C  MASKED_OUT_UPPER   W/O    [31:16]=mask [15:0]=data (upper 16 pins)
//   0x20  DIRECT_OE          R/W    [31:0] direct output enable
//   0x24  MASKED_OE_LOWER    W/O    [31:16]=mask [15:0]=oe  (lower 16 pins)
//   0x28  MASKED_OE_UPPER    W/O    [31:16]=mask [15:0]=oe  (upper 16 pins)
//   0x2C  INTR_CTRL_EN_RISING  R/W
//   0x30  INTR_CTRL_EN_FALLING R/W
//   0x34  INTR_CTRL_EN_LVLHIGH R/W
//   0x38  INTR_CTRL_EN_LVLLOW  R/W
//   0x3C  CTRL_EN_INPUT_FILTER R/W
//
// SPDX-License-Identifier: Apache-2.0 (OpenTitan-compatible)
// ============================================================================

`timescale 1ns/1ps

module gpio (
  input  logic clk_i,
  input  logic rst_ni,

  // TL-UL register interface
  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o,

  // Alert (tied off in simulation)
  input  prim_alert_pkg::alert_rx_t alert_rx_i,
  output prim_alert_pkg::alert_tx_t alert_tx_o,

  // GPIO pins
  input  logic [31:0] cio_gpio_i,
  output logic [31:0] cio_gpio_o,
  output logic [31:0] cio_gpio_en_o,

  // Interrupt output (32 lines, one per pin)
  output logic [31:0] intr_gpio_o
);

  // ==========================================================================
  // TL-UL register bus (single-outstanding, 1-cycle accept + 1-cycle response)
  // ==========================================================================
  logic        rsp_pend_q;
  logic [7:0]  rsp_src_q;
  logic [2:0]  rsp_sz_q;
  logic        rsp_we_q;
  logic [31:0] rsp_rdata_q;

  wire tl_req = tl_i.a_valid && !rsp_pend_q;
  wire tl_we  = tl_req && (tl_i.a_opcode != tlul_pkg::Get);
  wire tl_re  = tl_req && (tl_i.a_opcode == tlul_pkg::Get);
  wire [11:0] reg_addr  = tl_i.a_address[11:0];
  wire [31:0] reg_wdata = tl_i.a_data;

  logic [31:0] reg_rdata;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_pend_q  <= 1'b0;
      rsp_src_q   <= '0;
      rsp_sz_q    <= '0;
      rsp_we_q    <= 1'b0;
      rsp_rdata_q <= '0;
    end else begin
      if (rsp_pend_q && tl_i.d_ready) rsp_pend_q <= 1'b0;
      if (tl_req) begin
        rsp_pend_q  <= 1'b1;
        rsp_src_q   <= tl_i.a_source;
        rsp_sz_q    <= tl_i.a_size;
        rsp_we_q    <= tl_we;
        rsp_rdata_q <= reg_rdata;
      end
    end
  end

  always_comb begin
    tl_o          = '0;
    tl_o.a_ready  = ~rsp_pend_q;
    tl_o.d_valid  = rsp_pend_q;
    tl_o.d_opcode = rsp_we_q ? tlul_pkg::AccessAck : tlul_pkg::AccessAckData;
    tl_o.d_size   = rsp_sz_q;
    tl_o.d_source = rsp_src_q;
    tl_o.d_data   = rsp_rdata_q;
    tl_o.d_error  = 1'b0;
  end

  assign alert_tx_o = prim_alert_pkg::ALERT_TX_DEFAULT;

  // ==========================================================================
  // GPIO registers
  // ==========================================================================
  logic [31:0] intr_state_q;          // 0x00
  logic [31:0] intr_enable_q;         // 0x04
  logic [31:0] data_out_q;            // 0x14 / MASKED writes
  logic [31:0] data_oe_q;             // 0x20 / MASKED writes
  logic [31:0] intr_ctrl_en_rising_q; // 0x2C
  logic [31:0] intr_ctrl_en_falling_q;// 0x30
  logic [31:0] intr_ctrl_en_lvlhi_q;  // 0x34
  logic [31:0] intr_ctrl_en_lvllo_q;  // 0x38
  logic [31:0] ctrl_en_filt_q;        // 0x3C

  // Sampled GPIO input (one register stage)
  logic [31:0] data_in_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) data_in_q <= '0;
    else         data_in_q <= cio_gpio_i;
  end

  // ==========================================================================
  // Interrupt detection
  // ==========================================================================
  logic [31:0] data_in_prev_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) data_in_prev_q <= '0;
    else         data_in_prev_q <= data_in_q;
  end

  wire [31:0] rising_edge  = data_in_q & ~data_in_prev_q;
  wire [31:0] falling_edge = ~data_in_q & data_in_prev_q;
  wire [31:0] intr_event   = (rising_edge  & intr_ctrl_en_rising_q)  |
                              (falling_edge & intr_ctrl_en_falling_q) |
                              (data_in_q    & intr_ctrl_en_lvlhi_q)   |
                              (~data_in_q   & intr_ctrl_en_lvllo_q);

  // ==========================================================================
  // Register writes
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      intr_state_q           <= '0;
      intr_enable_q          <= '0;
      data_out_q             <= '0;
      data_oe_q              <= '0;
      intr_ctrl_en_rising_q  <= '0;
      intr_ctrl_en_falling_q <= '0;
      intr_ctrl_en_lvlhi_q   <= '0;
      intr_ctrl_en_lvllo_q   <= '0;
      ctrl_en_filt_q         <= '0;
    end else begin
      // Hardware: set interrupt state bits from events
      intr_state_q <= intr_state_q | intr_event;

      if (tl_we) unique case (reg_addr)
        12'h000: intr_state_q           <= intr_state_q & ~reg_wdata; // W1C
        12'h004: intr_enable_q          <= reg_wdata;
        12'h008: intr_state_q           <= intr_state_q |  reg_wdata; // INTR_TEST
        12'h014: data_out_q             <= reg_wdata;
        12'h018: begin  // MASKED_OUT_LOWER: mask in [31:16], data in [15:0]
          data_out_q[15:0] <= (data_out_q[15:0] & ~reg_wdata[31:16]) |
                              (reg_wdata[15:0]   &  reg_wdata[31:16]);
        end
        12'h01C: begin  // MASKED_OUT_UPPER
          data_out_q[31:16] <= (data_out_q[31:16] & ~reg_wdata[31:16]) |
                               (reg_wdata[15:0]    &  reg_wdata[31:16]);
        end
        12'h020: data_oe_q             <= reg_wdata;
        12'h024: begin  // MASKED_OE_LOWER
          data_oe_q[15:0] <= (data_oe_q[15:0] & ~reg_wdata[31:16]) |
                             (reg_wdata[15:0]   &  reg_wdata[31:16]);
        end
        12'h028: begin  // MASKED_OE_UPPER
          data_oe_q[31:16] <= (data_oe_q[31:16] & ~reg_wdata[31:16]) |
                              (reg_wdata[15:0]    &  reg_wdata[31:16]);
        end
        12'h02C: intr_ctrl_en_rising_q  <= reg_wdata;
        12'h030: intr_ctrl_en_falling_q <= reg_wdata;
        12'h034: intr_ctrl_en_lvlhi_q   <= reg_wdata;
        12'h038: intr_ctrl_en_lvllo_q   <= reg_wdata;
        12'h03C: ctrl_en_filt_q         <= reg_wdata;
        default: ;
      endcase
    end
  end

  // ==========================================================================
  // Register read mux
  // ==========================================================================
  always_comb begin
    reg_rdata = 32'h0;
    unique case (reg_addr)
      12'h000: reg_rdata = intr_state_q;
      12'h004: reg_rdata = intr_enable_q;
      12'h010: reg_rdata = data_in_q;
      12'h014: reg_rdata = data_out_q;
      12'h020: reg_rdata = data_oe_q;
      12'h02C: reg_rdata = intr_ctrl_en_rising_q;
      12'h030: reg_rdata = intr_ctrl_en_falling_q;
      12'h034: reg_rdata = intr_ctrl_en_lvlhi_q;
      12'h038: reg_rdata = intr_ctrl_en_lvllo_q;
      12'h03C: reg_rdata = ctrl_en_filt_q;
      default: reg_rdata = 32'h0;
    endcase
  end

  // ==========================================================================
  // Outputs
  // ==========================================================================
  assign cio_gpio_o    = data_out_q;
  assign cio_gpio_en_o = data_oe_q;
  assign intr_gpio_o   = intr_state_q & intr_enable_q;

endmodule
