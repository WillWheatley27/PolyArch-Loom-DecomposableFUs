# fu_fp_add_sub_decomp — Implementation Plan

**Date:** 2026-07-14
**Spec:** `docs/specs/2026-07-14-fu-fp-add-sub-decomp-design.md`

TDD, mirroring the earlier modules, with a DPI-C hardware golden (Verilator has no
usable `shortreal`).

## Step 1 — RED: DPI-C golden + testbench + stub

- `tb/fu_fp_add_sub_decomp_golden.c`: `extern "C"` DPI functions `g_fp64_add` (double),
  `g_fp32_add` (float), `g_fp16_add` (F16C `_cvtsh_ss`/`_cvtss_sh`). Each takes `(a,b,sub)`
  and returns the IEEE result bits. Bit-exact, DUT-independent.
- `tb/tb_fu_fp_add_sub_decomp.sv`: imports the DPI functions; golden per lane per mode;
  NaN-lenient compare (any qNaN accepted), bit-exact otherwise. Directed corners (spec §6)
  + ~20k uniform random + ~20k exponent-constrained random. Reuse join/backpressure/
  input-invalid handshake tasks.
- `rtl/fu_fp_add_sub_decomp.sv` **stub**: correct handshake; `out_data` = a plain 64-bit
  passthrough / integer combine that is *not* FP (fails immediately) → genuine RED.
- `run.sh`: extend to compile an optional `tb/${MOD}_golden.c` with `-mf16c` when present
  (backward compatible; add_sub / mult have no golden C).
- Verify: `./run.sh fu_fp_add_sub_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: shared format-parameterized IEEE core

Implement `function fp_lane(a, b, sub, EXP_W, MAN_W)` per spec §4:
unpack (mask/shift by MAN_W/EXP_W; classify NaN/Inf/zero/subnormal) → left-justify significands
(implicit at bit 63) with biased effective exponent (subnormal ⇒ exp 1, implicit 0) →
align (right-shift smaller, sticky) → add (carry→>>1) or sub (magnitude-order, diff, sign of
larger) → normalize (LZC + left-shift, clamped to emin for gradual underflow; zero→+0) →
round RNE (guard/round/sticky at MAN_W; carry→exp++) → pack (overflow→Inf, subnormal encode,
specials). Top: call per lane/mode, mode-mux the packed output.

Iterate to GREEN against the trusted golden: fix directed corners first (signed zero, Inf/NaN,
subnormal, ties, overflow, cancellation), then random. `verilator --lint-only -Wall` clean +
`PASS:`; ensure `./run.sh`, `./run.sh fu_mult_decomp` still pass (run.sh change is compatible).

## Step 3 — docs / build

- README: add a `fu_fp_add_sub_decomp` section (note the DPI-C golden).
- Whole-module review; commit series (docs → RED test+golden+stub → GREEN impl → README),
  single author `WillWheatley27`, subject-only messages; push to `origin main`.
