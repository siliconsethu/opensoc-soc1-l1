// ============================================================================
// t1_sram_top_32.sv  —  32-bit SRAM subsystem for the Shakti E-class SoC
//                        OpenSoC Tier-1
//
// PURPOSE
//   Provides the main program memory for the E-class SoC.  All code, read-only
//   data, initialised data, BSS (zeroed at runtime by crt0.S), and the stack
//   reside here.  It also contains the TOHOST register at byte offset 0x0FF0
//   from the SRAM base, used by the testbench to detect pass/fail.
//
// PHYSICAL ADDRESS MAPPING
//   Base address : 0x8000_0000
//   Size         : NumWords × 4 bytes = 32768 × 4 = 128 KB
//   End address  : 0x8001_FFFF
//   The crossbar (t1_xbar_32) routes any AR/AW with address in
//   [0x8000_0000, 0x800F_FFFF] to this module's slave ports.
//
// MEMORY LAYOUT (as used by the CPU boot test)
//   0x8000_0000  _start (crt0.S) — first instruction executed after Boot ROM jump
//   0x8000_0000+ .text  — compiled C code (test_arith, test_shift, main, etc.)
//   ...          .rodata — read-only constants (if any)
//   ...          .data   — initialised globals (if any)
//   ...          .bss    — zeroed globals (wbuf, bbuf, hbuf, walkbuf)
//   0x8000_0FF0  TOHOST  — testbench monitors this word; write 1=PASS, n=FAIL
//   0x8000_1000+ (free SRAM above TOHOST, below stack)
//   0x8001_0000  Stack top (sp set by Boot ROM; grows downward)
//
// AXI4 INTERFACE (read/write slave)
//   All 5 AXI4 channels are implemented:
//     AW — write address  (master → SRAM: store address + length)
//     W  — write data     (master → SRAM: write data + byte enables)
//     B  — write response (SRAM → master: acknowledge the write)
//     AR — read address   (master → SRAM: load address + length)
//     R  — read data      (SRAM → master: load data)
//
// BYTE-ENABLE (WSTRB) SUPPORT
//   The SRAM implements byte-granularity writes using the AXI4 WSTRB field.
//   Each bit of wstrb_i corresponds to one byte of the 32-bit data word:
//     wstrb_i[0] → data bits [7:0]   (byte lane 0)
//     wstrb_i[1] → data bits [15:8]  (byte lane 1)
//     wstrb_i[2] → data bits [23:16] (byte lane 2)
//     wstrb_i[3] → data bits [31:24] (byte lane 3)
//   Only bytes with their strobe bit set are written to the array.
//   This supports SB (store byte, strobe=4'b0001 shifted by offset) and
//   SH (store halfword, strobe=4'b0011 shifted) as well as full SW.
//
// WRITE LATENCY (AXI perspective)
//   The write path has a 3-state machine (WR_IDLE → WR_DATA → WR_RESP):
//     Cycle 1: AW handshake (awvalid+awready in same cycle; state→WR_DATA)
//     Cycle 2: W handshake  (wvalid+wready in same cycle; mem write; state→WR_RESP)
//     Cycle 3: B handshake  (bvalid+bready; state→WR_IDLE)
//   Total: 3 cycles from AW accepted to B consumed (minimum, no wait states).
//
// READ LATENCY (AXI perspective)
//   The read path has a 3-state machine (RD_IDLE → RD_WAIT → RD_DATA):
//     Cycle 1: AR handshake (arvalid+arready; state→RD_WAIT; raddr_q captured)
//     Cycle 2: Memory read  (rdata_q ← mem[raddr_q]; state→RD_DATA)
//     Cycle 3: R handshake  (rvalid+rready; state→RD_IDLE)
//   Total: 2 cycles of latency (AR accepted → R data valid), + 1 for handshake.
//   The RD_WAIT state is the 1-cycle SRAM read latency (registered array output).
//
// WHY RD_WAIT IS NEEDED
//   SRAM arrays in FPGAs and standard-cell implementations have a 1-cycle
//   registered output — you present the address, and the data appears on the
//   output registers on the next rising edge.  This module models that behaviour:
//   raddr_q is captured in RD_WAIT, mem[raddr_q] is registered into rdata_q
//   during the RD_WAIT cycle, and rdata_q is presented on rdata_o in RD_DATA.
//   Skipping RD_WAIT would require combinatorial memory reads, which is
//   not representative of real SRAM behaviour.
//
// BURST SUPPORT
//   Both read and write state machines support multi-beat INCR bursts.
//   The beat counter (wbeat_q for writes, rbeat_q for reads) tracks progress.
//   Each accepted beat increments the counter and the word address.
//   For the CPU boot test, only single-beat transactions (ARLEN=0, AWLEN=0)
//   are issued (the ISS issues one word per transaction).  Burst support is
//   exercised by the crossbar path testbench and potentially by cache-line
//   refill in a future cached CPU.
//
// SERIALISATION (writes vs reads)
//   Writes and reads are serialised by the two independent state machines.
//   The SRAM array itself is single-port (one access per cycle).
//   A structural hazard (simultaneous read and write to the same word) could
//   theoretically occur in simulation.  In the CPU boot test this does not
//   happen because the ISS is single-issue sequential — it either fetches OR
//   does a data access, never both simultaneously.
//
// ADDRESS WORD-INDEX CONVERSION
//   AXI addresses are byte addresses.  The SRAM array is word-indexed.
//     word_index = addr[AW+1 : 2]
//   where AW = $clog2(NumWords) = $clog2(32768) = 15.
//   Bits [16:2] give the 15-bit word index (0..32767).
//   Bits [1:0] are the byte-lane offset (0 for word-aligned accesses).
//   Sub-word byte selection is handled by wstrb_i (writes) and w_ld_val in
//   the ISS (reads).
//
// TOHOST DETECTION
//   The testbench (t1_eclass_cpu_tb.sv) accesses the mem[] array directly
//   via a hierarchical reference: u_sram.mem[TOHOST_IDX] where TOHOST_IDX = 1020.
//   This bypasses the AXI interface and reads the underlying register value
//   directly every clock cycle.  The mem[] array must be declared with a
//   visible scope (not inside a generate block or a sub-module).
//
// PARAMETERS
//   AxiAddrWidth : AXI address bus width (32 bits)
//   AxiDataWidth : AXI data bus width    (32 bits = 1 word per beat)
//   AxiIdWidth   : AXI transaction ID width (4 bits; matches crossbar)
//   AxiUserWidth : AXI user signal width (1 bit; unused; interface compatibility)
//   NumWords     : SRAM depth in 32-bit words (default 32768 = 128 KB)
// ============================================================================

`timescale 1ns/1ps

module t1_sram_top_32 #(
  parameter int unsigned AxiAddrWidth = 32,
  parameter int unsigned AxiDataWidth = 32,
  parameter int unsigned AxiIdWidth   = 4,
  parameter int unsigned AxiUserWidth = 1,
  parameter int unsigned NumWords     = 32768   // 128 KB (32 K × 4 B)
) (
  input  logic clk_i,    // System clock (rising-edge triggered)
  input  logic rst_ni,   // Active-low synchronous reset

  // ── AXI4 Write address channel (AW) — store address ──────────────────────
  input  logic                        awvalid_i,  // write address is valid
  output logic                        awready_o,  // SRAM accepts the address (1 when WR_IDLE)
  input  logic [AxiIdWidth-1:0]       awid_i,     // transaction ID (echoed on bid_o)
  input  logic [AxiAddrWidth-1:0]     awaddr_i,   // byte address of the write
  input  logic [7:0]                  awlen_i,    // burst length minus 1
  input  logic [2:0]                  awsize_i,   // transfer size (2=4B; only 4B used)
  input  logic [1:0]                  awburst_i,  // burst type (01=INCR)

  // ── AXI4 Write data channel (W) — store data ──────────────────────────────
  input  logic                        wvalid_i,   // write data is valid
  output logic                        wready_o,   // SRAM accepts the data (1 when WR_DATA)
  input  logic [AxiDataWidth-1:0]     wdata_i,    // 32-bit write data (byte-replicated for SB/SH)
  input  logic [(AxiDataWidth/8)-1:0] wstrb_i,    // byte enable strobes (4 bits)
  input  logic                        wlast_i,    // 1 on last beat of burst

  // ── AXI4 Write response channel (B) — store acknowledgement ──────────────
  output logic                        bvalid_o,   // response is valid (1 when WR_RESP)
  input  logic                        bready_i,   // master accepts the response
  output logic [AxiIdWidth-1:0]       bid_o,      // echoed transaction ID
  output logic [1:0]                  bresp_o,    // response code (always OKAY = 2'b00)

  // ── AXI4 Read address channel (AR) — load address ─────────────────────────
  input  logic                    arvalid_i,  // read address is valid
  output logic                    arready_o,  // SRAM accepts the address (1 when RD_IDLE)
  input  logic [AxiIdWidth-1:0]   arid_i,     // transaction ID
  input  logic [AxiAddrWidth-1:0] araddr_i,   // byte address of the read
  input  logic [7:0]              arlen_i,    // burst length minus 1
  input  logic [2:0]              arsize_i,   // transfer size (2=4B)
  input  logic [1:0]              arburst_i,  // burst type (01=INCR)

  // ── AXI4 Read data channel (R) — load data ────────────────────────────────
  output logic                    rvalid_o,   // data is valid (1 when RD_DATA)
  input  logic                    rready_i,   // master accepts the data
  output logic [AxiIdWidth-1:0]   rid_o,      // echoed transaction ID
  output logic [AxiDataWidth-1:0] rdata_o,    // 32-bit data from SRAM
  output logic [1:0]              rresp_o,    // response code (always OKAY = 2'b00)
  output logic                    rlast_o     // 1 on last beat of burst
);

  // ── Address width for word indexing ──────────────────────────────────────
  // AW = $clog2(32768) = 15 for the default 128 KB SRAM.
  // Word index = addr[AW+1 : 2] = addr[16:2] (15-bit word address).
  localparam int unsigned AW = $clog2(NumWords);

  // ── SRAM storage array ────────────────────────────────────────────────────
  // Declared at module scope so the testbench can access it by hierarchical
  // reference: u_sram.mem[TOHOST_IDX].
  // In simulation this is a register array (not synthesisable as standard SRAM;
  // replace with a technology-specific SRAM macro for physical implementation).
  // The array is zero-initialised at simulation time 0 via the initial block
  // below.  This removes the need for the testbench to write mem[] directly
  // (which triggers vopt-7061 when mem is also driven by always_ff).
  // $readmemh in the testbench is still allowed as a system task.
  logic [AxiDataWidth-1:0] mem [0:NumWords-1];

  // Simulation-only zero-initialisation.  Runs once at time 0, before any
  // always_ff updates, so it does not conflict with the write path.
  // synthesis translate_off
  initial begin
    for (int i = 0; i < NumWords; i++) mem[i] = '0;
  end
  // synthesis translate_on

  // ==========================================================================
  // Write path: AW → WR_DATA → WR_RESP
  // ==========================================================================
  //
  // The write state machine serialises write transactions:
  //   WR_IDLE  — idle; awready=1; accepting AW.
  //   WR_DATA  — waiting for W data beat(s); wready=1.
  //   WR_RESP  — write complete; presenting B response.
  //
  // The beat counter (wbeat_q) and address (waddr_q) are updated per beat
  // to support burst writes.  For single-beat stores (AWLEN=0) the WR_DATA
  // state is entered and exited in one cycle (one W handshake).
  typedef enum logic [1:0] {WR_IDLE, WR_DATA, WR_RESP} wr_state_e;
  wr_state_e             wr_state_q;
  logic [AxiIdWidth-1:0] wid_q;     // captured transaction ID
  logic [AW-1:0]         waddr_q;   // current write word address
  logic [7:0]            wlen_q;    // captured burst length
  logic [7:0]            wbeat_q;   // current beat within the burst

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_state_q <= WR_IDLE;
      wid_q      <= '0;
      waddr_q    <= '0;
      wlen_q     <= '0;
      wbeat_q    <= '0;
    end else case (wr_state_q)
      WR_IDLE: if (awvalid_i) begin
        wr_state_q <= WR_DATA;
        wid_q      <= awid_i;
        waddr_q    <= AW'(awaddr_i[AW+1:2]);
        wlen_q     <= awlen_i;
        wbeat_q    <= '0;
      end
      WR_DATA: if (wvalid_i) begin
        if (wbeat_q == wlen_q) wr_state_q <= WR_RESP;
        else begin wbeat_q <= wbeat_q + 1; waddr_q <= waddr_q + 1; end
      end
      WR_RESP: if (bready_i) wr_state_q <= WR_IDLE;
      default: wr_state_q <= WR_IDLE;
    endcase
  end

  // mem[] is written in a plain always block (not always_ff) so that the
  // simulation-only initial block above can also drive it without triggering
  // QuestaSim vopt-7061 (which forbids any other process from driving a
  // variable owned by always_ff).  Synthesis infers identical flip-flop array.
  always @(posedge clk_i) begin
    if (wr_state_q == WR_DATA && wvalid_i) begin
      for (int b = 0; b < AxiDataWidth/8; b++) begin
        if (wstrb_i[b])
          mem[waddr_q][b*8 +: 8] <= wdata_i[b*8 +: 8];
      end
    end
  end

  // ── Write channel output assignments ──────────────────────────────────────
  // awready: 1 only in WR_IDLE (SRAM can accept a new write address)
  assign awready_o = (wr_state_q == WR_IDLE);
  // wready: 1 only in WR_DATA (SRAM can accept the write data)
  assign wready_o  = (wr_state_q == WR_DATA);
  // bvalid: 1 only in WR_RESP (write response is available)
  assign bvalid_o  = (wr_state_q == WR_RESP);
  assign bid_o     = wid_q;     // echo the captured transaction ID
  assign bresp_o   = 2'b00;    // OKAY — all writes succeed

  // ==========================================================================
  // Read path: AR → RD_WAIT → RD_DATA
  // ==========================================================================
  //
  // The read state machine models the 1-cycle registered SRAM read latency:
  //   RD_IDLE — idle; arready=1; accepting AR.
  //   RD_WAIT — address captured; reading from array into rdata_q (1 cycle).
  //   RD_DATA — data ready on rdata_o; rvalid=1; waiting for master rready.
  //
  // The RD_WAIT state is the 1-cycle pipeline register of a real SRAM:
  //   address presented in RD_WAIT → data valid at the next posedge (RD_DATA).
  // This means there is exactly 1 clock of latency from AR accepted to R valid.
  //
  // For burst reads, after each beat is consumed in RD_DATA, the state
  // transitions back through RD_DATA immediately (skipping RD_WAIT for
  // subsequent beats, since the read latency has already been absorbed by
  // the pipeline — the next beat's data is pre-fetched).
  typedef enum logic [1:0] {RD_IDLE, RD_WAIT, RD_DATA} rd_state_e;
  rd_state_e               rd_state_q;
  logic [AxiIdWidth-1:0]   rid_q;     // captured transaction ID
  logic [AW-1:0]           raddr_q;   // current read word address
  logic [7:0]              rlen_q;    // captured burst length
  logic [7:0]              rbeat_q;   // current beat within the burst
  logic [AxiDataWidth-1:0] rdata_q;   // registered SRAM read data

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_state_q <= RD_IDLE;
      rid_q      <= '0;
      raddr_q    <= '0;
      rlen_q     <= '0;
      rbeat_q    <= '0;
      rdata_q    <= '0;
    end else case (rd_state_q)

      // ── RD_IDLE ──────────────────────────────────────────────────────
      // Wait for a read address request.  On AR handshake, capture
      // transaction parameters and move to RD_WAIT.
      RD_IDLE: if (arvalid_i) begin
        rd_state_q <= RD_WAIT;
        rid_q      <= arid_i;
        raddr_q    <= AW'(araddr_i[AW+1:2]);   // byte addr → word index
        rlen_q     <= arlen_i;
        rbeat_q    <= '0;
      end

      // ── RD_WAIT ──────────────────────────────────────────────────────
      // 1-cycle SRAM read latency: present raddr_q to the array and
      // register the output into rdata_q.  The array read happens
      // combinatorially on this cycle; rdata_q captures it on the next edge.
      // Unconditionally advance to RD_DATA (no handshake in this state).
      RD_WAIT: begin
        rdata_q    <= mem[raddr_q];   // register SRAM output (1-cycle latency)
        rd_state_q <= RD_DATA;
      end

      // ── RD_DATA ──────────────────────────────────────────────────────
      // Present rdata_q (the registered SRAM output) with rvalid=1.
      // Wait for the master to assert rready_i.
      // On the last beat: return to RD_IDLE.
      // For burst reads: advance raddr_q, pre-fetch the next word into
      // rdata_q, and stay in RD_DATA (effectively zero wait states between
      // beats after the initial RD_WAIT latency).
      RD_DATA: if (rready_i) begin
        if (rbeat_q == rlen_q) begin
          // Last beat: transaction complete
          rd_state_q <= RD_IDLE;
        end else begin
          // More beats: advance address and pre-fetch next word
          rbeat_q    <= rbeat_q + 1;
          raddr_q    <= raddr_q + 1;
          rdata_q    <= mem[raddr_q + 1];   // pre-fetch next beat's data
          rd_state_q <= RD_DATA;            // stay in RD_DATA (pipelined)
        end
      end

      // Safety: any unexpected state → return to idle
      default: rd_state_q <= RD_IDLE;

    endcase
  end

  // ── Read channel output assignments ───────────────────────────────────────
  // arready: 1 only in RD_IDLE (SRAM can accept a new read address)
  assign arready_o = (rd_state_q == RD_IDLE);
  // rvalid: 1 only in RD_DATA (registered data is available)
  assign rvalid_o  = (rd_state_q == RD_DATA);
  assign rid_o     = rid_q;     // echo the captured transaction ID
  assign rdata_o   = rdata_q;   // registered SRAM output (valid in RD_DATA)
  assign rresp_o   = 2'b00;    // OKAY — all reads succeed
  // rlast: 1 on the last beat of the burst (when beat counter reaches burst length)
  assign rlast_o   = (rd_state_q == RD_DATA) && (rbeat_q == rlen_q);

endmodule
