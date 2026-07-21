# fu_abs_decomp — Design Spec

**Date:** 2026-07-21
**Status:** Approved (design)
**Ops:** `math.absf` (FP absolute value) + `math.absi` (integer absolute value). Singleton unary
ops in loom's `fabric.op` catalog (not a hardware share group); both trivially lane-separable.
**Deliverable:** standalone RTL + self-checking testbench (native-SV golden)

## 1. Context & decomposability

Absolute value is the cheapest decomposable op: `absf` is a per-lane **sign-bit clear**, `absi` is
a per-lane **conditional two's-complement negate** (carries contained within the lane). Both are
combinational, lane-separable, no constant tables. One module covers both via a global `is_float`.

`decomposability = [32,16]` → 1×64 / 2×32 / 4×16 lanes (fp64/fp32/fp16 for `absf`; int64/32/16 for
`absi`).

## 2. Semantics

- **`absf` (`is_float=1`):** `|x|` = clear the lane's sign bit. This is IEEE abs (a bit operation):
  `−0→+0`, `−Inf→+Inf`, NaN → NaN with sign cleared (payload preserved), subnormals sign-cleared.
- **`absi` (`is_float=0`):** per lane, `x<0 ? −x : x` (two's-complement). `INT_MIN` (`0x8000…`)
  wraps to itself (`−INT_MIN` is unrepresentable), matching standard hardware abs.

## 3. Interface (unary)

```systemverilog
module fu_abs_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=1×64, 01=2×32, 10=4×16, 11=rsvd→1×64
  input  logic        is_float,        // global: 1=absf (clear sign), 0=absi (conditional negate)
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

Single operand — 1-input handshake. Little-endian lanes; `is_float` global.

## 4. Datapath (combinational)

- **absf:** `out = in & ~sign_mask(mode)`, where `sign_mask` has 1s at the lane-MSB positions
  (`0x8000…0000` for 1×64; `0x8000_0000_8000_0000` for 2×32; `0x8000_8000_8000_8000` for 4×16).
- **absi:** per lane, `neg = ~lane + 1`; `out_lane = lane_msb ? neg : lane`. Computed per mode
  (16/32/64-bit lanes) and mode-muxed — the +1 carry stays within each lane (no cross-lane spill).
- `out = is_float ? absf_result : absi_result`.

Functional decomposition; a physically-shared segmented negate/sign-clear is the synthesis
objective (though for abs the datapath is nearly free).

## 5. Handshake & latency

Unary, combinational, latency 0.

## 6. Verification

Native-SV golden (both ops are exact bit/integer operations): per lane on the isolated slice,
`absf` = clear the lane sign bit; `absi` = `msb ? −lane : lane`. Bit-exact compare (absf's NaN is
sign-cleared deterministically, so no leniency needed). Directed: `absf` on ±normal, ±0, ±Inf,
NaN, subnormal; `absi` on ±int, `INT_MIN` (wrap), 0; per-lane independence, both `is_float`.
~20,000 random over `(mode, is_float, a)`. `$fatal(1)` on mismatch. `./run.sh fu_abs_decomp`.

## 7. Out of scope / follow-ups

- **Physical shared segmented datapath**; **area validation**; **generator integration**.
