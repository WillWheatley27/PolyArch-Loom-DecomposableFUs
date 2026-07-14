# fu_fp_add_sub_decomp — Design Spec

**Date:** 2026-07-14
**Status:** Approved (design)
**Share group:** 10 (`arith.addf`, `arith.subf`) — Tier-A in `DECOMPOSABILITY_ANALYSIS.md`.
**Deliverable:** standalone RTL + self-checking testbench (DPI-C golden; no generator wiring)

## 1. Context & decomposability

FP add/sub is Tier-A decomposable: the dominant area — the mantissa **alignment shifter**,
**mantissa adder/subtractor**, **normalization (LZC + shifter)**, and rounding — scales with
significand width and is *lane-separable*. A datapath sized for fp64's 53-bit significand
segments into 2×(fp32 24-bit) or 4×(fp16 11-bit); the mantissa adder breaks carries like
`fu_add_sub_decomp`, and the shifters are mode-gated so a lane's shift cannot cross into a
neighbor. Neither disqualifier applies: it is *combinational* (not an iterative FSM like
dividers) and has *no per-format constant tables* (unlike transcendentals) — the only format
dependence is field widths and exponent bias, which are cheap muxes. This is exactly packed-FP
SIMD (GPU packed-fp16 add).

`decomposability = [32, 16]` maps to IEEE formats:

| mode | lanes | format (sign/exp/mant, bias) |
|------|-------|------------------------------|
| 1×64 | [63:0]                            | binary64: 1/11/52, bias 1023 |
| 2×32 | [31:0], [63:32]                   | binary32: 1/8/23, bias 127 |
| 4×16 | [15:0],[31:16],[47:32],[63:48]    | binary16: 1/5/10, bias 15 |

## 2. Fidelity — full IEEE-754

- **Rounding:** round-to-nearest, ties-to-even (RNE) only.
- **Subnormals:** full gradual underflow on inputs and outputs.
- **Specials:** NaN (input propagation → canonical qNaN out), ±Inf (Inf−Inf → NaN, Inf±finite → Inf),
  signed zero (RNE sign rules: `x−x=+0`, `−0 + −0 = −0`, `+0 + −0 = +0`).
- **op_sel** per lane: `0`=add, `1`=subtract (`a − b`, implemented by flipping b's sign bit).

Area inequality `Area(1 decomposable FPU) < Area(fp64)+2·fp32+4·fp16` is a **synthesis** result
(follow-up, §8), not claimed from RTL.

## 3. Interface

```systemverilog
module fu_fp_add_sub_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=1×fp64, 01=2×fp32, 10=4×fp16, 11=rsvd→1×fp64
  input  logic [3:0]  op_sel,          // per-lane 0=add, 1=sub (flip b sign)
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

Little-endian lane packing (lane0 = LSBs). `op_sel` lane mapping matches `fu_add_sub_decomp`:
1×64→`op_sel[0]`; 2×32→`op_sel[0],op_sel[2]`; 4×16→`op_sel[0..3]`. No flag outputs.

## 4. Datapath — shared format-parameterized IEEE core

One SV `function` `fp_lane(a, b, sub, EXP_W, MAN_W)` implements a full IEEE-754 add/sub for a
single lane of the given format, operating on a **uniform internal representation**
(64-bit left-justified significand, implicit bit at bit 63, signed biased exponent). The
core — unpack → align (right-shift smaller significand, collect sticky) → add/sub → normalize
(LZC + left-shift, exponent-clamped for gradual underflow) → round (RNE via guard/round/sticky)
→ pack (handling overflow→Inf, underflow→subnormal, specials) — is written **once** and reused
for all formats/lanes; only `MAN_W` (round position) and `EXP_W` (bias/exponent limits) differ,
as cheap muxes. This is the shared-datapath description the decomposition thesis rests on.

Each call site passes **compile-time-constant** `EXP_W`/`MAN_W`, so the function specialises per
format under constant propagation. The top calls it per active lane and mode-muxes the packed
output:

```
1×64 : fp_lane(in0[63:0],  in1[63:0],  op_sel[0], 11, 52)
2×32 : {fp_lane(in0[63:32],in1[63:32], op_sel[2], 8, 23),
        fp_lane(in0[31:0], in1[31:0],  op_sel[0], 8, 23)}
4×16 : {fp_lane(in0[63:48],in1[63:48], op_sel[3], 5, 10), ... , fp_lane(in0[15:0],in1[15:0],op_sel[0],5,10)}
out  = (mode==2×32) ? p2 : (mode==4×16) ? p4 : p1     // 00 and reserved 11 → p1
```

This RTL proves **functional** decomposition (correct independent per-lane IEEE results, no
cross-lane interference, one core description at three widths). **Physical** single-datapath
sharing (a segmented aligner/adder/normalizer that morphs 1×53b ↔ 4×11b) is the synthesis
objective — same status as the area inequality that is a follow-up for every module here (§8).

## 5. Handshake & latency

Unchanged from the family — 2-input join, combinational, latency 0
(`out_valid = in_valid_0 & in_valid_1`, `in_ready_* = out_ready & out_valid`). A real FP adder
would pipeline; the combinational core proves functional decomposition (pipelining is a
synthesis follow-up, §8).

## 6. Verification — DPI-C hardware golden

Verilator does **not** support `shortreal` (promotes to `real`), so native fp32/fp16 arithmetic
is unavailable in pure SV. The golden is therefore **hardware FP via DPI-C** (`tb/fu_fp_add_sub_decomp_golden.c`):
`double` (fp64), `float` (fp32), and **F16C** intrinsics `_cvtsh_ss`/`_cvtss_sh` (fp16). This is
a fully DUT-independent, bit-exact reference with zero hand-written rounding. `run.sh` compiles
the C file with `-mf16c` when present.

**Golden per lane:** `g_fpNN_add(a_lane, b_lane, op_sel_lane)`; results repacked per mode.

**NaN comparison is lenient:** IEEE leaves qNaN payload/sign unspecified, so when the golden
result is a NaN the check requires only that the DUT result is *a* NaN (exp all-ones, mantissa≠0).
All non-NaN results (including signed zero and subnormals) are compared bit-exact.

**Directed corners (per format):** basic normals; signed-zero rules (`x−x`, `−0+−0`, `+0+−0`);
Inf (`inf+inf`, `inf−inf`→NaN, `inf+finite`); NaN propagation; subnormals (min-subnormal sums,
subnormal↔normal boundary, cancellation into subnormal range); RNE ties (round-to-even);
overflow→Inf; massive-cancellation left-normalize; per-lane independence and mixed add/sub;
2×32-vs-1×64 and 4×16 lane-isolation (a lane's Inf/overflow must not touch neighbors).

**Randomized:** ~20,000 uniform-random vectors over `(mode, op_sel, a, b)`, plus a second
~20,000 batch with exponents constrained near zero/format-min to stress subnormals, ties, and
near-equal cancellation.

**PASS/FAIL:** single `PASS:`/`FAIL:` line; `$fatal(1)` on any mismatch.

## 7. `run.sh`

`verilator --lint-only -Wall` on the RTL (clean), then `verilator --binary --timing` with the
optional `tb/<mod>_golden.c` and `-mf16c`, grep `^PASS:`. Invoked `./run.sh fu_fp_add_sub_decomp`.

## 8. Out of scope / follow-ups

- **Area validation** (synthesis: decomposable vs bank) — the motivating inequality.
- **Physical segmented datapath** — a single aligner/adder/normalizer that reconfigures across
  widths (this RTL proves functional decomposition; physical sharing is the area objective).
- **Pipelining / timing.**
- **Alternative rounding modes** (only RNE here); **exception flags** (inexact/overflow/invalid).
- **Generator/share-group integration** and **generalization** to other base widths.
