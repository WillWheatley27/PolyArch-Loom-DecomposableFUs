# fu_fp_mult_decomp — Design Spec

**Date:** 2026-07-14
**Status:** Approved (design)
**Op:** `arith.mulf` — **not** a share group in `fabric_op_gen` (like integer multiply);
the highest-ROI decomposition target per `DECOMPOSABILITY_ANALYSIS.md`. Standalone RTL.
**Deliverable:** standalone RTL + self-checking testbench (DPI-C golden; no generator wiring)

## 1. Context & decomposability

FP multiply's dominant area is the **mantissa multiplier** — the `(MAN_W+1)×(MAN_W+1)`
partial-product array. This is exactly the resource `DECOMPOSABILITY_ANALYSIS.md` flags as
the single best decomposition target: a 53×53 array (fp64) segments cleanly into 2×(24×24)
(fp32) or 4×(11×11) (fp16) by zeroing cross-lane partial products — the same PP-array
segmentation as `fu_mult_decomp`. Sign XOR, exponent add, normalization, and rounding are
small per-lane overhead. Combinational, no per-format constant tables → decomposable
(Tier-A analog; even higher ROI than fp_add_sub because the multiplier dominates).

`decomposability = [32, 16]` maps to IEEE formats:

| mode | lanes | format (sign/exp/mant, bias) |
|------|-------|------------------------------|
| 1×64 | [63:0]                            | binary64: 1/11/52, bias 1023 |
| 2×32 | [31:0], [63:32]                   | binary32: 1/8/23, bias 127 |
| 4×16 | [15:0],[31:16],[47:32],[63:48]    | binary16: 1/5/10, bias 15 |

## 2. Fidelity — full IEEE-754

- **Rounding:** round-to-nearest, ties-to-even (RNE).
- **Subnormals:** full gradual underflow on inputs and outputs.
- **Specials:** NaN → canonical qNaN; `Inf × 0 = NaN`; `Inf × finite = Inf`; `0 × finite = 0`;
  signed zero / signed Inf via sign XOR.
- **No `op_sel`** — multiply has no add/sub variant; the result sign is always `sign_a ^ sign_b`
  (matches `fu_mult_decomp`, which likewise has no `op_sel`).

Area inequality is a **synthesis** follow-up (§8), not claimed from RTL.

## 3. Interface

```systemverilog
module fu_fp_mult_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=1×fp64, 01=2×fp32, 10=4×fp16, 11=rsvd→1×fp64
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

Little-endian lane packing (lane0 = LSBs). No `op_sel`, no flag outputs.

## 4. Datapath — shared format-parameterized IEEE core

One SV `function` `fp_mul_lane(a, b, EXP_W, MAN_W)` implements a full IEEE-754 multiply for a
single lane. Core: unpack + classify → `sgn = sa ^ sb` → build `(MAN_W+1)`-bit integer
significands `A,B` (implicit bit; subnormal ⇒ implicit 0) → biased product exponent
`baseExp = (E_a) + (E_b) + BIAS` (unbiased `E = e-BIAS`, or `1-BIAS` for subnormal) → exact
product `P = A·B` placed left-justified in a 128-bit field → **single-shot normalize/round/pack**:
compute the normalized biased exponent `eNorm = baseExp + msb − IMP`; if `eNorm ≥ EXP_ONES`
overflow → Inf; else shift the significand to put the mantissa LSB at a fixed rounding position
(normal: MSB→IMP; subnormal `eNorm ≤ 0`: MSB below IMP so the exponent is `emin`, gradual
underflow), collect sticky, round RNE (guard/sticky), and pack (round-carry → exp++ or
subnormal→min-normal; overflow → Inf).

Unlike fp_add_sub the product exponent can fall far below `emin`, so underflow is handled by
computing `eNorm` up front and branching normal vs subnormal (rather than an `emin`-clamped
left-shift). The mantissa multiplier — the dominant area — is one description reused at all
three widths (only `MAN_W`/`EXP_W`/bias differ, as cheap muxes).

Each call site passes compile-time-constant `EXP_W`/`MAN_W` (constant-folded per format). The
top calls it per active lane and mode-muxes the packed output (`00`/reserved `11` → fp64).

This RTL proves **functional** decomposition; **physical** single-multiplier sharing (a
segmented PP array) is the synthesis/area objective (§8), as for every module here.

## 5. Handshake & latency

Unchanged from the family — 2-input join, combinational, latency 0. A real FP multiplier
would pipeline; the combinational core proves functional decomposition (pipelining is a
synthesis follow-up, §8).

## 6. Verification — DPI-C hardware golden

Golden is hardware FP via DPI-C (`tb/fu_fp_mult_decomp_golden.c`): `double` (fp64), `float`
(fp32), and **F16C** intrinsics (fp16), each computing `a * b`. Bit-exact and DUT-independent:
the fp16 product (≤22 significand bits) is exact in `float`, and fp32 is native — no
hand-written rounding. `run.sh` compiles it with `-mf16c`.

**NaN-lenient compare** (any qNaN accepted); all else — signed zero, subnormals — bit-exact.

**Directed corners (per format):** basic normals; `1×x`, `0×x`; signed-zero/sign rules;
`Inf×finite`, `Inf×0`→NaN, `Inf×Inf`; NaN propagation; overflow (max×max→Inf); underflow
(min-subnormal products → subnormal / →0); subnormal × normal; RNE ties; per-lane independence
and lane isolation (a lane's Inf/overflow must not touch neighbors).

**Randomized:** ~20,000 uniform random `(mode, a, b)`, plus ~20,000 with exponents constrained
near format-min to stress subnormals, underflow, and rounding.

**PASS/FAIL:** single `PASS:`/`FAIL:` line; `$fatal(1)` on any mismatch.

## 7. `run.sh`

`verilator --lint-only -Wall` on the RTL, then `verilator --binary --timing` with
`tb/fu_fp_mult_decomp_golden.c` + `-mf16c`; grep `^PASS:`. `./run.sh fu_fp_mult_decomp`.

## 8. Out of scope / follow-ups

- **Area validation** (synthesis: decomposable vs bank).
- **Physical segmented PP array** — one multiplier that reconfigures across widths (this RTL
  proves functional decomposition; physical sharing is the area objective).
- **Pipelining / timing.**
- **Alternative rounding modes** (only RNE); **exception flags**; **FMA**.
- **Generator/share-group integration** (add `arith.mulf`) and **generalization**.
