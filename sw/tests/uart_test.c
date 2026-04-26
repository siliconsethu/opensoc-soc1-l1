// ============================================================================
// uart_test.c  —  CPU-driven UART loopback test, OpenSoC Tier-1 L1
//
// IMPORTANT — L1 STACK CONSTRAINT
//   crt0.S sets sp = 0x8001_0000 (128 KB mark, designed for L2 SRAM).
//   L1 SRAM ends at 0x8000_0FFF (4 KB).  Any stack push goes to an unmapped
//   address and the AXI bus stalls forever.
//
//   Fix: keep main() as a leaf function (no sub-calls).  GCC -Os holds all
//   locals in caller-saved registers; no stack frame is generated for a leaf.
//
// REGISTER MAP  (uart.sv base 0x9000_0000)
//   0x10  CTRL     R/W  [15:0]=NCO [16]=TX_EN [17]=RX_EN
//   0x14  STATUS   RO   [0]=txfull [1]=rxfull [2]=txempty
//                        [3]=txidle [4]=rxidle [5]=rxempty
//   0x18  RDATA    RO   [7:0] — byte from RX FIFO (clears rx entry)
//   0x1C  WDATA    W/O  [7:0] — byte to TX FIFO (ignored if tx_full or !tx_en)
//
// BAUD RATE
//   NCO_SIM = 0x2000 (8192) → baud period = 65536/8192 = 8 cycles/bit.
//   One 8N1 frame = 10 × 8 = 80 cycles TX + ~172 cycles echo = ~252 total.
//   Must match BAUD_CYCLES in t1_eclass_uart_tb.sv.
//
// ECHO LOOPBACK
//   Testbench detects each TX frame on uart_tx_o, decodes the 8 data bits,
//   and re-serialises the same byte onto uart_rx_i.  C code polls STATUS
//   until the echo byte appears in the RX FIFO, then verifies it.
//
// TOHOST  0x8000_0FF0  (L1 SRAM word 1020)
//   0x00000001  PASS
//   0x1001      CTRL readback mismatch
//   0x1002      STATUS initial state wrong (txidle/txempty/rxempty not set)
//   0x20NN      TX timeout for byte NN (01=0x55 02=0xAA 03=0x00 04=0xFF)
//   0x30NN      RX timeout for byte NN
//   0x40NN      Received byte mismatch for byte NN
//
// TESTBENCH COUNTERPART: t1_eclass_uart_tb.sv
// ============================================================================

#include <stdint.h>

#define UART_BASE   0x90000000u

// CTRL (0x10): [15:0]=NCO, [16]=TX_EN, [17]=RX_EN
#define UART_CTRL   (*(volatile uint32_t *)(UART_BASE + 0x10u))

// STATUS (0x14): bit positions below
#define UART_STATUS (*(volatile uint32_t *)(UART_BASE + 0x14u))

// RDATA (0x18): [7:0] byte from RX FIFO (read pops the entry)
#define UART_RDATA  (*(volatile uint32_t *)(UART_BASE + 0x18u))

// WDATA (0x1C): write-only — [7:0] byte to TX FIFO; dropped if txfull or !TX_EN
#define UART_WDATA  (*(volatile uint32_t *)(UART_BASE + 0x1Cu))

// STATUS bit positions
#define STAT_TXFULL  (1u << 0)   // TX FIFO full
#define STAT_RXFULL  (1u << 1)   // RX FIFO full
#define STAT_TXEMPTY (1u << 2)   // TX FIFO empty
#define STAT_TXIDLE  (1u << 3)   // TX serialiser idle (last bit gone)
#define STAT_RXIDLE  (1u << 4)   // RX state machine idle
#define STAT_RXEMPTY (1u << 5)   // RX FIFO empty (no byte available)

// CTRL bit positions
#define CTRL_TX_EN  (1u << 16)
#define CTRL_RX_EN  (1u << 17)

// Simulation NCO value: baud period = 65536/NCO_SIM clock cycles.
// NCO_SIM = 0x2000 → 8 cycles/bit.  Must match BAUD_CYCLES in the SV TB.
#define NCO_SIM  0x2000u

#define TOHOST (*(volatile uint32_t *)0x80000FF0u)

// FAIL: write error code to TOHOST and return from main (leaf — no stack).
#define FAIL(code) do { TOHOST = (uint32_t)(code); return 0; } while(0)

// Polling iteration limit before declaring a timeout.
// At ~4 cycles/iteration, 100000 × 4 = 400 000 cycles >> 252 cycles/byte.
#define UART_TIMEOUT 100000u

// Inline loopback macro: send byte_val, wait TX idle, wait RX ready, verify.
// fail_tx/fail_rx/fail_cmp are the TOHOST error codes for each failure type.
#define DO_LOOPBACK(byte_val, fail_tx, fail_rx, fail_cmp) do {              \
    uint32_t _i;                                                              \
    UART_WDATA = (uint32_t)(byte_val);                                       \
    for (_i = 0u; _i < UART_TIMEOUT; _i++)                                   \
        if (UART_STATUS & STAT_TXIDLE) break;                                \
    if (_i == UART_TIMEOUT) FAIL(fail_tx);                                   \
    for (_i = 0u; _i < UART_TIMEOUT; _i++)                                   \
        if (!(UART_STATUS & STAT_RXEMPTY)) break;                            \
    if (_i == UART_TIMEOUT) FAIL(fail_rx);                                   \
    if ((UART_RDATA & 0xFFu) != (uint32_t)(byte_val)) FAIL(fail_cmp);       \
} while(0)

// main() is a leaf — no sub-calls — so GCC -Os generates no stack frame.
int main(void)
{
    uint32_t val, stat;

    // ── (1) Configure CTRL: fast-sim NCO, TX and RX enabled (8N1) ─────────────
    uint32_t ctrl_write = NCO_SIM | CTRL_TX_EN | CTRL_RX_EN;
    UART_CTRL = ctrl_write;
    val = UART_CTRL;
    if (val != ctrl_write) FAIL(0x1001u);

    // ── (2) Verify initial STATUS ─────────────────────────────────────────────
    // Before any TX: TXIDLE (bit 3), TXEMPTY (bit 2), RXEMPTY (bit 5) must all
    // be set.  If any is clear the TX FSM or RX FIFO is in an unexpected state.
    stat = UART_STATUS;
    if ((stat & (STAT_TXIDLE | STAT_TXEMPTY | STAT_RXEMPTY)) !=
        (STAT_TXIDLE | STAT_TXEMPTY | STAT_RXEMPTY)) FAIL(0x1002u);

    // ── (3–6) Loopback four test bytes ────────────────────────────────────────
    // The testbench echo task detects the TX frame, decodes the byte, and
    // re-drives it on uart_rx_i.  We poll TXIDLE then RXEMPTY between each.

    // 0x55 = 0101_0101: alternating pattern, LSB=1
    DO_LOOPBACK(0x55u, 0x2001u, 0x3001u, 0x4001u);

    // 0xAA = 1010_1010: complement of 0x55, LSB=0
    DO_LOOPBACK(0xAAu, 0x2002u, 0x3002u, 0x4002u);

    // 0x00 = all zeros: TX drives 0 for all 8 data bits
    DO_LOOPBACK(0x00u, 0x2003u, 0x3003u, 0x4003u);

    // 0xFF = all ones: TX stays high for 8 data bits (= same as idle)
    DO_LOOPBACK(0xFFu, 0x2004u, 0x3004u, 0x4004u);

    TOHOST = 1u;   // PASS
    return 0;
}
