// OpenSoC Tier-1 — top_pkg
// OpenTitan TL-UL bus parameter package.
// Must be compiled before tlul_pkg and all modules that reference top_pkg::.
//
// Values match the OpenTitan Earlgrey v0.9 / Sunburst specification.
// SPDX-License-Identifier: Apache-2.0 (compatible stub)

package top_pkg;
  localparam int unsigned TL_DW  = 32;          // data bus width
  localparam int unsigned TL_AIW = 8;            // A-channel source (initiator) ID width
  localparam int unsigned TL_AW  = 32;           // address width
  localparam int unsigned TL_DBW = TL_DW >> 3;  // data byte width (4)
  localparam int unsigned TL_SZW = 3;            // size field width  (covers 0..4 bytes log2)
  localparam int unsigned TL_DIW = 1;            // D-channel sink ID width
  localparam int unsigned TL_DUW = 4;            // D-channel user width
  // A-channel user width = rsvd(3) + mubi4(4) + cmd_intg(7) + data_intg(7) = 21
  localparam int unsigned TL_AUW = 21;
  localparam int unsigned TL_I   = 1;
endpackage
