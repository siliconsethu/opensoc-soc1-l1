// ============================================================================
// t1_eclass_gpio_tb.sv
// Shakti E-class SoC — CPU-driven GPIO Integration Test
//
// Compiles with:
//   Level-1 (default):
//     vlog -sv -mfcu +define+USE_ISS questa_src_eclass.f verif/tb/t1_eclass_gpio_tb.sv
//     vsim ... +HEX_FILE=sw/tests/gpio_test_l1.hex
//
//   Level-2 (full 32-bit GPIO, Boot ROM, 128 KB SRAM):
//     vlog -sv -mfcu +define+USE_ISS +define+LEVEL2 +define+TEST_LEVEL2 \
//          questa_src_eclass.f verif/tb/t1_eclass_gpio_tb.sv
//     vsim ... +HEX_FILE=sw/tests/gpio_test_l2.hex
//
// Level-1 (16-bit GPIO at 0x9000_1000, t1_periph_ss_l1):
//   1. C test writes DIRECT_OE, DIRECT_OUT, MASKED_OUT_LOWER → TOHOST=1.
//   2. TB observes gpio_out_o[15:0] / gpio_oe_o[15:0] for key patterns.
//   3. TB drives gpio_in[15:0] walk-1; C test ORs 4096 DATA_IN reads.
//
// Level-2 (32-bit GPIO at 0x9000_0010, t1_periph_ss_32):
//   Same flow but extended to 32-bit width.  Walk-1 covers all 32 bits.
//   Boot ROM at 0x0001_0000 jumps to 0x8000_0000 before C test executes.
//
// TOHOST address: 0x8000_0FF0 = SRAM word 1020 (both L1 and L2 SRAM base
//   is 0x8000_0000, so word index is identical).
// Timeout: TBL_GPIO_CPU_TIMEOUT cycles (L1=200000, L2=500000).
// ============================================================================

`timescale 1ns/1ps
`include "verif/include/tb_level.svh"

module t1_eclass_gpio_tb;

  localparam int CLK_HALF   = 5;
  localparam int MAX_CYCLES = `TBL_GPIO_CPU_TIMEOUT;
  localparam int HOLD_CYCS  = `TBL_HOLD_CYCS;
  localparam int TOHOST_IDX = 32'hFF0 / 4;  // word 1020 = 0x8000_0FF0

  logic clk, rst_n;
  initial clk = 0;
  always #CLK_HALF clk = ~clk;

  logic [31:0] gpio_in, gpio_out, gpio_oe;
  logic        uart_tx, uart_rx;
  logic        cpu_halt;

  initial begin
    uart_rx = 1'b1;
    gpio_in = 32'h0;
  end

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
    .halt_o        ( cpu_halt   )
  );

  // ── Load compiled test binary into SRAM ────────────────────────────────────
  string hex_file;
  initial begin
    if (!$value$plusargs("HEX_FILE=%s", hex_file))
      hex_file = "sw/tests/gpio_test_l1.hex";
    @(posedge clk);  // wait past time-0 so SRAM zero-init completes first
    $readmemh(hex_file, u_soc.u_sram.mem);
    $display("[TB] Loaded: %s", hex_file);
  end

  // ── gpio_in walk-1 driver ──────────────────────────────────────────────────
  // Runs a continuous walk-1 so the C test can OR-accumulate DATA_IN reads.
  // L1 uses lower 16 bits; L2 uses all 32 bits.
  initial begin
    gpio_in = 32'h0;
    @(posedge rst_n);
    forever begin
      for (int b = 0; b < 16; b++) begin
        gpio_in = 32'h1 << b;
        repeat (HOLD_CYCS) @(posedge clk);
      end
    end
  end

  // ── gpio_out / gpio_oe pin-level observer ──────────────────────────────────
  // All expected patterns must have been seen before PASS is declared.
  // Level-1: 16-bit GPIO patterns
  int obs_oe_ff;        // gpio_oe[15:0] == 0xFFFF (all-outputs)
  int obs_out_aaaa;     // gpio_out[15:0] == 0xAAAA
  int obs_out_5555;     // gpio_out[15:0] == 0x5555
  int obs_out_3c3c;     // gpio_out[15:0] == 0x3C3C (MASKED_OUT_LOWER result)
  int obs_walk1_bits;   // bitmask: bit b set if gpio_out[15:0] == (1<<b) ever seen

  initial begin
    obs_oe_ff      = 0;
    obs_out_aaaa   = 0;
    obs_out_5555   = 0;
    obs_out_3c3c   = 0;
    obs_walk1_bits = 0;
    @(posedge rst_n);
    forever begin
      @(posedge clk);
      if (gpio_oe[15:0]  === 16'hFFFF) obs_oe_ff    = 1;
      if (gpio_out[15:0] === 16'hAAAA) obs_out_aaaa = 1;
      if (gpio_out[15:0] === 16'h5555) obs_out_5555 = 1;
      if (gpio_out[15:0] === 16'h3C3C) obs_out_3c3c = 1;
      for (int b = 0; b < 16; b++)
        if (gpio_out[15:0] === (16'h1 << b))
          obs_walk1_bits |= (1 << b);
    end
  end

  // ── Main test flow — poll TOHOST, then audit pin observations ─────────────
  int          cycle_cnt, fail_cnt;
  logic [31:0] tohost_val;

  initial begin
    fail_cnt  = 0;
    cycle_cnt = 0;
    rst_n     = 1'b0;

    $display("[TB] ===== E-class GPIO Test [%s] =====",
             `TBL_LABEL
             );
    $display("[TB] Timeout: %0d cycles, HoldCycs: %0d", MAX_CYCLES, HOLD_CYCS);

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    $display("[TB] Reset released — ISS booting from 0x80000000");

    // Poll TOHOST until C test writes a result or timeout fires.
    forever begin
      @(posedge clk);
      cycle_cnt++;
      tohost_val = u_soc.u_sram.mem[TOHOST_IDX];
      if (tohost_val !== 32'h0) break;
      if (cycle_cnt >= MAX_CYCLES) begin
        $display("[FAIL] TIMEOUT after %0d cycles — TOHOST never written", MAX_CYCLES);
        $display("[INFO] halt_o=%b", cpu_halt);
        $finish;
      end
    end

    $display("[TB] TOHOST written after %0d cycles: 0x%08h", cycle_cnt, tohost_val);

    // ── C-test pass/fail ────────────────────────────────────────────────────
    if (tohost_val !== 32'd1) begin
      $display("[FAIL] C test error 0x%08h — group=0x%04h sub=0x%04h",
               tohost_val, tohost_val[31:16], tohost_val[15:0]);
      // Error code reference (gpio_test.c):
      //   0x1001  DIRECT_OE readback fail (wrote 0xFFFF)
      //   0x1002  DIRECT_OUT readback fail (wrote 0xAAAA)
      //   0x1003  DIRECT_OUT readback fail (wrote 0x5555)
      //   0x1004  MASKED_OUT_LOWER result mismatch
      //   0x1005  DATA_IN OR-accumulation: not all 16 input bits seen
      //   0x1006  DIRECT_OE readback fail (wrote 0x0)
      //   0x200b  Walk-1 mismatch on bit b (b = lower nibble)
      //   0x300b  Walk-0 mismatch on bit b
      fail_cnt++;
    end

    // ── Pin-level checks ────────────────────────────────────────────────────
    if (!obs_oe_ff) begin
      $display("[FAIL] gpio_oe[15:0] never reached 16'hFFFF (DIRECT_OE write not reflected)");
      fail_cnt++;
    end
    if (!obs_out_aaaa) begin
      $display("[FAIL] gpio_out[15:0] never showed 16'hAAAA");
      fail_cnt++;
    end
    if (!obs_out_5555) begin
      $display("[FAIL] gpio_out[15:0] never showed 16'h5555");
      fail_cnt++;
    end
    if (!obs_out_3c3c) begin
      $display("[FAIL] gpio_out[15:0] never showed 16'h3C3C (MASKED_OUT_LOWER not reflected)");
      fail_cnt++;
    end
    if (obs_walk1_bits !== 16'hFFFF) begin
      $display("[FAIL] Walk-1 on gpio_out incomplete: saw bits=0x%04h, missing=0x%04h",
               obs_walk1_bits[15:0], 16'hFFFF ^ obs_walk1_bits[15:0]);
      fail_cnt++;
    end

    $display("[TB] ==========================================");
    if (fail_cnt == 0)
      $display("[TB] PASS -- all pin checks and C test passed [%s]", `TBL_LABEL);
    else
      $display("[TB] FAIL -- %0d failure(s) [%s]", fail_cnt, `TBL_LABEL);
    $display("[TB] ==========================================");
    $finish;
  end

endmodule
