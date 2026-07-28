# fu_mult_dx — Design Spec

**Date:** 2026-07-28
**Status:** Approved (design)
**Op:** `arith.muli` (singleton — integer multiply, not a loom share group) — **duplex** decomposition.
**Family:** *64/32-only decomposable* FUs. One split boundary at bit 32 → **1×64 or 2×32** lanes only.
Built on the **DesignWare** duplex multiplier `DW_mult_dx`.
**Deliverable:** synthesizable RTL + self-checking Verilator testbench (native-SV golden).

## 1. Approach

`DW_mult_dx` is a natively 2-way duplex multiplier (`dplx` runtime knob, split point `p1_width`),
which maps exactly onto 1×64 / 2×32. The FU **instantiates `DW_mult_dx` directly** (DWBB directive),
so simulation (Verilator sim_ver model) and synthesis (`dw_foundation.sldb`) exercise the same block.

**Multiply-low semantics (matches `fu_mult_decomp`):** each lane returns the low W bits of its W×W
product (like `PMULLW`/`PMULLD`), which is **sign-agnostic** → no signed/unsigned `op_sel`, `tc=0`.
`DW_mult_dx` outputs the *full* `2·width`-bit product; the FU **slices the low bits** per lane.

## 2. Modes & semantics

| `mode` | Lanes | Result per lane |
|--------|-------|-----------------|
| `2'b00` | 1×64 | low 64 bits of a×b |
| `2'b01` | 2×32 | low 32 bits of each 32×32 |
| `2'b10`,`2'b11` | reserved → 1×64 | — |

Little-endian lanes (lane 0 = bits [31:0]). No `op_sel` (multiply-low is sign-agnostic).

## 3. Interface (2-input join)

```systemverilog
module fu_mult_dx (
  input  logic        clk, rst_n,        // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,              // 00=1×64, 01=2×32, rsvd→1×64
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,  // a
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,  // b
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

**2-input join** handshake: `out_valid = v0 & v1`, `in_ready_i = out_ready & out_valid`.
Combinational, latency 0.

## 4. Datapath — mapping onto `DW_mult_dx`

`DW_mult_dx #(.width(64), .p1_width(32))`, `tc=0`. Duplex product packing (verified in a small-width
probe): `dplx=0` → one 64×64 → 128-bit product; `dplx=1` → low 32×32 full product in `product[63:0]`,
high 32×32 full product in `product[127:64]`. Multiply-low slice:

```
dplx = (mode == 2'b01)
DW_mult_dx(.a(a), .b(b), .tc(0), .dplx(dplx), .product(prod))       // prod is 128-bit
out_data = dplx ? {prod[95:64], prod[31:0]}    // low 32 of high lane, low 32 of low lane
                :  prod[63:0]                   // low 64 of the single lane
```

`tc=0` is correct despite discarding sign: the low W bits of a W×W product are identical for
signed/unsigned (mod 2^W).

## 5. Verification

Native-SV golden (per-lane multiply-low). Directed: mode isolation — `0xFFFFFFFF × 0xFFFFFFFF` gives a
full-width low product in 1×64 vs an isolated low-32 lane in 2×32; independent 2×32 lanes; reserved
mode → 1×64; low-bit truncation. Handshake corners. ~20k random over `(mode, a, b)`. Bit-exact;
`$fatal(1)` on mismatch. `./run.sh fu_mult_dx`.

## 6. Out of scope / follow-ups

- Physical shared-datapath / area for the 64/32 family — synthesis corners measure it directly.
- Next in family: cmp (`DW_cmp_dx`), then FP ops (no DW duplex FP — hand-written) and conversions.
