# 3rd Run: Left-Edge Mode Decode, DC PPA and PrimePower Dynamic Power, 100 MHz to 2 GHz

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
| Synthesis | DC Y-2026.03-SP1, `compile_ultra -area_high_effort_script -no_autoungroup`, a fresh `dc_shell` per design (`synth/syn_rerun.tcl`): 1 GHz then 2 GHz in one session (the original runs), and one session per design and target for 100 MHz, 500 MHz and 1.5 GHz |
| Targets | max-delay inputs to outputs: 10 ns (100 MHz, `100_mhz`), 2 ns (500 MHz, `500_mhz`), 1 ns (1 GHz, `one_ghz`), 0.667 ns (1.5 GHz, `1p5_ghz`), 0.5 ns (2 GHz, `two_ghz`) |
| Timing closure | `CLOSURE=1`: if the first compile misses, retry with the constraint at 90%, 80%, then 70% of the period; keep the first result that meets the real target (`closure_factor` column) |
| DC power | uniform synthetic activity (static probability 0.5, toggle rate 0.2 per ns), as in every earlier run. The rate is per ns, not per cycle, so DC's dynamic estimate does not scale with the clock; use PrimePower to compare power across frequencies |
| Simulation power | gate netlist + SDF from the same compile, VCS gate simulation, PrimePower averaged mode (`synth/run_primepower.py`) |
| Stimulus | one shared file for every design: 20,000 random 64-bit operand pairs plus 32 random control bits, seed 20260930; one new operation per clock period of the target frequency; `mode` held for the whole run; one warm-up operation excluded |
| Activity scope | SAIF of the design only; 100% of nets annotated in every run |
| Wire load | the model DC chose for the same design (`set_wire_load_mode top`) |
| Modes | every supported mode of each decomposable unit; each fixed component in its only mode |

A row is marked `comparable=true` only when every design in it meets the corner's target.
With equal frequency on both sides, power savings equal energy-per-operation savings.

## Files

| File | Contents |
|---|---|
| `PPA_mode_left.csv` | DC area, static and dynamic power, timing and closure factor per design and corner, with the change against `reports/PPA_rerun.csv`; PrimePower power in the widest-format mode and mode-weighted (`mode_probabilities.csv`, renormalized over the supported modes), with the weighted energy per operation |
| `mode_left_overhead.csv` | adjacent-tier overhead (DC area, static, dynamic, and the PrimePower dynamic and total overhead of the same widest-format operation), against `reports/rerun_overhead.csv` |
| `mode_left_savings.csv` | DC savings against the fixed banks, against `reports/rerun_savings.csv`, with the PrimePower savings of the same comparison against a gated and an all-active bank (mode-weighted; the only mode for single-mode units) |
| `mode_left_primepower.csv` | PrimePower switching, internal, leakage and total power, energy per operation and per lane result, per design, corner, function (AddSub+MinMax only) and mode |
| `mode_left_power_savings.csv` | PrimePower savings per mode and weighted by `reports/mode_probabilities.csv` (64/32/16 = 25/50/25%, renormalized over the supported modes), against a gated bank and an all-active bank |
| `mode_left_side_function_power.csv` | PrimePower of AddSub with a Min/Max side function, per function and mode plus mode-weighted, against separate AddSub and Min/Max units (Section 5) |
| `raw/` | DC reports, `result.txt` and PrimePower reports for every design |

The AddSub+MinMax unit has one row per function in every table (`function` = `addsub` or
`minmax`, meaning `is_min_max` held at 0 or 1); `function` is empty for every other design.

Gate netlists and SDFs are not kept (125 MB). To reproduce, from the repository root:

```
OUTROOT=$PWD/reports/3rd_run/raw NETLIST=1 CLOSURE=1 JOB_FILTER='^<design> ' dc_shell -f synth/syn_rerun.tcl
OUTROOT=$PWD/reports/3rd_run/raw NETLIST=1 CLOSURE=1 CORNERS=<100_mhz|500_mhz|1p5_ghz> JOB_FILTER='^<design> ' dc_shell -f synth/syn_rerun.tcl
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

At the 1.5 GHz target added in Section 7, only the three Karatsuba tiers miss (k64 1.06 GHz,
k64_32 1.35 GHz, k64_32_16 1.03 GHz, after the 70% retry); Rounding, the DesignWare 64-bit
multiplier and the Karatsuba fixed 32x2 meet it. Every design meets 100 MHz and 500 MHz, and every
design other than those three meets 1.5 GHz on the first compile.

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

## 5. AddSub with a Min/Max side function

`rtl/fu_add_sub_minmax_gen.sv` computes Min/Max through the AddSub carry chain: it forces
A - B in every lane and reads equal, unsigned-greater and signed-greater from the zero, carry
and sign/overflow of the difference. Its four tiers (d1, d2, d4, d8) were synthesized on the
same flow and simulated twice per mode, with `is_min_max` held at 0 (AddSub) and at 1
(Min/Max). Operands are the shared stimulus; control bits are random. The comparison is with
separate AddSub and Min/Max units of the same capability (d8 pairs with m4, as Min/Max has no
8x8 tier). Every design meets 1 GHz and 2 GHz on the first compile.

DC, decomposable side-function unit vs the separate pair (`mode_left_savings.csv`;
negative = the side-function unit is worse):

| Tier | Corner | Side-function area (um2) | Separate pair (um2) | Area | Static | Dynamic |
|---|---|---:|---:|---:|---:|---:|
| d1 | 1 GHz / 2 GHz | 337.1 / 641.3 | 301.0 / 344.4 | -12.0% / -86.2% | -17.9% / -165.5% | -0.5% / -50.0% |
| d2 | 1 GHz / 2 GHz | 370.0 / 711.2 | 292.3 / 375.6 | -26.6% / -89.3% | -60.7% / -172.4% | -7.6% / -51.9% |
| d4 | 1 GHz / 2 GHz | 440.2 / 805.1 | 303.9 / 418.0 | -44.9% / -92.6% | -95.8% / -164.5% | -12.7% / -60.4% |
| d8 | 1 GHz / 2 GHz | 426.5 / 1114.8 | 355.8 / 441.7 | -19.9% / -152.4% | -34.6% / -247.3% | -11.8% / -86.3% |

PrimePower (`mode_left_side_function_power.csv`), total power per operation:

| Tier | Corner | vs the active separate unit alone (gated pair) | vs both separate units switching |
|---|---|---:|---:|
| d4 | 1 GHz | -111% (AddSub), -118..-122% (Min/Max) | -17% (AddSub), +1..+2% (Min/Max) |
| d4 | 2 GHz | -117..-133% (AddSub), -338..-414% (Min/Max) | -48..-54% |
| d8 | 1 GHz | -72..-73% (AddSub), -102..-105% (Min/Max) | -1..-2% (AddSub), +16..+17% (Min/Max) |
| d8 | 2 GHz | -162..-171% (AddSub), -450..-523% (Min/Max) | -76..-89% |

The idle unit's leakage is below 0.2 uW, so the gated pair is effectively the active unit.

- **Sharing the carry chain does not pay.** The side-function unit is larger than a separate
  AddSub plus a separate Min/Max at every tier and both corners, and uses 2-6x the power of the
  unit that is actually working. Only against a pair whose idle unit keeps switching does it
  break even, and only for Min/Max at 1 GHz.
- **Why.** Min/Max becomes serial: the full-width subtraction, then the zero chain, then the
  lane-top compare, then the select chain and the 64-bit byte muxes. A standalone Min/Max
  compares blocks in parallel and needs no carry-propagate result. To meet the target on the
  longer path DC upsizes the shared adder, which also makes AddSub mode slower and hungrier; the
  Min/Max logic keeps switching in AddSub mode (no operand isolation). The penalty grows sharply
  at 2 GHz, where the d8 unit is 2.5x the separate pair.
- **Reproducibility.** The d4 tier at 1 GHz is 440.18 um2, identical to the earlier
  `reports/addsub_minmax_savings.csv` run (the RTL is unchanged); the separate pair moved from
  308.3 to 303.9 um2 with the 3rd-run AddSub and Min/Max results.

## 6. FP min/max two-level experiment, rerun with PrimePower

The FP64 -> 2xFP32 split reuses the 3rd-run designs (m1, m2, DesignWare FP64 and FP32x2), which
are the same RTL and flow as the experiment's fresh-session configuration. The FP32 -> 2xFP16
split was synthesized here: `fp_minmax_w32_m1` (the sliced core at W=32 with MIN_LANE_W=32,
FP32 only), `fp_minmax_w32_m2` (`fu_fp_minmax_revised_32_16`, FP32/2xFP16), and the DesignWare
FP32 and FP16x2 units. All meet both targets on the first compile.

| Split | Corner | Area saving | Static | Dynamic (DC) | PrimePower vs all-active bank (weighted) | PrimePower vs gated bank (weighted) |
|---|---|---:|---:|---:|---:|---:|
| FP64 -> 2xFP32 | 1 GHz | 52.2% | 52.5% | 45.4% | +43.2% | -12.2% |
| FP64 -> 2xFP32 | 2 GHz | 49.9% | 49.4% | 48.8% | +53.6% | +8.4% |
| FP32 -> 2xFP16 | 1 GHz | 37.9% | 27.7% | 40.3% | +39.4% | -18.4% |
| FP32 -> 2xFP16 | 2 GHz | 42.3% | 38.5% | 44.1% | +47.7% | +0.8% |

Weights are the FP min/max mode probabilities renormalized over the two formats (wide 1/3,
narrow 2/3 for FP64/FP32; 2/3 and 1/3 for FP32/FP16). Overhead of adding the narrow lanes
(`mode_left_overhead.csv`):

| Split | Corner | Area | Static | Dynamic (DC) | PrimePower, wide-format operation |
|---|---|---:|---:|---:|---:|
| FP64 -> +2xFP32 (m1 -> m2) | 1 GHz / 2 GHz | +0.1% / +8.9% | -15.6% / +14.3% | +15.4% / +7.8% | +1.2% / +19.0% |
| FP32 -> +2xFP16 (w32_m1 -> w32_m2) | 1 GHz / 2 GHz | +15.1% / +10.3% | +10.8% / +19.4% | +6.7% / -0.8% | +0.4% / +4.0% |

- **Both splits still pay** against a bank whose components all switch: 39-54% power with
  simulated activity, in line with the DC estimates. Against a gated DesignWare bank, a single
  split loses 12-18% at 1 GHz and breaks even or wins at 2 GHz (+0.8% and +8.4%), because the
  DesignWare units grow more than the sliced core under the 0.5 ns target.
- **Deviation from the earlier experiment.** The DesignWare units reproduce the earlier
  fresh-session results exactly (FP32 63.0 / 87.6 um2, FP16x2 53.9 / 66.9 um2, FP64 138.9 /
  159.9 um2, FP32x2 127.7 / 176.8 um2), so the flow is identical. The hand-written units moved
  with the left-edge rewrite, as in Section 1. The FP32-only tier grew from 68.1 to 80.9 um2 at
  2 GHz with logic that did not change (one level, constant level bus), which lowers the FP32 ->
  +2xFP16 overhead at 2 GHz from +23.7% to +10.3%. The earlier conclusion that the narrow
  split's overhead rises at 2 GHz rested on the FP32-only tier barely growing between the
  corners (66.9 to 68.1 um2); with a normal timing-driven growth that rise is gone, and both
  splits cost about 10-15% area where the step is resolved. Area savings agree with the earlier
  ranges within 2-3 pp (FP64 split 49.1-50.5% / 49.2% before; FP32 split 35.2-36.1% / 45.5%
  before).

## 7. Frequency sweep: 100 MHz, 500 MHz and 1.5 GHz

All 65 designs (every tier, every fixed bank unit, the AddSub+MinMax side function and the FP
min/max two-level experiment) were also synthesized at 10 ns, 2 ns and 0.667 ns, one fresh
`dc_shell` per design and target, and simulated in PrimePower with one operation per clock period
of that target. Every table in this folder now has rows for `100_mhz`, `500_mhz`, `one_ghz`,
`1p5_ghz` and `two_ghz`; the 1 GHz and 2 GHz rows are unchanged. 100% of nets are annotated in all
195 new PrimePower runs.

### DC savings against the fixed bank, by target (`mode_left_savings.csv`)

Area saving (static saving in brackets); `*` = a design misses the target, not comparable.

| Comparison | 100 MHz | 500 MHz | 1 GHz | 1.5 GHz | 2 GHz |
|---|---:|---:|---:|---:|---:|
| AddSub d4 vs 64 + 32x2 + 16x4 | 69.8 (67.6) | 57.8 (59.4) | 66.3 (62.0) | 62.6 (54.7) | 59.9 (48.6) |
| AddSub d8 vs + 8x8 | 76.5 (75.0) | 65.7 (67.4) | 63.8 (48.3) | 65.9 (56.7) | 62.3 (48.9) |
| MinMax m4 | 62.0 (61.8) | 62.7 (67.8) | 64.7 (66.2) | 64.0 (65.1) | 58.4 (53.6) |
| Compare c4 | 59.3 (67.2) | 60.3 (66.1) | 56.7 (52.8) | 39.9 (31.0) | 32.9 (17.7) |
| Compare c8 | 70.0 (74.7) | 70.4 (73.7) | 66.5 (60.7) | 54.3 (46.4) | 49.1 (35.8) |
| Abs a3 | 60.9 (60.9) | 54.0 (47.8) | 52.5 (46.9) | 53.6 (44.4) | 49.3 (35.5) |
| Barrel Shift bs3 | 56.8 (57.0) | 53.2 (49.4) | 50.9 (46.1) | 45.8 (40.7) | 42.1 (37.8) |
| FP Compare g3 (DW bank) | 61.8 (66.1) | 61.2 (61.8) | 63.1 (65.9) | 64.3 (64.5) | 62.8 (59.3) |
| FP Min/Max m3 (DW bank) | 58.2 (55.9) | 59.1 (59.2) | 55.6 (48.6) | 52.9 (45.5) | 56.2 (52.8) |
| Rounding g3 | 21.7 (8.9) | 27.2 (31.2) | 13.4 (1.6) | 17.7 (13.5) | 20.3* |
| Mult k64_32_16 vs DW bank | **35.2** (37.0) | **28.6** (21.9) | -26.9 (-78.3) | -18.3* | 11.1* |
| Mult k64_32_16 vs Karatsuba bank | 43.9 (48.5) | 41.7 (38.6) | 28.0 (21.2) | 35.6* | 42.8* |
| FP min/max FP64 -> 2xFP32 | 50.3 (50.9) | 46.0 (40.3) | 52.2 (52.5) | 51.9 (53.5) | 49.9 (49.4) |
| FP min/max FP32 -> 2xFP16 | 44.5 (41.7) | 43.7 (41.6) | 37.9 (27.7) | 44.2 (44.4) | 42.3 (38.5) |
| AddSub+MinMax d4 vs separate pair | **12.1** (4.3) | -8.8 (-23.4) | -44.9 (-95.8) | -53.8 (-115.1) | -92.6 (-164.5) |

### PrimePower savings, mode-weighted (all-active bank / gated bank)

| Comparison | 100 MHz | 500 MHz | 1 GHz | 1.5 GHz | 2 GHz |
|---|---:|---:|---:|---:|---:|
| AddSub d4 | 59 / -22 | 35 / -95 | 57 / -14 | 54 / -19 | 55 / -21 |
| MinMax m4 | 63 / -10 | 60 / -18 | 54 / -30 | 66 / -6 | 64 / -9 |
| Compare c4 | 58 / -31 | 58 / -29 | 56 / -30 | 56 / -34 | 51 / -49 |
| Abs a3 | 61 / -14 | 53 / -42 | 42 / -53 | 32 / -104 | 28 / -111 |
| Barrel Shift bs3 | 56 / -34 | 57 / -32 | 58 / -32 | 53 / -47 | 55 / -44 |
| FP Compare g3 | 67 / **+4** | 66 / -1 | 67 / **0** | 64 / -8 | 68 / **+4** |
| FP Min/Max m3 | 61 / -15 | 62 / -13 | 57 / -26 | 59 / -25 | 64 / -5 |
| Rounding g3 | 10 / -167 | 28 / -109 | 22 / -126 | 37 / -87 | not comparable |
| Mult k64_32_16 vs DW bank | 16 / -166 | 29 / -118 | 3 / -192 | not comparable | not comparable |
| FP64 -> 2xFP32 | 53 / +5 | 50 / +2 | 43 / -12 | 54 / +6 | 54 / +8 |
| FP32 -> 2xFP16 | 48 / -1 | 51 / +5 | 39 / -18 | 48 / -1 | 48 / +1 |
| AddSub+MinMax d4, Min/Max function | 44 / -19 | 16 / -110 | 2 / -119 | -21 / -258 | -53 / -370 |

### Overhead of each added lane format, by target (`mode_left_overhead.csv`)

Area overhead at 100 MHz / 500 MHz / 1 GHz / 1.5 GHz / 2 GHz, and the median over the comparable
targets (area, and PrimePower power of the widest-format operation):

| Step | Area by target | Median area | Median PrimePower |
|---|---|---:|---:|
| AddSub d1 -> d2 | -7.5 / +1.1 / -1.9 / +22.8 / +9.2 | +1.1% | +19.4% |
| AddSub d2 -> d4 | -3.3 / +8.5 / +3.3 / -7.4 / +10.8 | +3.3% | +3.8% |
| AddSub d4 -> d8 | +2.2 / +4.7 / +28.1 / +7.5 / +8.6 | +7.5% | +7.8% |
| MinMax m1 -> m2 | +5.5 / +4.0 / -4.4 / +17.4 / +8.8 | +5.5% | -1.0% |
| MinMax m2 -> m4 | +10.3 / +7.7 / +5.0 / -0.5 / +12.3 | +7.7% | +10.1% |
| Compare c1 -> c2 | +6.1 / +7.1 / +5.9 / +5.7 / +9.8 | +6.1% | +2.0% |
| Compare c2 -> c4 | +38.5 / +38.2 / +54.1 / +77.2 / +79.3 | +54.1% | +38.1% |
| Compare c4 -> c8 | -0.4 / -0.7 / +1.7 / +4.5 / +4.6 | +1.7% | +0.5% |
| Abs a1 -> a2 | +0.3 / +1.8 / +17.0 / +5.4 / +0.8 | +1.8% | +37.0% |
| Abs a2 -> a3 | +3.2 / -4.6 / -2.4 / +8.7 / +14.5 | +3.2% | +16.8% |
| Barrel bs1 -> bs2 | +3.4 / +4.5 / +5.2 / +2.6 / -6.0 | +3.4% | +2.7% |
| Barrel bs2 -> bs3 | +9.9 / +15.9 / +11.2 / +13.3 / +21.7 | +13.3% | +3.1% |
| FP Compare g1 -> g2 | +7.5 / +7.0 / +4.5 / +4.3 / +6.8 | +6.8% | -1.0% |
| FP Compare g2 -> g3 | +14.8 / +16.6 / +15.2 / +17.8 / +20.8 | +16.6% | +9.1% |
| FP Min/Max m1 -> m2 | +9.3 / +13.6 / +0.1 / +4.4 / +8.9 | +8.9% | -1.0% |
| FP Min/Max m2 -> m3 | +23.1 / +8.9 / +29.8 / +37.3 / +22.6 | +23.1% | +9.7% |
| FP Min/Max (W=32) m1 -> m2 | +20.7 / +17.5 / +15.1 / +15.9 / +10.3 | +15.9% | +0.4% |
| Rounding g1 -> g2 | +58.0 / +32.4 / +62.0 / +23.7 / +33.5* | +45.2% | +45.9% |
| Rounding g2 -> g3 | +34.5 / +12.3 / +12.7 / +26.6 / +12.2* | +19.7% | +30.6% |
| Mult k64 -> k64_32 | -8.1 / -6.6 / -27.3 / -12.8* / -19.2* | -8.1% | +4.4% |
| Mult k64_32 -> k64_32_16 | +10.5 / +6.0 / +47.7 / +17.3* / +17.8* | +10.5% | +2.1% |
| AddSub+MinMax d1 -> d2 | -4.1 / +7.3 / +9.8 / +4.6 / +10.9 | +7.3% | +6.9% |
| AddSub+MinMax d2 -> d4 | +2.8 / +6.8 / +19.0 / +3.3 / +13.2 | +6.8% | +3.6% |
| AddSub+MinMax d4 -> d8 | +7.3 / +4.3 / -3.1 / +30.2 / +38.5 | +7.3% | +3.8% |

### Findings

1. **Savings are largest at relaxed targets and fall as the target tightens for most integer
   families** (Compare c4 59 -> 33% area, Barrel 57 -> 42%, Abs 61 -> 49%, AddSub static 68 ->
   49%). At a relaxed target every unit is close to its minimum-area form. Under a tight target the
   decomposable unit's longest path, which runs through the lane-boundary muxes and selects, needs
   more upsizing than the short paths of the narrow fixed units. The FP units are the exception: the
   sliced tree is shallow, and their savings stay at 53-64% across the whole range.
2. **The multiplier crosses over.** Against the DesignWare bank the decomposable multiplier saves
   35% area at 100 MHz and 29% at 500 MHz, and loses from 1 GHz. The Karatsuba tiers nearly double
   between 500 MHz and 1 GHz (k64 2691 -> 4848 um2) while the DesignWare 64-bit unit grows 6%
   (2142 -> 2281 um2): the Karatsuba chain (pre-adder, multiply, subtract, add) is too deep for
   1 GHz without heavy upsizing. At 100 MHz k64 is only 14% larger than the DesignWare unit
   (2280 vs 2002 um2). So "Karatsuba is twice DesignWare" is a timing effect at 1 GHz and above,
   not an intrinsic property, and the decomposable multiplier is worth it at low frequency.
3. **Min/Max as an AddSub side function pays only at 100 MHz.** There the side-function units save
   7-12% area and, in Min/Max mode, 34-44% power against a separate pair whose units both switch.
   From 500 MHz the serial subtract-then-select path costs more than the shared carry chain saves,
   and the penalty grows with frequency (-9% at 500 MHz to -93% at 2 GHz for d4).
4. **Compare's c2 -> c4 step is structural.** It costs +38% even at 100 MHz, where timing plays no
   role, while c4 -> c8 is about free at every target. This rules out the timing explanation for
   anomaly C2; the extra logic is in how the 4x16 lanes split the compare chains, and it needs a
   look at the per-block netlist.
5. **The AddSub fixed 32x2 anomaly (B1) is timing-driven.** The DesignWare duplex adder is the size
   of the fixed 64-bit unit at 100 and 500 MHz (112.7 um2) and jumps to 263 um2 at 1 GHz. This is
   also why AddSub's savings dip at 500 MHz (58% area, 35% power against the all-active bank): its
   bank is small there.
6. **Rounding's overhead is structural:** g1 -> g2 costs +24 to +62% at every target, from the
   per-format lane decoders.
7. **FP Compare breaks even with a gated DesignWare bank at every target** (-8 to +4%), and both
   single splits of the two-level experiment break even or win against a gated bank at every target
   except 1 GHz (+2 to +8% for FP64 -> 2xFP32, -1 to +5% for FP32 -> 2xFP16).
8. **Single-compile noise is visible across the sweep.** The same step moves by 10-30 points between
   neighbouring targets (AddSub d1 -> d2: -7.5 to +22.8%), and some 1 GHz points stand out from
   their neighbours (MinMax m1, the two-level splits against the gated bank). Read trends across the
   five targets, or the median, rather than any single point.
9. **Leakage is negligible at every target.** Even at 100 MHz it is at most 0.05% of the PrimePower
   total for every top-tier unit (SAED14 RVT, TT, 25 C). Static savings matter for area-driven cost
   and for idle units, not for active power at these corners.
10. **Energy per operation is not monotonic in frequency.** AddSub d4 uses 0.92 pJ at 100 MHz and
    1.80 pJ at 2 GHz, as faster and larger cells switch more capacitance. The minimum-area 100 MHz
    multiplier and barrel shifter use more energy per operation than at 1 GHz (49.5 vs 38.8 pJ and
    4.38 vs 3.50 pJ), consistent with glitching along long unbalanced paths in area-minimized logic.

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
4. Building Min/Max as a side function of the AddSub carry chain costs more area and power than
   separate AddSub and Min/Max units at every tier and both corners; the serial
   subtract-then-select path is the cause.
5. In the FP min/max two-level experiment both single splits save 38-52% area; with simulated
   activity they save 39-54% power against an all-active bank, and break even with a gated
   DesignWare bank at 2 GHz.
6. Across 100 MHz to 2 GHz, decomposition saves the most at relaxed targets; the integer families
   lose 4-26 points of area saving by 2 GHz while the FP units hold at 53-64%. The decomposable
   multiplier beats a DesignWare bank at 100 and 500 MHz, and the AddSub side function pays only
   at 100 MHz, so the target frequency decides whether these two designs are worth building.
