# fu_fp_min_max_decomp — Design Spec

**Date:** 2026-07-17
**Status:** Approved (design)
**Share group:** 12 (`arith.minimumf`, `arith.maximumf`) — Tier-A in
`DECOMPOSABILITY_ANALYSIS.md`; the last module in the recommended build order.
**Deliverable:** standalone RTL + self-checking testbench (DPI-C golden)

## 1. Context & decomposability

FP min/max is Tier-A decomposable: its datapath is a **floating-point comparator** (a
sign+magnitude / monotonic-key compare) plus an output mux — lane-separable exactly like the
integer `min_max` comparator, and combinational with no per-format constant tables. This is the
FP counterpart of `fu_min_max_decomp`, reusing that segmented-compare idea with per-format NaN /
signed-zero handling. It completes the ✅-recommended decomposable set.

`decomposability = [32,16]` → 1×fp64 / 2×fp32 / 4×fp16, per-lane min/max.

## 2. Semantics — IEEE-754-2019 minimum/maximum

`arith.minimumf` / `arith.maximumf` (the *imum* variants):
- **NaN-propagating:** if either operand is NaN → result is NaN (canonical qNaN).
- **Signed zeros:** −0.0 is strictly less than +0.0. So `minimum(−0,+0) = −0`, `maximum(−0,+0) = +0`.
- Otherwise the numeric min/max (Inf and subnormals fall out of the magnitude compare; no rounding
  — the result is always exactly one of the inputs).

(Contrast `minnumf`/`maxnumf`, the NaN-*suppressing* IEEE-2008 variants — not this group.)

## 3. Interface

```systemverilog
module fu_fp_min_max_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=1×fp64, 01=2×fp32, 10=4×fp16, 11=rsvd→1×fp64
  input  logic [3:0]  op_sel,          // per-lane: 0=min, 1=max
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

Little-endian lanes; `op_sel` lane mapping matches the family (1×64→`op_sel[0]`;
2×32→`op_sel[0],op_sel[2]`; 4×16→`op_sel[0..3]`). No `is_signed` (FP).

## 4. Datapath — shared FP comparator (combinational)

Per lane `fp_mm_lane(a, b, is_max, EXP_W, MAN_W)`:
- Decode `sa/sb` (sign), `ea/eb` (exp), `ma/mb` (mant); `a_nan = (ea==all-ones)&&(ma!=0)`.
- If `a_nan || b_nan` → return canonical qNaN.
- Magnitude bits `mag = {exp, mant}` (the operand with sign cleared). Order:

```
a_lt_b = (sa != sb) ? sa                         // differing signs: negative one is smaller
                    : (sa ? (mag_a > mag_b)       // both negative: larger magnitude is smaller
                          : (mag_a < mag_b));     // both positive: smaller magnitude is smaller
```

  This gives the full IEEE order including Inf (largest magnitude), subnormals, and **−0 < +0**
  (when signs differ and both are zero, `a_lt_b = sa` picks the −0 correctly).
- Select: `result = is_max ? (a_lt_b ? b : a) : (a_lt_b ? a : b)` — always exactly one input's
  bits (no rounding).

Top: call per active lane with the right `EXP_W`/`MAN_W`/`op_sel`; mode-mux the packed output
(`00`/reserved `11` → fp64). The comparator (magnitude compare) is one description reused at all
widths — functional decomposition; a physically-shared segmented FP comparator is the
synthesis/area objective (§7), consistent with the family.

## 5. Handshake & latency

Unchanged — 2-input join, combinational, latency 0.

## 6. Verification — DPI-C hardware golden

Golden `tb/fu_fp_min_max_decomp_golden.c`: hardware compare (`double`/`float`/F16C) plus explicit
NaN and ±0 handling implementing `minimum`/`maximum` — returns exactly one input's bits (or qNaN).
Independent of the DUT's integer field logic.

**NaN-lenient compare** (any qNaN accepted); everything else — **including signed zero** —
bit-exact. Directed: NaN propagation (either operand, min & max); ±0 combinations (`min/max(±0,±0)`);
Inf vs finite; subnormal vs normal; normal min/max; equal operands; per-lane mixed min/max and
cross-lane isolation (one lane NaN/Inf must not affect neighbors). ~20,000 random over
`(mode, op_sel, a, b)` + ~20,000 with small exponents (more subnormals/zeros/ties).

**PASS/FAIL:** single line; `$fatal(1)` on mismatch. `run.sh` compiles the golden with `-mf16c`.

## 7. Out of scope / follow-ups

- **Physical shared segmented FP comparator** (the area objective).
- **Area validation** (synthesis); **pipelining**; **`minnumf`/`maxnumf` (NaN-suppressing) variant**;
  **generator/share-group integration**; **generalization**.
