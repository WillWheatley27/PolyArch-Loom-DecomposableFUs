# fu_add_sub_decomp — Design Spec

**Date:** 2026-07-10
**Status:** Approved (design), pending spec review
**Share group:** 1 (add_sub) — `arith.addi`, `arith.subi`
**Deliverable:** standalone RTL + self-checking testbench (no generator wiring)

## 1. Context

`fabric_op_gen` group 1 `fu_add_sub` is a combinational, `WIDTH`-parameterized shared
adder: 1-bit `op_sel` (0=add, 1=sub), packed operand buses, a 2-input join handshake
(latency 0), subtract implemented as `~B + carry_in`.

This module is the first **decomposable** (subword-SIMD) FU: one physical 64-bit unit
that also operates as two independent 32-bit lanes or four independent 16-bit lanes,
selected at runtime. add_sub is chosen first because its datapath (a single carry-propagate
adder) segments most cleanly and establishes the carry-break pattern the other Tier-A units
(min/max, fp_add_sub) will reuse.

## 2. Objective

Realize `decomposability = [32, 16]` on a 64-bit add/sub unit such that the shared adder is
reused across all three modes, targeting the area inequality:

```
Area( FU64 modes {1×64, 2×32, 4×16} )  <  Area(FU64) + 2·Area(FU32) + 4·Area(FU16)
```

**Scope of this deliverable:** functional correctness of decomposition — all three modes
correct, with no carry/borrow leakage across lane boundaries. The area inequality itself is a
**synthesis** result and is explicitly a follow-up (see §8); it is not claimed from RTL alone.

## 3. Interface

```systemverilog
module fu_add_sub_decomp (
  input  logic        clk, rst_n,      // held for FU convention; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // held config: 00=1×64, 01=2×32, 10=4×16, 11=rsvd→1×64
  input  logic [3:0]  op_sel,          // held config: per-lane 0=add, 1=sub
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

- Fixed 64-bit base width, 16-bit lane granularity (four blocks). Deliberately **not**
  over-parameterized; generalization to other base widths is out of scope (see §8).
- `mode` and `op_sel` are **held config** inputs with no handshake, matching how the original
  `op_sel` is treated.
- No flag/overflow outputs (matches the original FU).

### Operand lane packing (little-endian by lane)

| mode | lanes (bit ranges) | active op_sel bits |
|------|--------------------|--------------------|
| 1×64 | [63:0]             | op_sel[0] |
| 2×32 | [31:0], [63:32]    | op_sel[0], op_sel[2] |
| 4×16 | [15:0], [31:16], [47:32], [63:48] | op_sel[0], op_sel[1], op_sel[2], op_sel[3] |

## 4. Mode & op-governance decode

Operands split into four 16-bit blocks `a_k, b_k` (k=0..3). Each block is governed by the
`op_sel` bit of the lane it belongs to:

| block k | 1×64 | 2×32 | 4×16 |
|---|---|---|---|
| gov0 | op_sel[0] | op_sel[0] | op_sel[0] |
| gov1 | op_sel[0] | op_sel[0] | op_sel[1] |
| gov2 | op_sel[0] | op_sel[2] | op_sel[2] |
| gov3 | op_sel[0] | op_sel[2] | op_sel[3] |

Boundary "breaks" — block *k* starts a new lane, so its carry-in is a fresh subtract seed
instead of the carry propagated from block *k−1*:

```
brk16 = (mode == 4×16)              // boundary before block 1 (bit 16)
brk32 = (mode == 2×32) | (mode == 4×16)   // boundary before block 2 (bit 32)
brk48 = (mode == 4×16)              // boundary before block 3 (bit 48)
```

Reserved encoding `mode == 2'b11`: all breaks are 0 and all gov = op_sel[0], so it behaves
as 1×64. Documented as reserved; behavior is defined (safe) rather than X.

## 5. Datapath (combinational)

```
b_eff_k = gov_k ? ~b_k : b_k                 // per-block operand-B invert for subtract
cin0 = gov0                                  // lane-start seed (subtract adds +1)
cin1 = brk16 ? gov1 : cout0
cin2 = brk32 ? gov2 : cout1
cin3 = brk48 ? gov3 : cout2
{cout_k, sum_k} = a_k + b_eff_k + cin_k      // 16-bit add producing 17-bit result
out_data = {sum3, sum2, sum1, sum0}          // cout3 discarded (no flags)
```

The four 16-bit block-adders **are** the 64-bit adder in 1×64 mode; only the three boundary
carry-muxes change between modes. This is the shared-datapath reuse that motivates the design.
Written behaviorally so synthesis maps the adders to its preferred structure.

## 6. Handshake & latency

Unchanged from the original — 2-input join, combinational, latency 0:

```
out_valid  = in_valid_0 & in_valid_1;
in_ready_0 = out_ready & out_valid;
in_ready_1 = out_ready & out_valid;
```

`mode`/`op_sel` do not participate in the handshake.

## 7. Verification

**Files:** `tb/tb_fu_add_sub_decomp.sv`, `run.sh`.

**Golden model:** split `a`, `b` into lanes per `mode`, compute per-lane `a±b` at the lane
width (with per-lane `op_sel`), repack into a 64-bit expected value. One sim run covers all
modes — `mode` is runtime, so the TB loops over it internally (contrast the original TB, which
sweeps a compile-time `WIDTH`).

**Directed vectors (load-bearing = carry/borrow isolation):**
- 4×16: a lane computing `0xFFFF + 0x0001` must wrap to `0x0000` **without** carrying into the
  neighbor lane; neighbors carry independent nonzero values.
- Subtract borrow: a lane computing `0x0000 − 0x0001 = 0xFFFF` must borrow within-lane only.
- 2×32: a carry crossing the bit-31→32 boundary must **break** in 2×32 mode and **propagate**
  in 1×64 mode (same operands, different mode → different result).
- Mode equivalence: 1×64 reproduces a plain 64-bit `+/−`.
- Mixed per-lane ops: e.g. lane0 add, lane1 sub, lane2 add, lane3 sub.
- Per-lane corners: all-zeros, all-ones, min/max.

**Handshake corners:** join (`out_valid`), backpressure (`out_ready=0`), input-invalid —
reuse the three tasks from the original TB.

**Randomized:** ~20,000 vectors over random `(mode, op_sel[3:0], a, b)`, checked against golden.

**PASS/FAIL:** single `PASS:`/`FAIL:` line; `$fatal(1)` on any mismatch.

**`run.sh`:** `verilator --lint-only -Wall` (clean), then `verilator --binary --timing`
build + sim, grep `^PASS:`. Mirrors the original `tb/int_arith/add_sub/run.sh` flow, minus the
WIDTH sweep (all modes run in one sim).

## 8. Out of scope / follow-ups

- **Area validation:** confirming the §2 inequality requires synthesis (Yosys or DC) of the
  decomposable unit vs. the fixed-width bank. Separate task after RTL+TB are green.
- **Generator integration:** emitting this from `fabric_gen` (new template + registry entry)
  is deferred; this is a hand-authored standalone module first.
- **Generalization:** arbitrary base widths / lane granularities beyond 64-bit `[32,16]`.
- **Other Tier-A FUs:** min_max_signed/unsigned, barrel_shift, fp_add_sub, fp_min_max reuse
  this carry-break/segmented-compare pattern in later modules.
