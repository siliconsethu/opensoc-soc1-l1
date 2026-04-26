// OpenSoC Tier-1 — prim_util_pkg stub
// Provides vbits() utility function used by OpenTitan IPs
package prim_util_pkg;
  // Return number of bits needed to represent values 0..x-1
  function automatic int unsigned vbits(int unsigned x);
    return (x > 1) ? $clog2(x) : 1;
  endfunction
endpackage
