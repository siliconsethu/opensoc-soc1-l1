// ============================================================================
// crt0.S  —  Minimal C Runtime Zero (startup file) for OpenSoC Tier-1 E-class
//
// PURPOSE
//   This file is the very first code that executes after the Boot ROM hands
//   control to SRAM.  It sets up the bare minimum environment required by a
//   C program (stack, zeroed BSS) and then calls main().
//
// HOW CONTROL REACHES HERE
//   The Boot ROM at 0x0001_0000 contains three instructions hard-coded in
//   t1_boot_rom_32.sv:
//       lui  t0, 0x80000      ; t0 = 0x8000_0000  (SRAM base)
//       lui  sp, 0x80010      ; sp = 0x8001_0000  (SRAM top, stack origin)
//       jalr zero, 0(t0)      ; jump to 0x8000_0000, rd=x0 so no link reg
//   After the jalr, PC = 0x8000_0000, which is exactly where the linker
//   places _start (because eclass.ld puts .text.start first).
//
// MEMORY MAP (relevant to this file)
//   0x8000_0000  _start  (this file — first word in SRAM)
//   0x8000_xxxx  .text, .rodata, .data  (C code + constants + init data)
//   0x8000_xxxx  __bss_start … __bss_end  (zero-init globals)
//   0x8001_0000  top of stack (sp after ROM setup, grows downward toward BSS)
//
// RESPONSIBILITIES
//   1. Re-affirm sp = 0x8001_0000  (defensive — ROM already did this, but
//      crt0 must not rely on any external state beyond the ISA reset values)
//   2. Zero the .bss section word-by-word  (C standard requires BSS = 0)
//   3. Call main(argc=0, argv=NULL)  (bare-metal: no command-line args)
//   4. Spin forever after main returns  (main() writes to TOHOST before
//      returning, so the simulation testbench detects completion)
//
// REGISTER USAGE DURING STARTUP
//   sp   stack pointer — set first, before any stack-using instructions
//   a0   loop pointer for BSS zeroing, then argc for main
//   a1   BSS end pointer, then argv for main
//   ra   return address — set by 'call main', never used after
//
// WHY NO .init_array / constructors?
//   This is a bare-metal test binary, not a hosted C environment.
//   There is no OS, no dynamic linker, no C++ runtime.  GCC with
//   -nostdlib/-nostartfiles will not generate .init_array references.
// ============================================================================

    // Place this code in the .text.start sub-section.
    // The linker script (eclass.ld) ensures .text.start is emitted FIRST
    // within the .text section, so _start lands at exactly 0x8000_0000.
    .section .text.start,"ax",@progbits

    // Make _start visible to the linker so ENTRY(_start) in the linker
    // script can resolve it and the ELF entry point is set correctly.
    .global  _start
    .type    _start, @function

_start:
    // ------------------------------------------------------------------
    // Step 1: Stack Pointer
    // ------------------------------------------------------------------
    // The Boot ROM already set sp = 0x8001_0000 via 'lui sp, 0x80010'.
    // We re-set it here defensively: if this crt0 is ever run from a
    // different boot path (e.g., JTAG download, different ROM), the stack
    // will still be correct.
    //
    // RISC-V %hi/%lo pseudo-ops:
    //   0x8001_0000 → %hi = 0x80010 (upper 20 bits after rounding)
    //              → %lo = 0x000   (lower 12 bits)
    // Because %lo(0x80010000) = 0, the addi is a NOP in effect, but it
    // is required by the RISC-V calling convention for two-instruction
    // symbol addressing.
    lui     sp, %hi(0x80010000)     // sp[31:12] = 0x80010
    addi    sp, sp, %lo(0x80010000) // sp = 0x8001_0000  (stack top)

    // ------------------------------------------------------------------
    // Step 2: Zero the BSS section
    // ------------------------------------------------------------------
    // The C standard (ISO C11 §6.7.9 ¶10) requires that objects with
    // static storage duration (global/static variables without explicit
    // initializers) are zero-initialized before program startup.
    //
    // The linker script defines two symbols:
    //   __bss_start — first byte of the .bss section
    //   __bss_end   — one past the last byte of .bss
    //
    // 'la' (load address) expands to auipc+addi or lui+addi sequences
    // that resolve the symbol address at link time.
    //
    // The loop writes one 32-bit zero word per iteration.  This assumes
    // __bss_start and __bss_end are both 4-byte aligned, which the linker
    // script ensures with '. = ALIGN(4)' at the section boundaries.
    la      a0, __bss_start         // a0 = pointer to first BSS word
    la      a1, __bss_end           // a1 = pointer past last BSS word

.Lbss:
    bge     a0, a1, .Lbss_done     // if a0 >= a1, all words zeroed → exit loop
    sw      zero, 0(a0)            // write 32'b0 to *a0
    addi    a0, a0, 4              // advance pointer by one word (4 bytes)
    j       .Lbss                  // unconditional branch back to loop top

.Lbss_done:
    // BSS is now fully zeroed.  Global variables like wbuf[], walkbuf[],
    // bbuf[], hbuf[] in eclass_cpu_test.c are ready to use.

    // ------------------------------------------------------------------
    // Step 3: Call main()
    // ------------------------------------------------------------------
    // C calling convention (RISC-V ilp32 ABI):
    //   a0 = first argument  (int argc)
    //   a1 = second argument (char **argv)
    // For bare-metal there are no command-line arguments, so both are 0.
    //
    // 'call' is a pseudo-instruction that expands to auipc + jalr.
    // It sets ra (x1) = PC+4 so main() can return here.
    li      a0, 0                   // argc = 0
    li      a1, 0                   // argv = NULL
    call    main                    // jump to main(); ra = address of next insn

    // ------------------------------------------------------------------
    // Step 4: Spin loop after main() returns
    // ------------------------------------------------------------------
    // main() is responsible for writing the test result to TOHOST
    // (address 0x8000_0FF0) BEFORE returning.  The testbench monitors
    // TOHOST and declares PASS or FAIL when it sees a non-zero write.
    //
    // After main() returns (a0 = return value), we do NOT call exit() or
    // trigger a system call — there is no OS.  We simply spin forever.
    // The simulator's timeout watchdog (TBL_CPU_TIMEOUT cycles) will
    // terminate the run if TOHOST is never written.
    //
    // Using a local label (.L prefix) avoids polluting the global symbol
    // table — the linker will not export this label.
.Lspin:
    j       .Lspin                  // infinite loop — simulation ends via $finish

    // Emit the size of _start in the ELF symbol table (useful for
    // debugging with riscv32-unknown-elf-objdump -d).
    .size _start, . - _start
