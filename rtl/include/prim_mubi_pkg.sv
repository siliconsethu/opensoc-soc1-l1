// OpenSoC Tier-1 — prim_mubi_pkg stub
// Provides multi-bit boolean types used by OpenTitan register tops
package prim_mubi_pkg;
  typedef logic [3:0] mubi4_t;
  localparam int MuBi4Width = 4;
  localparam mubi4_t MuBi4True  = 4'b1010;
  localparam mubi4_t MuBi4False = 4'b0101;

  typedef logic [7:0] mubi8_t;
  localparam mubi8_t MuBi8True  = 8'b10101010;
  localparam mubi8_t MuBi8False = 8'b01010101;

  typedef logic [11:0] mubi12_t;
  localparam mubi12_t MuBi12True  = 12'hAAA;
  localparam mubi12_t MuBi12False = 12'h555;

  function automatic mubi4_t mubi4_bool_to_mubi(logic val);
    return val ? MuBi4True : MuBi4False;
  endfunction

  function automatic logic mubi4_test_true_strict(mubi4_t val);
    return val == MuBi4True;
  endfunction

  function automatic logic mubi4_test_false_strict(mubi4_t val);
    return val == MuBi4False;
  endfunction

  // Returns 1 if val is neither MuBi4True nor MuBi4False (invalid encoding).
  // Used by tlul_pkg::tl_a_user_chk.
  function automatic logic mubi4_test_invalid(mubi4_t val);
    return (val != MuBi4True) && (val != MuBi4False);
  endfunction

  function automatic logic mubi8_test_true_strict(mubi8_t val);
    return val == MuBi8True;
  endfunction

  function automatic logic mubi8_test_false_strict(mubi8_t val);
    return val == MuBi8False;
  endfunction

  function automatic logic mubi12_test_true_strict(mubi12_t val);
    return val == MuBi12True;
  endfunction

  function automatic logic mubi12_test_false_strict(mubi12_t val);
    return val == MuBi12False;
  endfunction
endpackage
