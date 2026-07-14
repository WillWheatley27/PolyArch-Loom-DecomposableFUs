# fu_mult_decomp — Design Spec

**Date:** 2026-07-14
**Status:** Approved (design)
**Share group:** integer multiply (`arith.muli`) — **not currently a share group** in
`fabric_op_gen` (see `DECOMPOSABILITY_ANALYSIS.md`); this is a standalone decomposable
RTL deliverable, the highest-ROI decomposition target.
**Deliverable:** standalone RTL + self-checking testbench (no generator wiring)

## 1. Context

`DECOMPOSABILITY_ANALYSIS.md` flags integer multiply as the single best decomposition
target: a 64×64 partial-product (PP) array segments cleanly into 2×(32×32) or 4×(16×16)
by zeroing cross-lane partial products, giving very large area reuse. Multiply is *not*
one of the 19 `fabric_op_gen` share groups, so there is no base `fu_mult` to mirror; this
module instead reuses the interface skeleton and verification method established by
`fu_add_sub_decomp`.

This is the second decomposable FU and the first that decomposes a **product** datapath
rather than a carry chain.

## 2. Objective

Realize `decomposability = [32, 16]` on a 64-bit integer multiply unit such that the
dominant resource — the 16×16 block-product array — is reused across all three modes,
targeting the area inequality:

```
Area( FU64 modes {1×64, 2×32, 4×16} )  <  Area(FU64) + 2·Area(FU32) + 4·Area(FU16)
```

**Scope of this deliverable:** functional correctness of decomposition — all three modes
correct, with no partial-product leakage across lane boundaries. The area inequality is a
**synthesis** result and is an explicit follow-up (see §8); it is not claimed from RTL.

## 3. Multiply semantics — low-half (truncated), sign-agnostic

The FU produces a **same-width** output (64-bit in, 64-bit out), matching the whole FU
family and the `!fabric.bits<W>` convention. Each lane therefore returns the **low
`w` bits** of its `w×w` product (truncated / "multiply-low", like SSE `PMULLW`/`PMULLD`):

| mode | lanes (bit ranges) | per-lane result |
|------|--------------------|-----------------|
| 1×64 | [63:0]                          | low 64 of `a[63:0]  × b[63:0]` |
| 2×32 | [31:0], [63:32]                 | low 32 of each `32×32` lane |
| 4×16 | [15:0], [31:16], [47:32], [63:48] | low 16 of each `16×16` lane |

**No `op_sel` (no signed/unsigned knob).** The low `w` bits of a two's-complement product
are identical whether the operands are read as signed or unsigned:
`(a − 2^w·a_{msb})(b − 2^w·b_{msb}) ≡ a·b  (mod 2^w)`. A truncated multiply is therefore
sign-agnostic per lane, and since the packed output is just a concatenation of per-lane
low bits, the whole unit is sign-agnostic. Signedness only affects the *discarded* high
half, so a full-product / high-half variant is out of scope (see §8).

Little-endian lane packing (lane0 = LSBs), matching `fu_add_sub_decomp` and Loom's
`dataflow.pack` convention (`M = bitwidth(T)·vec_size`, lane 0 in the LSB slot).

## 4. Interface

```systemverilog
module fu_mult_decomp (
  input  logic        clk, rst_n,      // held for FU convention; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // held config: 00=1×64, 01=2×32, 10=4×16, 11=rsvd→1×64
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

- Fixed 64-bit base width, 16-bit lane granularity (four blocks). No `op_sel` port (§3).
- `mode` is **held config** with no handshake, matching how `op_sel` is treated in the
  base FUs.
- No flag/overflow outputs; the discarded high half is not exposed.

## 5. Datapath (combinational)

Operands split into four 16-bit blocks `a_k, b_k` (k=0..3). Define the block-product array

```
pp_ij = a_i × b_j     // 16×16 → 32-bit unsigned; the shared partial-product array
```

This is the 64×64 PP array at 16-bit granularity. A low-half decomposable multiply needs
**14** of the 16 products; the two corner products `pp13`, `pp31` have weight 2^64 (i+j=4)
and influence *no* lane's low bits, so they are intentionally not generated.

Per-mode output (all sums evaluated mod 2^{lane width}, i.e. by truncation):

```
1×64 :  p1 =  pp00
             + (pp01 + pp10)               << 16
             + (pp02 + pp11 + pp20)        << 32
             + (pp03 + pp12 + pp21 + pp30) << 48        // taken mod 2^64

2×32 :  lane0 = ( pp00 + (pp01 + pp10) << 16 )[31:0]    // low 32 of a[31:0]×b[31:0]
        lane1 = ( pp22 + (pp23 + pp32) << 16 )[31:0]    // low 32 of a[63:32]×b[63:32]
        p2    = {lane1, lane0}

4×16 :  p4 = { pp33[15:0], pp22[15:0], pp11[15:0], pp00[15:0] }

out_data = (mode==2×32) ? p2 : (mode==4×16) ? p4 : p1      // 00 and reserved 11 → p1
```

**Reuse:** the 16×16 block multipliers (the area) are instantiated once and shared across
modes; `pp00,pp01,pp10,pp11,pp22` are each used by more than one mode. Only the summation
+ alignment network and the final 64-bit output mux change between modes — the same
"shared datapath, cheap mode-muxing" story as `fu_add_sub_decomp` (there: one adder, three
carry muxes; here: one block-product array, mode-selected summation).

Written behaviorally (`*`, `+`, `<<`) so synthesis maps the array/reduction to its
preferred structure. All widths are explicit in RTL to keep `--lint-only -Wall` clean
(operands zero-extended before each `*`; weighted terms summed in 64 bits).

## 6. Handshake & latency

Unchanged from the family — 2-input join, combinational, latency 0:

```
out_valid  = in_valid_0 & in_valid_1;
in_ready_0 = out_ready & out_valid;
in_ready_1 = out_ready & out_valid;
```

A real 64×64 multiplier would be pipelined; here the core is combinational (matching the
FU family) because the deliverable is functional decomposition, not timing. Pipelining is
a synthesis follow-up alongside area validation (§8).

## 7. Verification

**Files:** `tb/tb_fu_mult_decomp.sv`, `run.sh` (parameterized by module basename).

**Golden model:** split `a`, `b` into lanes per `mode`, compute per-lane low-width product
(`a_lane * b_lane` truncated to lane width), repack into a 64-bit expected value. One sim
run covers all modes (`mode` is runtime).

**Directed vectors (load-bearing = cross-lane PP isolation):**
- 4×16 overflow isolation: a lane computing `0xFFFF × 0xFFFF = 0xFFFE0001` must keep only
  low 16 (`0x0001`) and **not** spill the high half into the neighbor lane; neighbors
  carry independent nonzero products.
- 2×32 vs 1×64 distinction: same operands, different result because cross-lane products
  (`pp02/pp11/pp20` etc.) are included in 1×64 but excluded from the 2×32 lanes — e.g.
  `a=b=0x0000_0001_0000_0001`: 1×64 → `0x0000_0002_0000_0001`, 2×32 → `0x0000_0001_0000_0001`.
- Mode equivalence: 1×64 reproduces a plain 64-bit truncated `×`.
- Sign-agnostic corner: operands with the lane MSB set (would be negative if signed) give
  the same low bits (implicitly checked — golden is unsigned, DUT must match).
- Per-lane corners: all-zeros, all-ones, max × max, ×1, ×0, alternating.

**Handshake corners:** join (`out_valid`), backpressure (`out_ready=0`), input-invalid —
the three tasks from `tb_fu_add_sub_decomp`.

**Randomized:** ~20,000 vectors over random `(mode, a, b)`, checked against golden.

**PASS/FAIL:** single `PASS:`/`FAIL:` line; `$fatal(1)` on any mismatch.

**`run.sh fu_mult_decomp`:** `verilator --lint-only -Wall` (clean) on the RTL, then
`verilator --binary --timing` build + sim, grep `^PASS:`.

## 8. Out of scope / follow-ups

- **Area validation:** confirming the §2 inequality requires synthesis (Yosys/DC) of the
  decomposable unit vs. the fixed-width bank. Separate task after RTL+TB are green.
- **Full / high-half product & signed·unsigned distinction:** this FU returns the low half
  only (sign-agnostic). A widening (2W-bit) product or a high-half tap would add a second
  output port / hi-lo select and a signedness `op_sel`; deferred.
- **Pipelining / timing:** the combinational core proves functional decomposition; a
  pipelined 64×64 array is a synthesis concern.
- **Share-group / generator integration:** integer multiply must first be added as an
  `arith.muli` share group in `fabric_op_gen`'s registry before this can be emitted by the
  generator; hand-authored standalone module first.
- **Generalization:** arbitrary base widths / lane granularities beyond 64-bit `[32,16]`.
