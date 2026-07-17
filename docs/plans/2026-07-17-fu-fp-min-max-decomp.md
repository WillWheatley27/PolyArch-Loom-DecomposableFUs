# fu_fp_min_max_decomp — Implementation Plan

**Date:** 2026-07-17
**Spec:** `docs/specs/2026-07-17-fu-fp-min-max-decomp-design.md`

TDD with a DPI-C hardware golden (like the other FP units).

## Step 1 — RED: golden + testbench + stub
- `tb/fu_fp_min_max_decomp_golden.c`: `g_fp64_minmax` (double), `g_fp32_minmax` (float),
  `g_fp16_minmax` (F16C), each `(a,b,is_max)` implementing IEEE minimum/maximum (NaN→qNaN,
  −0<+0, else hardware compare; returns one input's bits).
- `tb/tb_fu_fp_min_max_decomp.sv`: DPI golden per lane per mode; NaN-lenient compare, else
  bit-exact (incl signed zero). Directed (NaN, ±0, Inf, subnormal, mixed per-lane) + ~20k
  uniform + ~20k small-exponent random. Reuse handshake tasks.
- `rtl/fu_fp_min_max_decomp.sv` **stub**: handshake; `out_data = in_data_0 ^ in_data_1` → RED.
- Verify: `./run.sh fu_fp_min_max_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: shared FP comparator
- `fp_mm_lane(a,b,is_max,EXP_W,MAN_W)`: decode + NaN→qNaN; magnitude order with sign & −0<+0;
  select one input. Per-mode lane calls + mode mux.
- Verify: `PASS:`; other modules still pass.

## Step 3 — docs / build
- README section; commit series (docs → RED → GREEN → README), author `WillWheatley27`,
  subject-only; push.
