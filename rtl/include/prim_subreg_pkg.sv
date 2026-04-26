// OpenSoC Tier-1 — prim_subreg_pkg stub
// Provides SW access type enum used by OpenTitan register tops
package prim_subreg_pkg;
  typedef enum logic [3:0] {
    SwAccessRW  = 4'h0,
    SwAccessRO  = 4'h1,
    SwAccessWO  = 4'h2,
    SwAccessW1C = 4'h3,
    SwAccessW1S = 4'h4,
    SwAccessW0C = 4'h5,
    SwAccessRC  = 4'h6
  } sw_access_e;
endpackage
