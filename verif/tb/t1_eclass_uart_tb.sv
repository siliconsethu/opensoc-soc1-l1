// ============================================================================
// t1_eclass_uart_tb.sv
// Shakti E-class SoC — CPU-driven UART loopback test  (USE_ISS)
//
// Compiles with:
//   Level-1 (t1_periph_ss_l1, NCO-based baud):
//     vlog -sv +define+USE_ISS ... t1_eclass_uart_tb.sv
//     vsim ... +HEX_FILE=build/sw/uart_test_l1.hex
//
//   Level-2 (t1_periph_ss_32, baud_div-based, Boot ROM, 128 KB SRAM):
//     vlog -sv +define+USE_ISS +define+LEVEL2 +define+TEST_LEVEL2 \
//          ... t1_eclass_uart_tb.sv
//     vsim ... +HEX_FILE=build/sw/uart_test_l2.hex
//
// What this test verifies:
//   1. C test configures UART (baud, enable) and reads CTRL back.
//   2. C test checks initial STATUS (txempty set).
//   3. C test sends four bytes (0x55, 0xAA, 0x00, 0xFF); TB echoes each byte.
//
// BAUD TIMING
//   Level-1: NCO_SIM = 0x2000 (8192) → baud period = 65536/8192 = 8 cycles.
//   Level-2: baud_div = 10             → baud period = 10 cycles.
//   BAUD_CYCLES must match the C test configuration.
//
// TOHOST: 0x8000_0FF0 = SRAM word 1020 (same index for L1 and L2).
// Timeout: TBL_UART_CPU_TIMEOUT cycles.
// ============================================================================

`timescale 1ns/1ps
`include "verif/include/tb_level.svh"

module t1_eclass_uart_tb;

  localparam int CLK_HALF   = 5;
  localparam int MAX_CYCLES = `TBL_UART_CPU_TIMEOUT;
  localparam int TOHOST_IDX = 32'hFF0 / 4;  // word 1020 = 0x8000_0FF0

  // Baud period in clock cycles — must match C test configuration:
  //   Level-1: NCO_SIM = 0x2000 (8192) → baud_period = 65536/8192 = 8 cycles
  //   Level-2: baud_div = 10           → baud_period = 10 cycles
`ifdef LEVEL2
  localparam int BAUD_CYCLES = 10;
`else
  localparam int BAUD_CYCLES = 8;
`endif

  logic clk, rst_n;
  initial clk = 0;
  always #CLK_HALF clk = ~clk;

  logic        uart_tx, uart_rx;
  logic [31:0] gpio_in, gpio_out, gpio_oe;
  logic        cpu_halt;

  initial begin uart_rx = 1'b1; gpio_in = 32'h0; end

  t1_soc_top_eclass u_soc (
    .clk_i         ( clk        ),
    .rst_ni        ( rst_n      ),
    .jtag_tck_i    ( 1'b0       ),
    .jtag_tms_i    ( 1'b0       ),
    .jtag_trst_ni  ( 1'b1       ),
    .jtag_tdi_i    ( 1'b0       ),
    .jtag_tdo_o    (            ),
    .jtag_tdo_oe_o (            ),
    .uart_rx_i     ( uart_rx    ),
    .uart_tx_o     ( uart_tx    ),
    .gpio_in_i     ( gpio_in    ),
    .gpio_out_o    ( gpio_out   ),
    .gpio_oe_o     ( gpio_oe    ),
`ifdef LEVEL2
    .spi_sck_o     (            ),
    .spi_csb_o     (            ),
    .spi_sd_i      ( 1'b0       ),
    .spi_sd_o      (            ),
    .i2c_scl_o     (            ),
    .i2c_scl_i     ( 1'b1       ),
    .i2c_sda_o     (            ),
    .i2c_sda_i     ( 1'b1       ),
`endif
    .halt_o        ( cpu_halt   )
  );

  // ── Load compiled test binary into SRAM ────────────────────────────────────
  string hex_file;
  initial begin
    if (!$value$plusargs("HEX_FILE=%s", hex_file))
`ifdef LEVEL2
      hex_file = "build/sw/uart_test_l2.hex";
`else
      hex_file = "build/sw/uart_test_l1.hex";
`endif
    @(posedge clk);  // wait past time-0 so SRAM zero-init completes first
    $readmemh(hex_file, u_soc.u_sram.mem);
    $display("[TB] Loaded: %s", hex_file);
  end

  // ── UART echo task ─────────────────────────────────────────────────────────
  // Decodes one 8N1 frame from uart_tx and re-drives the same byte on uart_rx.
  //
  // Timing (BAUD_CYCLES = 8, 3-FF RX synchroniser included in analysis):
  //   Detect negedge uart_tx (TX start bit falling edge).
  //   Wait BAUD_CYCLES/2 posedges → centre of start bit.
  //   Sample each data bit after BAUD_CYCLES posedges (LSB first).
  //   Drive echo after stop bit + 2-baud gap on uart_rx (on negedge for setup).
  //
  // BAUD_CYCLES must equal 65536/NCO_SIM from uart_test.c.
  task automatic uart_echo_one;
    logic [7:0] rx_byte;

    // Wait for falling edge of start bit on TX
    @(negedge uart_tx);

    // Position at centre of start bit (no sample needed)
    repeat(BAUD_CYCLES / 2) @(posedge clk);

    // Sample 8 data bits, one per baud period, LSB first
    for (int b = 0; b < 8; b++) begin
      repeat(BAUD_CYCLES) @(posedge clk);
      rx_byte[b] = uart_tx;
    end

    // Consume stop bit
    repeat(BAUD_CYCLES) @(posedge clk);

    // Inter-frame gap: 2 baud periods before driving echo
    repeat(2 * BAUD_CYCLES) @(posedge clk);

    // Drive echo frame on uart_rx.
    // Bits driven on negedge so the signal is stable before the next posedge
    // that the DUT's 3-FF RX synchroniser will sample.

    // Start bit (0)
    @(negedge clk);
    uart_rx = 1'b0;

    // 8 data bits LSB first
    for (int b = 0; b < 8; b++) begin
      repeat(BAUD_CYCLES) @(negedge clk);
      uart_rx = rx_byte[b];
    end

    // Stop bit (1)
    repeat(BAUD_CYCLES) @(negedge clk);
    uart_rx = 1'b1;

    // Hold stop bit for one baud period to keep uart_rx stable
    repeat(BAUD_CYCLES) @(posedge clk);
  endtask

  // ── Echo service thread ────────────────────────────────────────────────────
  // Continuous echo loop — started after reset release, terminated by $finish.
  initial begin
    uart_rx = 1'b1;
    @(posedge rst_n);
    @(posedge clk);
    forever begin
      uart_echo_one;
    end
  end

  // ── Main test flow — poll TOHOST ──────────────────────────────────────────
  int          cycle_cnt, fail_cnt;
  logic [31:0] tohost_val;

  initial begin
    fail_cnt  = 0;
    cycle_cnt = 0;
    rst_n     = 1'b0;

    $display("[TB] ===== E-class UART Test [%s] =====", `TBL_LABEL);
    $display("[TB] Timeout: %0d cycles, BAUD_CYCLES: %0d", MAX_CYCLES, BAUD_CYCLES);

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    $display("[TB] Reset released — ISS booting from 0x80000000");

    forever begin
      @(posedge clk);
      cycle_cnt++;
      tohost_val = u_soc.u_sram.mem[TOHOST_IDX];
      if (tohost_val !== 32'h0) break;
      if (cycle_cnt >= MAX_CYCLES) begin
        $display("[FAIL] TIMEOUT after %0d cycles — TOHOST never written", MAX_CYCLES);
        $display("[INFO] halt_o=%b  uart_tx=%b  uart_rx=%b", cpu_halt, uart_tx, uart_rx);
        $finish;
      end
    end

    $display("[TB] TOHOST written after %0d cycles: 0x%08h", cycle_cnt, tohost_val);

    // ── C-test result ────────────────────────────────────────────────────────
    if (tohost_val !== 32'd1) begin
      $display("[FAIL] UART test error 0x%08h", tohost_val);
      // Error code table (uart_test.c):
      //   0x1001  CTRL readback mismatch
      //   0x1002  STATUS initial state wrong
      //   0x20NN  TX timeout for byte NN (01=0x55 02=0xAA 03=0x00 04=0xFF)
      //   0x30NN  RX timeout for byte NN
      //   0x40NN  Received byte != sent byte for byte NN
      fail_cnt++;
    end

    $display("[TB] ==========================================");
    if (fail_cnt == 0)
      $display("[TB] PASS -- all checks passed [%s]", `TBL_LABEL);
    else
      $display("[TB] FAIL -- %0d failure(s) [%s]", fail_cnt, `TBL_LABEL);
    $display("[TB] ==========================================");
    $finish;
  end

endmodule
