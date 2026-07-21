# fu_fp_cmp_decomp — Design Spec

**Date:** 2026-07-21
**Status:** Approved (design)
**Op:** `arith.cmpf` — packed floating-point compare. Singleton, predicate-configurable op (not
a hardware share group); the float sibling of `fu_cmp_decomp`.
**Deliverable:** standalone RTL + self-checking testbench (DPI-C golden)

## 1. Context & decomposability

FP comparison is a sign+magnitude comparator + boolean output — the same lane-separable datapath
as `fu_fp_min_max_decomp`, so it decomposes. As a **packed** FU it emits a per-lane **mask**
(all-ones/all-zeros over the lane width — SSE `CMPPS`-style). Combinational, no constant tables →
decomposable.

`decomposability = [32,16]` → 1×fp64 / 2×fp32 / 4×fp16 independent lanes.

## 2. Semantics — IEEE ordered/unordered predicates

Per lane the comparison yields **`uno`** (either operand NaN) and, for non-NaN operands, a
trichotomy **`lt/eq/gt`** where **−0 == +0** (IEEE compare, *not* the −0<+0 of min/max).
`pred[3:0]` (global) selects one of the 16 MLIR `arith.cmpf` predicates:

| pred | | pred | | pred | | pred | |
|---|---|---|---|---|---|---|---|
| 0 | false | 4 | OLT | 8 | UEQ | 12 | ULE |
| 1 | OEQ | 5 | OLE | 9 | UGT | 13 | UNE |
| 2 | OGT | 6 | ONE | 10 | UGE | 14 | UNO |
| 3 | OGE | 7 | ORD | 11 | ULT | 15 | true |

Ordered `O*` = `!uno & relation`; unordered `U*` = `uno | relation`; `ORD = !uno`; `UNO = uno`.
`out_lane = predicate ? all-ones : all-zeros`.

## 3. Interface

```systemverilog
module fu_fp_cmp_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=1×fp64, 01=2×fp32, 10=4×fp16, 11=rsvd→1×fp64
  input  logic [3:0]  pred,            // held: predicate selector (global, table above)
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

2-input join handshake. Little-endian lanes. `out_data` is the packed lane mask.

## 4. Datapath (combinational)

Per lane `fp_cmp_lane(pred, a, b, EXP_W, MAN_W)`:
- Decode; `uno = a_nan | b_nan`; magnitude bits `mag = {exp,mant}`.
- Trichotomy: if both operands are zero → `eq` (−0==+0); else `lt/gt` by sign+magnitude
  (differing signs: negative is less; same sign: unsigned magnitude order, reversed if negative),
  `eq = ~lt & ~gt`.
- 16-way predicate mux (`O*` gated by `~uno`, `U*` OR-ed with `uno`) → 1-bit; broadcast to the
  lane mask.
- Top: per-mode lane calls + mode mux; mask replication per lane width. Shared comparator reused
  at all widths (functional decomposition; physically-shared segmented comparator is the
  synthesis/area objective).

## 5. Handshake & latency

2-input join, combinational, latency 0.

## 6. Verification — DPI-C golden

`tb/fu_fp_cmp_decomp_golden.c`: decode each format to `double` (fp32/fp16 exact; fp16 via F16C)
and evaluate the predicate with C's NaN-aware relational operators + `isnan` — trusted, matches
the ordered/unordered definitions and `−0==+0`. Returns the boolean; TB replicates to the mask.
Bit-exact compare. Directed: every predicate on ±0/±0, NaN (ordered→false, unordered→true), Inf,
equal, a<b, a>b, subnormal; per-lane independence. ~20,000 uniform + ~20,000 small-exponent
random over `(mode, pred, a, b)`. `$fatal(1)` on mismatch. `-mf16c`.

## 7. Out of scope / follow-ups

- **Physical shared segmented comparator**; **area validation**; **generator integration**.
