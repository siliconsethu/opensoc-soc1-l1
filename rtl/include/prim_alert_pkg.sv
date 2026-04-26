// OpenSoC Tier-1 — prim_alert_pkg stub
package prim_alert_pkg;
  typedef struct packed { logic ping_p; logic ping_n; logic ack_p; logic ack_n; } alert_rx_t;
  typedef struct packed { logic alert_p; logic alert_n; }                         alert_tx_t;
  localparam alert_rx_t ALERT_RX_DEFAULT = '{ping_p:1'b0, ping_n:1'b1, ack_p:1'b0, ack_n:1'b1};
  localparam alert_tx_t ALERT_TX_DEFAULT = '{alert_p:1'b0, alert_n:1'b1};
endpackage
