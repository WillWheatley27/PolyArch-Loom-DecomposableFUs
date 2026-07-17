# fu_int_to_fp_decomp — Implementation Plan

**Date:** 2026-07-17
**Spec:** `docs/specs/2026-07-17-fu-int-to-fp-decomp-design.md`

TDD with a DPI-C golden. Unary FU.

## Step 1 — RED: golden + testbench + stub
- `tb/fu_int_to_fp_decomp_golden.c`: `g_fp64_i2f`/`g_fp32_i2f`/`g_fp16_i2f`, each `(x, is_signed)`
  doing the trusted C int→float cast (fp16 via float then F16C). Returns FP bits.
- `tb/tb_fu_int_to_fp_decomp.sv`: unary DUT; golden per lane per mode; bit-exact compare.
  Directed (0, ±small, powers of 2, rounding, max/min, unsigned-max→Inf, both signedness) +
  ~20k uniform + ~20k large-magnitude random. Unary handshake tasks.
- `rtl/fu_int_to_fp_decomp.sv` **stub**: handshake; `out_data = in_data_0` (identity, not a
  conversion) → RED.
- Verify: `./run.sh fu_int_to_fp_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: shared converter core
- `i2f_lane(x, is_signed, EXP_W, MAN_W)`: sign/magnitude; MSB find; left-justify to a wide field;
  RNE round; round-overflow → Inf; pack. Per-mode lane calls + mode mux.
- Verify: `PASS:`; other modules still pass.

## Step 3 — docs / build / synth
- README section; commit series (docs → RED → GREEN → README), author `WillWheatley27`,
  subject-only; push. Then synthesize on SAED14nm (DC, both corners) and add to the PPA chart.
