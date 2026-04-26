// ============================================================================
// gpio_test.c  —  CPU-driven GPIO register test, OpenSoC Tier-1 L1
//
// IMPORTANT — L1 STACK CONSTRAINT
//   crt0.S sets sp = 0x8001_0000 (128 KB mark, designed for L2 SRAM).
//   L1 SRAM ends at 0x8000_0FFF (4 KB).  Any stack push goes to an unmapped
//   address and the AXI bus stalls forever.
//
//   Fix: keep main() as a leaf function (no sub-calls).  GCC -Os holds all
//   locals in caller-saved registers (t0-t6, a0-a7); no stack frame is
//   generated for a leaf.
//
// REGISTER MAP  (OpenTitan gpio.sv, base 0x9000_1000)
//   0x10  DATA_IN          RO   sampled gpio_in_i
//   0x14  DIRECT_OUT       R/W  direct output data
//   0x18  MASKED_OUT_LOWER W    [31:16]=mask [15:0]=data (pins [15:0])
//   0x20  DIRECT_OE        R/W  output-enable per pin
//
// L1 NOTE: only gpio[15:0] are physically connected; upper 16 bits read 0.
//
// TOHOST  0x8000_0FF0  (L1 SRAM word 1020)
//   0x00000001  PASS
//   other       FAIL — see error code table in t1_eclass_gpio_tb.sv
//
// TESTBENCH COUNTERPART: t1_eclass_gpio_tb.sv
//   Drives gpio_in[15:0] as a continuous walk-1 so step (7) below can
//   OR-accumulate DATA_IN reads and verify all 16 input bits are reachable.
// ============================================================================

#include <stdint.h>

#define GPIO_BASE        0x90001000u
#define DATA_IN          (*(volatile uint32_t *)(GPIO_BASE + 0x10u))
#define DIRECT_OUT       (*(volatile uint32_t *)(GPIO_BASE + 0x14u))
#define MASKED_OUT_LOWER (*(volatile uint32_t *)(GPIO_BASE + 0x18u))
#define DIRECT_OE        (*(volatile uint32_t *)(GPIO_BASE + 0x20u))

#define TOHOST (*(volatile uint32_t *)0x80000FF0u)

// main() is a leaf — no sub-calls — so GCC -Os generates no stack frame.
// The FAIL macro writes TOHOST and returns from main directly.
#define FAIL(code) do { TOHOST = (uint32_t)(code); return 0; } while(0)

int main(void)
{
    uint32_t val, seen, pat;

    // ── (1) DIRECT_OE: enable all 16 outputs ─────────────────────────────────
    DIRECT_OE = 0x0000FFFFu;
    val = DIRECT_OE;
    if (val != 0x0000FFFFu) FAIL(0x1001u);

    // ── (2) Walk-1 on DIRECT_OUT bits [0..15] ────────────────────────────────
    for (uint32_t b = 0u; b < 16u; b++) {
        DIRECT_OUT = 1u << b;
        val = DIRECT_OUT;
        if (val != (1u << b)) FAIL(0x2000u | b);
    }

    // ── (3) Alternating pattern 0xAAAA ───────────────────────────────────────
    DIRECT_OUT = 0x0000AAAAu;
    val = DIRECT_OUT;
    if (val != 0x0000AAAAu) FAIL(0x1002u);

    // ── (4) Alternating pattern 0x5555 ───────────────────────────────────────
    DIRECT_OUT = 0x00005555u;
    val = DIRECT_OUT;
    if (val != 0x00005555u) FAIL(0x1003u);

    // ── (5) Walk-0 on DIRECT_OUT bits [0..15] ────────────────────────────────
    for (uint32_t b = 0u; b < 16u; b++) {
        pat = 0x0000FFFFu & ~(1u << b);
        DIRECT_OUT = pat;
        val = DIRECT_OUT;
        if (val != pat) FAIL(0x3000u | b);
    }

    // ── (6) MASKED_OUT_LOWER: write via mask+data ─────────────────────────────
    // Clear first, then write mask=0xFFFF data=0x3C3C → DIRECT_OUT must be 0x3C3C.
    DIRECT_OUT = 0x00000000u;
    MASKED_OUT_LOWER = (0xFFFFu << 16) | 0x3C3Cu;
    val = DIRECT_OUT;
    if (val != 0x00003C3Cu) FAIL(0x1004u);

    // ── (7) DATA_IN OR-accumulation ──────────────────────────────────────────
    // TB drives walk-1 on gpio_in[15:0] continuously.  Reading many times and
    // OR-ing must cover all 16 input bits.
    seen = 0u;
    for (int i = 0; i < 4096; i++) seen |= DATA_IN;
    if ((seen & 0x0000FFFFu) != 0x0000FFFFu) FAIL(0x1005u);

    // ── (8) DIRECT_OE: return all pins to input mode ─────────────────────────
    DIRECT_OE = 0x00000000u;
    val = DIRECT_OE;
    if (val != 0x00000000u) FAIL(0x1006u);

    // ── (9) Clear DIRECT_OUT ─────────────────────────────────────────────────
    DIRECT_OUT = 0x00000000u;

    TOHOST = 1u;   // PASS
    return 0;
}
