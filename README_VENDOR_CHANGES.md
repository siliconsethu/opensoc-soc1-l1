# Vendor Directory Changes — OpenSoC Tier-1

This document describes every file inside `rtl/vendor/` that was modified to make
the OpenSoC Tier-1 E-class SoC compile and simulate in **QuestaSim 2024.1** on Windows.

These changes are required for the **Level-1** peripheral subsystem (`t1_periph_ss_l1`)
which uses OpenTitan `uart.sv` and `gpio.sv` via the TLUL bus.
The Level-2 subsystem (`t1_periph_ss_32`) is self-contained and does not use vendor IP.

---

## Scope

| Directory | Modified? | Notes |
|-----------|-----------|-------|
| `rtl/vendor/rv_plic/` | **Yes** — 2 files | prim_subreg, prim_subreg_ext |
| `rtl/vendor/rv_uart/` | **Yes** — 1 file | prim_assert include added |

---

## 1. `rtl/vendor/rv_plic/prim_subreg.sv`

### What changed

The file was rewritten to support the **newer OpenTitan `reg_top` API** used by
`uart_reg_top.sv` and `gpio_reg_top.sv` in the Level-1 peripheral subsystem.

#### Parameters added

| Parameter | Type | Default | Reason |
|-----------|------|---------|--------|
| `SwAccess` | `prim_subreg_pkg::sw_access_e` | `SwAccessRW` | Newer reg_tops pass `.SwAccess(...)` enum |
| `Mubi` | `logic` | `1'b0` | Newer reg_tops pass `.Mubi(...)` — ignored in simulation |

The old `SWACCESS` string parameter is kept for backward compatibility.

#### Port added

```systemverilog
output logic [DW-1:0] ds
```

Newer OpenTitan `reg_top` modules connect `.ds()` (data-strobe / write-data shadow).
Without this port QuestaSim issues **vopt-2912** and aborts design loading.

`ds` is driven with the same value as `qs`:

```systemverilog
assign ds = q;
assign qs = q;
```

#### Logic change

Old code used `if (SWACCESS == "RW")` string comparisons. New code uses `case (SwAccess)`:

```systemverilog
case (SwAccess)
  prim_subreg_pkg::SwAccessRO: begin wr_en = de;      wr_data = d; end
  prim_subreg_pkg::SwAccessWO: begin wr_en = we | de; wr_data = we ? wd : d; end
  prim_subreg_pkg::SwAccessW1S: ...
  prim_subreg_pkg::SwAccessW1C: ...
  prim_subreg_pkg::SwAccessW0C: ...
  prim_subreg_pkg::SwAccessRC:  ...
  default: begin wr_en = we | de; wr_data = we ? wd : d; end // RW
endcase
```

### Error fixed

```
** Error: vopt-2912: Port 'ds' not found in module 'prim_subreg'
```

---

## 2. `rtl/vendor/rv_plic/prim_subreg_ext.sv`

### What changed

#### Port added

```systemverilog
output logic [DW-1:0] ds
```

Same reason as `prim_subreg.sv` — newer reg_tops connect `.ds()` on both the
clocked (`prim_subreg`) and the external/combinational (`prim_subreg_ext`) variants.

```systemverilog
assign qs = d;
assign ds = d;   // added
```

### Before vs after

```systemverilog
// Before (8 ports):
module prim_subreg_ext #(parameter DW = 32) (
  input          re, we,
  input [DW-1:0] wd, d,
  output logic   qe, qre,
  output logic [DW-1:0] q, qs
);

// After (9 ports — added ds):
module prim_subreg_ext #(parameter DW = 32) (
  input          re, we,
  input [DW-1:0] wd, d,
  output logic   qe, qre,
  output logic [DW-1:0] q, ds, qs   // ds added
);
```

### Error fixed

```
** Error: vopt-2912: Port 'ds' not found in module 'prim_subreg_ext'
```

---

## 3. `rtl/vendor/rv_uart/uart_core.sv`

### What changed

One line added at the top of the file:

```systemverilog
`include "prim_assert.sv"
```

### Why this was necessary

`uart_core.sv` uses assertion macros such as `` `ASSERT_KNOWN ``. Without `-mfcu`,
each file compiled by `vlog` is its own isolated compilation unit and does not
inherit macros from previously compiled files. Adding the include makes the file
self-sufficient with respect to assertion macros, regardless of compilation order.

---

## Summary Table

| File | Type of change | Root cause | Error fixed |
|------|---------------|------------|-------------|
| `rv_plic/prim_subreg.sv` | Added `SwAccess` enum param, `Mubi` param, `ds` output; rewrote access logic | Newer OpenTitan reg_tops use enum API + `ds` port | vopt-2912 port not found |
| `rv_plic/prim_subreg_ext.sv` | Added `ds` output port | Newer OpenTitan reg_tops connect `.ds()` | vopt-2912 port not found |
| `rv_uart/uart_core.sv` | Added `` `include "prim_assert.sv" `` | No `-mfcu`; macros not in scope | Undefined macros / syntax errors |

---

## Background

The Level-1 peripheral subsystem (`t1_periph_ss_l1`) uses OpenTitan `uart.sv` and
`gpio.sv` from `rtl/vendor/rv_uart/` and OpenTitan GPIO.  These IP blocks were
designed to be compiled as part of the full OpenTitan build system which sets up
assertion macro includes globally.

In a standalone QuestaSim compile without `-mfcu`, assertion macros are invisible
unless explicitly included.  The targeted changes above resolve this without
modifying the rest of the vendor tree.
