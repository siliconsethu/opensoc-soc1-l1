// OpenSoC Tier-1 — prim_ram_1p_pkg stub (needed by i2c.sv)
package prim_ram_1p_pkg;
  typedef struct packed {
    logic       cfg_en;
    logic [3:0] cfg;
  } ram_1p_cfg_t;
  localparam ram_1p_cfg_t RAM_1P_CFG_DEFAULT = '{cfg_en: 1'b0, cfg: 4'h0};
endpackage
