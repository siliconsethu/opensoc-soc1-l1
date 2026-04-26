// ============================================================================
// t1_soc_top_eclass.sv  —  Unified SoC Top-Level, OpenSoC Tier-1
//                           Shakti E-class (RV32IMAC)
//
// TWO ORTHOGONAL COMPILE-TIME SWITCHES
//
//   +define+LEVEL2   →  Level-2: Boot ROM, 128 KB SRAM, full peripheral set
//                        (UART / 32-bit GPIO / SPI / I2C / timers / PLIC)
//                        Boot address: 0x0001_0000 (Boot ROM)
//   (no LEVEL2)      →  Level-1: No Boot ROM, 4 KB SRAM, UART + 16-bit GPIO
//                        Boot address: 0x8000_0000 (SRAM direct)
//
//   +define+USE_ISS  →  CPU = rv32i_iss  (behavioural RV32IM; executes C code)
//                        Use for RTL simulation with compiled test binaries.
//   (no USE_ISS)     →  CPU = shakti_eclass_wrapper
//                        Stub in sim; replace body with BSV-compiled mkE_Class
//                        for FPGA / ASIC implementation.
//
// ADDRESS MAP
//   Level-2:
//     0x0001_0000 – 0x0001_FFFF  Boot ROM    (1 KB)
//     0x8000_0000 – 0x800F_FFFF  SRAM        (128 KB)
//     0x9000_0000 – 0x901F_FFFF  Peripheral subsystem
//   Level-1:
//     0x8000_0000 – 0x8000_0FFF  SRAM        (4 KB)
//     0x9000_0000 – 0x9000_1FFF  Peripheral subsystem
//
// PORT POLICY
//   SPI and I2C ports are present only when +define+LEVEL2 is set.
//   JTAG outputs are always tied off (Shakti debug is BSV-internal).
//   halt_o is driven by rv32i_iss; tied 0 when using shakti_eclass_wrapper.
//
// REPLACING THE STUB WITH THE REAL CPU (FPGA / ASIC flow)
//   1. Compile the Shakti E-class BSV sources:
//        bsc -verilog -g mkE_Class E_Class.bsv
//   2. Replace the body of shakti_eclass_wrapper with mkE_Class instantiation.
//   3. Compile without +define+USE_ISS.
// ============================================================================

`timescale 1ns/1ps

module t1_soc_top_eclass #(
  parameter int unsigned AxiAddrWidth = 32,
  parameter int unsigned AxiDataWidth = 32,
  parameter int unsigned AxiIdWidth   = 4,
  parameter int unsigned AxiUserWidth = 1,
  // 0 = use level default (L2: 32768 words = 128 KB; L1: 1024 words = 4 KB)
  parameter int unsigned SramNumWords = 0,
  parameter int unsigned RomDepth     = 256   // Boot ROM words (L2 only)
) (
  input  logic clk_i,
  input  logic rst_ni,

  // ── JTAG ─────────────────────────────────────────────────────────────────
  // Reserved for future real-CPU integration. Outputs always tied off.
  input  logic jtag_tck_i,
  input  logic jtag_tms_i,
  input  logic jtag_trst_ni,
  input  logic jtag_tdi_i,
  output logic jtag_tdo_o,
  output logic jtag_tdo_oe_o,

  // ── UART ─────────────────────────────────────────────────────────────────
  input  logic uart_rx_i,
  output logic uart_tx_o,

  // ── GPIO (32-bit) ─────────────────────────────────────────────────────────
  // Level-1: only [15:0] connected to t1_periph_ss_l1; [31:16] tied off.
  // Level-2: full 32 bits active.
  input  logic [31:0] gpio_in_i,
  output logic [31:0] gpio_out_o,
  output logic [31:0] gpio_oe_o,

`ifdef LEVEL2
  // ── SPI (Level-2 only) ────────────────────────────────────────────────────
  output logic spi_sck_o,
  output logic spi_csb_o,
  input  logic spi_sd_i,
  output logic spi_sd_o,

  // ── I2C (Level-2 only, open-drain) ───────────────────────────────────────
  output logic i2c_scl_o,
  input  logic i2c_scl_i,
  output logic i2c_sda_o,
  input  logic i2c_sda_i,
`endif

  // ── ISS halt status ───────────────────────────────────────────────────────
  // Asserted when rv32i_iss enters S_HALT (ECALL/EBREAK/illegal instruction).
  // Tied to 0 when compiled without USE_ISS (shakti_eclass_wrapper stub).
  output logic halt_o
);

  // ==========================================================================
  // Level-specific localparams
  // ==========================================================================
`ifdef LEVEL2
  localparam int unsigned  SRAM_WORDS = (SramNumWords == 0) ? 32768 : SramNumWords;
  localparam logic [31:0]  BOOT_ADDR  = 32'h0001_0000;
`else
  localparam int unsigned  SRAM_WORDS = (SramNumWords == 0) ? 1024  : SramNumWords;
  localparam logic [31:0]  BOOT_ADDR  = 32'h8000_0000;
`endif

  // ==========================================================================
  // CPU IMEM / DMEM AXI4 wire declarations (shared by all configurations)
  // ==========================================================================

  logic                    imem_arvalid, imem_arready;
  logic [AxiIdWidth-1:0]   imem_arid;
  logic [AxiAddrWidth-1:0] imem_araddr;
  logic [7:0]              imem_arlen;
  logic [2:0]              imem_arsize;
  logic [1:0]              imem_arburst;
  // sideband: only driven by shakti_eclass_wrapper; assigned 0 under USE_ISS
  logic                    imem_arlock;
  logic [3:0]              imem_arcache;
  logic [2:0]              imem_arprot;
  logic                    imem_rvalid, imem_rready;
  logic [AxiIdWidth-1:0]   imem_rid;
  logic [AxiDataWidth-1:0] imem_rdata;
  logic [1:0]              imem_rresp;
  logic                    imem_rlast;

  logic                        dmem_awvalid, dmem_awready;
  logic [AxiIdWidth-1:0]       dmem_awid;
  logic [AxiAddrWidth-1:0]     dmem_awaddr;
  logic [7:0]                  dmem_awlen;
  logic [2:0]                  dmem_awsize;
  logic [1:0]                  dmem_awburst;
  logic                        dmem_wvalid, dmem_wready;
  logic [AxiDataWidth-1:0]     dmem_wdata;
  logic [(AxiDataWidth/8)-1:0] dmem_wstrb;
  logic                        dmem_wlast;
  logic                        dmem_bvalid, dmem_bready;
  logic [AxiIdWidth-1:0]       dmem_bid;
  logic [1:0]                  dmem_bresp;
  logic                        dmem_arvalid, dmem_arready;
  logic [AxiIdWidth-1:0]       dmem_arid;
  logic [AxiAddrWidth-1:0]     dmem_araddr;
  logic [7:0]                  dmem_arlen;
  logic [2:0]                  dmem_arsize;
  logic [1:0]                  dmem_arburst;
  logic                        dmem_rvalid, dmem_rready;
  logic [AxiIdWidth-1:0]       dmem_rid;
  logic [AxiDataWidth-1:0]     dmem_rdata;
  logic [1:0]                  dmem_rresp;
  logic                        dmem_rlast;

  // ==========================================================================
  // Interrupt wires (declared here; driven by peripheral subsystem below)
  // ==========================================================================
  // Level-2 (t1_periph_ss_32): timer_irq_o → timer_irq, ext_irq_o → ext_irq
  // Level-1 (t1_periph_ss_l1): uart_irq_o → ext_irq;  timer_irq = 0
  logic timer_irq, ext_irq;

  // CPU halt
  logic cpu_halt;
  assign halt_o = cpu_halt;

  // JTAG always tied off
  assign jtag_tdo_o    = 1'b0;
  assign jtag_tdo_oe_o = 1'b0;

  // ==========================================================================
  // CPU: rv32i_iss (USE_ISS) or shakti_eclass_wrapper (stub / real BSV)
  // ==========================================================================
`ifdef USE_ISS
  // rv32i_iss has no arlock/arcache/arprot ports; drive sideband to safe values.
  assign imem_arlock  = 1'b0;
  assign imem_arcache = 4'b0;
  assign imem_arprot  = 3'b0;

  rv32i_iss #(
    .BootAddr   ( BOOT_ADDR  ),
    .AxiIdWidth ( AxiIdWidth )
  ) u_cpu (
    .clk_i,
    .rst_ni,
    .imem_arvalid_o ( imem_arvalid ),
    .imem_arready_i ( imem_arready ),
    .imem_arid_o    ( imem_arid    ),
    .imem_araddr_o  ( imem_araddr  ),
    .imem_arlen_o   ( imem_arlen   ),
    .imem_arsize_o  ( imem_arsize  ),
    .imem_arburst_o ( imem_arburst ),
    .imem_rvalid_i  ( imem_rvalid  ),
    .imem_rready_o  ( imem_rready  ),
    .imem_rid_i     ( imem_rid     ),
    .imem_rdata_i   ( imem_rdata   ),
    .imem_rresp_i   ( imem_rresp   ),
    .imem_rlast_i   ( imem_rlast   ),
    .dmem_awvalid_o ( dmem_awvalid ),
    .dmem_awready_i ( dmem_awready ),
    .dmem_awid_o    ( dmem_awid    ),
    .dmem_awaddr_o  ( dmem_awaddr  ),
    .dmem_awlen_o   ( dmem_awlen   ),
    .dmem_awsize_o  ( dmem_awsize  ),
    .dmem_awburst_o ( dmem_awburst ),
    .dmem_wvalid_o  ( dmem_wvalid  ),
    .dmem_wready_i  ( dmem_wready  ),
    .dmem_wdata_o   ( dmem_wdata   ),
    .dmem_wstrb_o   ( dmem_wstrb   ),
    .dmem_wlast_o   ( dmem_wlast   ),
    .dmem_bvalid_i  ( dmem_bvalid  ),
    .dmem_bready_o  ( dmem_bready  ),
    .dmem_bid_i     ( dmem_bid     ),
    .dmem_bresp_i   ( dmem_bresp   ),
    .dmem_arvalid_o ( dmem_arvalid ),
    .dmem_arready_i ( dmem_arready ),
    .dmem_arid_o    ( dmem_arid    ),
    .dmem_araddr_o  ( dmem_araddr  ),
    .dmem_arlen_o   ( dmem_arlen   ),
    .dmem_arsize_o  ( dmem_arsize  ),
    .dmem_arburst_o ( dmem_arburst ),
    .dmem_rvalid_i  ( dmem_rvalid  ),
    .dmem_rready_o  ( dmem_rready  ),
    .dmem_rid_i     ( dmem_rid     ),
    .dmem_rdata_i   ( dmem_rdata   ),
    .dmem_rresp_i   ( dmem_rresp   ),
    .dmem_rlast_i   ( dmem_rlast   ),
    .halt_o         ( cpu_halt     )
  );

`else
  // shakti_eclass_wrapper: non-executing BSV stub in sim;
  // replace its body with mkE_Class for FPGA/ASIC.
  assign cpu_halt = 1'b0;

  shakti_eclass_wrapper #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidth   ),
    .BootAddr     ( BOOT_ADDR    )
  ) u_cpu (
    .clk_i,
    .rst_ni,
    .irq_m_ext_i   ( ext_irq   ),
    .irq_m_timer_i ( timer_irq ),
    .irq_m_soft_i  ( 1'b0      ),
    .debug_req_i   ( 1'b0      ),
    .imem_arvalid_o ( imem_arvalid ),
    .imem_arready_i ( imem_arready ),
    .imem_arid_o    ( imem_arid    ),
    .imem_araddr_o  ( imem_araddr  ),
    .imem_arlen_o   ( imem_arlen   ),
    .imem_arsize_o  ( imem_arsize  ),
    .imem_arburst_o ( imem_arburst ),
    .imem_arlock_o  ( imem_arlock  ),
    .imem_arcache_o ( imem_arcache ),
    .imem_arprot_o  ( imem_arprot  ),
    .imem_rvalid_i  ( imem_rvalid  ),
    .imem_rready_o  ( imem_rready  ),
    .imem_rid_i     ( imem_rid     ),
    .imem_rdata_i   ( imem_rdata   ),
    .imem_rresp_i   ( imem_rresp   ),
    .imem_rlast_i   ( imem_rlast   ),
    .dmem_awvalid_o ( dmem_awvalid ),
    .dmem_awready_i ( dmem_awready ),
    .dmem_awid_o    ( dmem_awid    ),
    .dmem_awaddr_o  ( dmem_awaddr  ),
    .dmem_awlen_o   ( dmem_awlen   ),
    .dmem_awsize_o  ( dmem_awsize  ),
    .dmem_awburst_o ( dmem_awburst ),
    .dmem_wvalid_o  ( dmem_wvalid  ),
    .dmem_wready_i  ( dmem_wready  ),
    .dmem_wdata_o   ( dmem_wdata   ),
    .dmem_wstrb_o   ( dmem_wstrb   ),
    .dmem_wlast_o   ( dmem_wlast   ),
    .dmem_bvalid_i  ( dmem_bvalid  ),
    .dmem_bready_o  ( dmem_bready  ),
    .dmem_bid_i     ( dmem_bid     ),
    .dmem_bresp_i   ( dmem_bresp   ),
    .dmem_arvalid_o ( dmem_arvalid ),
    .dmem_arready_i ( dmem_arready ),
    .dmem_arid_o    ( dmem_arid    ),
    .dmem_araddr_o  ( dmem_araddr  ),
    .dmem_arlen_o   ( dmem_arlen   ),
    .dmem_arsize_o  ( dmem_arsize  ),
    .dmem_arburst_o ( dmem_arburst ),
    .dmem_rvalid_i  ( dmem_rvalid  ),
    .dmem_rready_o  ( dmem_rready  ),
    .dmem_rid_i     ( dmem_rid     ),
    .dmem_rdata_i   ( dmem_rdata   ),
    .dmem_rresp_i   ( dmem_rresp   ),
    .dmem_rlast_i   ( dmem_rlast   )
  );
`endif  // USE_ISS

  // ==========================================================================
  // Level-2: 3-slave bus (ROM + SRAM + Periph) — Boot ROM, 128 KB SRAM,
  //          full peripheral set (UART / 32-bit GPIO / SPI / I2C / timers)
  // ==========================================================================
`ifdef LEVEL2

  logic                        rom_arvalid,  rom_arready;
  logic [AxiIdWidth-1:0]       rom_arid;
  logic [AxiAddrWidth-1:0]     rom_araddr;
  logic [7:0]                  rom_arlen;
  logic [2:0]                  rom_arsize;
  logic [1:0]                  rom_arburst;
  logic                        rom_rvalid,   rom_rready;
  logic [AxiIdWidth-1:0]       rom_rid;
  logic [AxiDataWidth-1:0]     rom_rdata;
  logic [1:0]                  rom_rresp;
  logic                        rom_rlast;

  logic                        sram_awvalid, sram_awready;
  logic [AxiIdWidth-1:0]       sram_awid;
  logic [AxiAddrWidth-1:0]     sram_awaddr;
  logic [7:0]                  sram_awlen;
  logic [2:0]                  sram_awsize;
  logic [1:0]                  sram_awburst;
  logic                        sram_wvalid,  sram_wready;
  logic [AxiDataWidth-1:0]     sram_wdata;
  logic [(AxiDataWidth/8)-1:0] sram_wstrb;
  logic                        sram_wlast;
  logic                        sram_bvalid,  sram_bready;
  logic [AxiIdWidth-1:0]       sram_bid;
  logic [1:0]                  sram_bresp;
  logic                        sram_arvalid, sram_arready;
  logic [AxiIdWidth-1:0]       sram_arid;
  logic [AxiAddrWidth-1:0]     sram_araddr;
  logic [7:0]                  sram_arlen;
  logic [2:0]                  sram_arsize;
  logic [1:0]                  sram_arburst;
  logic                        sram_rvalid,  sram_rready;
  logic [AxiIdWidth-1:0]       sram_rid;
  logic [AxiDataWidth-1:0]     sram_rdata;
  logic [1:0]                  sram_rresp;
  logic                        sram_rlast;

  logic                        periph_awvalid, periph_awready;
  logic [AxiIdWidth-1:0]       periph_awid;
  logic [AxiAddrWidth-1:0]     periph_awaddr;
  logic [7:0]                  periph_awlen;
  logic [2:0]                  periph_awsize;
  logic [1:0]                  periph_awburst;
  logic                        periph_wvalid,  periph_wready;
  logic [AxiDataWidth-1:0]     periph_wdata;
  logic [(AxiDataWidth/8)-1:0] periph_wstrb;
  logic                        periph_wlast;
  logic                        periph_bvalid,  periph_bready;
  logic [AxiIdWidth-1:0]       periph_bid;
  logic [1:0]                  periph_bresp;
  logic                        periph_arvalid, periph_arready;
  logic [AxiIdWidth-1:0]       periph_arid;
  logic [AxiAddrWidth-1:0]     periph_araddr;
  logic [7:0]                  periph_arlen;
  logic [2:0]                  periph_arsize;
  logic [1:0]                  periph_arburst;
  logic                        periph_rvalid,  periph_rready;
  logic [AxiIdWidth-1:0]       periph_rid;
  logic [AxiDataWidth-1:0]     periph_rdata;
  logic [1:0]                  periph_rresp;
  logic                        periph_rlast;

  // 2-master × 3-slave crossbar
  t1_xbar_32 #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidth   )
  ) u_xbar (
    .clk_i,
    .rst_ni,
    .imem_arvalid_i ( imem_arvalid ),
    .imem_arready_o ( imem_arready ),
    .imem_arid_i    ( imem_arid    ),
    .imem_araddr_i  ( imem_araddr  ),
    .imem_arlen_i   ( imem_arlen   ),
    .imem_arsize_i  ( imem_arsize  ),
    .imem_arburst_i ( imem_arburst ),
    .imem_rvalid_o  ( imem_rvalid  ),
    .imem_rready_i  ( imem_rready  ),
    .imem_rid_o     ( imem_rid     ),
    .imem_rdata_o   ( imem_rdata   ),
    .imem_rresp_o   ( imem_rresp   ),
    .imem_rlast_o   ( imem_rlast   ),
    .dmem_awvalid_i ( dmem_awvalid ),
    .dmem_awready_o ( dmem_awready ),
    .dmem_awid_i    ( dmem_awid    ),
    .dmem_awaddr_i  ( dmem_awaddr  ),
    .dmem_awlen_i   ( dmem_awlen   ),
    .dmem_awsize_i  ( dmem_awsize  ),
    .dmem_awburst_i ( dmem_awburst ),
    .dmem_wvalid_i  ( dmem_wvalid  ),
    .dmem_wready_o  ( dmem_wready  ),
    .dmem_wdata_i   ( dmem_wdata   ),
    .dmem_wstrb_i   ( dmem_wstrb   ),
    .dmem_wlast_i   ( dmem_wlast   ),
    .dmem_bvalid_o  ( dmem_bvalid  ),
    .dmem_bready_i  ( dmem_bready  ),
    .dmem_bid_o     ( dmem_bid     ),
    .dmem_bresp_o   ( dmem_bresp   ),
    .dmem_arvalid_i ( dmem_arvalid ),
    .dmem_arready_o ( dmem_arready ),
    .dmem_arid_i    ( dmem_arid    ),
    .dmem_araddr_i  ( dmem_araddr  ),
    .dmem_arlen_i   ( dmem_arlen   ),
    .dmem_arsize_i  ( dmem_arsize  ),
    .dmem_arburst_i ( dmem_arburst ),
    .dmem_rvalid_o  ( dmem_rvalid  ),
    .dmem_rready_i  ( dmem_rready  ),
    .dmem_rid_o     ( dmem_rid     ),
    .dmem_rdata_o   ( dmem_rdata   ),
    .dmem_rresp_o   ( dmem_rresp   ),
    .dmem_rlast_o   ( dmem_rlast   ),
    .rom_arvalid_o  ( rom_arvalid  ),
    .rom_arready_i  ( rom_arready  ),
    .rom_arid_o     ( rom_arid     ),
    .rom_araddr_o   ( rom_araddr   ),
    .rom_arlen_o    ( rom_arlen    ),
    .rom_arsize_o   ( rom_arsize   ),
    .rom_arburst_o  ( rom_arburst  ),
    .rom_rvalid_i   ( rom_rvalid   ),
    .rom_rready_o   ( rom_rready   ),
    .rom_rid_i      ( rom_rid      ),
    .rom_rdata_i    ( rom_rdata    ),
    .rom_rresp_i    ( rom_rresp    ),
    .rom_rlast_i    ( rom_rlast    ),
    .sram_awvalid_o ( sram_awvalid ),
    .sram_awready_i ( sram_awready ),
    .sram_awid_o    ( sram_awid    ),
    .sram_awaddr_o  ( sram_awaddr  ),
    .sram_awlen_o   ( sram_awlen   ),
    .sram_awsize_o  ( sram_awsize  ),
    .sram_awburst_o ( sram_awburst ),
    .sram_wvalid_o  ( sram_wvalid  ),
    .sram_wready_i  ( sram_wready  ),
    .sram_wdata_o   ( sram_wdata   ),
    .sram_wstrb_o   ( sram_wstrb   ),
    .sram_wlast_o   ( sram_wlast   ),
    .sram_bvalid_i  ( sram_bvalid  ),
    .sram_bready_o  ( sram_bready  ),
    .sram_bid_i     ( sram_bid     ),
    .sram_bresp_i   ( sram_bresp   ),
    .sram_arvalid_o ( sram_arvalid ),
    .sram_arready_i ( sram_arready ),
    .sram_arid_o    ( sram_arid    ),
    .sram_araddr_o  ( sram_araddr  ),
    .sram_arlen_o   ( sram_arlen   ),
    .sram_arsize_o  ( sram_arsize  ),
    .sram_arburst_o ( sram_arburst ),
    .sram_rvalid_i  ( sram_rvalid  ),
    .sram_rready_o  ( sram_rready  ),
    .sram_rid_i     ( sram_rid     ),
    .sram_rdata_i   ( sram_rdata   ),
    .sram_rresp_i   ( sram_rresp   ),
    .sram_rlast_i   ( sram_rlast   ),
    .periph_awvalid_o ( periph_awvalid ),
    .periph_awready_i ( periph_awready ),
    .periph_awid_o    ( periph_awid    ),
    .periph_awaddr_o  ( periph_awaddr  ),
    .periph_awlen_o   ( periph_awlen   ),
    .periph_awsize_o  ( periph_awsize  ),
    .periph_awburst_o ( periph_awburst ),
    .periph_wvalid_o  ( periph_wvalid  ),
    .periph_wready_i  ( periph_wready  ),
    .periph_wdata_o   ( periph_wdata   ),
    .periph_wstrb_o   ( periph_wstrb   ),
    .periph_wlast_o   ( periph_wlast   ),
    .periph_bvalid_i  ( periph_bvalid  ),
    .periph_bready_o  ( periph_bready  ),
    .periph_bid_i     ( periph_bid     ),
    .periph_bresp_i   ( periph_bresp   ),
    .periph_arvalid_o ( periph_arvalid ),
    .periph_arready_i ( periph_arready ),
    .periph_arid_o    ( periph_arid    ),
    .periph_araddr_o  ( periph_araddr  ),
    .periph_arlen_o   ( periph_arlen   ),
    .periph_arsize_o  ( periph_arsize  ),
    .periph_arburst_o ( periph_arburst ),
    .periph_rvalid_i  ( periph_rvalid  ),
    .periph_rready_o  ( periph_rready  ),
    .periph_rid_i     ( periph_rid     ),
    .periph_rdata_i   ( periph_rdata   ),
    .periph_rresp_i   ( periph_rresp   ),
    .periph_rlast_i   ( periph_rlast   )
  );

  // Boot ROM (3-instruction jump sequence)
  t1_boot_rom_32 #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidth   ),
    .RomDepth     ( RomDepth     )
  ) u_boot_rom (
    .clk_i,
    .rst_ni,
    .arvalid_i ( rom_arvalid ),
    .arready_o ( rom_arready ),
    .arid_i    ( rom_arid    ),
    .araddr_i  ( rom_araddr  ),
    .arlen_i   ( rom_arlen   ),
    .arsize_i  ( rom_arsize  ),
    .arburst_i ( rom_arburst ),
    .rvalid_o  ( rom_rvalid  ),
    .rready_i  ( rom_rready  ),
    .rid_o     ( rom_rid     ),
    .rdata_o   ( rom_rdata   ),
    .rresp_o   ( rom_rresp   ),
    .rlast_o   ( rom_rlast   ),
    .awvalid_i ( 1'b0  ),
    .awready_o (       ),
    .wvalid_i  ( 1'b0  ),
    .wready_o  (       ),
    .bvalid_o  (       ),
    .bready_i  ( 1'b1  ),
    .bid_o     (       ),
    .bresp_o   (       )
  );

  // SRAM (128 KB)
  t1_sram_top_32 #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidth   ),
    .NumWords     ( SRAM_WORDS   )
  ) u_sram (
    .clk_i,
    .rst_ni,
    .awvalid_i ( sram_awvalid ),
    .awready_o ( sram_awready ),
    .awid_i    ( sram_awid    ),
    .awaddr_i  ( sram_awaddr  ),
    .awlen_i   ( sram_awlen   ),
    .awsize_i  ( sram_awsize  ),
    .awburst_i ( sram_awburst ),
    .wvalid_i  ( sram_wvalid  ),
    .wready_o  ( sram_wready  ),
    .wdata_i   ( sram_wdata   ),
    .wstrb_i   ( sram_wstrb   ),
    .wlast_i   ( sram_wlast   ),
    .bvalid_o  ( sram_bvalid  ),
    .bready_i  ( sram_bready  ),
    .bid_o     ( sram_bid     ),
    .bresp_o   ( sram_bresp   ),
    .arvalid_i ( sram_arvalid ),
    .arready_o ( sram_arready ),
    .arid_i    ( sram_arid    ),
    .araddr_i  ( sram_araddr  ),
    .arlen_i   ( sram_arlen   ),
    .arsize_i  ( sram_arsize  ),
    .arburst_i ( sram_arburst ),
    .rvalid_o  ( sram_rvalid  ),
    .rready_i  ( sram_rready  ),
    .rid_o     ( sram_rid     ),
    .rdata_o   ( sram_rdata   ),
    .rresp_o   ( sram_rresp   ),
    .rlast_o   ( sram_rlast   )
  );

  // Peripheral subsystem: UART / 32-bit GPIO / SPI / I2C / timers / PLIC
  t1_periph_ss_32 #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidth   )
  ) u_periph (
    .clk_i,
    .rst_ni,
    .awvalid_i  ( periph_awvalid ),
    .awready_o  ( periph_awready ),
    .awid_i     ( periph_awid    ),
    .awaddr_i   ( periph_awaddr  ),
    .awlen_i    ( periph_awlen   ),
    .awsize_i   ( periph_awsize  ),
    .awburst_i  ( periph_awburst ),
    .wvalid_i   ( periph_wvalid  ),
    .wready_o   ( periph_wready  ),
    .wdata_i    ( periph_wdata   ),
    .wstrb_i    ( periph_wstrb   ),
    .wlast_i    ( periph_wlast   ),
    .bvalid_o   ( periph_bvalid  ),
    .bready_i   ( periph_bready  ),
    .bid_o      ( periph_bid     ),
    .bresp_o    ( periph_bresp   ),
    .arvalid_i  ( periph_arvalid ),
    .arready_o  ( periph_arready ),
    .arid_i     ( periph_arid    ),
    .araddr_i   ( periph_araddr  ),
    .arlen_i    ( periph_arlen   ),
    .arsize_i   ( periph_arsize  ),
    .arburst_i  ( periph_arburst ),
    .rvalid_o   ( periph_rvalid  ),
    .rready_i   ( periph_rready  ),
    .rid_o      ( periph_rid     ),
    .rdata_o    ( periph_rdata   ),
    .rresp_o    ( periph_rresp   ),
    .rlast_o    ( periph_rlast   ),
    .uart_tx_o,
    .uart_rx_i,
    .gpio_out_o,
    .gpio_oe_o,
    .gpio_in_i,
    .spi_sck_o,
    .spi_csb_o,
    .spi_sd_i,
    .spi_sd_o,
    .i2c_scl_o(i2c_scl_o),
    .i2c_scl_i(i2c_scl_i),
    .i2c_sda_o(i2c_sda_o),
    .i2c_sda_i(i2c_sda_i),
    .timer_irq_o ( timer_irq ),
    .ext_irq_o   ( ext_irq   )
  );

`else
  // ==========================================================================
  // Level-1: 2-slave bus (SRAM + Periph) — No Boot ROM, 4 KB SRAM,
  //          UART + 16-bit GPIO only.  SPI / I2C / upper GPIO tied off.
  // ==========================================================================

  logic                        sram_awvalid, sram_awready;
  logic [AxiIdWidth-1:0]       sram_awid;
  logic [AxiAddrWidth-1:0]     sram_awaddr;
  logic [7:0]                  sram_awlen;
  logic [2:0]                  sram_awsize;
  logic [1:0]                  sram_awburst;
  logic                        sram_wvalid,  sram_wready;
  logic [AxiDataWidth-1:0]     sram_wdata;
  logic [(AxiDataWidth/8)-1:0] sram_wstrb;
  logic                        sram_wlast;
  logic                        sram_bvalid,  sram_bready;
  logic [AxiIdWidth-1:0]       sram_bid;
  logic [1:0]                  sram_bresp;
  logic                        sram_arvalid, sram_arready;
  logic [AxiIdWidth-1:0]       sram_arid;
  logic [AxiAddrWidth-1:0]     sram_araddr;
  logic [7:0]                  sram_arlen;
  logic [2:0]                  sram_arsize;
  logic [1:0]                  sram_arburst;
  logic                        sram_rvalid,  sram_rready;
  logic [AxiIdWidth-1:0]       sram_rid;
  logic [AxiDataWidth-1:0]     sram_rdata;
  logic [1:0]                  sram_rresp;
  logic                        sram_rlast;

  logic                        periph_awvalid, periph_awready;
  logic [AxiIdWidth-1:0]       periph_awid;
  logic [AxiAddrWidth-1:0]     periph_awaddr;
  logic [7:0]                  periph_awlen;
  logic [2:0]                  periph_awsize;
  logic [1:0]                  periph_awburst;
  logic                        periph_wvalid,  periph_wready;
  logic [AxiDataWidth-1:0]     periph_wdata;
  logic [(AxiDataWidth/8)-1:0] periph_wstrb;
  logic                        periph_wlast;
  logic                        periph_bvalid,  periph_bready;
  logic [AxiIdWidth-1:0]       periph_bid;
  logic [1:0]                  periph_bresp;
  logic                        periph_arvalid, periph_arready;
  logic [AxiIdWidth-1:0]       periph_arid;
  logic [AxiAddrWidth-1:0]     periph_araddr;
  logic [7:0]                  periph_arlen;
  logic [2:0]                  periph_arsize;
  logic [1:0]                  periph_arburst;
  logic                        periph_rvalid,  periph_rready;
  logic [AxiIdWidth-1:0]       periph_rid;
  logic [AxiDataWidth-1:0]     periph_rdata;
  logic [1:0]                  periph_rresp;
  logic                        periph_rlast;

  logic uart_irq_l1;
  assign timer_irq = 1'b0;        // no timer in Level-1 peripheral subsystem
  assign ext_irq   = uart_irq_l1; // UART interrupt as external interrupt

  // 2-master × 2-slave bus (SRAM + Periph; no Boot ROM port)
  t1_bus_l1 #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidth   )
  ) u_bus (
    .clk_i,
    .rst_ni,
    .imem_arvalid_i ( imem_arvalid ),
    .imem_arready_o ( imem_arready ),
    .imem_arid_i    ( imem_arid    ),
    .imem_araddr_i  ( imem_araddr  ),
    .imem_arlen_i   ( imem_arlen   ),
    .imem_arsize_i  ( imem_arsize  ),
    .imem_arburst_i ( imem_arburst ),
    .imem_rvalid_o  ( imem_rvalid  ),
    .imem_rready_i  ( imem_rready  ),
    .imem_rid_o     ( imem_rid     ),
    .imem_rdata_o   ( imem_rdata   ),
    .imem_rresp_o   ( imem_rresp   ),
    .imem_rlast_o   ( imem_rlast   ),
    .dmem_awvalid_i ( dmem_awvalid ),
    .dmem_awready_o ( dmem_awready ),
    .dmem_awid_i    ( dmem_awid    ),
    .dmem_awaddr_i  ( dmem_awaddr  ),
    .dmem_awlen_i   ( dmem_awlen   ),
    .dmem_awsize_i  ( dmem_awsize  ),
    .dmem_awburst_i ( dmem_awburst ),
    .dmem_wvalid_i  ( dmem_wvalid  ),
    .dmem_wready_o  ( dmem_wready  ),
    .dmem_wdata_i   ( dmem_wdata   ),
    .dmem_wstrb_i   ( dmem_wstrb   ),
    .dmem_wlast_i   ( dmem_wlast   ),
    .dmem_bvalid_o  ( dmem_bvalid  ),
    .dmem_bready_i  ( dmem_bready  ),
    .dmem_bid_o     ( dmem_bid     ),
    .dmem_bresp_o   ( dmem_bresp   ),
    .dmem_arvalid_i ( dmem_arvalid ),
    .dmem_arready_o ( dmem_arready ),
    .dmem_arid_i    ( dmem_arid    ),
    .dmem_araddr_i  ( dmem_araddr  ),
    .dmem_arlen_i   ( dmem_arlen   ),
    .dmem_arsize_i  ( dmem_arsize  ),
    .dmem_arburst_i ( dmem_arburst ),
    .dmem_rvalid_o  ( dmem_rvalid  ),
    .dmem_rready_i  ( dmem_rready  ),
    .dmem_rid_o     ( dmem_rid     ),
    .dmem_rdata_o   ( dmem_rdata   ),
    .dmem_rresp_o   ( dmem_rresp   ),
    .dmem_rlast_o   ( dmem_rlast   ),
    .sram_awvalid_o ( sram_awvalid ),
    .sram_awready_i ( sram_awready ),
    .sram_awid_o    ( sram_awid    ),
    .sram_awaddr_o  ( sram_awaddr  ),
    .sram_awlen_o   ( sram_awlen   ),
    .sram_awsize_o  ( sram_awsize  ),
    .sram_awburst_o ( sram_awburst ),
    .sram_wvalid_o  ( sram_wvalid  ),
    .sram_wready_i  ( sram_wready  ),
    .sram_wdata_o   ( sram_wdata   ),
    .sram_wstrb_o   ( sram_wstrb   ),
    .sram_wlast_o   ( sram_wlast   ),
    .sram_bvalid_i  ( sram_bvalid  ),
    .sram_bready_o  ( sram_bready  ),
    .sram_bid_i     ( sram_bid     ),
    .sram_bresp_i   ( sram_bresp   ),
    .sram_arvalid_o ( sram_arvalid ),
    .sram_arready_i ( sram_arready ),
    .sram_arid_o    ( sram_arid    ),
    .sram_araddr_o  ( sram_araddr  ),
    .sram_arlen_o   ( sram_arlen   ),
    .sram_arsize_o  ( sram_arsize  ),
    .sram_arburst_o ( sram_arburst ),
    .sram_rvalid_i  ( sram_rvalid  ),
    .sram_rready_o  ( sram_rready  ),
    .sram_rid_i     ( sram_rid     ),
    .sram_rdata_i   ( sram_rdata   ),
    .sram_rresp_i   ( sram_rresp   ),
    .sram_rlast_i   ( sram_rlast   ),
    .periph_awvalid_o ( periph_awvalid ),
    .periph_awready_i ( periph_awready ),
    .periph_awid_o    ( periph_awid    ),
    .periph_awaddr_o  ( periph_awaddr  ),
    .periph_awlen_o   ( periph_awlen   ),
    .periph_awsize_o  ( periph_awsize  ),
    .periph_awburst_o ( periph_awburst ),
    .periph_wvalid_o  ( periph_wvalid  ),
    .periph_wready_i  ( periph_wready  ),
    .periph_wdata_o   ( periph_wdata   ),
    .periph_wstrb_o   ( periph_wstrb   ),
    .periph_wlast_o   ( periph_wlast   ),
    .periph_bvalid_i  ( periph_bvalid  ),
    .periph_bready_o  ( periph_bready  ),
    .periph_bid_i     ( periph_bid     ),
    .periph_bresp_i   ( periph_bresp   ),
    .periph_arvalid_o ( periph_arvalid ),
    .periph_arready_i ( periph_arready ),
    .periph_arid_o    ( periph_arid    ),
    .periph_araddr_o  ( periph_araddr  ),
    .periph_arlen_o   ( periph_arlen   ),
    .periph_arsize_o  ( periph_arsize  ),
    .periph_arburst_o ( periph_arburst ),
    .periph_rvalid_i  ( periph_rvalid  ),
    .periph_rready_o  ( periph_rready  ),
    .periph_rid_i     ( periph_rid     ),
    .periph_rdata_i   ( periph_rdata   ),
    .periph_rresp_i   ( periph_rresp   ),
    .periph_rlast_i   ( periph_rlast   )
  );

  // SRAM (4 KB)
  t1_sram_top_32 #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidth   ),
    .NumWords     ( SRAM_WORDS   )
  ) u_sram (
    .clk_i,
    .rst_ni,
    .awvalid_i ( sram_awvalid ),
    .awready_o ( sram_awready ),
    .awid_i    ( sram_awid    ),
    .awaddr_i  ( sram_awaddr  ),
    .awlen_i   ( sram_awlen   ),
    .awsize_i  ( sram_awsize  ),
    .awburst_i ( sram_awburst ),
    .wvalid_i  ( sram_wvalid  ),
    .wready_o  ( sram_wready  ),
    .wdata_i   ( sram_wdata   ),
    .wstrb_i   ( sram_wstrb   ),
    .wlast_i   ( sram_wlast   ),
    .bvalid_o  ( sram_bvalid  ),
    .bready_i  ( sram_bready  ),
    .bid_o     ( sram_bid     ),
    .bresp_o   ( sram_bresp   ),
    .arvalid_i ( sram_arvalid ),
    .arready_o ( sram_arready ),
    .arid_i    ( sram_arid    ),
    .araddr_i  ( sram_araddr  ),
    .arlen_i   ( sram_arlen   ),
    .arsize_i  ( sram_arsize  ),
    .arburst_i ( sram_arburst ),
    .rvalid_o  ( sram_rvalid  ),
    .rready_i  ( sram_rready  ),
    .rid_o     ( sram_rid     ),
    .rdata_o   ( sram_rdata   ),
    .rresp_o   ( sram_rresp   ),
    .rlast_o   ( sram_rlast   )
  );

  // Peripheral subsystem: UART + 16-bit GPIO only
  t1_periph_ss_l1 #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidth   )
  ) u_periph (
    .clk_i,
    .rst_ni,
    .awvalid_i  ( periph_awvalid ),
    .awready_o  ( periph_awready ),
    .awid_i     ( periph_awid    ),
    .awaddr_i   ( periph_awaddr  ),
    .awlen_i    ( periph_awlen   ),
    .awsize_i   ( periph_awsize  ),
    .awburst_i  ( periph_awburst ),
    .wvalid_i   ( periph_wvalid  ),
    .wready_o   ( periph_wready  ),
    .wdata_i    ( periph_wdata   ),
    .wstrb_i    ( periph_wstrb   ),
    .wlast_i    ( periph_wlast   ),
    .bvalid_o   ( periph_bvalid  ),
    .bready_i   ( periph_bready  ),
    .bid_o      ( periph_bid     ),
    .bresp_o    ( periph_bresp   ),
    .arvalid_i  ( periph_arvalid ),
    .arready_o  ( periph_arready ),
    .arid_i     ( periph_arid    ),
    .araddr_i   ( periph_araddr  ),
    .arlen_i    ( periph_arlen   ),
    .arsize_i   ( periph_arsize  ),
    .arburst_i  ( periph_arburst ),
    .rvalid_o   ( periph_rvalid  ),
    .rready_i   ( periph_rready  ),
    .rid_o      ( periph_rid     ),
    .rdata_o    ( periph_rdata   ),
    .rresp_o    ( periph_rresp   ),
    .rlast_o    ( periph_rlast   ),
    .uart_rx_i,
    .uart_tx_o,
    .gpio_in_i  ( gpio_in_i[15:0]  ),
    .gpio_out_o ( gpio_out_o[15:0] ),
    .gpio_oe_o  ( gpio_oe_o[15:0]  ),
    .uart_irq_o ( uart_irq_l1      )
  );

  // Level-1 tie-offs for upper GPIO bits not driven by t1_periph_ss_l1
  assign gpio_out_o[31:16] = '0;
  assign gpio_oe_o[31:16]  = '0;

`endif  // LEVEL2

endmodule
