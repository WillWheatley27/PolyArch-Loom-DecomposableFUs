# PolyArch-Loom Decomposable FUs

Decomposable (subword-SIMD) function units for the loom `fabric` share groups: a
single wide datapath that also operates as narrower independent lanes, selected at
runtime, so one unit replaces a bank of fixed-width units.

## Contents

- `DECOMPOSABILITY_ANALYSIS.md` — which of the 19 share-group FUs can decompose, and why.
- `docs/specs/` — per-FU design specs.
- `docs/plans/` — per-FU implementation plans.
- `rtl/` — synthesizable SystemVerilog modules.
- `tb/` — self-checking Verilator testbenches.

## fu_add_sub_decomp

64-bit add/sub that runs as 1×64, 2×32, or 4×16 lanes via a runtime `mode` input,
with a per-lane `op_sel` (add/sub) bit. One shared adder segmented at the
16/32/48-bit boundaries by mode-gated carries. Combinational, latency 0.

```bash
./run.sh                  # fu_add_sub_decomp (default): lint -Wall, then build + sim
./run.sh fu_mult_decomp   # any module: rtl/<name>.sv + tb/tb_<name>.sv
```

## fu_mult_decomp

64-bit integer multiply that runs as 1×64, 2×32, or 4×16 lanes via a runtime `mode`
input. Each lane returns the low (truncated) product of its width — multiply-low, like
`PMULLW`/`PMULLD` — which is sign-agnostic, so there is no signed/unsigned `op_sel`. One
shared 16×16 block-product array (the 64×64 partial-product array at 16-bit granularity)
is reused across modes; only the summation/alignment network and the output mux change.
Combinational, latency 0. The two corner partial products (weight 2⁶⁴) influence no
lane's low bits and are not built.

## fu_fp_add_sub_decomp

Full IEEE-754 add/sub that runs as 1×fp64, 2×fp32, or 4×fp16 lanes via a runtime
`mode` input, with a per-lane `op_sel` (add/sub) bit. Round-to-nearest-even, gradual
underflow (subnormals), NaN / ±Inf / signed-zero. One shared format-parameterized core
(align → add/sub → normalize → round) is written once and reused at all three lane
widths; only the mantissa/exponent field widths and bias differ. Combinational, latency 0.
This proves functional decomposition; a physically segmented aligner/adder/normalizer is
the area follow-up.

Because Verilator does not support `shortreal`, the testbench golden is **hardware FP via
DPI-C** (`tb/fu_fp_add_sub_decomp_golden.c`: `double` / `float` / x86 F16C for fp16) —
a bit-exact, DUT-independent reference. `run.sh` compiles it with `-mf16c` automatically.

## fu_min_max_decomp

64-bit min/max that runs as 1×64, 2×32, or 4×16 lanes via a runtime `mode`, with per-lane
`op_sel` (min/max) and a global `is_signed` bit — covering share groups 6 (`minsi/maxsi`) and
7 (`minui/maxui`) in one unit. One shared 64-bit comparator (four 16-bit block comparators)
whose lexicographic combine chain is broken at the 16/32/48-bit boundaries by mode; signedness
reinterprets only each lane's top block. Combinational, latency 0. Same segmented-datapath
pattern as `fu_add_sub_decomp`, on a comparator instead of an adder.

## fu_fp_mult_decomp

Full IEEE-754 multiply that runs as 1×fp64, 2×fp32, or 4×fp16 lanes via a runtime `mode`.
Round-to-nearest-even, gradual underflow (subnormals), NaN / ±Inf / signed-zero, Inf×0→NaN.
No `op_sel` (multiply has no add/sub variant; result sign = sign_a ^ sign_b). One shared
format-parameterized core (sign XOR, exponent add, exact mantissa multiply into a wide field,
single-shot normalize/round handling gradual underflow) reused at all three lane widths — the
mantissa multiplier is the dominant, lane-separable resource. Combinational, latency 0.
Golden is hardware FP via DPI-C (`double` / `float` / F16C), compiled with `-mf16c`.

## fu_barrel_shift_decomp

64-bit barrel shift that runs as 1×64, 2×32, or 4×16 lanes via a runtime `mode`, with a global
`shift_op` (SLL / SRL / SRA — share group 4: `shli`/`shrui`/`shrsi`) and **per-lane independent
shift amounts** taken from `in_data_1` (each lane's low `log2(width)` bits; higher count bits
ignored, as in x86/RISC-V masking). Each lane shifts within its own width — no cross-lane spill.
Combinational, latency 0. Proves functional decomposition; a physically-shared segmented barrel
network (per-stage lane blocking) is the area follow-up (the per-lane-amount caveat).

## fu_fp_min_max_decomp

IEEE-754 min/max (share group 12: `minimumf`/`maximumf`) that runs as 1×fp64, 2×fp32, or
4×fp16 lanes via a runtime `mode`, with per-lane `op_sel` (min/max). IEEE-754-2019 semantics:
NaN-propagating (NaN if either operand is NaN) and −0.0 < +0.0. Order is a sign+magnitude
(monotonic-key) compare; the result is always exactly one input (no rounding). One shared
format-parameterized comparator reused at all lane widths. Combinational, latency 0. DPI-C
hardware golden (`double`/`float`/F16C), compiled with `-mf16c`.

## fu_rounding_decomp

FP round-to-integral (share group 17: `floor`/`ceil`/`trunc`/`round`/`roundeven`) that runs as
1×fp64, 2×fp32, or 4×fp16 lanes via a runtime `mode`, with a global `round_mode[2:0]` selecting
the rounding direction. **Unary** op (single operand, 1-input handshake). Per lane: clear the
fractional bits and conditionally increment the integer part per mode/sign/guard/sticky, then
renormalize; NaN/Inf/±0/already-integral returned unchanged, sign preserved. Combinational,
latency 0. DPI-C golden (C `floor`/`ceil`/`trunc`/`round`/`rint` on `double`/`float`/F16C),
compiled with `-mf16c`.

## fu_int_to_fp_decomp

Integer→float conversion (share group 8: `sitofp`/`uitofp`) that runs as 1×(int64→fp64),
2×(int32→fp32), or 4×(int16→fp16) via a runtime `mode`, with a global `is_signed` (sitofp vs
uitofp). **Unary** op. Per lane: sign/magnitude → leading-one position → left-justify → RNE round
→ pack; round-overflow → +Inf (e.g. `uitofp(0xFFFF)`→fp16 = +Inf). One shared LZC + shifter +
rounder reused at all widths; only bias/mantissa-width/packing switch per mode. Combinational,
latency 0. DPI-C golden (trusted C int→float casts; fp16 via float then F16C), `-mf16c`.

## fu_fp_to_int_decomp

Float→integer conversion (share group 9: `fptosi`/`fptoui`) that runs as 1×(fp64→int64),
2×(fp32→int32), or 4×(fp16→int16) via a runtime `mode`, with a global `is_signed`. **Unary** op.
**Saturating**, round-toward-zero (the defined hardware behavior — `arith.fptosi/fptoui` are UB on
overflow): NaN→0, ±Inf→saturate, out-of-range→clamp to int min/max, `|x|<1`→0. One shared shifter
+ saturation logic reused at all widths; bias/significand-width/range switch per mode.
Combinational, latency 0. DPI-C golden (C `trunc` + range clamp; fp16 via F16C), `-mf16c`.

## Verification gate

`verilator --lint-only -Wall` clean + testbench `PASS:`. All three modes run in one
simulation (mode is a runtime input), covering carry/borrow isolation, mode
equivalence, mixed per-lane ops, handshake corners, and ~20k random vectors.

## Follow-up: area validation

Functional decomposition is verified here. The motivating area inequality —
`Area(one decomposable FU64) < Area(FU64) + 2·FU32 + 4·FU16)` — is a synthesis
result and is tracked as a separate task (Yosys/DC), not claimed from RTL.
