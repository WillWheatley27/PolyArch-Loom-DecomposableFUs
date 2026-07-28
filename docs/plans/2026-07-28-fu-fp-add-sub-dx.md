# fu_fp_add_sub_dx — Implementation Plan

**Spec:** `docs/specs/2026-07-28-fu-fp-add-sub-dx-design.md`

**DesignWare:** not used (no duplex/multi-format FP block exists — see spec §1). Hand-written shared
`fp_lane` core, reused from `fu_fp_add_sub_decomp` at fp64/fp32 only.

## Steps

1. **Spec** (done).
2. **RED** — `tb/tb_fu_fp_add_sub_dx.sv` + `tb/fu_fp_add_sub_dx_golden.c` (DPI `double`/`float`),
   2 modes, `op_sel[1:0]`, directed IEEE corners + random, against a **stub** (`out_data = a`).
   Expect lint clean, sim FAIL.
3. **GREEN** — RTL reusing the verified `fp_lane` core; fp64 lane + two fp32 lanes, mode-muxed.
   Expect `PASS:`.
4. **README** — `fu_fp_add_sub_dx` section + the "no DW for FP" note.
5. **Commit series** (WillWheatley27, subject-only, no AI traces): docs → RED → GREEN → README; push.
6. **Synthesize** SAED14nm both corners (speed 0.10 caution — FP add is deep; use a comfortable area
   period). Compare to `fu_fp_add_sub_decomp`.
7. **Chart** — append `fp_add_sub_dx` to the `_dx` family chart.

## Checks

- `fp_lane` is verified (reused verbatim) — risk is only in the fp64/fp32 wiring + mode mux.
- Signed-zero / subnormal / NaN corners carried over from the 3-format tb.
