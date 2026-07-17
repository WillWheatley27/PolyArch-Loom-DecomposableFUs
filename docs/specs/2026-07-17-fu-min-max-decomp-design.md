# fu_min_max_decomp — Design Spec

**Date:** 2026-07-17
**Status:** Approved (design)
**Share groups:** 6 (`arith.minsi`, `arith.maxsi`) + 7 (`arith.minui`, `arith.maxui`) — Tier-A
in `DECOMPOSABILITY_ANALYSIS.md`; next in the recommended build order after `add_sub`.
**Deliverable:** standalone RTL + self-checking testbench (native-SV golden; no generator wiring)

## 1. Context & decomposability

min/max is Tier-A decomposable: its datapath is a **magnitude comparator** (a subtract /
lexicographic compare) plus an output mux. Like `fu_add_sub_decomp`'s adder, the comparator is
lane-separable — a 64-bit compare chain cut at the 16/32/48-bit boundaries yields independent
2×32 or 4×16 lane comparisons, with the bulk of the logic (the per-block comparators) shared.
Combinational, no per-format constant tables → decomposable. This is the second module and the
first to decompose a **compare** datapath; it establishes the segmented-compare pattern that
`fp_min_max` will later reuse.

One module covers **both** share groups 6 (signed) and 7 (unsigned): the comparator is identical
except for how the most-significant block of each lane is interpreted, selected by a held
`is_signed` bit. This is the honest shared-datapath story — one comparator serving signed and
unsigned, min and max, across three lane widths.

## 2. Objective

Realize `decomposability = [32, 16]` on a 64-bit min/max unit such that the shared comparator is
reused across all three modes and both signednesses, targeting the area inequality
`Area(FU64 modes {1×64,2×32,4×16}) < Area(FU64)+2·FU32+4·FU16`. Scope: functional correctness
of decomposition (independent per-lane results, no cross-lane compare leakage). Area is a
synthesis follow-up (§8).

## 3. Interface

```systemverilog
module fu_min_max_decomp (
  input  logic        clk, rst_n,      // held for FU convention; combinational core (lint-waived)
  input  logic [1:0]  mode,            // 00=1×64, 01=2×32, 10=4×16, 11=rsvd→1×64
  input  logic        is_signed,       // held config: 1=signed compare, 0=unsigned (all lanes)
  input  logic [3:0]  op_sel,          // held config, per-lane: 0=min, 1=max
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

- Little-endian lane packing (lane0 = LSBs), matching the family.
- `op_sel` lane mapping matches `fu_add_sub_decomp`: 1×64→`op_sel[0]`; 2×32→`op_sel[0],op_sel[2]`;
  4×16→`op_sel[0..3]`.
- `is_signed` is a global held config (packed min/max is signed *or* unsigned per instruction).
  It is the one addition beyond the base family interface.
- No flag outputs.

## 4. Datapath — shared segmented comparator (combinational)

Operands split into four 16-bit blocks `a_k, b_k` (k=0..3). Per block compute the shared
primitives:

```
gt_u_k = (a_k >  b_k)   // unsigned 16-bit magnitude compare  (the shared comparators)
eq_k   = (a_k == b_k)
```

**Signed handling (top block of each lane only).** For two's-complement values, same-sign
operands compare correctly as unsigned; only differing signs flip the order. So the signed
adjustment applies solely to the MSB block of each lane:

```
is_top[3] = 1                                   // block3 is a lane top in every mode
is_top[2] = (mode==4×16)
is_top[1] = (mode==2×32) || (mode==4×16)
is_top[0] = (mode==4×16)
gt_k = (is_signed && is_top[k] && (a_k[15]^b_k[15])) ? b_k[15] : gt_u_k
```

(When signs differ, `a>b` iff `a` is non-negative and `b` negative, i.e. `b_k[15]`.)

**Lexicographic combine with lane-boundary breaks** (MSB block dominates; chain broken exactly
where a lane starts — the compare analogue of `add_sub`'s carry breaks):

```
r0 = gt0
r1 = (mode==4×16)                     ? gt1 : (gt1 | (eq1 & r0))
r2 = (mode==2×32 || mode==4×16)       ? gt2 : (gt2 | (eq2 & r1))
r3 = (mode==4×16)                     ? gt3 : (gt3 | (eq3 & r2))
```

`r_k` is "a > b" for the lane whose top block is `k`. Per-lane `a_gt_b`:
1×64 → `r3`; 2×32 → lane0 `r1`, lane1 `r3`; 4×16 → lane_k `r_k`.

**Per-block output mux.** Each block selects `a_k` or `b_k` from its lane's `a_gt_b` and op:

```
pick_b = op ? ~a_gt_b : a_gt_b        // op 0=min: b when a>b ; op 1=max: b when a<=b
out_k  = pick_b ? b_k : a_k
```

with each block's `(a_gt_b, op)` routed per mode:

| block | 1×64 | 2×32 | 4×16 |
|---|---|---|---|
| 0 | (r3, op_sel[0]) | (r1, op_sel[0]) | (r0, op_sel[0]) |
| 1 | (r3, op_sel[0]) | (r1, op_sel[0]) | (r1, op_sel[1]) |
| 2 | (r3, op_sel[0]) | (r3, op_sel[2]) | (r2, op_sel[2]) |
| 3 | (r3, op_sel[0]) | (r3, op_sel[2]) | (r3, op_sel[3]) |

The four 16-bit block comparators are the shared area; only the mode-gated combine and the
output routing change between modes — the same reuse story as `fu_add_sub_decomp`.

## 5. Handshake & latency

Unchanged from the family — 2-input join, combinational, latency 0
(`out_valid = in_valid_0 & in_valid_1`, `in_ready_* = out_ready & out_valid`).

## 6. Verification

**Files:** `tb/tb_fu_min_max_decomp.sv`, `run.sh`.

**Golden (native SV):** split `a`, `b` into lanes per `mode`; per lane compute signed or unsigned
min/max at the lane width (`$signed()` casts for signed) per the lane's `op_sel`; repack.

**Directed vectors (load-bearing = cross-lane compare isolation + signedness at lane tops):**
- 4×16 isolation: one lane's compare must not affect neighbors (distinct results per lane).
- 2×32 vs 1×64: same operands, different result because the compare chain breaks at bit 32.
- Signed vs unsigned on the same bits (e.g. `0xFFFF` = −1 signed / 65535 unsigned) → different
  min/max; check the sign bit is the *lane top* (bit 15/31/63 per mode), not a fixed bit.
- Mixed per-lane min/max; equal operands (a==b); all-zeros / all-ones / min / max corners.

**Handshake corners:** join, backpressure, input-invalid (family tasks).

**Randomized:** ~20,000 vectors over `(mode, is_signed, op_sel, a, b)`.

**PASS/FAIL:** single `PASS:`/`FAIL:` line; `$fatal(1)` on any mismatch.

## 7. `run.sh`

`verilator --lint-only -Wall` (clean) then `verilator --binary --timing` build + sim, grep
`^PASS:`. Invoked `./run.sh fu_min_max_decomp`.

## 8. Out of scope / follow-ups

- **Area validation** (synthesis: decomposable vs bank).
- **Physical segmented comparator** (this proves functional decomposition).
- **Pipelining / timing**; **generator/share-group integration**; **generalization**.
