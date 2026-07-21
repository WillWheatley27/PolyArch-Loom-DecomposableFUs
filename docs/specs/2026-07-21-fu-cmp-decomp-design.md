# fu_cmp_decomp — Design Spec

**Date:** 2026-07-21
**Status:** Approved (design)
**Op:** `arith.cmpi` — packed integer compare. **Not a hardware share group** (it is a
singleton, predicate-configurable op in loom's `fabric.op` catalog, not in the multi-member
share-group table), but it is genuinely lane-separable — the first decomposable FU built from
outside the share-group scope.
**Deliverable:** standalone RTL + self-checking testbench (native-SV golden)

## 1. Context & decomposability

Integer comparison is a magnitude comparator + boolean output — the same lane-separable
datapath as `fu_min_max_decomp`, so it decomposes cleanly. As a **packed** FU it produces a
per-lane **mask** (all-ones/all-zeros over the lane width), the standard SIMD compare output
(SSE `PCMPGT*`, AVX). Combinational, no constant tables → decomposable.

`decomposability = [32,16]` → 1×64 / 2×32 / 4×16 independent integer lanes.

## 2. Semantics

`out_lane = pred(a_lane, b_lane) ? all-ones : all-zeros` over the lane width. `pred` (global,
per-instruction) selects one of the 10 MLIR `arith.cmpi` predicates; signedness is part of the
predicate:

| pred | op | | pred | op |
|---|---|---|---|---|
| 0 | eq | | 5 | sge |
| 1 | ne | | 6 | ult |
| 2 | slt | | 7 | ule |
| 3 | sle | | 8 | ugt |
| 4 | sgt | | 9 | uge |

Reserved codes (10–15) → all-zeros (false).

## 3. Interface

```systemverilog
module fu_cmp_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=1×64, 01=2×32, 10=4×16, 11=rsvd→1×64
  input  logic [3:0]  pred,            // held: predicate selector (global, table above)
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

2-input join handshake (binary op). Little-endian lanes. `out_data` is the packed lane mask.

## 4. Datapath — shared segmented comparator + predicate mux (combinational)

Split into four 16-bit blocks. Per block: `gtu_k = a_k > b_k` (unsigned), `eq_k = a_k == b_k`;
signed top-block adjust `gts_k = (top_k & (a_k[15]^b_k[15])) ? b_k[15] : gtu_k` (as in `min_max`).
Three mode-gated lexicographic combines (broken at lane starts):
- `r_u[k]` — unsigned `a>b` (uses `gtu`),
- `r_s[k]` — signed `a>b` (uses `gts`),
- `e[k]` — lane `a==b` (AND of the lane's block `eq`s).

Per lane-top `k`, the predicate result:

```
eq: e ; ne: ~e ; sgt: r_s ; sge: r_s|e ; slt: ~(r_s|e) ; sle: ~r_s
ugt: r_u ; uge: r_u|e ; ult: ~(r_u|e) ; ule: ~r_u ; reserved: 0
```

Route each block to its lane's result (1×64→`k=3`; 2×32→`k∈{1,3}`; 4×16→`k∈{0..3}`) and
broadcast: `out_block = {16{res}}`. Shared block comparators reused across modes; only the
combine breaks and output routing change — same pattern as `min_max`.

## 5. Handshake & latency

2-input join, combinational, latency 0.

## 6. Verification

Native-SV golden: per lane, evaluate the predicate (signed/unsigned compare at lane width via
`$signed`) → all-ones/all-zeros mask; repack. Directed: each predicate on equal / a<b / a>b /
signed-vs-unsigned boundary (e.g. `0xFFFF` = −1 signed / 65535 unsigned differ under slt vs ult);
per-lane independence; corners. ~20,000 random over `(mode, pred, a, b)`. Bit-exact; `$fatal(1)`
on mismatch. `./run.sh fu_cmp_decomp`.

## 7. Out of scope / follow-ups

- **`arith.cmpf`** (packed float compare, ordered/unordered predicates) — the sibling FU (reuses
  the `fp_min_max` sign+magnitude comparator).
- **Physical shared segmented comparator**; **area validation**; **generator integration**.
