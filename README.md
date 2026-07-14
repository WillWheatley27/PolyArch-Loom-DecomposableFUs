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

## Verification gate

`verilator --lint-only -Wall` clean + testbench `PASS:`. All three modes run in one
simulation (mode is a runtime input), covering carry/borrow isolation, mode
equivalence, mixed per-lane ops, handshake corners, and ~20k random vectors.

## Follow-up: area validation

Functional decomposition is verified here. The motivating area inequality —
`Area(one decomposable FU64) < Area(FU64) + 2·FU32 + 4·FU16)` — is a synthesis
result and is tracked as a separate task (Yosys/DC), not claimed from RTL.
