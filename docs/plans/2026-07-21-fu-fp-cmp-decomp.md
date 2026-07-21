# fu_fp_cmp_decomp — Implementation Plan

**Date:** 2026-07-21
**Spec:** `docs/specs/2026-07-21-fu-fp-cmp-decomp-design.md`

TDD with a DPI-C golden. Reuses the `fp_min_max` sign+magnitude comparator (with −0==+0) and the
`cmp` mask-output + predicate-mux structure.

## Step 1 — RED: golden + testbench + stub
- `tb/fu_fp_cmp_decomp_golden.c`: `g_fp64_cmpf`/`g_fp32_cmpf`/`g_fp16_cmpf`, each `(a,b,pred)`
  decode to double (fp16 via F16C) and evaluate the predicate via C relational ops + `isnan`.
  Returns 0/1.
- `tb/tb_fu_fp_cmp_decomp.sv`: golden per lane per mode → replicate to mask; bit-exact compare.
  Directed (every predicate; ±0, NaN, Inf, equal, lt, gt, subnormal) + ~20k uniform + ~20k
  small-exponent random. Reuse handshake tasks.
- `rtl/fu_fp_cmp_decomp.sv` **stub**: handshake; `out_data = in_data_0 ^ in_data_1` → RED.
- Verify: `./run.sh fu_fp_cmp_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: shared FP comparator + predicate mux
- `fp_cmp_lane(pred,a,b,EXP_W,MAN_W)`: decode; `uno`; both-zero→eq else sign+magnitude lt/gt;
  16-way predicate mux → 1-bit. Per-mode lane calls + mode mux + mask replication.
- Verify: `PASS:`; other modules still pass.

## Step 3 — docs / build / synth
- README section; commit series (docs → RED → GREEN → README), author `WillWheatley27`,
  subject-only; push. Then synthesize on SAED14nm (DC, both corners) and add to the PPA chart.
