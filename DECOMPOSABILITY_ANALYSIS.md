# Decomposable FU Analysis — fabric_op_gen share groups

Scope: the **19 hardware share groups** in `fabric_op_gen` (`registry.yaml`). Other
`/edata1` RTL (Sihao's FHE accelerator, etc.) is explicitly out of scope.

## Objective (restated)

"Decompose" = **subword / SIMD segmentation**: one physical W=64-bit FU that can also
act as 2×32-bit or 4×16-bit independent lanes, selected by a mode knob
(`decomposability = [32, 16]`).

The win condition — a single mode-switchable unit is cheaper than a bank of dedicated
fixed-width units covering the same widths:

```
Area( FU64  with modes {1×64, 2×32, 4×16} )  <  Area(FU64) + 2·Area(FU32) + 4·Area(FU16)
```

(This is the corrected reading of the inequality in the request.) It holds **iff the
dominant datapath area is *reused* across modes**, with only cheap mode-muxing added.

### The single criterion that decides it

> Is the FU's dominant combinational structure **lane-separable** — can it be cut at the
> 16/32-bit boundaries by gating a *small* number of signals (carries, borrows, cross-lane
> bit movement), while the bulk of the area (adder, PP-array, shifter, comparator) is shared?

Two structural properties make an FU **NOT** decomposable:

1. **Sequential / iterative** datapath with per-op state (dividers): a 64-bit iteration
   can't be split into k independent narrower iterations sharing the same silicon — you
   end up rebuilding k separate engines. RHS wins.
2. **Per-format baked constants** (transcendentals: coefficient ROMs, CORDIC tables, LUTs):
   fp16/fp32/fp64 need *different* constants, so a single unit can't hold one shared
   constant set that serves all lane widths — the "shared datapath" story collapses into
   "k datapaths + k constant sets + muxes."

A third property makes it **trivially** decomposable but with **no tradeoff to exploit**:
bitwise ops are already fully lane-independent (a 64-bit AND *is* four 16-bit ANDs).

---

## Classification

| # | Share group | Family | Datapath | Decomposable? | Tier |
|---|-------------|--------|----------|---------------|------|
| 1 | add_sub | int | one W-bit adder | **YES** | A — build |
| 6 | min_max_signed | int | comparator (subtract) + mux | **YES** | A — build |
| 7 | min_max_unsigned | int | comparator (subtract) + mux | **YES** | A — build |
| 10 | fp_add_sub | fp | align-shift + mantissa add + normalize | **YES** | A — build |
| 12 | fp_min_max | fp | monotonic-key compare | **YES** | A — build |
| 4 | barrel_shift | int | log-depth mux network | **YES\*** | B — build (caveat) |
| 5 | bitwise_alu | int | per-bit and/or/xor | **YES (trivial)** | — no module needed |
| 17 | rounding | fp | exponent/mantissa mask+incr | feasible | C — low priority |
| 8 | int_to_fp | int↔fp | LZC + normalize shifter + round | feasible\*\* | C — low priority |
| 9 | fp_to_int | int↔fp | align shifter + saturate | feasible\*\* | C — low priority |
| 2 | div_rem_signed | int | **iterative restoring FSM** | **NO** | — |
| 3 | div_rem_unsigned | int | **iterative restoring FSM** | **NO** | — |
| 11 | fp_div_rem | fp | **iterative restoring FSM** | **NO** | — |
| 13 | cordic_trig | math | unrolled iterative shift-add + tables | **NO** | — |
| 14 | cordic_hyp | math | unrolled iterative shift-add + tables | **NO** | — |
| 15 | exp_series | math | Horner poly, **per-format coeffs** | **NO** | — |
| 16 | log_core | math | Horner poly, **per-format coeffs** | **NO** | — |
| 18 | sqrt_rsqrt | math | Horner poly, **per-format coeffs** | **NO** | — |
| 19 | approx_tanh_erf | math | **LUT + interp** | **NO** | — |

`*`  barrel_shift: shifter network is reused, but *independent per-lane shift amounts* need
     replicated shift-amount decode + per-stage cross-lane blocking muxes. Cheap if a common
     shift amount is acceptable; more overhead if each lane shifts independently.
`**` conversions couple int width to FP format — decomposing means the *output format itself*
     changes per lane (int32→fp32, int16→fp16), so rounding / bias / field-packing must switch
     per mode. Datapath (LZC+shifter) segments fine, but control/packing overhead is high vs. a
     modest datapath → marginal net win.

---

## Verdict buckets

### ✅ Decompose — real area win, recommended to build (6)
`add_sub`, `min_max_signed`, `min_max_unsigned`, `fp_add_sub`, `fp_min_max`, `barrel_shift`

These are all **carry/borrow/compare/shift** datapaths. Segmentation = break the carry (or
compare, or cross-lane shift) chain at bits 16/32/48 with mode-gated signals; the adder /
comparator / shifter — which is the area — is shared across all three modes. This is exactly
classic SIMD (MMX/SSE `PADD*`, `PMIN*`, `PSLL*`; GPU packed-fp16 add). `fp_add_sub` costs more
overhead than integer (per-lane exponent paths, special-cases, GRS rounding) but the align +
normalize shifters + mantissa adder dominate and are reused, so the inequality still holds.

### ⚪ Decomposable but degenerate / low value (4)
- **`bitwise_alu`** — trivially already SIMD; a wide bitwise unit needs *zero* extra logic to
  run as narrow lanes and there is nothing to share/save. The inequality holds trivially but
  a dedicated "decomposable" module is pointless.
- **`rounding`, `int_to_fp`, `fp_to_int`** — genuinely lane-separable, but either the FU is so
  cheap the absolute saving is tiny (rounding is mostly masks) or the per-mode format switch
  adds control/packing overhead that eats the benefit. Feasible, low priority.

### ❌ Not practically decomposable (9)
- **Dividers** (`div_rem_signed`, `div_rem_unsigned`, `fp_div_rem`) — iterative restoring-division
  FSMs with per-op sequential state and width-dependent iteration counts. Cannot share the
  sequential datapath across lane widths; SIMD integer/FP divide is essentially never built.
- **Transcendentals** (`cordic_trig`, `cordic_hyp`, `exp_series`, `log_core`, `sqrt_rsqrt`,
  `approx_tanh_erf`) — dominated by **per-format baked constants** (CORDIC angle tables, minimax
  coefficient sets, the 129-entry tanh/erf LUT). Different lane widths need different constants,
  and the LUT would need k read ports (or replication) for k lanes — the sharing benefit is lost.
  Build narrow instances instead.

---

## Note on the requested examples

`AddSub` (group 1) and `FPAdd` (group 10) are share groups → both in the "build" bucket. ✔

**`Mult` and `FPMult` are NOT share groups in `fabric_op_gen`** — there is no `arith.muli` or
`arith.mulf` group in `registry.yaml` (the 19 groups cover add/sub, div/rem, shift, bitwise,
min/max, int↔fp, fp add/sub, fp div/rem, fp min/max, and 7 transcendentals — no multiply).
They are the single best decomposition targets that exist (a 64×64 partial-product array cleanly
segments into 2×(32×32) or 4×(16×16) by zeroing cross-lane partial products — very large area
reuse), so **recommend adding integer-multiply and fp-multiply share groups** if they are to be
part of this effort.

---

## Recommended build order

1. `add_sub` — simplest, canonical, highest confidence; establishes the segmented-carry pattern.
2. `min_max_signed` / `min_max_unsigned` — reuse the same segmented compare chain.
3. `barrel_shift` — segmented shifter (decide: common vs. per-lane shift amount).
4. `fp_add_sub`, `fp_min_max` — packed-FP; higher overhead, biggest individual payoff.
5. *(if in scope)* add + decompose **integer multiply** and **fp multiply** — best ROI of all.
