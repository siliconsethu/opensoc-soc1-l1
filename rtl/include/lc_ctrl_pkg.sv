// OpenSoC Tier-1 — lc_ctrl_pkg stub
package lc_ctrl_pkg;
  typedef logic [3:0] lc_tx_t;
  localparam lc_tx_t On  = 4'b1010;
  localparam lc_tx_t Off = 4'b0101;

  function automatic logic lc_tx_test_false_strict(lc_tx_t val);
    return val == Off;
  endfunction

  function automatic logic lc_tx_test_true_strict(lc_tx_t val);
    return val == On;
  endfunction
endpackage
