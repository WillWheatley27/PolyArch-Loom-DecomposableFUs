# fu_mult_dx — Design Spec

**Date:** 2026-07-28
**Status:** Approved (design). **Revised:** DesignWare dropped in favor of a hand-written datapath
after synthesis showed `DW_mult_dx` costs ~2× the area and is slower (it computes the *full* 128-bit
product; multiply-low needs only the low partial products, which a full-product block cannot skip).
**Op:** `arith.muli` (singleton — integer multiply, not a loom share group).
**Family:** *dual* (64/32-only) decomposable FUs — suffix `_dx`. One split boundary at bit 32 →
**1×64 or 2×32** lanes only. DesignWare is used where it wins (`fu_add_sub_dx`); multiply is
hand-written multiply-low.
**Deliverable:** synthesizable RTL + self-checking Verilator testbench (native-SV golden).

## 1. Approach — hand-written segmented multiply-low

**Multiply-low semantics** (matches `fu_mult_decomp`): each lane returns the low W bits of its W×W
product (like `PMULLW`/`PMULLD`), sign-agnostic → no `op_sel`.

Split operands into 32-bit halves `a = {a1,a0}`, `b = {b1,b0}`. With `Pij = ai·bj`:

```
low64(a·b) = P00 + (P10_lo + P01_lo)·2^32   (mod 2^64)     // the a1·b1·2^64 term vanishes
```

- **1×64** needs `P00` (full 64b) + cross terms `P01_lo`, `P10_lo` (low 32b). It does **not** need
  `P11` (the high product) — that is the vanishing 2^64 term.
- **2×32** needs `P00_lo` (lane 0) + `P11_lo` (lane 1), independent. It does **not** need the cross
  terms.

So the shared datapath is four 32×32 block products — only `P00` full-width, the rest low-32 — with a
mode-routed high word. This builds only the low half of the partial-product array (why it beats the
DesignWare full-product block for this op).

## 2. Modes & semantics

| `mode` | Lanes | Result per lane |
|--------|-------|-----------------|
| `2'b00` | 1×64 | low 64 bits of a×b |
| `2'b01` | 2×32 | low 32 bits of each 32×32 |
| `2'b10`,`2'b11` | reserved → 1×64 | — |

Little-endian lanes (lane 0 = bits [31:0]). No `op_sel`.

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

## 4. Datapath

```
a = {a1,a0}, b = {b1,b0}                      // 32-bit halves
P00 = a0*b0 (full 64b) ; P01 = a0*b1, P10 = a1*b0, P11 = a1*b1 (low 32b each)
out[31:0]  = P00[31:0]                        // low word: same in both modes
out[63:32] = (mode==2x32) ? P11               // 2x32: high lane low product
                          : P00[63:32] + P10 + P01   // 1x64: high word with carry from P00
```

## 5. Verification

Unchanged testbench (`tb/tb_fu_mult_dx.sv`) — native-SV multiply-low golden, mode isolation, handshake
corners, ~20k random. Bit-exact; `$fatal(1)` on mismatch. `./run.sh fu_mult_dx`.

## 6. Out of scope / follow-ups

- Synthesis corners quantify the hand-written vs DW gap for the record.
- Next in family: cmp (`DW_cmp_dx` — expected a tie, like add_sub), then FP + conversions.
