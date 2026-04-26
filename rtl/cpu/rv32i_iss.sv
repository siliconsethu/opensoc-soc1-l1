// ============================================================================
// rv32i_iss.sv  —  RV32IM Instruction-Set Simulator (AXI4 master)
//                  OpenSoC Tier-1 Shakti E-class
//
// PURPOSE
//   A fully synthesisable (but simulation-only-intended) behavioural model of
//   a RISC-V RV32IM CPU.  It replaces the non-executing shakti_eclass_wrapper
//   stub for the CPU boot test (t1_eclass_cpu_tb.sv), allowing compiled C
//   binaries to be executed in RTL simulation without a real BSV-generated CPU.
//
// SUPPORTED ISA
//   RV32I  — all 37 base integer instructions:
//              LUI, AUIPC, JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU,
//              LB, LH, LW, LBU, LHU, SB, SH, SW,
//              ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI,
//              ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND,
//              FENCE (treated as NOP), ECALL/EBREAK (halt)
//   RV32M  — 8 multiply/divide instructions:
//              MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//
// EXECUTION MODEL
//   The ISS is fully sequential (single-issue, in-order, no pipelining):
//   one instruction is fetched and executed at a time.  This is slow compared
//   to real hardware but is correct by construction and easy to verify.
//
//   Instruction cycle breakdown (minimum clock cycles per instruction):
//     IMEM fetch  : 2 cycles (AR handshake + R handshake)
//     Decode+exec : 1 cycle  (S_EXEC is a single registered cycle)
//     Load        : 2 more cycles (DMEM AR + DMEM R)
//     Store       : 3 more cycles (DMEM AW + DMEM W + DMEM B)
//
//   With Boot ROM (1-cycle AR + 1-cycle R), every instruction fetch costs
//   exactly 2 cycles.  With SRAM (1-cycle AR + 1-cycle R), same.
//   Total per-instruction cost:
//     ALU/branch/JAL/LUI/AUIPC : 3 cycles (fetch 2 + exec 1)
//     Load                     : 5 cycles (fetch 2 + exec 1 + LD 2)
//     Store                    : 6 cycles (fetch 2 + exec 1 + ST 3)
//
// STATE MACHINE
//   The ISS has 9 states encoded as a 4-bit enum:
//
//     S_IF_AR   Issue instruction fetch AR channel.
//               Driven: imem_arvalid=1, imem_araddr=pc_q.
//               Advance: when imem_arready_i is asserted.
//
//     S_IF_R    Wait for instruction fetch R data.
//               Driven: imem_rready=1.
//               Advance: when imem_rvalid_i is asserted; captures insn_q.
//
//     S_EXEC    Decode insn_q and execute it (1 clock).
//               All combinatorial decode wires (w_op, w_rs1v, w_alu_ri, etc.)
//               are based on insn_q.  The registered state updates in the
//               same clock cycle that the case statement runs.
//               Advance: unconditionally to next state determined by opcode.
//
//     S_LD_AR   Issue DMEM AR for a load instruction.
//               Driven: dmem_arvalid=1, dmem_araddr=mem_addr_q.
//               Advance: when dmem_arready_i is asserted.
//
//     S_LD_R    Wait for DMEM R data for a load.
//               Driven: dmem_rready=1.
//               Advance: when dmem_rvalid_i asserted; write-back w_ld_val → rd_q.
//
//     S_ST_AW   Issue DMEM AW for a store instruction.
//               Driven: dmem_awvalid=1, dmem_awaddr=mem_addr_q.
//               Advance: when dmem_awready_i is asserted.
//
//     S_ST_W    Issue DMEM W data.
//               Driven: dmem_wvalid=1, dmem_wdata=st_data_q, dmem_wstrb=st_strb_q.
//               wlast is always 1 (single-beat transfer).
//               Advance: when dmem_wready_i is asserted.
//
//     S_ST_B    Wait for DMEM B (write response).
//               Driven: dmem_bready=1.
//               Advance: when dmem_bvalid_i is asserted.
//
//     S_HALT    Entered on ECALL, EBREAK, or illegal opcode.
//               halt_o is asserted.  The ISS stays here forever; the testbench
//               detects completion by polling TOHOST in SRAM, not by halt_o.
//
// AXI4 INTERFACE
//   The ISS has two separate AXI4 master ports:
//     IMEM — read-only, used only for instruction fetches (AR/R channels).
//             Write channels (AW/W/B) are not driven and can be left unconnected.
//     DMEM — read/write, used for all data loads and stores.
//
//   Both ports issue single-beat INCR transfers:
//     ARLEN/AWLEN = 8'h00   (1 beat)
//     ARSIZE/AWSIZE = 3'b010 (4 bytes per beat = one 32-bit word)
//     ARBURST/AWBURST = 2'b01 (INCR)
//     ARID/AWID = '0          (always ID 0; the ISS never issues concurrent txns)
//
//   The ISS cannot issue concurrent read and write transactions.  Each state
//   machine step handles exactly one AXI transaction.  No burst transactions
//   are issued.
//
// TOHOST CONVENTION
//   The C test program (eclass_cpu_test.c) communicates pass/fail by writing
//   to address 0x8000_0FF0.  This is an ordinary STORE instruction — the ISS
//   executes it as a normal DMEM SW transaction.  The testbench monitors the
//   SRAM array directly (u_sram.mem[0x3FC]) rather than watching the AXI bus.
//
// REGISTER FILE
//   31 general-purpose 32-bit registers (x1..x31) implemented as regs_q[32].
//   x0 (regs_q[0]) is never written; reads from it return 0 via:
//     w_rs1v = (w_rs1 == 5'd0) ? 32'd0 : regs_q[w_rs1]
//   This approach is simpler than a separate hardwired-zero guard and avoids
//   any ambiguity about what regs_q[0] contains.
//
// PARAMETERS
//   BootAddr   [31:0] — Reset PC.  Set to 32'h0001_0000 for the Boot ROM.
//                       The Boot ROM contains: lui t0,0x80000 / lui sp,0x80010
//                       / jalr zero,0(t0), which jumps to SRAM at 0x8000_0000.
//   AxiIdWidth [int]  — Width of AXI ID fields.  Must match the crossbar.
//                       Set to 4 in the testbench (same as t1_xbar_32 default).
//
// KNOWN LIMITATIONS (acceptable for simulation use)
//   - No CSR instructions (CSRRW/CSRRS/etc.) — treated as halt via OP_SYSTEM
//   - No memory-mapped CSRs (mtime/mtimecmp)
//   - No interrupt handling (PLIC/CLINT are ignored)
//   - No memory-access misalignment detection
//   - No instruction-fetch misalignment detection
//   - No physical memory protection (PMP)
//   - No privilege level support (machine mode only, implicitly)
// ============================================================================

`timescale 1ns/1ps

module rv32i_iss #(
  // Reset program counter.  The ISS starts fetching instructions from this
  // address on the first clock after rst_ni deasserts.
  // For the E-class boot flow: BootAddr = 0x0001_0000 (Boot ROM base).
  parameter logic [31:0] BootAddr    = 32'h0001_0000,

  // AXI4 ID field width.  Must match the crossbar and slave ID widths.
  // Increasing this does not change ISS behaviour; the ISS always drives ID=0.
  parameter int unsigned AxiIdWidth  = 4
) (
  input  logic clk_i,   // System clock (rising-edge triggered)
  input  logic rst_ni,  // Active-low synchronous reset

  // ── IMEM AXI4 master (instruction fetch, read-only) ──────────────────────
  // The ISS uses this port exclusively for instruction fetches (PC→memory).
  // Write channels (AW/W/B) are not driven by the ISS; tie them off externally.
  output logic                      imem_arvalid_o,  // AR valid (fetch request)
  input  logic                      imem_arready_i,  // AR ready (slave accepts)
  output logic [AxiIdWidth-1:0]     imem_arid_o,     // AR ID (always 0)
  output logic [31:0]               imem_araddr_o,   // AR address (= pc_q)
  output logic [7:0]                imem_arlen_o,    // AR burst length (0 = 1 beat)
  output logic [2:0]                imem_arsize_o,   // AR transfer size (2 = 4 bytes)
  output logic [1:0]                imem_arburst_o,  // AR burst type (01 = INCR)
  input  logic                      imem_rvalid_i,   // R valid (data available)
  output logic                      imem_rready_o,   // R ready (ISS accepts data)
  input  logic [AxiIdWidth-1:0]     imem_rid_i,      // R ID (ignored by ISS)
  input  logic [31:0]               imem_rdata_i,    // R data (32-bit instruction)
  input  logic [1:0]                imem_rresp_i,    // R response (ignored)
  input  logic                      imem_rlast_i,    // R last (ignored; single beat)

  // ── DMEM AXI4 master (data loads and stores, read/write) ─────────────────
  // The ISS uses this port for all LB/LH/LW/LBU/LHU and SB/SH/SW instructions.
  // All five AXI4 channels (AW/W/B/AR/R) are used.
  output logic                      dmem_awvalid_o,  // AW valid (store address)
  input  logic                      dmem_awready_i,  // AW ready
  output logic [AxiIdWidth-1:0]     dmem_awid_o,     // AW ID (always 0)
  output logic [31:0]               dmem_awaddr_o,   // AW address (effective addr)
  output logic [7:0]                dmem_awlen_o,    // AW burst length (0 = 1 beat)
  output logic [2:0]                dmem_awsize_o,   // AW size (2 = 4 bytes)
  output logic [1:0]                dmem_awburst_o,  // AW burst (01 = INCR)
  output logic                      dmem_wvalid_o,   // W valid (store data)
  input  logic                      dmem_wready_i,   // W ready
  output logic [31:0]               dmem_wdata_o,    // W data (byte-replicated for SB/SH)
  output logic [3:0]                dmem_wstrb_o,    // W byte enables
  output logic                      dmem_wlast_o,    // W last (always 1; single beat)
  input  logic                      dmem_bvalid_i,   // B valid (write response)
  output logic                      dmem_bready_o,   // B ready
  input  logic [AxiIdWidth-1:0]     dmem_bid_i,      // B ID (ignored)
  input  logic [1:0]                dmem_bresp_i,    // B response (ignored)
  output logic                      dmem_arvalid_o,  // AR valid (load address)
  input  logic                      dmem_arready_i,  // AR ready
  output logic [AxiIdWidth-1:0]     dmem_arid_o,     // AR ID (always 0)
  output logic [31:0]               dmem_araddr_o,   // AR address (effective addr)
  output logic [7:0]                dmem_arlen_o,    // AR burst length (0 = 1 beat)
  output logic [2:0]                dmem_arsize_o,   // AR size (2 = 4 bytes)
  output logic [1:0]                dmem_arburst_o,  // AR burst (01 = INCR)
  input  logic                      dmem_rvalid_i,   // R valid (load data)
  output logic                      dmem_rready_o,   // R ready
  input  logic [AxiIdWidth-1:0]     dmem_rid_i,      // R ID (ignored)
  input  logic [31:0]               dmem_rdata_i,    // R data (32-bit word from SRAM)
  input  logic [1:0]                dmem_rresp_i,    // R response (ignored)
  input  logic                      dmem_rlast_i,    // R last (ignored; single beat)

  // ── Status ────────────────────────────────────────────────────────────────
  // halt_o is asserted when the ISS enters S_HALT (ECALL/EBREAK/illegal).
  // The testbench may use this for debug display, but primary completion
  // detection is via TOHOST polling of u_sram.mem[0x3FC].
  output logic halt_o
);

  // ── Opcode constants (bits [6:0] of a 32-bit RISC-V instruction) ─────────
  // These match the RISC-V Unprivileged ISA Spec Table 24.1.
  // All RISC-V opcodes have bits [1:0] = 2'b11 (32-bit instruction marker).
  localparam logic [6:0]
    OP_LUI    = 7'b0110111,  // Load Upper Immediate (U-type)
    OP_AUIPC  = 7'b0010111,  // Add Upper Immediate to PC (U-type)
    OP_JAL    = 7'b1101111,  // Jump And Link (J-type)
    OP_JALR   = 7'b1100111,  // Jump And Link Register (I-type)
    OP_BRANCH = 7'b1100011,  // Conditional Branch (B-type): BEQ/BNE/BLT/BGE/BLTU/BGEU
    OP_LOAD   = 7'b0000011,  // Load (I-type): LB/LH/LW/LBU/LHU
    OP_STORE  = 7'b0100011,  // Store (S-type): SB/SH/SW
    OP_ALUI   = 7'b0010011,  // ALU with Immediate (I-type): ADDI/SLTI/XORI/ORI/ANDI/SLLI/SRLI/SRAI
    OP_ALU    = 7'b0110011,  // ALU register-register (R-type): ADD/SUB/SLL/SLT/XOR/SRL/SRA/OR/AND
                              //   also M-extension (MUL/DIV/etc.) when insn_q[25]=1
    OP_FENCE  = 7'b0001111,  // Memory ordering fence (treated as NOP — no cache/pipeline here)
    OP_SYSTEM = 7'b1110011;  // System instructions: ECALL, EBREAK, CSR* (→ halt)

  // ── State machine encoding ────────────────────────────────────────────────
  // A 4-bit enum is used; QuestaSim elaborates this as a 4-bit register with
  // symbolic state names visible in the waveform viewer.
  typedef enum logic [3:0] {
    S_IF_AR,  // Instruction Fetch — issue AR channel
    S_IF_R,   // Instruction Fetch — wait for R data
    S_EXEC,   // Decode and execute the captured instruction
    S_LD_AR,  // Load — issue AR channel
    S_LD_R,   // Load — wait for R data, then write-back to register file
    S_ST_AW,  // Store — issue AW channel
    S_ST_W,   // Store — issue W data
    S_ST_B,   // Store — wait for B (write response)
    S_HALT    // Halted (ECALL/EBREAK/illegal); halt_o asserted
  } state_e;

  // ── Registered CPU state (flip-flops, reset by rst_ni) ───────────────────
  state_e      state_q;      // Current state machine state
  logic [31:0] pc_q;         // Program Counter — address of current instruction
  logic [31:0] insn_q;       // Instruction register — holds fetched instruction

  // Register file: x0..x31.  x0 is never written (hardwired to 0 by w_rs1v/w_rs2v).
  // Initialised to 0 on reset (crt0.S also sets sp = 0x8001_0000 via LUI+ADDI).
  logic [31:0] regs_q [32];

  // Latched memory access state (set in S_EXEC, used in load/store states):
  logic [31:0] mem_addr_q;   // Effective address of the load/store
  logic [31:0] st_data_q;    // Store data (byte-replicated for SB/SH)
  logic  [3:0] st_strb_q;    // Store byte-enable strobes
  logic  [4:0] rd_q;         // Destination register for a load
  logic  [2:0] ld_f3_q;      // funct3 of the load instruction (selects sign-extension mode)

  // ========================================================================
  // Combinatorial decode wires
  // All signals below are purely combinatorial and re-computed every cycle
  // from insn_q.  They are valid and stable throughout S_EXEC.
  // ========================================================================

  // ── Instruction field extraction ─────────────────────────────────────────
  logic [6:0]  w_op;    // Opcode field [6:0]
  logic [4:0]  w_rd;    // Destination register [11:7]
  logic [4:0]  w_rs1;   // Source register 1    [19:15]
  logic [4:0]  w_rs2;   // Source register 2    [24:20]
  logic [2:0]  w_f3;    // funct3 field [14:12]  — selects operation variant
  logic        w_f7b5;  // insn_q[30] — funct7 bit 5:
                        //   OP_ALU:  distinguishes ADD (0) vs SUB (1), SRL (0) vs SRA (1)
                        //   OP_ALUI: distinguishes SRLI (0) vs SRAI (1)
  logic        w_mext;  // insn_q[25] — when OP_ALU and w_mext=1: M-extension (MUL/DIV)

  // ── Register values (x0 reads as 0) ──────────────────────────────────────
  logic [31:0] w_rs1v;  // Value of rs1 register (or 0 if rs1=x0)
  logic [31:0] w_rs2v;  // Value of rs2 register (or 0 if rs2=x0)

  // ── Immediate decode (all types defined, only relevant one used per insn) ─
  // RISC-V immediates are sign-extended from bit 31 of the instruction.
  // Each format scrambles the immediate bits differently to keep bits 31..12
  // of the instruction always in the same position for fast sign-extension.
  logic [31:0] w_imm_i; // I-type immediate: {sign[21], insn[30:20]}  (ADDI, loads, JALR)
  logic [31:0] w_imm_s; // S-type immediate: {sign[21], insn[30:25], insn[11:7]}  (stores)
  logic [31:0] w_imm_b; // B-type immediate: {sign[20], insn[7], insn[30:25], insn[11:8], 0}
  logic [31:0] w_imm_u; // U-type immediate: {insn[31:12], 12'b0}  (LUI, AUIPC)
  logic [31:0] w_imm_j; // J-type immediate: {sign[12], insn[19:12], insn[20], insn[30:21], 0}

  // ── Effective address (load/store) ────────────────────────────────────────
  // EA = rs1 + imm_i  (for loads and JALR)
  // EA = rs1 + imm_s  (for stores)
  // The mux is combined here to avoid recomputing in S_EXEC.
  logic [31:0] w_ea;

  // ── ALU results ──────────────────────────────────────────────────────────
  logic [31:0] w_alu_ri;  // Result of register-immediate ALU op (OP-IMM)
  logic [31:0] w_alu_rr;  // Result of register-register ALU op (OP / M-ext)

  // ── Branch taken / not taken ──────────────────────────────────────────────
  logic        w_taken;   // 1 if the branch condition is true

  // ── Store data and strobes ────────────────────────────────────────────────
  // SB: byte-replicate rs2[7:0] to all 4 byte lanes; strobe selects the target lane.
  // SH: halfword-replicate rs2[15:0] to both halfword lanes; strobe selects the half.
  // SW: pass rs2 through; all strobes enabled.
  logic [31:0] w_st_data;  // Data to write to DMEM W channel
  logic  [3:0] w_st_strb;  // Byte-enable strobes for DMEM W channel

  // ── Load value (sign-extended from raw 32-bit DMEM read data) ─────────────
  // Computed in S_LD_R using mem_addr_q[1:0] and ld_f3_q.
  logic [31:0] w_ld_val;

  // ── Field extraction assignments ─────────────────────────────────────────
  assign w_op    = insn_q[6:0];
  assign w_rd    = insn_q[11:7];
  assign w_f3    = insn_q[14:12];
  assign w_rs1   = insn_q[19:15];
  assign w_rs2   = insn_q[24:20];
  assign w_f7b5  = insn_q[30];   // funct7[5]: SUB/SRA/SRAI qualifier
  assign w_mext  = insn_q[25];   // funct7[0] for M-extension

  // Zero-guard for x0: if rs1 or rs2 is register x0 (index 0), return 0.
  // This is correct-by-construction without needing to reset regs_q[0].
  assign w_rs1v  = (w_rs1 == 5'd0) ? 32'd0 : regs_q[w_rs1];
  assign w_rs2v  = (w_rs2 == 5'd0) ? 32'd0 : regs_q[w_rs2];

  // ── Immediate sign-extension ──────────────────────────────────────────────
  // {21{insn_q[31]}} replicates the sign bit 21 times to fill bits [31:11].
  assign w_imm_i = {{21{insn_q[31]}}, insn_q[30:20]};
  assign w_imm_s = {{21{insn_q[31]}}, insn_q[30:25], insn_q[11:7]};
  assign w_imm_b = {{20{insn_q[31]}}, insn_q[7], insn_q[30:25], insn_q[11:8], 1'b0};
  assign w_imm_u = {insn_q[31:12], 12'b0};
  assign w_imm_j = {{12{insn_q[31]}}, insn_q[19:12], insn_q[20], insn_q[30:21], 1'b0};

  // Effective address: rs1 + offset (offset type depends on load vs store)
  assign w_ea    = w_rs1v + ((w_op == OP_STORE) ? w_imm_s : w_imm_i);

  // ========================================================================
  // ALU functions (automatic functions — synthesise as combinatorial logic)
  // ========================================================================

  // ── Register-immediate ALU (OP-IMM instructions) ──────────────────────────
  // Implements all 9 OP-IMM variants selected by funct3:
  //   000 ADDI  — add rs1 + sign_ext(imm[11:0])
  //   010 SLTI  — set if rs1 < imm (signed comparison) → {31'b0, result}
  //   011 SLTIU — set if rs1 < imm (unsigned)
  //   100 XORI  — bitwise XOR; XORI rd, rs, -1 implements NOT
  //   110 ORI   — bitwise OR
  //   111 ANDI  — bitwise AND
  //   001 SLLI  — shift left logical by imm[4:0]
  //   101 SRLI  — shift right logical (f7b5=0) or SRAI arithmetic (f7b5=1)
  //
  // $signed() casts the operand to a signed type for comparison/shift.
  // $unsigned() casts back to unsigned for the assignment.
  function automatic logic [31:0] alu_ri_f(
    input logic [2:0] f3, input logic f7b5,
    input logic [31:0] a,  input logic [31:0] imm
  );
    case (f3)
      3'b000: return a + imm;                                              // ADDI
      3'b010: return {31'b0, $signed(a) < $signed(imm)};                  // SLTI  (signed)
      3'b011: return {31'b0, a < imm};                                     // SLTIU (unsigned)
      3'b100: return a ^ imm;                                              // XORI
      3'b110: return a | imm;                                              // ORI
      3'b111: return a & imm;                                              // ANDI
      3'b001: return a << imm[4:0];                                        // SLLI
      3'b101: return f7b5 ? $unsigned($signed(a) >>> imm[4:0])            // SRAI (arithmetic)
                           : a >> imm[4:0];                               // SRLI (logical)
      default: return '0;
    endcase
  endfunction

  // ── Register-register ALU (OP instructions, base RV32I) ───────────────────
  // Implements all 10 OP variants:
  //   000 ADD (f7b5=0) / SUB (f7b5=1)
  //   001 SLL  — shift left logical by rs2[4:0]
  //   010 SLT  — set if rs1 < rs2 (signed)
  //   011 SLTU — set if rs1 < rs2 (unsigned)
  //   100 XOR
  //   101 SRL (f7b5=0) / SRA (f7b5=1)
  //   110 OR
  //   111 AND
  function automatic logic [31:0] alu_rr_f(
    input logic [2:0] f3, input logic f7b5,
    input logic [31:0] a,  input logic [31:0] b
  );
    case (f3)
      3'b000: return f7b5 ? a - b : a + b;                                // ADD/SUB
      3'b001: return a << b[4:0];                                          // SLL (shift amount in rs2[4:0])
      3'b010: return {31'b0, $signed(a) < $signed(b)};                    // SLT
      3'b011: return {31'b0, a < b};                                       // SLTU
      3'b100: return a ^ b;                                                // XOR
      3'b101: return f7b5 ? $unsigned($signed(a) >>> b[4:0]) : a >> b[4:0]; // SRA/SRL
      3'b110: return a | b;                                                // OR
      3'b111: return a & b;                                                // AND
      default: return '0;
    endcase
  endfunction

  // ── M-extension: multiply and divide ─────────────────────────────────────
  // All 8 M-extension instructions, selected by funct3 (same bit as OP_ALU
  // but with insn_q[25]=1, which sets w_mext).
  //
  // MUL [2:0]=000   Lower 32 bits of rs1 × rs2 (unsigned × unsigned)
  // MULH [2:0]=001  Upper 32 bits of signed(rs1) × signed(rs2)
  // MULHSU [2:0]=010 Upper 32 bits of signed(rs1) × unsigned(rs2)
  // MULHU [2:0]=011 Upper 32 bits of unsigned(rs1) × unsigned(rs2)
  // DIV [2:0]=100   Signed division, truncates toward zero
  // DIVU [2:0]=101  Unsigned division
  // REM [2:0]=110   Signed remainder (sign matches dividend)
  // REMU [2:0]=111  Unsigned remainder
  //
  // MULH/MULHSU/MULHU IMPLEMENTATION NOTE
  //   A 32×32 bit multiplication in SV yields a 32-bit result by default.
  //   To get the upper 32 bits of a 64-bit product, we use 'longint' (64-bit
  //   signed) or 'longint unsigned' (64-bit unsigned) intermediate variables.
  //   Casting the 32-bit inputs to longint/longint unsigned before multiplying
  //   tells the tool to perform a 64-bit × 64-bit multiply and keep all 64 bits.
  //   Shifting the 64-bit product right by 32 gives the upper 32 bits.
  //
  // DIVISION CORNER CASES (RISC-V spec §M.2)
  //   DIV  by zero: result = -1  (all-ones = 0xFFFF_FFFF)
  //   DIVU by zero: result = 2^32 - 1 = 0xFFFF_FFFF
  //   REM  by zero: result = dividend
  //   REMU by zero: result = dividend
  //   DIV  overflow (INT_MIN / -1): result = INT_MIN (0x8000_0000)
  //   REM  overflow (INT_MIN / -1): result = 0
  function automatic logic [31:0] mul_f(
    input logic [2:0] f3,
    input logic [31:0] a, b
  );
    case (f3)
      // MUL: lower 32 bits of rs1 × rs2 (unsigned × unsigned product truncated)
      3'b000: return a * b;

      // MULH: upper 32 of signed(a) × signed(b)
      // longint = 64-bit signed; $signed(a) zero-extends a 32-bit signed value
      // to the 64-bit signed range.  The product is 64 bits; >>32 gives upper half.
      3'b001: begin
        longint sa = longint'($signed(a));
        longint sb = longint'($signed(b));
        return (sa * sb) >> 32;
      end

      // MULHSU: upper 32 of signed(a) × unsigned(b)
      // sa is sign-extended to 64 bits; ub is zero-extended (upper 32 = 0,
      // so treating ub as signed longint gives the same value — no overflow).
      // The 32×32 signed×unsigned product fits within 64 signed bits.
      3'b010: begin
        longint       sa = longint'($signed(a));
        logic [63:0]  ub = {32'b0, b};          // zero-extend: ub[63]=0 always
        return (sa * longint'(ub)) >> 32;
      end

      // MULHU: upper 32 of unsigned(a) × unsigned(b)
      // Both zero-extended to 64 bits.  Product of two 32-bit values < 2^64,
      // so fits in 64-bit unsigned; >> 32 gives the correct upper 32 bits.
      3'b011: begin
        logic [63:0]  ua = {32'b0, a};
        logic [63:0]  ub = {32'b0, b};
        return (ua * ub) >> 32;
      end

      // DIV: signed division, truncates toward zero
      // Corner case: b=0 → -1 (all-ones); INT_MIN/-1 → INT_MIN (overflow)
      3'b100: begin
        if (b == '0)                            return '1;            // ÷0 → -1
        if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) return a;      // overflow: return dividend
        return $unsigned($signed(a) / $signed(b));
      end

      // DIVU: unsigned division
      // Corner case: b=0 → 0xFFFF_FFFF (maximum unsigned value)
      3'b101: return (b == '0) ? '1 : a / b;

      // REM: signed remainder (sign of result = sign of dividend)
      // Corner case: b=0 → a (dividend); INT_MIN%-1 → 0 (overflow)
      3'b110: begin
        if (b == '0)                            return a;             // %0 → dividend
        if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) return '0;     // overflow → 0
        return $unsigned($signed(a) % $signed(b));
      end

      // REMU: unsigned remainder
      // Corner case: b=0 → a (dividend)
      3'b111: return (b == '0) ? a : a % b;

      default: return '0;
    endcase
  endfunction

  // ALU result mux: for OP_ALU, choose M-extension or base R-R ALU
  assign w_alu_ri = alu_ri_f(w_f3, w_f7b5, w_rs1v, w_imm_i);
  assign w_alu_rr = w_mext ? mul_f(w_f3, w_rs1v, w_rs2v)
                           : alu_rr_f(w_f3, w_f7b5, w_rs1v, w_rs2v);

  // ── Branch condition ──────────────────────────────────────────────────────
  // The RISC-V B-type instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU) are all
  // encoded as OP_BRANCH with funct3 selecting the comparison:
  //   000 BEQ   — branch if rs1 == rs2
  //   001 BNE   — branch if rs1 != rs2
  //   100 BLT   — branch if rs1 <  rs2 (signed)
  //   101 BGE   — branch if rs1 >= rs2 (signed)
  //   110 BLTU  — branch if rs1 <  rs2 (unsigned)
  //   111 BGEU  — branch if rs1 >= rs2 (unsigned)
  //
  // w_taken is used in S_EXEC to choose: PC+imm_b (taken) or PC+4 (not taken).
  always_comb begin
    case (w_f3)
      3'b000:  w_taken = (w_rs1v == w_rs2v);                      // BEQ
      3'b001:  w_taken = (w_rs1v != w_rs2v);                      // BNE
      3'b100:  w_taken = $signed(w_rs1v) <  $signed(w_rs2v);     // BLT  (signed)
      3'b101:  w_taken = $signed(w_rs1v) >= $signed(w_rs2v);     // BGE  (signed)
      3'b110:  w_taken = (w_rs1v <  w_rs2v);                      // BLTU (unsigned)
      3'b111:  w_taken = (w_rs1v >= w_rs2v);                      // BGEU (unsigned)
      default: w_taken = 1'b0;
    endcase
  end

  // ── Store data and byte-enable calculation ────────────────────────────────
  // RISC-V stores write a full 32-bit word to the AXI W channel, but use
  // byte-enable strobes to select which bytes to actually commit to memory.
  //
  // SB (funct3=000): byte store
  //   Data: rs2[7:0] replicated to all 4 byte lanes ({4{rs2[7:0]}})
  //         so any lane can be written with the correct byte.
  //   Strobe: 4'b0001 << EA[1:0]  — selects the correct byte lane based on
  //           the address offset within the aligned word.
  //           EA[1:0]=00 → strobe=0001 → byte 0 (bits [7:0])
  //           EA[1:0]=01 → strobe=0010 → byte 1 (bits [15:8])
  //           EA[1:0]=10 → strobe=0100 → byte 2 (bits [23:16])
  //           EA[1:0]=11 → strobe=1000 → byte 3 (bits [31:24])
  //
  // SH (funct3=001): halfword store
  //   Data: rs2[15:0] replicated to both halfword lanes ({2{rs2[15:0]}})
  //   Strobe: 4'b0011 << {EA[1], 1'b0}
  //           EA[1]=0 → shift=0 → strobe=0011 → lower halfword (bytes 0+1)
  //           EA[1]=1 → shift=2 → strobe=1100 → upper halfword (bytes 2+3)
  //
  // SW (funct3=010): word store
  //   Data: rs2v unchanged
  //   Strobe: 4'b1111 (all bytes enabled)
  always_comb begin
    case (w_f3)
      3'b000: begin  // SB
        w_st_data = {4{w_rs2v[7:0]}};
        w_st_strb = 4'b0001 << w_ea[1:0];
      end
      3'b001: begin  // SH
        w_st_data = {2{w_rs2v[15:0]}};
        w_st_strb = 4'b0011 << {w_ea[1], 1'b0};
      end
      default: begin // SW (and any unrecognised funct3 → safe default)
        w_st_data = w_rs2v;
        w_st_strb = 4'b1111;
      end
    endcase
  end

  // ── Load value: extract and sign-extend from 32-bit DMEM word ─────────────
  // RISC-V loads always request a full aligned 32-bit word from the bus (the
  // AXI size is always 4 bytes, arsize=010).  The sub-word extraction and
  // sign-extension is done here in the ISS, using:
  //   mem_addr_q[1:0] — byte offset within the aligned word (determines lane)
  //   ld_f3_q         — load funct3 (determines width and signed/unsigned)
  //
  // Byte extraction:
  //   byte_v = dmem_rdata_i[mem_addr_q[1:0]*8 +: 8]
  //   mem_addr_q[1:0]=00 → bits [7:0]
  //   mem_addr_q[1:0]=01 → bits [15:8]
  //   mem_addr_q[1:0]=10 → bits [23:16]
  //   mem_addr_q[1:0]=11 → bits [31:24]
  //
  // Halfword extraction:
  //   half_v = dmem_rdata_i[mem_addr_q[1]*16 +: 16]
  //   mem_addr_q[1]=0 → bits [15:0]  (lower halfword)
  //   mem_addr_q[1]=1 → bits [31:16] (upper halfword)
  //
  // Sign-extension modes (ld_f3_q):
  //   000 LB  — sign-extend byte   (bit 7 replicated to bits [31:8])
  //   001 LH  — sign-extend half   (bit 15 replicated to bits [31:16])
  //   010 LW  — full word, no extension needed
  //   100 LBU — zero-extend byte   (bits [31:8] = 0)
  //   101 LHU — zero-extend half   (bits [31:16] = 0)
  //
  // Note: this block uses mem_addr_q and ld_f3_q (registered from S_EXEC),
  // not the combinatorial w_ea and w_f3.  This is because dmem_rdata_i arrives
  // in state S_LD_R, at which point insn_q may have been overwritten.
  // (In this ISS, insn_q is never overwritten until the next S_IF_R, so it
  // would be safe to use w_f3 directly — but using the registered copies is
  // more robust and makes the design intent explicit.)
  always_comb begin
    logic [7:0]  byte_v;
    logic [15:0] half_v;
    byte_v = dmem_rdata_i[mem_addr_q[1:0]*8 +: 8];
    half_v = dmem_rdata_i[mem_addr_q[1]*16  +: 16];
    case (ld_f3_q)
      3'b000: w_ld_val = {{24{byte_v[7]}},  byte_v};   // LB  — sign-extend byte
      3'b001: w_ld_val = {{16{half_v[15]}}, half_v};   // LH  — sign-extend halfword
      3'b010: w_ld_val = dmem_rdata_i;                  // LW  — full word
      3'b100: w_ld_val = {24'b0, byte_v};               // LBU — zero-extend byte
      3'b101: w_ld_val = {16'b0, half_v};               // LHU — zero-extend halfword
      default:w_ld_val = dmem_rdata_i;                  // fallback: treat as LW
    endcase
  end

  // ========================================================================
  // AXI4 output assignments  (purely combinatorial; driven by state_q)
  // ========================================================================
  //
  // Each AXI channel is valid in exactly one state.  All other outputs are 0.
  // This meets AXI4 protocol requirements: a master must not assert xVALID
  // unless it is actually initiating a transaction.

  // IMEM AR channel: valid only in S_IF_AR
  assign imem_arvalid_o = (state_q == S_IF_AR);
  assign imem_araddr_o  = pc_q;          // fetch from current PC
  assign imem_arid_o    = '0;            // single outstanding transaction
  assign imem_arlen_o   = 8'h00;         // 1 beat (length = len+1 = 1)
  assign imem_arsize_o  = 3'b010;        // 4 bytes per beat
  assign imem_arburst_o = 2'b01;         // INCR (required for 1-beat transfers)

  // IMEM R channel: ready only in S_IF_R
  assign imem_rready_o  = (state_q == S_IF_R);

  // DMEM AR channel (loads): valid only in S_LD_AR
  assign dmem_arvalid_o = (state_q == S_LD_AR);
  assign dmem_araddr_o  = mem_addr_q;    // effective address from S_EXEC
  assign dmem_arid_o    = '0;
  assign dmem_arlen_o   = 8'h00;
  assign dmem_arsize_o  = 3'b010;        // always request a full word
  assign dmem_arburst_o = 2'b01;

  // DMEM R channel (loads): ready only in S_LD_R
  assign dmem_rready_o  = (state_q == S_LD_R);

  // DMEM AW channel (stores): valid only in S_ST_AW
  assign dmem_awvalid_o = (state_q == S_ST_AW);
  assign dmem_awaddr_o  = mem_addr_q;
  assign dmem_awid_o    = '0;
  assign dmem_awlen_o   = 8'h00;
  assign dmem_awsize_o  = 3'b010;
  assign dmem_awburst_o = 2'b01;

  // DMEM W channel (stores): valid only in S_ST_W
  assign dmem_wvalid_o  = (state_q == S_ST_W);
  assign dmem_wdata_o   = st_data_q;     // byte-replicated data (from S_EXEC)
  assign dmem_wstrb_o   = st_strb_q;     // byte enables (from S_EXEC)
  assign dmem_wlast_o   = 1'b1;          // always last (single-beat transfer)

  // DMEM B channel (stores): ready only in S_ST_B
  assign dmem_bready_o  = (state_q == S_ST_B);

  // Halt indicator: asserted when in S_HALT
  assign halt_o = (state_q == S_HALT);

  // ========================================================================
  // State machine + register file  (sequential logic)
  // ========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Synchronous reset: initialise all state to known values.
      // The ISS starts in S_IF_AR with PC = BootAddr, ready to fetch
      // the first instruction from the Boot ROM immediately after reset.
      state_q    <= S_IF_AR;
      pc_q       <= BootAddr;
      insn_q     <= '0;
      mem_addr_q <= '0;
      st_data_q  <= '0;
      st_strb_q  <= '0;
      rd_q       <= '0;
      ld_f3_q    <= '0;
      // Zero the entire register file.  x0 stays 0 forever; other registers
      // will be set by the compiled program (sp by crt0.S, etc.).
      for (int k = 0; k < 32; k++) regs_q[k] <= '0;

    end else begin
      case (state_q)

        // ── S_IF_AR: Instruction Fetch — Address Request ──────────────────
        // Drive imem_arvalid=1 (from the assign above) and wait for the
        // instruction memory to assert imem_arready_i.
        // The Boot ROM asserts arready in the same cycle as arvalid (zero wait).
        // The SRAM also asserts arready in the same cycle.
        // When accepted, advance to S_IF_R to wait for the data.
        S_IF_AR: begin
          if (imem_arready_i) state_q <= S_IF_R;
        end

        // ── S_IF_R: Instruction Fetch — Read Data ─────────────────────────
        // Wait for the instruction memory to present valid data on the R channel.
        // Boot ROM: rvalid asserts 1 cycle after arready (registered output).
        // Capture the instruction word into insn_q and advance to S_EXEC.
        S_IF_R: begin
          if (imem_rvalid_i) begin
            insn_q  <= imem_rdata_i;   // latch the 32-bit instruction
            state_q <= S_EXEC;
          end
        end

        // ── S_EXEC: Decode and Execute ────────────────────────────────────
        // The combinatorial decode wires (w_op, w_rs1v, w_alu_ri, etc.) are
        // already stable based on insn_q from S_IF_R.  This state reads them
        // and updates the registered state in one clock cycle.
        //
        // PC update policy:
        //   - Sequential instructions (ALU, LUI, AUIPC): pc_q += 4
        //   - Branches (taken): pc_q += imm_b; (not taken): pc_q += 4
        //   - JAL: pc_q += imm_j  (note: PC-relative, imm_j is signed)
        //   - JALR: pc_q = (rs1 + imm_i) & ~1  (LSB always cleared per spec)
        //   - Loads: pc_q is advanced NOW (before the load completes), so the
        //     next fetch starts from the correct PC after write-back.
        //   - Stores: same — pc_q advanced before the store completes.
        S_EXEC: begin
          case (w_op)

            // ── LUI ──────────────────────────────────────────────────────
            // Load Upper Immediate: rd = {imm[31:12], 12'b0}.
            // Does not add PC; the lower 12 bits of imm_u are already 0.
            // Used for: loading large constants and as the first half of
            // two-instruction symbol loading (LUI + ADDI).
            OP_LUI: begin
              if (w_rd != '0) regs_q[w_rd] <= w_imm_u;
              pc_q    <= pc_q + 4;
              state_q <= S_IF_AR;
            end

            // ── AUIPC ─────────────────────────────────────────────────────
            // Add Upper Immediate to PC: rd = pc + {imm[31:12], 12'b0}.
            // Used for PC-relative addressing (e.g., 'la' pseudo-instruction
            // with large offsets from the current PC).
            OP_AUIPC: begin
              if (w_rd != '0) regs_q[w_rd] <= pc_q + w_imm_u;
              pc_q    <= pc_q + 4;
              state_q <= S_IF_AR;
            end

            // ── JAL ───────────────────────────────────────────────────────
            // Jump And Link: rd = pc+4; pc = pc + imm_j (PC-relative).
            // imm_j is a signed 21-bit offset, so JAL reaches ±1 MB.
            // Used for function calls ('call' pseudo: auipc+jalr for far calls,
            // jal for near calls) and unconditional jumps ('j' pseudo = jal x0).
            OP_JAL: begin
              if (w_rd != '0) regs_q[w_rd] <= pc_q + 4;   // save return address
              pc_q    <= pc_q + w_imm_j;    // jump: PC += signed offset
              state_q <= S_IF_AR;
            end

            // ── JALR ──────────────────────────────────────────────────────
            // Jump And Link Register: rd = pc+4; pc = (rs1+imm_i) & ~1.
            // The LSB of the target address is forced to 0 (16-bit alignment).
            // Used for: 'ret' pseudo (jalr x0, ra, 0), indirect calls, and
            // the far 'call' sequence (auipc ra, %pcrel_hi(sym) + jalr ra, ra, %pcrel_lo(sym)).
            OP_JALR: begin
              if (w_rd != '0) regs_q[w_rd] <= pc_q + 4;
              pc_q    <= (w_rs1v + w_imm_i) & ~32'h1;  // clear LSB
              state_q <= S_IF_AR;
            end

            // ── BRANCH ────────────────────────────────────────────────────
            // Conditional branch: pc = pc + imm_b (taken) or pc+4 (not taken).
            // w_taken is computed combinatorially by the always_comb block above.
            // All 6 branch conditions (BEQ/BNE/BLT/BGE/BLTU/BGEU) handled.
            OP_BRANCH: begin
              pc_q    <= w_taken ? (pc_q + w_imm_b) : (pc_q + 4);
              state_q <= S_IF_AR;
            end

            // ── LOAD ──────────────────────────────────────────────────────
            // Memory load: compute effective address, advance PC, go to S_LD_AR.
            // The destination register (rd_q) and load width (ld_f3_q) are
            // latched here so they are available in S_LD_R after the AXI
            // round-trip completes.
            // PC is advanced now (not after write-back) so the state machine
            // can start the next fetch immediately after the load completes.
            OP_LOAD: begin
              mem_addr_q <= w_ea;       // latch effective address
              rd_q       <= w_rd;       // latch destination register index
              ld_f3_q    <= w_f3;       // latch load width / sign-extension mode
              pc_q       <= pc_q + 4;   // advance PC before the load completes
              state_q    <= S_LD_AR;
            end

            // ── STORE ─────────────────────────────────────────────────────
            // Memory store: compute effective address, compute data and strobes,
            // advance PC, go to S_ST_AW.
            // w_st_data and w_st_strb (computed combinatorially from w_ea/w_f3)
            // are latched into registers here so they persist through S_ST_W.
            OP_STORE: begin
              mem_addr_q <= w_ea;
              st_data_q  <= w_st_data;  // byte-replicated store data
              st_strb_q  <= w_st_strb;  // byte enables
              pc_q       <= pc_q + 4;
              state_q    <= S_ST_AW;
            end

            // ── OP-IMM (ALU with immediate) ───────────────────────────────
            // ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI.
            // All computed by alu_ri_f(); result in w_alu_ri.
            OP_ALUI: begin
              if (w_rd != '0) regs_q[w_rd] <= w_alu_ri;
              pc_q    <= pc_q + 4;
              state_q <= S_IF_AR;
            end

            // ── OP (ALU register-register + M-extension) ──────────────────
            // When w_mext=0: base RV32I ALU (ADD/SUB/SLL/SLT/XOR/SRL/SRA/OR/AND).
            // When w_mext=1: M-extension (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU).
            // Both cases are handled by w_alu_rr (muxed from alu_rr_f or mul_f).
            OP_ALU: begin
              if (w_rd != '0) regs_q[w_rd] <= w_alu_rr;
              pc_q    <= pc_q + 4;
              state_q <= S_IF_AR;
            end

            // ── FENCE ─────────────────────────────────────────────────────
            // Memory ordering fence: treated as NOP in this ISS.
            // Rationale: the ISS is fully sequential (no out-of-order execution,
            // no write buffers, no cache).  All memory accesses complete in
            // strict program order, so FENCE has no effect on correctness.
            // The C test may emit FENCE.I after a self-modifying code sequence,
            // but there is no self-modifying code in eclass_cpu_test.c.
            OP_FENCE: begin
              pc_q    <= pc_q + 4;
              state_q <= S_IF_AR;
            end

            // ── SYSTEM (ECALL, EBREAK, CSR*) → HALT ──────────────────────
            // These instructions require OS/environment support that does not
            // exist in bare-metal simulation.  The ISS halts here.
            // The C test never executes ECALL/EBREAK; it communicates via TOHOST.
            // crt0.S uses 'j .Lspin' (an infinite JAL loop) after main() returns,
            // so the ISS will loop forever on the 'j' — but the testbench
            // detects TOHOST before that happens and calls $finish.
            OP_SYSTEM: begin
              state_q <= S_HALT;
            end

            // ── Illegal opcode → HALT ─────────────────────────────────────
            // Any unrecognised opcode (e.g., if a fetch returns garbage data)
            // causes the ISS to halt.  halt_o will assert; the testbench will
            // display the PC and TOHOST value for debug.
            default: begin
              state_q <= S_HALT;
            end

          endcase
        end // S_EXEC

        // ── S_LD_AR: Load — Address Request ──────────────────────────────
        // Drive dmem_arvalid=1 and wait for the SRAM to accept the address.
        // SRAM asserts dmem_arready_i in the same cycle (zero wait).
        S_LD_AR: begin
          if (dmem_arready_i) state_q <= S_LD_R;
        end

        // ── S_LD_R: Load — Read Data + Register Write-Back ────────────────
        // Wait for SRAM to present the read data (1 cycle after arready).
        // When dmem_rvalid_i asserts, apply sub-word extraction and sign
        // extension (w_ld_val), then write to the destination register (rd_q).
        // The x0 guard prevents writes to the hardwired-zero register.
        S_LD_R: begin
          if (dmem_rvalid_i) begin
            if (rd_q != '0) regs_q[rd_q] <= w_ld_val;
            state_q <= S_IF_AR;   // return to fetch for next instruction
          end
        end

        // ── S_ST_AW: Store — Write Address ───────────────────────────────
        // Drive dmem_awvalid=1 and wait for the SRAM to accept the address.
        // AXI4 allows AW and W to be presented simultaneously; here we sequence
        // them for simplicity (AW first, then W).
        S_ST_AW: begin
          if (dmem_awready_i) state_q <= S_ST_W;
        end

        // ── S_ST_W: Store — Write Data ────────────────────────────────────
        // Drive dmem_wvalid=1 with the byte-replicated data and byte enables.
        // dmem_wlast_o is always 1 (single-beat burst; no multi-beat stores).
        // Wait for the SRAM to assert wready before advancing.
        S_ST_W: begin
          if (dmem_wready_i) state_q <= S_ST_B;
        end

        // ── S_ST_B: Store — Write Response ───────────────────────────────
        // Wait for the SRAM to assert bvalid (write acknowledgement).
        // The ISS ignores the BRESP field (assumes OKAY=2'b00).
        // On bvalid, return to instruction fetch for the next instruction.
        S_ST_B: begin
          if (dmem_bvalid_i) state_q <= S_IF_AR;
        end

        // ── S_HALT: CPU Halted ────────────────────────────────────────────
        // The ISS stays in this state until simulation ends.
        // halt_o=1 is asserted (from the assign above).
        // The testbench calls $finish when TOHOST is detected, so this state
        // is rarely reached in normal test execution.
        S_HALT: begin
          // Intentionally empty — stay halted.
          // halt_o is driven by the continuous assign above.
        end

        // Safety: any unexpected state encoding → halt
        default: state_q <= S_HALT;

      endcase
    end
  end

endmodule
