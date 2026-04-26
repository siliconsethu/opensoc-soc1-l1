// ============================================================================
// shakti_eclass_wrapper.sv  —  Shakti E-class CPU wrapper
//                               OpenSoC Tier-1
//
// PURPOSE
//   This module presents the AXI4 master interface of the Shakti E-class
//   CPU to the rest of the SoC.  In production it would instantiate the
//   BSV-compiled Verilog core (mkE_Class.v).  In this simulation environment
//   it provides a behavioural stub that drives the AXI4 bus correctly — with
//   proper valid/ready handshaking and no X-propagation — without requiring
//   the BSV toolchain.
//
// REAL CPU (when available)
//   The Shakti E-class is a 3-stage in-order RV32IMAC processor developed at
//   IIT Madras.  Source: https://gitlab.com/shaktiproject/cores/e-class
//   It is written in Bluespec System Verilog (BSV), which compiles to Verilog.
//   The compiled output is a single module named 'mkE_Class'.
//
//   To replace this stub with the real CPU:
//   1. Run the BSV compiler: bsc -verilog -g mkE_Class E_Class.bsv
//   2. Replace the 'Behavioural simulation stub' block below with:
//        mkE_Class u_eclass (
//          .CLK             (clk_i),
//          .RST_N           (rst_ni),
//          .ext_interrupt   (irq_m_ext_i),
//          .timer_interrupt (irq_m_timer_i),
//          .soft_interrupt  (irq_m_soft_i),
//          // ... map remaining AXI ports to imem_*/dmem_* above
//        );
//   3. Verify that the mkE_Class port names match (BSV-generated names differ
//      by version; check the generated .v file for exact port names).
//
// STUB BEHAVIOUR
//   When the real BSV Verilog is unavailable, this stub drives a minimal
//   AXI4 read sequence:
//     1. After reset, immediately issues a single IMEM fetch at BootAddr.
//     2. Repeats the fetch for 16 sequential words (fetch_cnt: 0..15).
//     3. After 16 fetches, enters S_IDLE and stays there indefinitely.
//   This exercises the IMEM AXI4 AR and R channels (arvalid/arready handshake,
//   then rvalid/rready handshake) but does NOT decode or execute instructions.
//   The stub is only used in t1_soc_top_eclass to populate the SoC top level;
//   the CPU boot test (t1_eclass_cpu_tb.sv) bypasses this wrapper entirely
//   and instantiates rv32i_iss.sv directly.
//
// AXI4 INTERFACE
//   Two separate AXI4 master ports:
//     IMEM — instruction fetch (AR + R channels only; AW/W/B never driven)
//     DMEM — data access  (all 5 channels; in this stub, always idle)
//
//   AXI4 channel conventions used throughout:
//     AR  = Address Read    (master → slave: address of read transaction)
//     R   = Read data       (slave → master: data response)
//     AW  = Address Write   (master → slave: address of write transaction)
//     W   = Write data      (master → slave: write data + byte enables)
//     B   = Write response  (slave → master: write acknowledgement)
//
// CPU PARAMETERS
//   BootAddr: Reset Program Counter.  The CPU starts fetching from this address
//             on the first cycle after rst_ni deasserts.
//             For E-class SoC: 0x0001_0000 = Boot ROM base address.
//             The Boot ROM contains a 3-instruction jump sequence to SRAM.
//
// KEY DIFFERENCES FROM CVA6 WRAPPER (cva6_wrapper.sv)
//   - 32-bit data and address (CVA6 uses 64-bit)
//   - RV32IMAC ISA (CVA6 implements RV64GC)
//   - 3-stage in-order pipeline (CVA6 is 6-stage out-of-order)
//   - Two AXI4 master ports: IMEM + DMEM (CVA6 uses a single NoC port)
//   - No hardware FPU (IMAC has no F/D extensions)
//   - Boot address width: 32 bits vs 64 bits
// ============================================================================

`timescale 1ns/1ps

module shakti_eclass_wrapper #(
  // AXI4 address width (32 for RV32; must match crossbar AxiAddrWidth)
  parameter int unsigned AxiAddrWidth = 32,
  // AXI4 data width (32 for RV32; must match crossbar AxiDataWidth)
  parameter int unsigned AxiDataWidth = 32,
  // AXI4 ID field width (4 bits; must match t1_xbar_32 AxiIdWidth)
  parameter int unsigned AxiIdWidth   = 4,
  // AXI4 user signal width (1-bit; unused in this SoC; kept for interface compatibility)
  parameter int unsigned AxiUserWidth = 1,
  // Reset Program Counter — first address the CPU fetches from after reset
  parameter logic [31:0] BootAddr     = 32'h0001_0000
) (
  input  logic clk_i,    // System clock (rising-edge triggered)
  input  logic rst_ni,   // Active-low synchronous reset

  // ── Interrupt inputs ──────────────────────────────────────────────────────
  // These come from the PLIC (Platform-Level Interrupt Controller) and CLINT
  // (Core-Local Interruptor) in the full SoC.  In the stub they are latched
  // but never acted upon; in the real E-class CPU they trigger trap handling.
  input  logic        irq_m_ext_i,    // Machine External Interrupt (PLIC → CPU)
  input  logic        irq_m_timer_i,  // Machine Timer Interrupt    (CLINT mtime ≥ mtimecmp)
  input  logic        irq_m_soft_i,   // Machine Software Interrupt (CLINT msip write)

  // ── Debug interface ───────────────────────────────────────────────────────
  // In the real E-class, this connects to the RISC-V Debug Module (DM) via DMI.
  // The DM asserts debug_req_i to halt the CPU for JTAG debugging.
  // In this stub, the signal is unused.
  input  logic        debug_req_i,

  // ── Instruction Memory AXI4 Master Port (read-only) ──────────────────────
  // Used exclusively for instruction fetches.  In the real CPU this port is
  // the pipeline's instruction cache miss interface (or direct fetch path for
  // a cacheless core like E-class).  Only AR and R channels are used;
  // AW/W/B (write channels) are not present on this port.

  // AR channel: CPU → memory  (instruction fetch address request)
  output logic                        imem_arvalid_o,  // address request is valid
  input  logic                        imem_arready_i,  // memory accepts the request
  output logic [AxiIdWidth-1:0]       imem_arid_o,     // transaction ID (always 0 in stub)
  output logic [AxiAddrWidth-1:0]     imem_araddr_o,   // fetch address (= fetch_addr)
  output logic [7:0]                  imem_arlen_o,    // burst length (0 = 1 beat)
  output logic [2:0]                  imem_arsize_o,   // transfer size (2 = 4 bytes)
  output logic [1:0]                  imem_arburst_o,  // burst type (01 = INCR)
  output logic                        imem_arlock_o,   // exclusive access (0 = normal)
  output logic [3:0]                  imem_arcache_o,  // cache attributes (0010 = normal non-cacheable)
  output logic [2:0]                  imem_arprot_o,   // protection (100 = instruction)

  // R channel: memory → CPU  (instruction fetch data)
  input  logic                        imem_rvalid_i,   // data is valid
  output logic                        imem_rready_o,   // CPU accepts the data
  input  logic [AxiIdWidth-1:0]       imem_rid_i,      // transaction ID (echoed; ignored in stub)
  input  logic [AxiDataWidth-1:0]     imem_rdata_i,    // 32-bit instruction word
  input  logic [1:0]                  imem_rresp_i,    // response code (ignored in stub)
  input  logic                        imem_rlast_i,    // last beat of burst (used to advance fetch)

  // ── Data Memory AXI4 Master Port (read/write) ────────────────────────────
  // Used for all load/store instructions (LB/LH/LW/LBU/LHU, SB/SH/SW).
  // All 5 AXI4 channels are present.  In this stub all DMEM outputs are tied
  // to 0 / idle since the stub never executes any load or store instructions.

  // AW channel: CPU → memory  (store address)
  output logic                        dmem_awvalid_o,  // store address valid (always 0 in stub)
  input  logic                        dmem_awready_i,  // memory accepts store address
  output logic [AxiIdWidth-1:0]       dmem_awid_o,     // transaction ID
  output logic [AxiAddrWidth-1:0]     dmem_awaddr_o,   // store effective address
  output logic [7:0]                  dmem_awlen_o,    // burst length
  output logic [2:0]                  dmem_awsize_o,   // transfer size
  output logic [1:0]                  dmem_awburst_o,  // burst type

  // W channel: CPU → memory  (store data)
  output logic                        dmem_wvalid_o,   // store data valid (always 0 in stub)
  input  logic                        dmem_wready_i,   // memory accepts store data
  output logic [AxiDataWidth-1:0]     dmem_wdata_o,    // write data (byte-replicated for sub-word)
  output logic [(AxiDataWidth/8)-1:0] dmem_wstrb_o,    // byte enable strobes
  output logic                        dmem_wlast_o,    // last beat of burst

  // B channel: memory → CPU  (store response / write acknowledgement)
  input  logic                        dmem_bvalid_i,   // response valid
  output logic                        dmem_bready_o,   // CPU accepts response (always 1 in stub)
  input  logic [AxiIdWidth-1:0]       dmem_bid_i,      // transaction ID
  input  logic [1:0]                  dmem_bresp_i,    // response code (ignored)

  // AR channel: CPU → memory  (load address)
  output logic                        dmem_arvalid_o,  // load address valid (always 0 in stub)
  input  logic                        dmem_arready_i,  // memory accepts load address
  output logic [AxiIdWidth-1:0]       dmem_arid_o,     // transaction ID
  output logic [AxiAddrWidth-1:0]     dmem_araddr_o,   // load effective address
  output logic [7:0]                  dmem_arlen_o,    // burst length
  output logic [2:0]                  dmem_arsize_o,   // transfer size
  output logic [1:0]                  dmem_arburst_o,  // burst type

  // R channel: memory → CPU  (load data)
  input  logic                        dmem_rvalid_i,   // load data valid
  output logic                        dmem_rready_o,   // CPU accepts load data (always 1 in stub)
  input  logic [AxiIdWidth-1:0]       dmem_rid_i,      // transaction ID
  input  logic [AxiDataWidth-1:0]     dmem_rdata_i,    // load data word
  input  logic [1:0]                  dmem_rresp_i,    // response code (ignored)
  input  logic                        dmem_rlast_i     // last beat of burst
);

  // ==========================================================================
  // Behavioural simulation stub
  //
  // RATIONALE
  //   The Shakti E-class RTL is written in Bluespec System Verilog (BSV).
  //   Compiling BSV requires the Bluespec compiler (bsc), which is not part
  //   of the standard VLSI/EDA toolchain available in this environment.
  //   Rather than leave the CPU ports undriven (causing X-propagation and
  //   AXI protocol violations), this stub drives a minimal but protocol-correct
  //   instruction fetch sequence and then idles cleanly.
  //
  // STUB STATE MACHINE
  //   S_RESET  : one-cycle hold; advances to S_IFETCH unconditionally.
  //              Provides a clean registered transition out of reset.
  //
  //   S_IFETCH : Assert imem_arvalid=1 with fetch_addr on imem_araddr.
  //              Wait for the memory (crossbar + Boot ROM) to assert arready.
  //              When arready is seen, advance to S_IWAIT.
  //              The IMEM AR handshake is: arvalid held high until arready seen.
  //
  //   S_IWAIT  : Assert imem_rready=1.  Wait for the memory to assert rvalid.
  //              When rvalid AND rlast are both seen (end of single-beat burst),
  //              increment fetch_cnt and fetch_addr, then:
  //                - If fetch_cnt < 15: go back to S_IFETCH (next word)
  //                - If fetch_cnt == 15: go to S_IDLE (16 words fetched)
  //
  //   S_IDLE   : All AXI outputs de-asserted (imem_arvalid=0, rready=0).
  //              DMEM outputs were never asserted.
  //              The stub stays here permanently.  The testbench for the
  //              SoC-level tests (t1_eclass_tb_top.sv etc.) detects the idle
  //              state and declares the smoke test complete after the required
  //              number of run cycles.
  //
  //   S_DFETCH, S_DWAIT : Reserved states for optional DMEM exercises.
  //              Currently unreachable in the default stub flow.
  //
  // NOTE: This stub is NOT used by the CPU boot test (t1_eclass_cpu_tb.sv).
  //       That testbench instantiates rv32i_iss.sv directly and does not go
  //       through t1_soc_top_eclass or this wrapper.
  // ==========================================================================

  // ── State encoding ────────────────────────────────────────────────────────
  // A 3-bit enum covers 6 named states.  QuestaSim shows the symbolic name
  // in waveform views, making it easier to trace the fetch sequence.
  typedef enum logic [2:0] {
    S_RESET,   // One cycle after reset before starting fetch
    S_IFETCH,  // Instruction fetch: driving AR valid
    S_IWAIT,   // Waiting for R valid (instruction data from memory)
    S_IDLE,    // All fetches complete; CPU stub idles
    S_DFETCH,  // (Reserved) Data fetch AR channel
    S_DWAIT    // (Reserved) Data fetch R channel
  } cpu_state_e;

  // ── Registered state ─────────────────────────────────────────────────────
  cpu_state_e              state;       // Current state
  logic [AxiAddrWidth-1:0] fetch_addr;  // Current fetch address (starts at BootAddr)
  logic [3:0]              fetch_cnt;   // Number of completed fetches (0..15)

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Synchronous reset: start at S_RESET with PC = BootAddr.
      // fetch_cnt=0 means 0 fetches have completed; the first fetch will be
      // for BootAddr = 0x0001_0000 (Boot ROM word 0).
      state      <= S_RESET;
      fetch_addr <= BootAddr;
      fetch_cnt  <= '0;
    end else begin
      case (state)

        // ── S_RESET ─────────────────────────────────────────────────────
        // Extra one-cycle buffer after reset to allow downstream logic
        // (crossbar, ROM) to also complete their reset before seeing arvalid.
        S_RESET: state <= S_IFETCH;

        // ── S_IFETCH ────────────────────────────────────────────────────
        // Hold imem_arvalid=1 (driven by the continuous assign below)
        // with the current fetch_addr.  Move to S_IWAIT only when the
        // slave asserts arready (AXI4 handshake rule: both valid and ready
        // must be high in the same cycle to complete the transfer).
        S_IFETCH: begin
          if (imem_arready_i) begin
            state <= S_IWAIT;
            // Note: fetch_addr is NOT advanced here.  It is advanced only
            // after the data arrives, so that if arready takes multiple
            // cycles the address remains stable.
          end
        end

        // ── S_IWAIT ─────────────────────────────────────────────────────
        // Hold imem_rready=1 and wait for the instruction data.
        // The Boot ROM asserts rvalid one cycle after accepting the AR.
        // The condition 'rvalid AND rlast' detects the end of the single-beat
        // burst (for a single-beat transfer, rlast must be 1 on the last — and
        // only — data beat; we check both to be protocol-correct).
        S_IWAIT: begin
          if (imem_rvalid_i && imem_rlast_i) begin
            // One more fetch completed: increment counter and advance address.
            fetch_cnt  <= fetch_cnt + 1;
            fetch_addr <= fetch_addr + 4;   // next word = +4 bytes

            // After 16 fetches (fetch_cnt 0..15 → 16 completions), idle.
            // This is a deliberate cutoff; the real CPU would execute code.
            if (fetch_cnt >= 4'hF)
              state <= S_IDLE;
            else
              state <= S_IFETCH;  // go fetch the next word
          end
        end

        // ── S_IDLE ──────────────────────────────────────────────────────
        // All outputs de-asserted.  The stub stays here permanently.
        // The smoke tests (t1_smoke_test, t1_sram_test, etc.) that use
        // t1_soc_top_eclass as DUT simply run for a fixed number of cycles
        // and then check that the AXI signals were exercised correctly.
        S_IDLE: state <= S_IDLE;

        // Safety: any unexpected state encoding → go idle
        default: state <= S_IDLE;

      endcase
    end
  end

  // ── Instruction memory (IMEM) AXI4 output assignments ─────────────────────
  //
  // AR channel: valid only in S_IFETCH; address held stable at fetch_addr.
  // The other AR fields are constant:
  //   ARID=0       : single outstanding transaction, always ID 0
  //   ARLEN=0      : single-beat burst (length = ARLEN+1 = 1 beat)
  //   ARSIZE=2     : 4 bytes per beat (32-bit word)
  //   ARBURST=INCR : required for single-beat transfers
  //   ARLOCK=0     : normal (non-exclusive) access
  //   ARCACHE=0010 : Normal Non-cacheable Non-bufferable
  //                  (bit 1 = Modifiable; bits 3,2,0 = 0)
  //   ARPROT=100   : Instruction fetch (bit 2 = 1), Secure, Unprivileged
  assign imem_arvalid_o = (state == S_IFETCH);
  assign imem_arid_o    = '0;
  assign imem_araddr_o  = fetch_addr;
  assign imem_arlen_o   = 8'h00;        // 1 beat
  assign imem_arsize_o  = 3'b010;       // 4 bytes
  assign imem_arburst_o = 2'b01;        // INCR
  assign imem_arlock_o  = 1'b0;         // normal access
  assign imem_arcache_o = 4'b0010;      // normal non-cacheable
  assign imem_arprot_o  = 3'b100;       // instruction, secure, unprivileged

  // R channel: rready asserted only in S_IWAIT (stub is ready to accept data)
  assign imem_rready_o  = (state == S_IWAIT);

  // ── Data memory (DMEM) AXI4 output assignments ────────────────────────────
  //
  // The stub never executes loads or stores, so all DMEM master outputs
  // are permanently driven to 0 (safe idle state).
  //
  // Exception: dmem_bready_o and dmem_rready_o are tied to 1.
  // Rationale: AXI4 requires that a master must eventually assert ready
  // to prevent the slave from stalling indefinitely.  Since the stub drives
  // awvalid=0 and arvalid=0, the slave will never initiate B or R responses,
  // so bready=1 and rready=1 here are harmless and prevent protocol deadlocks
  // if a downstream module speculatively drives bvalid or rvalid.
  assign dmem_awvalid_o = 1'b0;    // no store address
  assign dmem_awid_o    = '0;
  assign dmem_awaddr_o  = '0;
  assign dmem_awlen_o   = '0;
  assign dmem_awsize_o  = '0;
  assign dmem_awburst_o = '0;
  assign dmem_wvalid_o  = 1'b0;    // no store data
  assign dmem_wdata_o   = '0;
  assign dmem_wstrb_o   = '0;
  assign dmem_wlast_o   = 1'b0;
  assign dmem_bready_o  = 1'b1;    // always ready to accept write responses (none will come)
  assign dmem_arvalid_o = 1'b0;    // no load address
  assign dmem_arid_o    = '0;
  assign dmem_araddr_o  = '0;
  assign dmem_arlen_o   = '0;
  assign dmem_arsize_o  = '0;
  assign dmem_arburst_o = '0;
  assign dmem_rready_o  = 1'b1;    // always ready to accept load data (none will come)

endmodule
