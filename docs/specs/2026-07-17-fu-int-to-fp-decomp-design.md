# fu_int_to_fp_decomp — Design Spec

**Date:** 2026-07-17
**Status:** Approved (design)
**Share group:** 8 (`arith.sitofp`, `arith.uitofp`) — ⚪ "decomposable, feasible but marginal" in
`DECOMPOSABILITY_ANALYSIS.md`.
**Deliverable:** standalone RTL + self-checking testbench (DPI-C golden)

## 1. Context & decomposability

Integer→float conversion's datapath is a **leading-zero count + normalize shifter + RNE
rounder** — lane-separable and combinational. Decomposing couples the integer lane width to the
FP output format: int16→fp16, int32→fp32, int64→fp64. The LZC+shifter segment cleanly; the
per-mode overhead is that the exponent bias, mantissa width, and field packing switch with `mode`
(the "marginal" caveat). Second **unary** FU. One module covers both group-8 members via a global
`is_signed` (1 = `sitofp`, 0 = `uitofp`).

`decomposability = [32,16]` → 1×(int64→fp64) / 2×(int32→fp32) / 4×(int16→fp16), RNE rounding.

## 2. Semantics

Convert each lane's `W`-bit integer to the lane's IEEE format with round-to-nearest-even.
Signed (`is_signed=1`): interpret two's-complement, produce sign + magnitude. Unsigned: magnitude
= value. `0 → +0.0`. Values with more significant bits than the mantissa are rounded (RNE); a value
that rounds beyond the format max becomes `+Inf` (e.g. `uitofp` of `0xFFFF` to fp16 → +Inf). No
NaN (integers are never NaN). Result sign is 0 except for negative signed inputs.

## 3. Interface (unary)

```systemverilog
module fu_int_to_fp_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=int64→fp64, 01=2×int32→fp32, 10=4×int16→fp16, 11=rsvd→00
  input  logic        is_signed,       // global: 1=sitofp, 0=uitofp
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,   // integer in
  output logic [63:0] out_data, output logic out_valid, input logic out_ready       // FP out
);
```

Single operand — 1-input handshake (`out_valid = in_valid_0`, `in_ready_0 = out_ready & out_valid`).
Little-endian lanes; `is_signed` global.

## 4. Datapath (combinational)

Per lane `i2f_lane(x, is_signed, EXP_W, MAN_W)` (`W = 1+EXP_W+MAN_W`):
- `sign = is_signed & x[W-1]`; magnitude `mag = sign ? (−x mod 2^W) : x` (W-bit). `mag==0 → +0`.
- Find MSB position `p` of `mag`; biased exponent `bexp = p + bias`.
- Left-justify `mag` so its MSB sits at bit `IMP` (=120) in a 128-bit field (exact — no bits lost).
- Round RNE at the mantissa LSB (bit `IMP−MAN_W`): guard = bit below, sticky = OR of the rest;
  `round_up = guard & (lsb | sticky)`; a rounding carry bumps `bexp`.
- If `bexp ≥ EXP_ONES` → `+Inf` (round-overflow); else pack `{sign, bexp, mantissa}`.

Top: per-mode lane calls + mode mux (`00`/reserved `11` → int64→fp64). The LZC + shifter + rounder
is one description reused at all widths — functional decomposition; a physically-shared segmented
converter is the synthesis/area objective.

## 5. Handshake & latency

Unary, combinational, latency 0.

## 6. Verification — DPI-C golden

`tb/fu_int_to_fp_decomp_golden.c`: trusted C casts — `(double)(int64_t/uint64_t)`,
`(float)(int32_t/uint32_t)`, and for fp16 `(float)(int16_t/uint16_t)` then F16C to fp16 (the
int16 value is exact in float, so it's a single RNE rounding). Bit-exact compare (no NaN possible).
Directed: 0, ±1, ±5, powers of two, exact-boundary (2^MAN_W), rounding (2^(MAN_W+1)+1), max/min
signed, unsigned max (→Inf for fp16), per-lane independence, both signednesses. ~20,000 uniform +
~20,000 large-magnitude random over `(mode, is_signed, a)`. `$fatal(1)` on mismatch. `run.sh`
compiles the golden with `-mf16c`.

## 7. Out of scope / follow-ups

- **Physical shared segmented converter** (area objective); **area validation**; **pipelining**;
  **`fp_to_int`** (group 9, the reverse); **generator/share-group integration**; **generalization**.
