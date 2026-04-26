/* ============================================================================
 * eclass.ld  —  GNU ld Linker Script for OpenSoC Tier-1 Shakti E-class
 *
 * PURPOSE
 *   Tells the linker how to map compiled object-file sections (.text, .data,
 *   .bss, etc.) into the physical memory regions of the E-class SoC.
 *   Only SRAM is used for code+data; the Boot ROM is handled separately by
 *   the RTL model (t1_boot_rom_32.sv) and is never written by the compiler.
 *
 * PHYSICAL MEMORY MAP
 *   Region  Start        Size    Description
 *   ------  -----------  ------  ----------------------------------------
 *   ROM     0x0001_0000   64 KB  Boot ROM (RTL model, read-only, fixed code)
 *   SRAM    0x8000_0000  128 KB  Main SRAM — code, constants, data, stack
 *
 * BOOT SEQUENCE
 *   1. CPU resets to PC = 0x0001_0000 (BootAddr in rv32i_iss / eclass_wrapper)
 *   2. Boot ROM executes:
 *         lui  t0, 0x80000   → t0 = 0x8000_0000
 *         lui  sp, 0x80010   → sp = 0x8001_0000  (SRAM top)
 *         jalr zero, 0(t0)   → PC = 0x8000_0000  (jump to SRAM)
 *   3. _start (crt0.S) begins at 0x8000_0000
 *   4. crt0 zeroes BSS, calls main()
 *   5. main() runs tests, writes result to TOHOST, returns
 *   6. crt0 spins forever; testbench detects TOHOST and terminates
 *
 * TOHOST CONVENTION
 *   The C test communicates pass/fail by writing to the fixed address
 *   0x8000_0FF0.  This address is within the SRAM region and translates to
 *   SRAM word index 0x3FC (= 0xFF0 / 4).  The testbench (t1_eclass_cpu_tb.sv)
 *   polls u_sram.mem[0x3FC] every clock cycle.
 *
 *   TOHOST values:
 *     0x0000_0001 = PASS (all tests passed)
 *     anything else non-zero = FAIL (upper 16 bits = test group,
 *                                    lower 16 bits = sub-error code)
 *
 * STACK
 *   The Boot ROM sets sp = 0x8001_0000 (top of 128 KB SRAM).
 *   The stack grows DOWNWARD toward the BSS end.
 *   No guard page is provided — this is bare-metal simulation only.
 *   With the L2 test, the deepest stack frame is fib(12), approximately
 *   12 nested frames × ~6 saved registers × 4 bytes = ~288 bytes of stack.
 *   The gap between __bss_end (~0x8000_0300) and the stack top (0x8001_0000)
 *   is ~64 KB, which is more than sufficient.
 *
 * SECTION LAYOUT (in SRAM order)
 *   0x8000_0000  .text.start  — _start (crt0.S) — MUST be at SRAM base
 *   ...          .text        — all other compiled code (main, test_* fns)
 *   ...          .rodata      — read-only constants (string literals, etc.)
 *   ...          .data        — initialised global/static variables
 *   ...          .bss         — uninitialised global/static variables
 *   0x8001_0000  (stack top)
 *
 * COMPILER FLAGS REQUIRED
 *   -march=rv32im        RV32 base + multiply/divide extension
 *   -mabi=ilp32          32-bit integer ABI, no hardware float
 *   -nostdlib            do not link glibc / newlib
 *   -nostartfiles        do not link the compiler's own crt0
 *   -ffreestanding       no hosted C assumptions (no main() prototype check)
 *   -T sw/boot/eclass.ld use this script
 * ============================================================================ */

/* Tell the linker we are targeting a RISC-V architecture.
   This affects ELF header fields and relocation types. */
OUTPUT_ARCH(riscv)

/* The entry point symbol.  This sets the ELF e_entry field so that
   debuggers (e.g. riscv32-unknown-elf-gdb) know where execution starts.
   It also generates a linker warning if _start is not found in any object. */
ENTRY(_start)

/* --------------------------------------------------------------------------
 * MEMORY REGIONS
 * Define the physical address ranges that the linker may use.
 * Attributes:
 *   r = readable    w = writable    x = executable
 *   Lowercase = NOT that attribute  (not used here, all SRAM is rwx)
 * -------------------------------------------------------------------------- */
MEMORY {
    /* SRAM: 128 KB at 0x8000_0000.
       'rwx' = read + write + execute.  All code and data live here.
       LENGTH = 128K corresponds to the t1_sram_top_32 default NumWords=32768
       (32768 words × 4 bytes/word = 131072 bytes = 128 KB). */
    sram (rwx) : ORIGIN = 0x80000000, LENGTH = 128K
}

/* --------------------------------------------------------------------------
 * OUTPUT SECTIONS
 * Each SECTIONS entry maps input sections (from .o files) into output
 * segments placed in SRAM.
 * -------------------------------------------------------------------------- */
SECTIONS {
    /* Location counter starts at SRAM base.
       This ensures the first byte of .text.start lands at 0x8000_0000,
       which is the address the Boot ROM jumps to. */
    . = 0x80000000;

    /* ------------------------------------------------------------------
     * .text  —  Executable machine code
     * ------------------------------------------------------------------ */
    .text : {
        /* .text.start MUST be listed FIRST.
           This sub-section contains crt0.S (_start), which the Boot ROM
           jumps to.  If any other code were placed before it, the CPU would
           start executing garbage after the ROM jump. */
        *(.text.start)

        /* All other .text sections from all object files, in link order.
           The wildcard *(.text.*) catches compiler-generated sub-sections
           such as .text.main, .text.test_arith, .text.fib, etc.
           GCC emits per-function sub-sections when -ffunction-sections is
           used (allows the linker to dead-strip unused functions with
           --gc-sections), but we do not use that flag here. */
        *(.text .text.*)

        /* Align location counter to 4-byte boundary after .text so that
           the next section starts on a word boundary (required for the
           RISC-V 32-bit ISA and for the $readmemh word-addressing in the
           SRAM model). */
        . = ALIGN(4);
    } > sram   /* Place this output section into the 'sram' memory region */

    /* ------------------------------------------------------------------
     * .rodata  —  Read-only data (string literals, const globals)
     * ------------------------------------------------------------------ */
    .rodata : {
        /* Captures all read-only data sub-sections.  In the current C test
           there are no string constants or const arrays, so this section
           will be empty, but it is included for correctness. */
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > sram

    /* ------------------------------------------------------------------
     * .data  —  Initialised read-write data
     * ------------------------------------------------------------------ */
    .data : {
        /* Global and static variables that have an explicit non-zero
           initializer (e.g., 'int x = 5;').  In the current test all
           globals use implicit zero-initialization and land in .bss, but
           the section must exist for a valid ELF layout. */
        *(.data .data.*)
        . = ALIGN(4);
    } > sram

    /* ------------------------------------------------------------------
     * .bss  —  Uninitialised (zero-initialised) read-write data
     * ------------------------------------------------------------------ */
    .bss : {
        /* Export __bss_start so crt0.S can reference it with 'la'.
           The linker resolves 'la a0, __bss_start' to the actual address. */
        __bss_start = .;

        /* All uninitialised globals and statics.
           In the C test: wbuf[8], bbuf[16], hbuf[8], walkbuf[64],
           and any internal compiler temporaries with static storage.
           *(COMMON) captures Fortran-style COMMON blocks and tentative
           C definitions (rarely generated by modern GCC but included for
           completeness). */
        *(.bss .bss.*)
        *(COMMON)

        /* Align so __bss_end is on a word boundary — crt0's zeroing loop
           writes one 32-bit word per iteration, so both start and end
           must be 4-byte aligned to avoid partial writes. */
        . = ALIGN(4);

        /* Export __bss_end so crt0.S loop knows when to stop. */
        __bss_end = .;
    } > sram

    /* Export _end as a convenience symbol indicating the first byte after
       all program sections.  This is the lowest valid stack guard address. */
    _end = .;

    /* ------------------------------------------------------------------
     * Discard sections not needed for bare-metal simulation
     * ------------------------------------------------------------------ */
    /DISCARD/ : {
        /* C++ exception handling frames — not needed, no exceptions */
        *(.eh_frame)
        /* RISC-V ELF attribute section (ISA string, ABI info) — not
           needed in the simulator; keeps the binary smaller */
        *(.riscv.attributes)
    }
}
