# fu_min_max_decomp — Implementation Plan

**Date:** 2026-07-17
**Spec:** `docs/specs/2026-07-17-fu-min-max-decomp-design.md`

TDD, mirroring `fu_add_sub_decomp` (native-SV golden; no DPI needed — min/max is exact integer).

## Step 1 — RED: testbench + stub

- `tb/tb_fu_min_max_decomp.sv`: golden splits `(a,b)` into lanes per `mode`, computes signed or
  unsigned min/max per lane (`$signed()` for signed) per `op_sel`, repacks. Directed corners
  (spec §6) + ~20k random over `(mode, is_signed, op_sel, a, b)`. Reuse join/backpressure/
  input-invalid handshake tasks.
- `rtl/fu_min_max_decomp.sv` **stub**: correct handshake; `out_data = in_data_0` always (ignores
  compare/mode) → passes trivially only when a is always the answer; fails min/max selection and
  all decomposed modes → genuine RED.
- Verify: `./run.sh fu_min_max_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: shared segmented comparator

Implement per spec §4:
- Split into `a0..a3`, `b0..b3`; per-block `gt_u_k`, `eq_k`.
- Mode decode → `is_top[k]`; signed adjust on top-block `gt_k`.
- Lexicographic combine `r0..r3` with mode-gated lane breaks.
- Per-block `(a_gt_b, op)` routing; `pick_b`; output mux; repack.
- Verify: `./run.sh fu_min_max_decomp` → `PASS:`; other modules still pass.

## Step 3 — docs / build

- README: add a `fu_min_max_decomp` section.
- Whole-module review; commit series (docs → RED test+stub → GREEN impl → README),
  single author `WillWheatley27`, subject-only; push to `origin main`.
