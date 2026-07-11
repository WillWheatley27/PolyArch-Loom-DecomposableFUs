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
./run.sh          # verilator --lint-only -Wall, then build + sim (all modes)
```

## Verification gate

`verilator --lint-only -Wall` clean + testbench `PASS:`. All three modes run in one
simulation (mode is a runtime input), covering carry/borrow isolation, mode
equivalence, mixed per-lane ops, handshake corners, and ~20k random vectors.

## Follow-up: area validation

Functional decomposition is verified here. The motivating area inequality —
`Area(one decomposable FU64) < Area(FU64) + 2·FU32 + 4·FU16)` — is a synthesis
result and is tracked as a separate task (Yosys/DC), not claimed from RTL.
