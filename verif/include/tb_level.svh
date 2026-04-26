// =============================================================================
// tb_level.svh
// Shared macro header — controls Level-1 (quick) vs Level-2 (full) test depth.
//
// Usage:
//   Level 1 (default):  vlog ... verif/tb/<tb>.sv
//   Level 2 (full):     vlog ... +define+TEST_LEVEL2 verif/tb/<tb>.sv
//
// Makefile shorthand:
//   make eclass_regression           → Level 1
//   make eclass_regression LEVEL=2   → Level 2
//
// All macros use the prefix TBL_ (TestBench Level) to avoid namespace
// collisions with DUT parameters.
// =============================================================================

`ifndef TB_LEVEL_SVH
`define TB_LEVEL_SVH

`ifdef TEST_LEVEL2

  // ── Level 2 — Full verification (stress / nightly) ────────────────────────
  `define TBL_LABEL         "LEVEL-2 (Full)"

  // Smoke test
  `define TBL_RUN_CYCLES    10000   // 10 000-cycle X-free run

  // Reset test
  `define TBL_N_RESETS      10      // 10 reset sequences
  `define TBL_SETTLE_CYCLES 10      // settle after reset release (short: eclass_wrapper
                                    // completes 16 fetches in ~45 cycles; a long settle
                                    // causes all fetches to finish before OBSERVE starts)
  `define TBL_OBSERVE_CYCS  200     // window to observe IMEM fetch

  // GPIO test
  `define TBL_HOLD_CYCS     30      // hold cycles per pattern
  `define TBL_GPIO_EXTRA    1       // enable extra patterns (random, byte-stride)
  `define TBL_GPIO_REPS     3       // repeat walk-1/walk-0 groups N times

  // UART idle test
  `define TBL_IDLE_CYCLES   5000    // TX idle check cycles
  `define TBL_N_FRAMES      20      // RX frames to inject
  `define TBL_POST_RX_CYCS  3000    // post-RX idle check cycles

  // SPI idle test
  `define TBL_SPI_P1_CYCS   1000   // phase 1 (MISO=0) cycles
  `define TBL_SPI_P2_CYCS   1000   // phase 2 (MISO=1) cycles
  `define TBL_SPI_P3_CYCS   3000   // phase 3 (MISO toggle) cycles

  // UART TX/RX test
  `define TBL_TX_IDLE_CYCS  1000   // initial TX idle check
  `define TBL_BURST_N       64     // burst frames (scenario 3)
  `define TBL_OFLOW_N       150    // overflow stress frames (scenario 4)
  `define TBL_BKBK_N        40     // back-to-back frames (scenario 6)

  // Combined top-level test
  `define TBL_TOP_RST_N     5      // number of resets in t1_eclass_tb_top
  `define TBL_TOP_UART_IDLE 2000   // uart_tx idle cycles
  `define TBL_TOP_SPI_IDLE  1000   // spi_csb idle cycles

  // CPU boot test (t1_eclass_cpu_tb)
  `define TBL_CPU_TIMEOUT   500000  // max cycles before TIMEOUT

  // GPIO CPU test (t1_gpio_cpu_tb)
  // GPIO accesses are fast (no serialisation); 500000 cycles is very generous.
  `define TBL_GPIO_CPU_TIMEOUT  500000

  // UART CPU test (t1_uart_cpu_tb)
  // At baud_div=10: ~200 cycles/byte.  L2 sends ~20 bytes → ~4000 active cycles.
  // 2000000 gives ample headroom for L2 baud-change and parity tests.
  `define TBL_UART_CPU_TIMEOUT  2000000

  // SPI CPU test (t1_spi_cpu_tb)
  // At clk_div=4: 8 cycles/bit × 8 bits × 2 phases = 128 cycles/byte.
  // L2 sends 8 bytes → ~1024 active SPI cycles + overhead.
  // 200000 gives wide margin.
  `define TBL_SPI_CPU_TIMEOUT   200000

  // I2C CPU test (t1_i2c_cpu_tb)
  // At clk_div=4: each I2C frame ≈ START(4) + 9bits×8 + ACK + 9bits×8 + ACK + STOP(8)
  // ≈ 200 active cycles. L2: 4 writes + 2 reads = 6 frames × ~200 + CPU overhead.
  // 500000 gives ample margin.
  `define TBL_I2C_CPU_TIMEOUT   500000

`else

  // ── Level 1 — Quick smoke (default / CI gate) ─────────────────────────────
  `define TBL_LABEL         "LEVEL-1 (Quick)"

  // Smoke test
  `define TBL_RUN_CYCLES    3000

  // Reset test
  `define TBL_N_RESETS      5
  `define TBL_SETTLE_CYCLES 30
  `define TBL_OBSERVE_CYCS  100

  // GPIO test
  `define TBL_HOLD_CYCS     20
  // TBL_GPIO_EXTRA intentionally left undefined → `ifdef skips extra patterns
  `define TBL_GPIO_REPS     1

  // UART idle test
  `define TBL_IDLE_CYCLES   2000
  `define TBL_N_FRAMES      8
  `define TBL_POST_RX_CYCS  1000

  // SPI idle test
  `define TBL_SPI_P1_CYCS   500
  `define TBL_SPI_P2_CYCS   500
  `define TBL_SPI_P3_CYCS   1000

  // UART TX/RX test
  `define TBL_TX_IDLE_CYCS  500
  `define TBL_BURST_N       32
  `define TBL_OFLOW_N       80
  `define TBL_BKBK_N        20

  // Combined top-level test
  `define TBL_TOP_RST_N     3
  `define TBL_TOP_UART_IDLE 1000
  `define TBL_TOP_SPI_IDLE  500

  // CPU boot test (t1_eclass_cpu_tb)
  `define TBL_CPU_TIMEOUT   100000  // max cycles before TIMEOUT

  // GPIO CPU test (t1_gpio_cpu_tb)
  `define TBL_GPIO_CPU_TIMEOUT  200000

  // UART CPU test (t1_uart_cpu_tb)
  // At baud_div=10: ~200 cycles/byte × 4 bytes L1 = ~800 cycles.
  // 200000 gives wide margin.
  `define TBL_UART_CPU_TIMEOUT  200000

  // SPI CPU test (t1_spi_cpu_tb)
  // At clk_div=4: 128 cycles/byte × 4 bytes L1 = ~512 SPI cycles + overhead.
  // 100000 gives wide margin.
  `define TBL_SPI_CPU_TIMEOUT   100000

  // I2C CPU test (t1_i2c_cpu_tb)
  // At clk_div=4: each I2C frame ≈ 200 active cycles. L1: 2 write frames.
  // 200000 gives wide margin.
  `define TBL_I2C_CPU_TIMEOUT   200000

`endif  // TEST_LEVEL2

`endif  // TB_LEVEL_SVH
