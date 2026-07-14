# fu_mult_decomp — Implementation Plan

**Date:** 2026-07-14
**Spec:** `docs/specs/2026-07-14-fu-mult-decomp-design.md`

TDD, mirroring `fu_add_sub_decomp`: write the self-checking testbench against a stub
(RED — lint clean, sim fails on the decomposed modes), then implement the shared
block-product datapath (GREEN — sim passes all modes).

## Step 1 — RED: testbench + stub

- `tb/tb_fu_mult_decomp.sv`: golden model splits `(a,b)` into lanes per `mode`, computes
  per-lane low-width truncated product, repacks. Directed corners (§7 of spec) +
  ~20k random. Reuse the join / backpressure / input-invalid tasks from the add/sub TB.
  No `op_sel` port on the DUT.
- `rtl/fu_mult_decomp.sv` **stub**: correct handshake + `out_data = (a*b)` truncated to
  64 bits always (ignores `mode`). Passes 1×64 and the handshake corners; **fails** 2×32
  and 4×16 (cross-lane products leak) → genuine RED.
- Generalize `run.sh` to take an optional module basename: `./run.sh [fu_name]`,
  default `fu_add_sub_decomp` (backward compatible). Lints `rtl/$MOD.sv`, builds+sims
  `tb/tb_$MOD.sv`.
- Verify: `./run.sh fu_mult_decomp` → lint clean, sim FAIL on decomposed modes.

## Step 2 — GREEN: shared block-product datapath

Implement per spec §5:
- Split into `a0..a3`, `b0..b3` (16-bit).
- 14 block products `pp_ij = {16'b0,a_i} * {16'b0,b_j}` (32-bit, unsigned, explicit widths);
  omit `pp13`, `pp31`.
- `p1` = weighted 64-bit sum (mod 2^64); `p2` = `{lane1,lane0}` low-32 sums; `p4` =
  concatenated diagonal low-16s.
- `out_data` mode mux (00/11 → p1, 01 → p2, 10 → p4).
- Verify: `./run.sh fu_mult_decomp` → `PASS:`; `./run.sh` (add_sub) still `PASS:`.

## Step 3 — docs / build

- README: add a `fu_mult_decomp` section.
- Whole-module review, then commit series (docs → RED test+stub → GREEN impl → README),
  single author `WillWheatley27`, subject-only messages; push to `origin main`.
