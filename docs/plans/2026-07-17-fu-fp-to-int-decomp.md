# fu_fp_to_int_decomp — Implementation Plan

**Date:** 2026-07-17
**Spec:** `docs/specs/2026-07-17-fu-fp-to-int-decomp-design.md`

TDD with a DPI-C golden. Unary FU. Saturating, round-toward-zero.

## Step 1 — RED: golden + testbench + stub
- `tb/fu_fp_to_int_decomp_golden.c`: `g_fp64_f2i`/`g_fp32_f2i`/`g_fp16_f2i`, each `(x, is_signed)`
  = C `trunc` + explicit int-range clamp + NaN→0 (fp16 via F16C→float). Returns integer bits.
- `tb/tb_fu_fp_to_int_decomp.sv`: unary DUT; golden per lane per mode; bit-exact compare.
  Directed (trunc, saturate over/under, ±Inf, NaN, ±0, subnormal, both signedness) + ~20k
  uniform + ~20k large-magnitude random. Unary handshake tasks.
- `rtl/fu_fp_to_int_decomp.sv` **stub**: handshake; `out_data = in_data_0` (identity) → RED.
- Verify: `./run.sh fu_fp_to_int_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: shared converter core
- `f2i_lane(x, is_signed, EXP_W, MAN_W)`: NaN→0; Inf→saturate; E<0→0; else truncated magnitude
  (shift, `E≥64` guard) + sign/saturation clamp. Per-mode lane calls + mode mux.
- Verify: `PASS:`; other modules still pass.

## Step 3 — docs / build / synth
- README section; commit series (docs → RED → GREEN → README), author `WillWheatley27`,
  subject-only; push. Then synthesize on SAED14nm (DC, both corners) and add to the PPA chart.
