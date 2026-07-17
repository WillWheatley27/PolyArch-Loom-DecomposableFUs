# fu_rounding_decomp — Implementation Plan

**Date:** 2026-07-17
**Spec:** `docs/specs/2026-07-17-fu-rounding-decomp-design.md`

TDD with a DPI-C golden. First **unary** FU (1-input handshake).

## Step 1 — RED: golden + testbench + stub
- `tb/fu_rounding_decomp_golden.c`: `g_fp64_round` (double), `g_fp32_round` (float),
  `g_fp16_round` (F16C), each `(x, round_mode)` dispatching to C `floor`/`ceil`/`trunc`/
  `round`/`rint` (reserved → trunc). Returns result bits.
- `tb/tb_fu_rounding_decomp.sv`: unary DUT; golden per lane per mode; NaN-lenient else bit-exact.
  Directed (each mode × key values incl ties, ±0, Inf, NaN, subnormal) + ~20k uniform +
  ~20k small-exponent random. Unary handshake tasks.
- `rtl/fu_rounding_decomp.sv` **stub**: handshake; `out_data = ~in_data_0` (not a rounding) → RED.
- Verify: `./run.sh fu_rounding_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: shared rounding core
- `round_lane(x, round_mode, EXP_W, MAN_W)`: decode; return x for NaN/Inf/±0/integral; else
  mask fractional bits + conditional increment (guard/sticky/int_lsb, per-mode `inc`);
  handle `E<0` (→±0/±1) and carry (exponent bump). Per-mode lane calls + mode mux.
- Verify: `PASS:`; other modules still pass.

## Step 3 — docs / build / synth
- README section; commit series (docs → RED → GREEN → README), author `WillWheatley27`,
  subject-only; push. Then synthesize on SAED14nm (DC, both corners) and add to the PPA chart.
