#!/usr/bin/env python3
# =============================================================================
# bin2hex.py  —  Convert a raw RISC-V binary to a $readmemh-compatible hex file
#                OpenSoC Tier-1 Shakti E-class build tool
#
# PURPOSE
#   The RISC-V GCC toolchain produces an ELF file.  The RTL SRAM model
#   (t1_sram_top_32.sv) uses Verilog's $readmemh system task to preload its
#   memory array, which expects a plain text file with one hex word per line.
#
#   The conversion pipeline used by the Makefile is:
#
#     riscv32-unknown-elf-gcc ... -o eclass_cpu_test.elf
#     riscv32-unknown-elf-objcopy -O binary eclass_cpu_test.elf eclass_cpu_test.bin
#     python3 scripts/bin2hex.py eclass_cpu_test.bin eclass_cpu_test.hex
#
#   This script handles the final step: binary → hex text.
#
# INPUT FORMAT
#   A raw binary file produced by objcopy -O binary.  This format strips all
#   ELF headers, symbol tables, relocation entries, and debug sections.
#   The remaining bytes are the actual machine code and initialized data,
#   in the order they appear in memory starting at the first LOAD segment's
#   virtual address (0x8000_0000 for our linker script).
#
# OUTPUT FORMAT
#   One 32-bit word per line, written as 8 lowercase hexadecimal digits.
#   Words are in little-endian byte order, which matches:
#     - The RISC-V ISA (all multi-byte values are little-endian in memory)
#     - The SRAM model's word storage (mem[i] holds 4 consecutive bytes at
#       addresses 4i, 4i+1, 4i+2, 4i+3, with byte 4i in bits [7:0])
#
#   Example: instruction 'addi sp, sp, -16' encodes to bytes:
#             0x13, 0x01, 0x01, 0xFF  (little-endian)
#           Output line: "ff010113"  ← bytes reversed into word order
#
#   No address markers are used (i.e., no "@<addr>" prefix lines).
#   $readmemh without address markers loads sequentially starting at index 0:
#     mem[0] ← first line of hex file  → maps to SRAM address 0x8000_0000
#     mem[1] ← second line             → maps to SRAM address 0x8000_0004
#     ...
#
# PADDING
#   If the binary length is not a multiple of 4 bytes, the script zero-pads
#   to the next 4-byte boundary before converting.  This should not normally
#   occur because the linker script aligns all section boundaries to 4 bytes
#   ('. = ALIGN(4)' before and after each section), but the padding ensures
#   the script never silently drops the last partial word.
#
# ALIGNMENT REQUIREMENT
#   The SRAM model uses 32-bit words exclusively.  $readmemh reads one word
#   per line with no byte-granularity.  Therefore:
#     - The binary must start at a 4-byte boundary (guaranteed by eclass.ld)
#     - Each output line represents exactly one 32-bit SRAM word
#     - The total number of output lines equals len(binary) / 4 (after padding)
#
# USAGE
#   python3 scripts/bin2hex.py <input.bin> <output.hex>
#
#   Arguments:
#     input.bin   Raw binary produced by objcopy -O binary
#     output.hex  Output hex text file, one word per line
#
#   Exit codes:
#     0   Success
#     1   Wrong number of arguments (usage error printed to stderr)
#
# EXAMPLE
#   $ riscv32-unknown-elf-objcopy -O binary build/sw/eclass_cpu_test_l1.elf \
#       build/sw/eclass_cpu_test_l1.bin
#   $ python3 scripts/bin2hex.py build/sw/eclass_cpu_test_l1.bin \
#       build/sw/eclass_cpu_test_l1.hex
#   bin2hex: 512 bytes -> 128 words -> build/sw/eclass_cpu_test_l1.hex
#
# WORD COUNT RELATIONSHIP TO SRAM
#   The SRAM model (t1_sram_top_32.sv) has NumWords=32768 by default,
#   meaning the mem[] array has 32768 entries (128 KB total).
#   $readmemh will load as many lines as the hex file contains and leave
#   the remainder of mem[] unchanged (we zero-fill mem[] in the testbench
#   before calling $readmemh, so unloaded words are 0).
#
# DEPENDENCY
#   Python 3.6+ for f-strings and struct.unpack_from.
#   No external packages required (struct is in the Python standard library).
# =============================================================================

import sys
import struct


def main():
    # ── Argument validation ──────────────────────────────────────────────────
    # Exactly two positional arguments are required: input binary and output hex.
    # Any other count is a usage error; print a helpful message and exit non-zero.
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.bin output.hex", file=sys.stderr)
        sys.exit(1)

    # ── Read raw binary ──────────────────────────────────────────────────────
    # Open in binary mode ('rb') to get the exact bytes without any newline
    # translation.  The entire file is read into memory at once; for a 128 KB
    # SRAM image this is only 131072 bytes, which is negligible.
    with open(sys.argv[1], 'rb') as f:
        data = f.read()

    # ── Pad to 4-byte boundary ───────────────────────────────────────────────
    # If len(data) % 4 != 0, append zero bytes to reach the next word boundary.
    # This situation should not arise with a correctly linked ELF (the linker
    # script aligns sections), but the padding protects against edge cases such
    # as manually trimmed binaries or linker scripts that omit ALIGN directives.
    #
    # rem = number of bytes past the last complete word
    # If rem > 0, we need (4 - rem) more bytes to complete the word.
    rem = len(data) % 4
    if rem:
        data += b'\x00' * (4 - rem)

    # ── Convert to hex words ─────────────────────────────────────────────────
    # struct.unpack_from('<I', data, offset):
    #   '<' = little-endian byte order (RISC-V is always little-endian)
    #   'I' = unsigned 32-bit integer (4 bytes)
    #   offset = i * 4 (byte offset of word i within the binary)
    #
    # Returns a one-element tuple; the comma after 'word' unpacks that tuple.
    #
    # f'{word:08x}' formats the word as exactly 8 lowercase hex digits,
    # zero-padded on the left.  Each line of the output file corresponds to
    # one 32-bit SRAM word, in the same order as SRAM addresses.
    #
    # Example (first three words of a typical E-class binary):
    #   mem[0]  @ 0x8000_0000 → first instruction in crt0.S (_start: lui sp, ...)
    #   mem[1]  @ 0x8000_0004 → second instruction (addi sp, sp, 0)
    #   mem[2]  @ 0x8000_0008 → third instruction (la a0, __bss_start)
    n_words = len(data) // 4
    with open(sys.argv[2], 'w') as f:
        for i in range(n_words):
            # Unpack one little-endian 32-bit word from byte offset i*4
            word, = struct.unpack_from('<I', data, i * 4)
            # Write as 8 hex digits followed by a newline
            f.write(f'{word:08x}\n')

    # ── Summary ──────────────────────────────────────────────────────────────
    # Print a single-line summary so the Makefile output is informative.
    # Shows: input byte count, output word count, output file path.
    print(f"bin2hex: {len(data)} bytes -> {n_words} words -> {sys.argv[2]}")


if __name__ == '__main__':
    main()
