# fu_fp_to_int_decomp — Design Spec

**Date:** 2026-07-17
**Status:** Approved (design)
**Share group:** 9 (`arith.fptosi`, `arith.fptoui`) — ⚪ "decomposable, feasible but marginal" in
`DECOMPOSABILITY_ANALYSIS.md`. The reverse of group 8; the last decomposable candidate.
**Deliverable:** standalone RTL + self-checking testbench (DPI-C golden)

## 1. Context & decomposability

Float→integer conversion's datapath is an **align/denormalize shifter** (shift the significand by
the exponent to expose the integer part) plus range/saturation logic — lane-separable and
combinational. Decomposing couples the FP input format to the integer lane width: fp16→int16,
fp32→int32, fp64→int64. The shifter segments cleanly; per-mode overhead is that the exponent bias,
significand width, and integer range switch with `mode`. Third **unary** FU; covers both group-9
members via a global `is_signed` (1 = `fptosi`, 0 = `fptoui`).

`decomposability = [32,16]` → 1×(fp64→int64) / 2×(fp32→int32) / 4×(fp16→int16).

## 2. Semantics — saturating, round-toward-zero

`arith.fptosi`/`fptoui` are UB on out-of-range/NaN, so this FU implements the standard **defined**
hardware behavior (as in `llvm.fptosi.sat`/RISC-V FCVT/ARM):
- **Round toward zero** (truncate the fractional part).
- **Saturate** out-of-range: signed → clamp to `[−2^(W−1), 2^(W−1)−1]`; unsigned → clamp to
  `[0, 2^W−1]` (negative values, incl `−0`/subnormals below 1, → 0).
- **NaN → 0**. **±Inf** → saturate (+Inf → max, −Inf → signed min / unsigned 0).
- `|x| < 1` → 0.

## 3. Interface (unary)

```systemverilog
module fu_fp_to_int_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=fp64→int64, 01=2×fp32→int32, 10=4×fp16→int16, 11=rsvd→00
  input  logic        is_signed,       // global: 1=fptosi, 0=fptoui
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,   // FP in
  output logic [63:0] out_data, output logic out_valid, input logic out_ready       // integer out
);
```

Single operand — 1-input handshake. Little-endian lanes; `is_signed` global.

## 4. Datapath (combinational)

Per lane `f2i_lane(x, is_signed, EXP_W, MAN_W)` (`W = 1+EXP_W+MAN_W`):
- Decode; `NaN → 0`; `±Inf →` saturate by sign; unbiased `E = exp − bias`.
- `E < 0` (`|x| < 1`) `→ 0`.
- Else truncated magnitude `M = (E ≤ MAN_W) ? (sig >> (MAN_W−E)) : (sig << (E−MAN_W))`, computed
  in 64 bits with an `E ≥ 64` overflow guard.
- Saturate & sign: signed negative → `−M` unless `M > 2^(W−1)` (→ min); signed positive → `M`
  unless `M ≥ 2^(W−1)` (→ max); unsigned negative → 0; unsigned positive → `M` unless `M ≥ 2^W`
  (→ max). (`M == 2^(W−1)` negated yields exactly `INT_MIN`.)

Top: per-mode lane calls + mode mux. Shared shifter + saturation logic reused at all widths —
functional decomposition; a physically-shared segmented converter is the synthesis/area objective.

## 5. Handshake & latency

Unary, combinational, latency 0.

## 6. Verification — DPI-C golden

`tb/fu_fp_to_int_decomp_golden.c`: C `trunc` on `double`/`float`/(F16C→float) plus explicit range
clamp and NaN→0, matching the saturating semantics (independent of the DUT's integer field logic).
Bit-exact compare. Directed: 0, ±0, ±1.5/±2.7 (trunc), values at/over the int max/min (saturate),
±Inf, NaN, subnormal, both signedness, per-lane independence. ~20,000 uniform + ~20,000
large-magnitude random over `(mode, is_signed, a)`. `$fatal(1)` on mismatch. `-mf16c`.

## 7. Out of scope / follow-ups

- **Physical shared segmented converter** (area objective); **area validation**; **pipelining**;
  **non-saturating / exception-flag variants**; **generator/share-group integration**.
