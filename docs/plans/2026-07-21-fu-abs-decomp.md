# fu_abs_decomp — Implementation Plan

**Date:** 2026-07-21
**Spec:** `docs/specs/2026-07-21-fu-abs-decomp-design.md`

TDD, native-SV golden (abs is exact — no DPI). Unary FU, covers `math.absf` + `math.absi`.

## Step 1 — RED: testbench + stub
- `tb/tb_fu_abs_decomp.sv`: golden `abs16/abs32/abs64(is_float, x)` per lane — clear sign bit
  (absf) or `msb ? −x : x` (absi); assemble per mode. Directed (absf ±0/±Inf/NaN/subnormal;
  absi ±int/INT_MIN/0; per-lane) + ~20k random over `(mode, is_float, a)`. Unary handshake tasks.
- `rtl/fu_abs_decomp.sv` **stub**: handshake; `out_data = ~in_data_0` (not abs) → RED.
- Verify: `./run.sh fu_abs_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: sign-clear + per-lane conditional negate
- `sign_mask` per mode; `absf = in & ~sign_mask`; `absi` per-lane `msb ? (~lane+1) : lane`
  (16/32/64) mode-muxed; `out = is_float ? absf : absi`.
- Verify: `PASS:`; other modules still pass.

## Step 3 — docs / build / synth
- README section; commit series (docs → RED → GREEN → README), author `WillWheatley27`,
  subject-only; push. Then synthesize on SAED14nm (DC, both corners) and add to the PPA chart.
