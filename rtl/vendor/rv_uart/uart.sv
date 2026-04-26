// ============================================================================
// uart.sv — OpenTitan-compatible UART peripheral
// OpenSoC Tier-1 vendor IP (rv_uart)
//
// Implements the OpenTitan UART register interface over TL-UL.
// Used by t1_periph_ss_l1 (L1) and t1_periph_ss_l2 (L2).
//
// Register map (byte offsets from base):
//   0x00  INTR_STATE   R/W1C  [7:tx_done 6:rx_timeout 5:rx_break_err
//                               4:rx_frame_err 3:rx_overflow 2:tx_empty
//                               1:rx_watermark 0:tx_watermark]
//   0x04  INTR_ENABLE  R/W
//   0x08  INTR_TEST    W/O
//   0x10  CTRL         R/W    [15:0]=NCO [16]=TX_EN [17]=RX_EN
//                              [21]=PARITY_EN [22]=PARITY_ODD
//   0x14  STATUS       RO     [5]=rxempty [4]=rxidle [3]=txidle
//                              [2]=txempty [1]=rxfull [0]=txfull
//   0x18  RDATA        RO     [7:0] — next byte from RX FIFO
//   0x1C  WDATA        W/O    [7:0] — push byte into TX FIFO
//   0x20  FIFO_CTRL    R/W    [1]=txrst [0]=rxrst; [9:2]=rxilvl; [14:10]=txilvl
//   0x24  FIFO_STATUS  RO     [9:0]=rxlvl [16:16+5]=txlvl (packed)
//   0x28  OVRD         R/W    [1]=txval [0]=txen_ovrd
//   0x30  TIMEOUT_CTRL R/W    [23:0]=val [31]=en
//
// TX/RX FIFO depth: 8 entries each.
// Baud clock: NCO accumulator — baud_tick every floor(2^16 / NCO) cycles.
// SPDX-License-Identifier: Apache-2.0 (OpenTitan-compatible)
// ============================================================================

`timescale 1ns/1ps

module uart (
  input  logic clk_i,
  input  logic rst_ni,

  // TL-UL register interface
  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o,

  // Alert (not used in simulation — tied off)
  input  prim_alert_pkg::alert_rx_t alert_rx_i,
  output prim_alert_pkg::alert_tx_t alert_tx_o,

  // UART pins
  input  logic cio_rx_i,
  output logic cio_tx_o,
  output logic cio_tx_en_o,

  // Interrupt outputs
  output logic intr_tx_watermark_o,
  output logic intr_rx_watermark_o,
  output logic intr_tx_empty_o,
  output logic intr_rx_overflow_o,
  output logic intr_rx_frame_err_o,
  output logic intr_rx_break_err_o,
  output logic intr_rx_timeout_o,
  output logic intr_tx_done_o
);

  // ==========================================================================
  // TL-UL register bus
  // ==========================================================================
  // Accept one request at a time: a_ready = !rsp_pending.
  // Latch request; drive d_valid one cycle later.
  // --------------------------------------------------------------------------
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
  wire [3:0]  reg_wmask = tl_i.a_mask;

  logic [31:0] reg_rdata;   // combinational read mux

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
  // Registers
  // ==========================================================================
  logic [31:0] intr_state_q;   // 0x00
  logic [31:0] intr_enable_q;  // 0x04
  logic [31:0] ctrl_q;         // 0x10
  logic [31:0] fifo_ctrl_q;    // 0x20
  logic [31:0] ovrd_q;         // 0x28
  logic [31:0] timeout_ctrl_q; // 0x30

  wire tx_en = ctrl_q[16];
  wire rx_en = ctrl_q[17];

  // ==========================================================================
  // TX FIFO (8 entries)
  // ==========================================================================
  logic [7:0] tx_fifo [0:7];
  logic [2:0] tx_wr_ptr_q, tx_rd_ptr_q;
  logic [3:0] tx_cnt_q;

  wire tx_fifo_empty = (tx_cnt_q == 4'd0);
  wire tx_fifo_full  = (tx_cnt_q == 4'd8);
  wire tx_push = tl_we && (reg_addr == 12'h01C) && !tx_fifo_full && tx_en;
  wire tx_pop;  // driven by serialiser below

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || fifo_ctrl_q[1]) begin
      tx_wr_ptr_q <= '0;
      tx_rd_ptr_q <= '0;
      tx_cnt_q    <= '0;
    end else begin
      if (tx_push && !tx_pop) begin
        tx_fifo[tx_wr_ptr_q] <= reg_wdata[7:0];
        tx_wr_ptr_q <= tx_wr_ptr_q + 3'd1;
        tx_cnt_q    <= tx_cnt_q + 4'd1;
      end else if (!tx_push && tx_pop) begin
        tx_rd_ptr_q <= tx_rd_ptr_q + 3'd1;
        tx_cnt_q    <= tx_cnt_q - 4'd1;
      end else if (tx_push && tx_pop) begin
        tx_fifo[tx_wr_ptr_q] <= reg_wdata[7:0];
        tx_wr_ptr_q <= tx_wr_ptr_q + 3'd1;
        // cnt unchanged
      end
    end
  end

  // ==========================================================================
  // TX serialiser (NCO baud clock)
  // ==========================================================================
  logic [9:0]  tx_sr_q;      // {stop, data[7:0], start}
  logic [3:0]  tx_bcnt_q;    // bits left (0 = idle)
  logic [15:0] tx_acc_q;

  wire [15:0] nco        = ctrl_q[15:0];
  wire [16:0] acc_nxt    = {1'b0, tx_acc_q} + {1'b0, nco};
  wire        baud_tick  = acc_nxt[16] && (tx_bcnt_q != 4'd0);
  wire        tx_idle    = (tx_bcnt_q == 4'd0);
  assign      tx_pop     = baud_tick && (tx_bcnt_q == 4'd1) && !tx_fifo_empty;
                           // when last bit finishes and FIFO has data, pop

  // Actually tx_pop should pop BEFORE next frame starts:
  // Pop happens when serialiser finishes the stop bit and wants next byte.
  // Simplification: pop when stop bit is being sent (bcnt==1) and fifo non-empty.

  assign cio_tx_o    = tx_idle ? 1'b1 : tx_sr_q[0];
  assign cio_tx_en_o = tx_en;

  logic tx_done_pulse;
  assign tx_done_pulse = baud_tick && (tx_bcnt_q == 4'd1); // last bit going out

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_sr_q    <= 10'h3FF;
      tx_bcnt_q  <= '0;
      tx_acc_q   <= '0;
    end else begin
      if (!tx_idle) begin
        tx_acc_q <= acc_nxt[15:0];
        if (baud_tick) begin
          tx_sr_q   <= {1'b1, tx_sr_q[9:1]};
          tx_bcnt_q <= tx_bcnt_q - 4'd1;
          // If this was the last bit and FIFO is non-empty, reload immediately
          if (tx_bcnt_q == 4'd1 && !tx_fifo_empty) begin
            tx_sr_q   <= {1'b1, tx_fifo[tx_rd_ptr_q], 1'b0};
            tx_bcnt_q <= 4'd10;
            tx_acc_q  <= '0;
          end
        end
      end else if (!tx_fifo_empty && tx_en) begin
        // Idle → start new frame
        tx_sr_q   <= {1'b1, tx_fifo[tx_rd_ptr_q], 1'b0};
        tx_bcnt_q <= 4'd10;
        tx_acc_q  <= '0;
      end
    end
  end

  // FIFO pop: when serialiser grabs the next byte from FIFO
  // Happens at end of last bit (tx_bcnt_q==1 && baud_tick) OR on IDLE→START
  wire tx_pop_end   = baud_tick && (tx_bcnt_q == 4'd1) && !tx_fifo_empty;
  wire tx_pop_start = tx_idle && !tx_fifo_empty && tx_en;
  assign tx_pop = tx_pop_end || tx_pop_start;

  // ==========================================================================
  // RX FIFO (8 entries)
  // ==========================================================================
  logic [7:0] rx_fifo [0:7];
  logic [2:0] rx_wr_ptr_q, rx_rd_ptr_q;
  logic [3:0] rx_cnt_q;

  wire rx_fifo_empty = (rx_cnt_q == 4'd0);
  wire rx_fifo_full  = (rx_cnt_q == 4'd8);
  wire rx_pop = tl_re && (reg_addr == 12'h018);

  // ==========================================================================
  // RX deserialiser
  // ==========================================================================
  // 3-FF synchroniser
  logic cio_rx_s1_q, cio_rx_s2_q, cio_rx_s3_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cio_rx_s1_q <= 1'b1;
      cio_rx_s2_q <= 1'b1;
      cio_rx_s3_q <= 1'b1;
    end else begin
      cio_rx_s1_q <= cio_rx_i;
      cio_rx_s2_q <= cio_rx_s1_q;
      cio_rx_s3_q <= cio_rx_s2_q;
    end
  end
  wire rx_bit = cio_rx_s3_q;

  typedef enum logic [1:0] { RX_IDLE, RX_START, RX_DATA, RX_STOP } rx_st_e;
  rx_st_e      rx_st_q;
  logic [15:0] rx_acc_q;
  logic [7:0]  rx_sr_q;
  logic [2:0]  rx_bcnt_q;
  logic        rx_push;
  logic [7:0]  rx_push_data;
  logic        rx_frame_err_pulse;
  logic        rx_overflow_pulse;

  wire [16:0] rx_acc_nxt  = {1'b0, rx_acc_q} + {1'b0, nco};
  wire        rx_baud_tick = rx_acc_nxt[16];
  // Half-baud tick for start-bit sampling.
  // half_nco = 2×nco so overflow fires in 65536/(2×nco) = baud_period/2 cycles.
  wire [15:0] half_nco    = {nco[14:0], 1'b0};
  wire [16:0] rx_half_nxt = {1'b0, rx_acc_q} + {1'b0, half_nco};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || fifo_ctrl_q[0]) begin
      rx_wr_ptr_q        <= '0;
      rx_rd_ptr_q        <= '0;
      rx_cnt_q           <= '0;
      rx_st_q            <= RX_IDLE;
      rx_acc_q           <= '0;
      rx_sr_q            <= '0;
      rx_bcnt_q          <= '0;
      rx_push            <= 1'b0;
      rx_push_data       <= '0;
      rx_frame_err_pulse <= 1'b0;
      rx_overflow_pulse  <= 1'b0;
    end else begin
      rx_push            <= 1'b0;
      rx_frame_err_pulse <= 1'b0;
      rx_overflow_pulse  <= 1'b0;

      // RX FIFO pop
      if (rx_pop && !rx_fifo_empty) begin
        rx_rd_ptr_q <= rx_rd_ptr_q + 3'd1;
        rx_cnt_q    <= rx_cnt_q - 4'd1;
      end

      // RX FIFO push
      if (rx_push) begin
        if (!rx_fifo_full) begin
          rx_fifo[rx_wr_ptr_q] <= rx_push_data;
          rx_wr_ptr_q          <= rx_wr_ptr_q + 3'd1;
          rx_cnt_q             <= rx_cnt_q + 4'd1;
        end else begin
          rx_overflow_pulse <= 1'b1;
        end
      end

      // RX state machine
      if (rx_en) unique case (rx_st_q)
        RX_IDLE: begin
          if (!rx_bit) begin  // start bit detected
            rx_st_q  <= RX_START;
            rx_acc_q <= '0;
          end
        end
        RX_START: begin
          rx_acc_q <= rx_half_nxt[15:0];
          if (rx_half_nxt[16]) begin
            // Sample at bit centre
            if (!rx_bit) begin
              rx_st_q   <= RX_DATA;
              rx_bcnt_q <= 3'd0;
              rx_acc_q  <= '0;
            end else begin
              rx_st_q <= RX_IDLE; // false start
            end
          end
        end
        RX_DATA: begin
          rx_acc_q <= rx_acc_nxt[15:0];
          if (rx_baud_tick) begin
            rx_acc_q <= '0;
            rx_sr_q  <= {rx_bit, rx_sr_q[7:1]};
            rx_bcnt_q <= rx_bcnt_q + 3'd1;
            if (rx_bcnt_q == 3'd7) rx_st_q <= RX_STOP;
          end
        end
        RX_STOP: begin
          rx_acc_q <= rx_acc_nxt[15:0];
          if (rx_baud_tick) begin
            rx_acc_q <= '0;
            rx_st_q  <= RX_IDLE;
            if (rx_bit) begin
              rx_push      <= 1'b1;
              rx_push_data <= rx_sr_q;
            end else begin
              rx_frame_err_pulse <= 1'b1;
            end
          end
        end
      endcase
    end
  end

  // ==========================================================================
  // Register read mux
  // ==========================================================================
  logic [31:0] fifo_status;
  assign fifo_status = {6'h0, tx_cnt_q[3:0], 6'h0, rx_cnt_q[3:0]};

  always_comb begin
    reg_rdata = 32'h0;
    unique case (reg_addr)
      12'h000: reg_rdata = intr_state_q;
      12'h004: reg_rdata = intr_enable_q;
      12'h010: reg_rdata = ctrl_q;
      12'h014: reg_rdata = {26'h0,
                            rx_fifo_empty,   // [5] rxempty
                            rx_st_q == RX_IDLE, // [4] rxidle
                            tx_idle,          // [3] txidle
                            tx_fifo_empty,   // [2] txempty
                            rx_fifo_full,    // [1] rxfull
                            tx_fifo_full};   // [0] txfull
      12'h018: reg_rdata = {24'h0, rx_fifo_empty ? 8'h0 : rx_fifo[rx_rd_ptr_q]};
      12'h020: reg_rdata = fifo_ctrl_q;
      12'h024: reg_rdata = fifo_status;
      12'h028: reg_rdata = ovrd_q;
      12'h030: reg_rdata = timeout_ctrl_q;
      default: reg_rdata = 32'h0;
    endcase
  end

  // ==========================================================================
  // Register writes
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      intr_state_q   <= '0;
      intr_enable_q  <= '0;
      ctrl_q         <= '0;
      fifo_ctrl_q    <= '0;
      ovrd_q         <= '0;
      timeout_ctrl_q <= '0;
    end else begin
      // Hardware interrupt state updates
      if (tx_done_pulse)         intr_state_q[7] <= 1'b1;
      if (rx_frame_err_pulse)    intr_state_q[4] <= 1'b1;
      if (rx_overflow_pulse)     intr_state_q[3] <= 1'b1;
      if (tx_fifo_empty)         intr_state_q[2] <= 1'b1;
      if (!tx_fifo_empty && tx_cnt_q <= 4'd4) intr_state_q[0] <= 1'b1; // tx watermark
      if (!rx_fifo_empty && rx_cnt_q >= 4'd4) intr_state_q[1] <= 1'b1; // rx watermark

      // SW register writes
      if (tl_we) unique case (reg_addr)
        12'h000: intr_state_q   <= intr_state_q   & ~reg_wdata;  // W1C
        12'h004: intr_enable_q  <= reg_wdata;
        12'h008: intr_state_q   <= intr_state_q   |  reg_wdata;  // INTR_TEST set
        12'h010: ctrl_q         <= reg_wdata;
        12'h020: fifo_ctrl_q    <= reg_wdata;
        12'h028: ovrd_q         <= reg_wdata;
        12'h030: timeout_ctrl_q <= reg_wdata;
        default: ;
      endcase
    end
  end

  // ==========================================================================
  // Interrupt outputs
  // ==========================================================================
  assign intr_tx_watermark_o = intr_state_q[0] & intr_enable_q[0];
  assign intr_rx_watermark_o = intr_state_q[1] & intr_enable_q[1];
  assign intr_tx_empty_o     = intr_state_q[2] & intr_enable_q[2];
  assign intr_rx_overflow_o  = intr_state_q[3] & intr_enable_q[3];
  assign intr_rx_frame_err_o = intr_state_q[4] & intr_enable_q[4];
  assign intr_rx_break_err_o = intr_state_q[5] & intr_enable_q[5];
  assign intr_rx_timeout_o   = intr_state_q[6] & intr_enable_q[6];
  assign intr_tx_done_o      = intr_state_q[7] & intr_enable_q[7];

endmodule
