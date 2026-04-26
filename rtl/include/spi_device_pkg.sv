// OpenSoC Tier-1 — spi_device_pkg stub (needed by spi_host.sv passthrough)
package spi_device_pkg;
  typedef struct packed {
    logic [3:0] s;          // SD output lines (field name used by spi_host)
    logic [3:0] s_en;       // SD output enables
    logic       csb;
    logic       csb_en;
    logic       sck;
    logic       sck_en;
    logic       passthrough_en;
  } passthrough_req_t;
  typedef struct packed {
    logic [3:0] s;          // SD input lines from spi_host side
  } passthrough_rsp_t;
  localparam passthrough_req_t PASSTHROUGH_REQ_DEFAULT = '0;
  localparam passthrough_rsp_t PASSTHROUGH_RSP_DEFAULT = '0;
endpackage
