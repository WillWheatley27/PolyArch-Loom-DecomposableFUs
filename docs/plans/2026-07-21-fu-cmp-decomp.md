# fu_cmp_decomp — Implementation Plan

**Date:** 2026-07-21
**Spec:** `docs/specs/2026-07-21-fu-cmp-decomp-design.md`

TDD, native-SV golden (integer compare is exact). Reuses the `min_max` segmented comparator.

## Step 1 — RED: testbench + stub
- `tb/tb_fu_cmp_decomp.sv`: golden `cmp16/cmp32/cmp64(pred,a,b)` → per-lane mask (all-ones/zeros
  via `$signed`/unsigned compares per predicate); assemble per mode. Directed (each predicate;
  eq/lt/gt; signed-vs-unsigned boundary; per-lane isolation) + ~20k random over `(mode,pred,a,b)`.
  Reuse join/backpressure/input-invalid handshake tasks.
- `rtl/fu_cmp_decomp.sv` **stub**: handshake; `out_data = in_data_0 & in_data_1` (not a compare) → RED.
- Verify: `./run.sh fu_cmp_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: segmented comparator + predicate mux
- Block `gtu`/`eq`; signed top-adjust `gts`; three mode-gated combines `r_u`/`r_s`/`e`;
  `pred_eval` per lane-top; route per block + `{16{res}}` broadcast.
- Verify: `PASS:`; other modules still pass.

## Step 3 — docs / build / synth
- README section; commit series (docs → RED → GREEN → README), author `WillWheatley27`,
  subject-only; push. Then synthesize on SAED14nm (DC, both corners) and add to the PPA chart.
