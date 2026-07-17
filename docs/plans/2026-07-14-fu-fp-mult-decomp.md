# fu_fp_mult_decomp — Implementation Plan

**Date:** 2026-07-14
**Spec:** `docs/specs/2026-07-14-fu-fp-mult-decomp-design.md`

TDD, mirroring `fu_fp_add_sub_decomp`, with a DPI-C hardware golden.

## Step 1 — RED: DPI-C golden + testbench + stub

- `tb/fu_fp_mult_decomp_golden.c`: `extern "C"` DPI functions `g_fp64_mul` (double),
  `g_fp32_mul` (float), `g_fp16_mul` (F16C). Each takes `(a,b)` and returns the IEEE
  product bits. Bit-exact, DUT-independent.
- `tb/tb_fu_fp_mult_decomp.sv`: imports the DPI functions; golden per lane per mode;
  NaN-lenient compare (any qNaN), bit-exact otherwise. Directed corners (spec §6) +
  ~20k uniform random + ~20k exponent-constrained random. Reuse join/backpressure/
  input-invalid handshake tasks. No `op_sel`.
- `rtl/fu_fp_mult_decomp.sv` **stub**: correct handshake; `out_data` = non-FP integer
  combine (XOR) → genuine RED.
- `run.sh` already compiles an optional `tb/${MOD}_golden.c` with `-mf16c`.
- Verify: `./run.sh fu_fp_mult_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN: shared format-parameterized IEEE multiply core

Implement `function fp_mul_lane(a, b, EXP_W, MAN_W)` per spec §4:
unpack + classify → `sgn = sa ^ sb` → integer significands `A,B` (implicit; subnormal ⇒ 0) →
`baseExp = E_a + E_b + BIAS` → exact `P = A·B` (128-bit) → `mag = P << (IMP - 2·MAN_W)` →
single-shot: `eNorm = baseExp + msb − IMP`; overflow (`eNorm ≥ EXP_ONES`) → Inf; shift to
rounding frame (normal MSB→IMP, else subnormal at emin), sticky, RNE round, pack
(round-carry → exp++/min-normal; overflow → Inf). Specials: NaN, Inf×0→NaN, Inf, zero.
Top: call per lane/mode, mode-mux the packed output.

Iterate to GREEN against the trusted golden (specials, overflow, underflow/subnormal, ties,
then random). `verilator --lint-only -Wall` clean + `PASS:`; other modules still pass.

## Step 3 — docs / build

- README: add a `fu_fp_mult_decomp` section (DPI-C golden note).
- Whole-module review; commit series (docs → RED test+golden+stub → GREEN impl → README),
  single author `WillWheatley27`, subject-only; push to `origin main`.
