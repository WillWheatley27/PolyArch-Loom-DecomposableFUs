# fu_barrel_shift_decomp — Design Spec

**Date:** 2026-07-17
**Status:** Approved (design)
**Share group:** 4 (`arith.shli`, `arith.shrsi`, `arith.shrui`) — Tier-B in
`DECOMPOSABILITY_ANALYSIS.md` (build with the per-lane-shift-amount caveat). Third in the
recommended build order (after `add_sub`, `min_max`).
**Deliverable:** standalone RTL + self-checking testbench (native-SV golden)

## 1. Context & decomposability

A barrel shifter is a log-depth mux network. It is Tier-B decomposable: the network is reused
across modes, but — the caveat — **independent per-lane shift amounts** need replicated
shift-amount decode and per-stage cross-lane blocking (bits must not spill into a neighbor
lane; the low/high fill is 0 or sign per lane). A common shift amount would be cheaper; this
module implements the more general **independent per-lane amount** version, which is the
interesting decomposition and matches AVX2-style packed variable shifts.

`decomposability = [32,16]`: each lane shifts within its own width (1×64 / 2×32 / 4×16). This is
the third integer module; it decomposes a **shifter** network (after the adder and comparator).

## 2. Operation

`out = shift(a, amt, shift_op)` per lane:
- **SLL** (`shli`): logical left, zero-fill.
- **SRL** (`shrui`): logical right, zero-fill.
- **SRA** (`shrsi`): arithmetic right, sign-fill.

`shift_op` is **global** (the shift *type* is per-instruction, like the ISA member selector of
share group 4). Shift **amounts are per-lane**: each lane's amount is the low `log2(lane_width)`
bits of the corresponding lane of `in_data_1` (`b`) — 4 bits for fp16-width lanes (0..15),
5 bits for 32-bit (0..31), 6 bits for 64-bit (0..63). Higher bits of each `b` lane are ignored
(the standard shift-count masking, e.g. x86/RISC-V), so amounts are always `< lane_width` and no
lane ever spills into a neighbor.

## 3. Interface

```systemverilog
module fu_barrel_shift_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=1×64, 01=2×32, 10=4×16, 11=rsvd→1×64
  input  logic [1:0]  shift_op,        // held: 00=SLL, 01=SRL, 10=SRA, 11=rsvd→SLL
  input  logic [63:0] in_data_0,       // a = data to shift (packed lanes)
  input  logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1,       // b = per-lane shift amounts (low log2(w) bits per lane)
  input  logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

- Little-endian lane packing. `shift_op` is global (like `min_max`'s `is_signed`); it replaces the
  base family's `op_sel` for this module (the op is the shift type).
- Unused high bits of `in_data_1` (shift-count masking) are lint-waived, matching real
  shift units that ignore the high count bits.

## 4. Datapath (combinational)

Per lane, shift the lane's data by its masked amount at the lane width:

```
per w-bit lane:  amt = b_lane[log2(w)-1:0]
  SLL: x << amt        SRL: x >> amt        SRA: $signed(x) >>> amt
```

Lane amount sources: 1×64 → `b[5:0]`; 2×32 → `b[4:0]`, `b[36:32]`; 4×16 → `b[3:0]`, `b[19:16]`,
`b[35:32]`, `b[51:48]`. Results computed per mode and mode-muxed (`00`/reserved `11` → 1×64).

This RTL proves **functional** decomposition (correct independent per-lane shifts, no cross-lane
spill). A **physically-shared segmented barrel network** (one log-depth mux network with
per-stage lane-boundary blocking and per-lane stage-enables) is the synthesis/area objective —
the per-lane-amount overhead the analysis flags — tracked as a follow-up (§7), consistent with
the rest of the family.

## 5. Handshake & latency

Unchanged — 2-input join, combinational, latency 0.

## 6. Verification

**Golden (native SV):** per lane, `SLL/SRL/SRA` at the lane width using `<<`, `>>`, `$signed>>>`
with the same low-`log2(w)`-bit amount. Directed: each shift type at each width; amounts 0, 1,
`w-1`, and `≥w` (must mask, i.e. use low bits only); SRA sign-fill of negative and positive
values; cross-lane isolation (a lane's shift must not affect neighbors); all-ones / patterns.
Handshake corners (family tasks). ~20,000 random over `(mode, shift_op, a, b)`.

**PASS/FAIL:** single line; `$fatal(1)` on mismatch. `./run.sh fu_barrel_shift_decomp`.

## 7. Out of scope / follow-ups

- **Physical shared segmented barrel network** (per-stage lane blocking) — the area objective.
- **Area validation** (synthesis: decomposable vs bank); **pipelining**; **common-amount variant**;
  **generator/share-group integration**; **generalization**.
