// OpenSoC Tier-1 — prim_secded_pkg simulation stub
// Provides SEC-DED ECC encoding functions referenced by tlul_pkg.
// Returns identity (pass-through data, all-ones ECC) — integrity not checked
// in simulation.
// SPDX-License-Identifier: Apache-2.0 (compatible stub)

package prim_secded_pkg;

  // 64-bit = 7-bit ECC + 57-bit data  (inverted Hamming variant)
  function automatic logic [63:0] prim_secded_inv_64_57_enc(logic [56:0] in);
    return {7'h7f, in};
  endfunction

  // 39-bit = 7-bit ECC + 32-bit data
  function automatic logic [38:0] prim_secded_inv_39_32_enc(logic [31:0] in);
    return {7'h7f, in};
  endfunction

  // 72-bit = 8-bit ECC + 64-bit data
  function automatic logic [71:0] prim_secded_inv_72_64_enc(logic [63:0] in);
    return {8'hff, in};
  endfunction

  // 22-bit = 6-bit ECC + 16-bit data
  function automatic logic [21:0] prim_secded_inv_22_16_enc(logic [15:0] in);
    return {6'h3f, in};
  endfunction

endpackage
