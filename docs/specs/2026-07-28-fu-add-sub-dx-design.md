# fu_add_sub_dx — Design Spec

**Date:** 2026-07-28
**Status:** Approved (design)
**Op:** `arith.addi` / `arith.subi` (share group `integer_add_sub`) — **duplex** decomposition.
**Family:** *64/32-only decomposable* FUs (new). One split boundary at bit 32 → **1×64 or 2×32**
lanes only (no 16-bit). Built on the **DesignWare** duplex adder `DW_addsub_dx`.
**Deliverable:** synthesizable RTL + self-checking Verilator testbench (native-SV golden).

## 1. Why 64/32-only + DesignWare

This module opens a second FU family: decomposable at a **single** 32-bit boundary rather than the
three-way 16/32/48 segmentation of `fu_add_sub_decomp`. The narrower scope is a *perfect* match for a
Synopsys DesignWare Building Block: **`DW_addsub_dx` is a natively 2-way duplex adder-subtractor**
(`dplx` runtime knob, split point `p1_width`). Mapping our decomposition onto it needs **no manual
carry-kill** — the vendor block *is* the segmented datapath, pre-verified and area-optimized.

Per the DWBB directive, this FU **instantiates `DW_addsub_dx` directly** (not operator inference), so
both simulation (Verilator, via the DW `sim_ver` model) and synthesis (DC, via `dw_foundation.sldb`)
exercise the same vendor component.

## 2. Modes & semantics

| `mode` | Lanes | Lane width |
|--------|-------|-----------|
| `2'b00` | 1×64 | one 64-bit add/sub |
| `2'b01` | 2×32 | two independent 32-bit add/sub |
| `2'b10`,`2'b11` | reserved → behaves as 1×64 | — |

- **`op_sel[1:0]`** — per-32-bit-lane op: `0`→add, `1`→subtract. In 1×64 mode only `op_sel[0]`
  applies (controls the single lane); `op_sel[1]` is ignored.
- Little-endian lanes (lane 0 = bits [31:0]). Two's-complement wrap (no saturation).

## 3. Interface (2-input join)

```systemverilog
module fu_add_sub_dx (
  input  logic        clk, rst_n,        // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,              // 00=1×64, 01=2×32, rsvd→1×64
  input  logic [1:0]  op_sel,            // per-lane add(0)/sub(1)
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,  // a
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,  // b
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

**2-input join** handshake: `out_valid = v0 & v1`, `in_ready_i = out_ready & out_valid`.
Combinational, latency 0.

## 4. Datapath — mapping onto `DW_addsub_dx`

`DW_addsub_dx #(.width(64), .p1_width(32))` runs in **add mode** (`addsub=0`, `tc=sat=avg=0`); per-lane
subtract is realized the classic way — **invert the subtracting lane's `b` and inject that segment's
carry-in** (`a − b = a + ~b + 1`). The block's dual carry-ins `ci1`/`ci2` make the two segments
independent:

```
dplx   = (mode == 2'b01)
sub_lo = op_sel[0]
sub_hi = dplx ? op_sel[1] : op_sel[0]     // 1×64: whole word uses op_sel[0]
b_eff[31:0]  = b[31:0]  ^ {32{sub_lo}}
b_eff[63:32] = b[63:32] ^ {32{sub_hi}}
ci1 = sub_lo ; ci2 = sub_hi               // ci2 used only when dplx=1
DW_addsub_dx(.a(a), .b(b_eff), .ci1, .ci2, .addsub(0), .tc(0), .sat(0), .avg(0),
             .dplx(dplx), .sum(out_data), .co1(), .co2())
```

- **1×64 subtract:** both halves of `b` inverted (both use `op_sel[0]`), `ci1=1`, `dplx=0` →
  `a + ~b + 1 = a−b` across the full 64-bit chain (carry crosses bit 32).
- **2×32:** low = `a_lo ± b_lo + ci1`, high = `a_hi ± b_hi + ci2`, independent (no carry across bit 32).

## 5. Verification

Native-SV golden (per-lane wrap add/sub, mode-dependent). Directed: carry **crossing** bit 32 in 1×64
vs **blocked** in 2×32 (mode-isolation proof); 1×64 sub / INT_MIN edges; 2×32 mixed op (low add + high
sub); reserved-mode → 1×64. Handshake corners (backpressure, input-invalid). ~20k random over
`(mode, op_sel, a, b)`. Bit-exact; `$fatal(1)` on mismatch. `./run.sh fu_add_sub_dx` (auto-loads the
DW sim library).

## 6. Out of scope / follow-ups

- **Physical shared-datapath / area inequality** for the 64/32 family — the synthesis corners below
  measure it directly (DW duplex is one shared block).
- Rest of the 64/32-only family: Mult (`DW_mult_dx`), cmp (`DW_cmp_dx`), then FP (no DW duplex FP —
  hand-written) and the conversions.
