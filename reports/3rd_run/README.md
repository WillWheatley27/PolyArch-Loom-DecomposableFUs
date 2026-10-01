# 3rd Run: Left-Edge Mode Decode, DC PPA and PrimePower Dynamic Power

## What changed

In every decomposable unit, mode selection now sits at the left edge: one `mode_decode` block at
the input is the only logic that reads `mode`, and it produces a one-hot lane-width bus
(`l64/l32/l16/l8`, or `lvl[]` in the FP cores). Every downstream select is an AND-OR of that bus
with per-width candidates, not a priority if-chain on the mode value.

| RTL | Before | After |
|---|---|---|
| `fu_fp_min_max_gen.sv`, `fu_fp_cmp_gen.sv` | integer level `k` decoded inside every slice | one `lvl[]` decode; evaluator inputs and output selects AND-OR on it |
| `fu_cmp_gen.sv` | mode compares in the break mask and the result route | `l32/l16/l8/l64` decode; break, top-of-lane and route are AND-OR |
| `fu_abs_gen.sv`, `fu_barrel_shift_gen.sv` | `case (mode)` in the sign, mask and keep logic | `l32/l16/l64` decode; AND-OR of per-width constants |
| `fu_rounding_gen.sv` | mode compares in the masks and carry breaks | `l32/l16/l64` decode (with the EN tier gates); AND-OR masks |
| `fu_mult_decomp.sv`, `fu_mult_karatsuba_64_32.sv` | mode compared at the output mux | decode at the input; AND-OR (or single-bit) output select |

`fu_add_sub_gen.sv` and `fu_min_max_gen.sv` already had a single input decode and are
unchanged. All ten family testbenches, the Karatsuba 64/32 testbench, the revised FP tests and
the FP two-level tests pass.

## Method (apples to apples)

| Setting | Value |
|---|---|
| Library and corner | SAED14nm RVT, TT, 0.8 V, 25 C |
| Synthesis | DC Y-2026.03-SP1, `compile_ultra -area_high_effort_script -no_autoungroup`, one fresh `dc_shell` per design (`synth/syn_rerun.tcl`) |
| Targets | 1.000 ns and 0.500 ns max-delay, inputs to outputs |
| Timing closure | `CLOSURE=1`: if the first compile misses, retry with the constraint at 90%, 80%, then 70% of the period; keep the first result that meets the real target (`closure_factor` column) |
| DC power | uniform synthetic activity (static probability 0.5, toggle rate 0.2 per ns), as in every earlier run |
| Simulation power | gate netlist + SDF from the same compile, VCS gate simulation, PrimePower averaged mode (`synth/run_primepower.py`) |
| Stimulus | one shared file for every design: 20,000 random 64-bit operand pairs plus 32 random control bits, seed 20260930; one new operation per clock period; `mode` held for the whole run; one warm-up operation excluded |
| Activity scope | SAIF of the design only; 100% of nets annotated in all 180 runs |
| Wire load | the model DC chose for the same design (`set_wire_load_mode top`) |
| Modes | every supported mode of each decomposable unit; each fixed component in its only mode |

A row is marked `comparable=true` only when every design in it meets the corner's target.
With equal frequency on both sides, power savings equal energy-per-operation savings.

## Files

| File | Contents |
|---|---|
| `PPA_mode_left.csv` | DC area, static and dynamic power, timing and closure factor per design and corner, with the change against `reports/PPA_rerun.csv` |
| `mode_left_overhead.csv` | adjacent-tier overhead (DC area, static, dynamic, and the PrimePower overhead of the same 64-bit operation), against `reports/rerun_overhead.csv` |
| `mode_left_savings.csv` | DC savings against the fixed banks, against `reports/rerun_savings.csv` |
| `mode_left_primepower.csv` | PrimePower switching, internal, leakage and total power, energy per operation and per lane result, per design, corner and mode |
| `mode_left_power_savings.csv` | PrimePower savings per mode and weighted by `reports/mode_probabilities.csv` (64/32/16 = 25/50/25%, renormalized over the supported modes), against a gated bank and an all-active bank |
| `raw/` | DC reports, `result.txt` and PrimePower reports for every design |

Gate netlists and SDFs are not kept (125 MB). To reproduce, from the repository root:

```
OUTROOT=$PWD/reports/3rd_run/raw NETLIST=1 CLOSURE=1 JOB_FILTER='^<design> ' dc_shell -f synth/syn_rerun.tcl
python3 synth/run_primepower.py reports/3rd_run/raw <work_dir> [design ...]
cd reports && python3 collect_mode_left.py
```

Run one `dc_shell` per design (the job names are in `synth/syn_rerun.tcl`); the collector
rebuilds every table in this folder from `raw/`.

## 1. Effect of the left-edge decode on DC PPA

Every unedited design reproduces the previous rerun exactly, at both corners. The only
exceptions are the 2 GHz closure retries in Section 2. So the flow is deterministic, and any
change below comes from the RTL edit alone.

The single-mode tiers (`cmp_c1`, `abs_a1`, `barrel_bs1`, `rounding_g1` at 1 GHz, `fp_cmp_g1`)
also reproduce exactly, and so do the multi-mode `abs_a2` and `fp_cmp_g2`. Of the multi-mode units, both decomposable
multipliers reproduce bit for bit at 1 GHz.

Changes larger than 3% in the edited multi-mode units:

| Design | Corner | Area | Static | Dynamic |
|---|---|---:|---:|---:|
| `cmp_c2` | 1 GHz / 2 GHz | -0.2% / +7.7% | +17.4% / +17.1% | -4.9% / -3.9% |
| `cmp_c4` | 1 GHz / 2 GHz | -4.1% / +3.7% | -15.1% / +4.4% | +1.7% / +2.9% |
| `cmp_c8` | 1 GHz | -4.1% | -15.4% | +2.5% |
| `abs_a3` | 1 GHz | -1.6% | -1.7% | +10.3% |
| `barrel_bs3` | 2 GHz | -3.4% | -4.5% | -1.6% |
| `fp_cmp_g3` | 1 GHz / 2 GHz | +1.8% / +3.6% | -6.9% / +12.2% | -0.4% / +4.6% |
| `fp_minmax_m1` | 1 GHz / 2 GHz | +9.2% / +4.7% | +34.2% / +2.7% | -2.1% / +3.5% |
| `fp_minmax_m2` | 1 GHz | -3.3% | -3.2% | -2.0% |
| `fp_minmax_m3` | 1 GHz / 2 GHz | +5.0% / +2.5% | +1.9% / +1.7% | -0.5% / +3.8% |
| `rounding_g2` | 1 GHz | +3.7% | +6.2% | +9.3% |
| `rounding_g3` | 1 GHz | +5.8% | +10.4% | +13.9% |

- **Not a systematic cost or gain.** Changes go both ways and stay within about ±5% area. The
  left-edge form is a structural rewrite, not a change in function or hardware content, so
  DC does not get consistently smaller or larger logic from it.
- **Synthesis noise sets the floor.** `fp_minmax_m1` has a single mode: its one-hot bus is the
  constant `lvl[L] = 1`, so its logic is identical before and after. Yet it moved by +9.2% area
  and +34% leakage at 1 GHz, and by +4.7% area at 2 GHz. Equivalent but differently written
  RTL gives DC a different starting structure. For units of 100–200 um2, this is the
  resolution limit of single-compile DC comparisons: about ±5–9% area and much more in
  leakage. Differences smaller than this should not be read as architectural.
- **Savings barely move** (`mode_left_savings.csv`). Area savings change by -2.4 to +2.0 pp in
  every comparable row except `rounding_g3` at 1 GHz (-4.7 pp). Static savings change by up to
  +8.4 pp (`cmp_c4` at 1 GHz, from the c4 leakage drop) and down to -9.3 pp (`rounding_g3` at
  1 GHz).
- **Overhead.** The FP min/max ladder's steady first step (m1 to m2, +12.9% area at 1 GHz)
  now reads +0.1% at 1 GHz and +8.9% at 2 GHz. The second step (m2 to m3) reads +29.8% and
  +22.6%. This is not a real redistribution: the m1 baseline grew 9.2% for a design whose logic
  did not change. The two steps together go from +35% to +30% at 1 GHz and from +36% to +34%
  at 2 GHz, so the overall cost of decomposition is stable. Only the split between the steps
  is inside the noise. FP compare stays gradual (+4.5% then +15.2% at 1 GHz; +6.8% then +20.8%
  at 2 GHz).

## 2. Designs that cannot meet 2 GHz

All 57 designs meet 1 GHz on the first compile, and 49 meet 2 GHz on the first compile. The
other eight miss 2 GHz even at the 70% retry:

| Design | Best fmax with closure | Best with constraint at 40% + incremental compile |
|---|---:|---:|
| `rounding_g1` | 1.75 GHz | 1.87 GHz |
| `rounding_g2` | 1.89 GHz | 1.70 GHz |
| `rounding_g3` | 1.70 GHz | 1.76 GHz |
| `mult_dwfix_64` (DesignWare 64-bit) | 1.85 GHz | 1.89 GHz |
| `mult_kfix_32x2` | 1.68 GHz | 1.69 GHz |
| `mult_k64_32` | 1.34 GHz | not tried |
| `mult_k64` | 0.97 GHz | not tried |
| `mult_k64_32_16` | 0.92 GHz | not tried |

A further test tightened the constraint to 60%, 50% and 40% of the period and added
`compile_ultra -incremental`. The closest design gained 0.04 GHz and some lost speed, which
shows these units are at the delay limit of a single combinational stage in SAED14 RVT. A
64-bit rounder (a 64-bit increment plus masking) and a 64-bit multiplier both exceed 0.5 ns of
logic.

Consequences:
- **Rounding:** the decomposable unit and its bank are comparable at 1 GHz only.
- **Multipliers:** comparable at 1 GHz only. At 2 GHz every decomposable multiplier misses, as
  do two bank components.
- **Every other family** (AddSub, MinMax, Compare, Abs, Barrel Shift, FP Compare, FP Min/Max):
  comparable at both 1 GHz and 2 GHz.

The 2 GHz rows for rounding and the multipliers are kept, marked `comparable=false`, and must
not be used for conclusions:
- DC sizes a design that cannot meet its target differently from one that can.
- A gate simulation clocked faster than the critical path measures a circuit whose outputs
  never settle.

Making 2 GHz comparable for these two families needs a pipeline register, which changes the
designs (latency 1). That is outside this rerun.

## 3. PrimePower: what the simulation shows

### Simulation power vs DC's estimate

PrimePower dynamic power is 1.8–3.6x DC's estimate at 1 GHz and 2.9–6.5x at 2 GHz (timing-met rows).
`primepower_over_dc_dynamic` records the ratio for every row. This is expected, for two
reasons:
- **Input activity.** DC assumes 0.2 toggles per ns on every input. Random operands toggle each
  bit with probability 0.5 per operation, which is 0.5 per ns at 1 GHz and 1.0 per ns at 2 GHz.
- **Glitches.** The SDF-timed simulation counts glitches, which DC's probabilistic propagation
  does not. Glitches are worst in deep arithmetic. Decomposable units glitch more than the
  equivalent fixed unit: `addsub_d1` is 2.9x its DC estimate while `addsub_fix_64` is 2.1x, so
  simulation widens gaps that DC underestimates.

The ratio is consistent within each family, so DC's dynamic numbers rank designs correctly in
most families but understate absolute power. Leakage agrees with DC to within -0.8% to +2.1% in every row.

### Savings depend on the bank model

| Family (bank) | 1 GHz vs all-active bank | 1 GHz vs gated bank (weighted) | 2 GHz vs all-active | 2 GHz vs gated (weighted) |
|---|---:|---:|---:|---:|
| AddSub d4 (64 + 32x2 + 16x4) | +56.6% | -13.7% | +55.0% | -20.8% |
| MinMax m4 | +53.5% | -30.4% | +63.6% | -9.0% |
| Compare c4 | +56.4% | -29.5% | +51.1% | -48.7% |
| Abs a3 | +42.2% | -53.0% | +28.4% | -110.5% |
| Barrel Shift bs3 | +57.6% | -32.2% | +54.5% | -44.4% |
| FP Compare g3 (DW bank) | +66.5% | **+0.1%** | +68.1% | **+3.8%** |
| FP Min/Max m3 (DW bank) | +57.0% | -26.1% | +64.0% | -5.0% |
| Rounding g3 | +22.3% | -126.0% | not comparable | not comparable |
| Mult k64_32_16 (DW bank) | +2.5% | -191.7% | not comparable | not comparable |
| Mult k64_32_16 (Karatsuba bank) | +30.0% | -118.8% | not comparable | not comparable |

The two bank models:
- **All-active bank:** every bank component sees the operands every cycle. This is the bank DC's
  savings implicitly assume.
- **Gated bank:** only the component for the current mode switches, and the idle components
  contribute leakage only. This assumes perfect, free operand isolation in the bank; the
  isolation and output-mux logic it would need is not counted.

The real fixed-bank design lies between the two. Positive numbers mean the decomposable unit
uses less power.

1. **Against an all-active bank, the decomposable unit saves 42–68% of power.** This holds for
   every non-multiplier family at both corners and agrees with the DC dynamic savings. Rounding
   saves 22%, the Karatsuba-bank multiplier 30%, and the DesignWare-bank multiplier 2.5%.
2. **Against a gated bank, the decomposable unit uses more power per operation in almost every
   family.** It is a single wider datapath that switches fully in every mode. A gated bank
   switches only the one specialized component needed, and each component is smaller and
   simpler than the decomposable unit:
   - in AddSub 4x16 mode, the 16x4 unit uses 0.72 mW and the decomposable unit 1.55 mW;
   - in Abs 4x16 mode, the 16x4 unit uses 0.30 mW and the decomposable unit 0.92 mW.
3. **FP Compare is the exception.** It breaks even with the gated DesignWare bank at 1 GHz (+0.1%)
   and wins at 2 GHz (+3.8%; +9.5% in FP64 mode), while saving 63% area. The sliced comparator
   is close to the DesignWare FP64 comparator in per-operation energy. FP Min/Max is within 5%
   of the gated bank at 2 GHz.
4. **Decomposable multipliers do not scale power with mode.** `mult_k64_32_16` uses 38.7–38.8 mW
   in every mode, because the two 32x32 Karatsuba halves and the 33x33 cross multiplier compute
   on every cycle. The narrow modes only select different output bits. In 4x16 mode the gated
   DesignWare bank needs 3.9 mW: 10x less. Operand isolation, which forces the cross multiplier's
   and the off-diagonal partial products' inputs to zero in narrow modes, is the standard fix.
   It is a design change and was not made here.
5. **Mode dependence.** The per-mode rows show where each architecture spends energy.
   - Barrel Shift is the only family whose decomposable power falls with mode: 3.9 to 3.0 mW at
     1 GHz, because shifts in narrow lanes move bits across fewer positions.
   - Abs and FP Min/Max rise slightly in the narrow modes: more lanes produce results and more
     sign or NaN logic switches.

So the area and leakage savings hold in every family except the multipliers against a
DesignWare bank. Dynamic energy savings hold only if the alternative bank leaves its idle
components switching. A bank that isolates idle components beats every decomposable unit on
energy except FP Compare. FP Min/Max and AddSub come closest at 2 GHz.

## 4. Other deviations from expected data

- **AddSub fixed 32x2 is an outlier in the bank.** `addsub_fix_32x2` (263 um2, 1.91 mW) is larger
  and uses more power than `addsub_fix_64` (174 um2, 0.99 mW). This is the only reason the
  decomposable AddSub beats the gated bank in its 2x32 mode (+17.7% at 1 GHz). The anomaly was
  already present in the original data and in `reports/PPA_rerun.csv`; it comes from that standalone
  RTL, not from this run.
- **DesignWare multiplier vs hand-written Karatsuba (flagged).** At 1 GHz the DesignWare 64-bit
  multiplier is 53% smaller (2281 vs 4848 um2) and uses 37% less power (22.5 vs 36.0 mW) than
  the hand-written Karatsuba `mult_k64`. It is also faster: 1.89 GHz maximum versus 0.97 GHz.
  - **Pros of DesignWare:** smaller, faster, and lower energy at this width and node; the
    Karatsuba saving in multipliers does not pay for its pre- and post-adders at 64 bits in
    SAED14.
  - **Cons of DesignWare:** it is a black box. Its sub-products cannot be shared between modes,
    so a DesignWare bank cannot be made decomposable. And the comparison depends on the
    DesignWare version.
- **Rounding carry breaks are redundant.** The lane breaks in `fu_rounding_gen.sv` can never
  change the result, because rounding never carries across a lane. A mutation that removes them
  passes every test. This is a design note, not a test gap.
- **Identical fixed 16x4 multipliers.** `mult_kfix_16x4` and `mult_dwfix_16x4` report identical
  numbers because both are four DesignWare `DW02_mult` 16x16 leaves.

## Conclusions

1. Moving mode selection to the left edge does not change PPA beyond DC's run-to-run structural
   noise. Area changes stay within about ±5% (one equivalent design moved 9%), and every
   savings figure moves by at most 4.7 pp. The circuit diagrams can use the left-edge structure
   with no PPA penalty.
2. Every family is comparable at 1 GHz. Every family except Rounding and the multipliers is
   comparable at 2 GHz. Those two families cannot reach 2 GHz as single combinational stages
   in SAED14 RVT and would need pipelining.
3. With simulated activity, decomposable units save 42–68% of dynamic power against a bank
   whose components all switch. Against a bank that isolates its idle components, every
   decomposable unit except FP Compare uses more energy per operation. The area and leakage
   savings are robust; the dynamic savings depend on whether the alternative is operand-gated.
