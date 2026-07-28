# fu_fp_add_sub_dx — Design Spec

**Date:** 2026-07-28
**Status:** Approved (design)
**Op:** `arith.addf` / `arith.subf` (share group `float_add_sub`) — dual (64/32) decomposition.
**Family:** `_dx` (64/32-only). **1×fp64 or 2×fp32** lanes (no fp16).
**Deliverable:** synthesizable RTL + self-checking Verilator testbench (DPI-C hardware-FP golden).

## 1. DesignWare decision — DO NOT use DesignWare

**Verdict: hand-written shared core; no DesignWare.** The DW audit is conclusive:

- **No `DW_fp_*_dx` duplex block exists**, and no multi-format FP block (`DW_lp_fp_multifunc` is
  multi-*function*, single-format). Every `DW_fp_*` is a single-format leaf: `DW_fp_addsub` fixes
  `sig_width`/`exp_width` at **elaboration**, not at runtime.
- A DW-based decomposable FP add/sub would therefore need a *separate* fp64 adder **plus** two fp32
  adders, output-muxed by `mode` — i.e. a **bank** with area ≈ `fp64 + 2·fp32`. That is exactly the
  cost decomposability exists to eliminate, so DW here is strictly worse than one shared datapath.

Contrast with `fu_add_sub_dx` (DW `DW_addsub_dx` duplex was a ~tie) and `fu_mult_dx` (DW dropped for
over-generality). Emerging rule: DW duplex helps only for the **integer** ops that have a native
`_dx` block; **FP decomposition has no DW support** and is always hand-written.

## 2. Approach

Reuse the verified shared `fp_lane(a, b, sub, EXP_W, MAN_W)` core from `fu_fp_add_sub_decomp`
(full IEEE-754: RNE, subnormals, NaN/±Inf/signed-zero) at two widths only — fp64 (11/52) and
fp32 (8/23). One core, mode-selected output.

## 3. Modes & semantics

| `mode` | Lanes | Format |
|--------|-------|--------|
| `2'b00` | 1×fp64 | 1/11/52, bias 1023 |
| `2'b01` | 2×fp32 | 1/8/23, bias 127 |
| `2'b10`,`2'b11` | reserved → 1×fp64 | — |

`op_sel[1:0]` per lane: 0→add, 1→subtract (flip b's sign). 1×fp64 uses `op_sel[0]`; 2×fp32 uses
`op_sel[0]` (low lane) / `op_sel[1]` (high lane). Little-endian lanes. 2-input join, latency 0.

## 4. Interface

```systemverilog
module fu_fp_add_sub_dx (
  input logic clk, rst_n, input logic [1:0] mode, input logic [1:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready);
```

## 5. Verification

DPI-C hardware-FP golden (`double` for fp64, `float` for fp32 — **no F16C** needed). NaN-lenient
(any qNaN accepted); else bit-exact incl signed zero/subnormals. Directed IEEE corners (both formats)
+ uniform random + cancellation-stress random, ~20k each. `./run.sh fu_fp_add_sub_dx`.

## 6. Follow-ups

- Synthesis corners; compare to `fu_fp_add_sub_decomp` (64/32/16). No DW comparison (none exists).
