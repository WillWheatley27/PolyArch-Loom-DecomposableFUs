# PPA Rerun: Verification Against the Original Data

Every capability tier and fixed-bank component of the nine decomposable FU families (AddSub,
MinMax, Compare, Abs, Barrel shift, FP Compare, FP MinMax, Rounding, Karatsuba Mult) was
synthesized again on SAED14nm to check the original data for errors and anomalies:
57 designs, 1.000 ns and 0.500 ns targets, the same flow as the original runs
(`compile_ultra -area_high_effort_script -no_autoungroup`, SAED14nm RVT TT/0.8 V/25 C,
uniform synthetic activity), and every design in its own fresh `dc_shell` session. All
designs pass their self-checking testbenches first (`./run.sh all` and every standalone
group).

- Data: `PPA_rerun.csv` (area, static leakage power, dynamic power split into internal and
  switching, with the original values and the change), `rerun_overhead.csv`,
  `rerun_savings.csv`; raw reports in `rerun/raw/`.
- Reproduce: `synth/syn_rerun.tcl` (one `JOB_FILTER` per design), then
  `collect_rerun.py`.
- Power: static power is the cell leakage power; dynamic power is internal plus switching
  power under the uniform synthetic activity (no workload trace). Static power is listed
  first throughout. It is three to four orders of magnitude smaller than dynamic power in
  this library and corner.

## 1. Does the rerun reproduce the original data?

| Corner | Designs | Identical to original | Area mean / max abs change | Static power mean / max | Dynamic power mean / max |
|---|---:|---:|---:|---:|---:|
| 1 GHz | 54 | 6 | 2.4% / 11.1% | 5.9% / 34.5% | 4.9% / 33.8% |
| 2 GHz | 53 | 53 | 0.0% / 0.0% | 0.0% / 0.0% | 0.0% / 0.0% |

"Identical" means the same area, static power, and dynamic power to every printed digit.

- 2 GHz reproduces exactly for every design. The data is correct.
- 1 GHz differs by 2.4% in area on average (up to 11.1%) and by 5.9% in static power (up to
  34.5%). The cause is the synthesis session, not the designs: at the relaxed 1 GHz target,
  Design Compiler's area-recovery result depends on what was compiled earlier in the same
  session. The original runs compiled many designs back to back in one session; the rerun
  gives each design a fresh session. Evidence:
  - The same design has different values in different original runs at 1 GHz, for example
    `fu_mult_decomp` at 4982.7 um2 (`ppa_summary.csv`) and 5207.0 um2
    (`mult_karatsuba_ppa.csv`), and the rerun reproduces one of them exactly (5207.0).
  - Designs whose RTL has not changed since the original run still move at 1 GHz, for example
    the fixed Compare 32x2 unit by 11.1% and the Barrel shift bs1 tier by 6.0%.
  - Two RTL files had cosmetic edits after the original runs (Rounding: an unused carry;
    Abs: a mask width). Synthesizing the pre-edit RTL in a fresh session gives exactly the
    same area as the current RTL (Abs a2 156.110402, Rounding g1 658.318799, Rounding g3
    1136.995196 um2), so the edits have no effect and the 1 GHz differences are the session.
- Static power moves most at 1 GHz because it follows the cell mix that area recovery picks,
  and the absolute values are tens of nanowatts, so small changes are large percentages.

## 2. Savings against the fixed banks

Rerun value, original in parentheses. The AddSub and Compare banks use the standalone 64-bit
units (`fu_add_sub_64`, `fu_cmp_64`), as the original `synth_common_fixed` data did after its
refresh; the Abs, Barrel shift, and Rounding banks use the wide-only tier as their 64-bit unit,
as in the original.

| FU | Unit vs bank | Corner | Area saving (orig) | Static saving (orig) | Dynamic saving (orig) | Timing met |
|---|---|---|---:|---:|---:|:---:|
| addsub | addsub_d4 vs 64 + 32x2 + 16x4 | 1 GHz | 66.3% (65.7) | 62.0% (60.6) | 68.0% (67.3) | yes |
| addsub | addsub_d4 vs 64 + 32x2 + 16x4 | 2 GHz | 59.9% (59.0) | 48.6% (45.5) | 68.4% (67.9) | yes |
| addsub | addsub_d8 vs 64 + 32x2 + 16x4 + 8x8 | 1 GHz | 63.8% (n/a) | 48.3% (n/a) | 71.3% (n/a) | yes |
| addsub | addsub_d8 vs 64 + 32x2 + 16x4 + 8x8 | 2 GHz | 62.3% (n/a) | 48.9% (n/a) | 70.2% (n/a) | yes |
| minmax | minmax_m4 vs 64 + 32x2 + 16x4 | 1 GHz | 64.7% (64.4) | 66.2% (65.9) | 55.5% (55.1) | yes |
| minmax | minmax_m4 vs 64 + 32x2 + 16x4 | 2 GHz | 58.4% (58.4) | 53.6% (53.6) | 60.3% (60.3) | yes |
| cmp | cmp_c4 vs 64 + 32x2 + 16x4 | 1 GHz | 54.9% (53.6) | 44.3% (42.5) | 62.6% (56.8) | yes |
| cmp | cmp_c4 vs 64 + 32x2 + 16x4 | 2 GHz | 35.4% (35.4) | 21.2% (21.2) | 54.6% (54.6) | yes |
| cmp | cmp_c8 vs 64 + 32x2 + 16x4 + 8x8 | 1 GHz | 65.0% (n/a) | 53.6% (n/a) | 70.1% (n/a) | yes |
| cmp | cmp_c8 vs 64 + 32x2 + 16x4 + 8x8 | 2 GHz | 48.4% (n/a) | 34.0% (n/a) | 64.2% (n/a) | yes |
| abs | abs_a3 vs a1 + 32x2 + 16x4 | 1 GHz | 51.7% (52.9) | 46.0% (46.3) | 53.5% (55.4) | yes |
| abs | abs_a3 vs a1 + 32x2 + 16x4 | 2 GHz | 49.2% (49.2) | 36.1% (36.1) | 39.5% (39.5) | yes |
| barrel | barrel_bs3 vs bs1 + 32x2 + 16x4 | 1 GHz | 50.8% (48.5) | 46.3% (43.3) | 52.5% (52.0) | yes |
| barrel | barrel_bs3 vs bs1 + 32x2 + 16x4 | 2 GHz | 40.1% (40.1) | 34.8% (34.8) | 48.5% (48.5) | yes |
| fp_cmp | fp_cmp_g3 vs DW FP64 + FP32x2 + FP16x4 | 1 GHz | 63.7% (63.7) | 63.4% (64.3) | 63.9% (61.5) | yes |
| fp_cmp | fp_cmp_g3 vs DW FP64 + FP32x2 + FP16x4 | 2 GHz | 64.1% (64.1) | 63.7% (63.7) | 66.5% (66.5) | yes |
| fp_minmax | fp_minmax_m3 vs DW FP64 + FP32x2 + FP16x4 | 1 GHz | 57.7% (57.2) | 49.6% (51.1) | 56.4% (56.3) | yes |
| fp_minmax | fp_minmax_m3 vs DW FP64 + FP32x2 + FP16x4 | 2 GHz | 57.3% (57.3) | 53.6% (53.6) | 60.3% (60.3) | yes |
| rounding | rounding_g3 vs g1 + FP32x2 + FP16x4 | 1 GHz | 18.1% (6.2) | 10.9% (-7.5) | 30.3% (11.8) | yes |
| rounding | rounding_g3 vs g1 + FP32x2 + FP16x4 | 2 GHz | 18.3% (n/a) | 13.5% (n/a) | 28.1% (n/a) | no |
| mult | mult_k64_32_16 vs DW 64 + 32x2 + 16x4 | 1 GHz | -26.9% (-23.7) | -78.3% (-76.2) | -28.2% (-37.5) | yes |
| mult | mult_k64_32_16 vs DW 64 + 32x2 + 16x4 | 2 GHz | 14.8% (n/a) | 15.3% (n/a) | -10.4% (n/a) | no |
| mult | mult_k64_32_16 vs Karatsuba 64 + 32x2 + 16x4 | 1 GHz | 28.0% (27.0) | 21.2% (19.5) | 24.5% (25.4) | yes |
| mult | mult_k64_32_16 vs Karatsuba 64 + 32x2 + 16x4 | 2 GHz | 43.1% (n/a) | 43.7% (n/a) | 37.5% (n/a) | no |
| mult | mult_k64_32 vs DW 64 + 32x2 | 1 GHz | -0.5% (-2.8) | -18.7% (-25.7) | 6.3% (-2.7) | yes |
| mult | mult_k64_32 vs DW 64 + 32x2 | 2 GHz | 14.6% (14.6) | 14.1% (14.1) | -2.5% (-2.5) | no |
| mult | mult_k64_32 vs Karatsuba 64 + 32x2 | 1 GHz | 46.9% (46.0) | 51.7% (50.5) | 47.3% (48.0) | yes |
| mult | mult_k64_32 vs Karatsuba 64 + 32x2 | 2 GHz | 45.5% (45.5) | 44.8% (44.8) | 45.6% (45.6) | no |

- Area savings reproduce within about 3 points everywhere except Rounding at 1 GHz, and
  exactly at 2 GHz except AddSub (+0.9 points). Static-power savings reproduce within about
  3 points except Rounding at 1 GHz (+18.4), Karatsuba 64/32 versus the DesignWare bank at
  1 GHz (+7.0), and the FP MinMax FP64-only tier versus DesignWare at 1 GHz (-5.0), all from
  the 1 GHz session effect on leakage, and AddSub at 2 GHz (+3.1, the RTL change below). The AddSub original savings were computed from a run on
  8 September, before `rtl/fu_add_sub_gen.sv` was restructured on 11 September (commit
  7e60d16); the rerun uses the current RTL and matches the later AddSub tier data exactly.
- Rounding at 1 GHz: 18.1% versus 6.2% originally (static 10.9% versus -7.5%). Both the
  Rounding g1 bank component (+7.3%) and the g3 unit (-9.5%) moved with the session, and
  Rounding is the family where the unit and the bank are closest in size, so the same noise
  swings its saving the most. Treat its 1 GHz saving as uncertain by about 12 points. At
  2 GHz every Rounding tier misses timing (about 1.8 GHz maximum), as in the original.
- The savings are not near 0%, and should not be. A fixed bank holds three separate datapaths
  (64 + 2x32 + 4x16, each about as large as the others), while the decomposable unit shares
  one datapath plus the logic to split it. With two to three bank components of similar size,
  the saving is roughly 1 - (1 + overhead) / (number of components); a 3-component bank and a
  unit 30-40% larger than one component gives the observed 50-65%.
- Two families differ because of the design, not the data:
  - Rounding saves only 18%: its per-lane rounding control is built separately for each
    format (fp64, 2x fp32, 4x fp16), so its overhead is large (g1 -> g2 +56% area).
  - Karatsuba Mult is 26.9% larger than the DesignWare bank at 1 GHz (and 0.5% at 64/32):
    the Karatsuba 64-bit multiply-low itself is 2.1x the DesignWare 64-bit multiplier
    (next table). Against a bank built from the same Karatsuba units it saves 28.0%
    (64/32/16) and 46.9% (64/32). At 2 GHz the multipliers miss timing, so those savings
    are not equal-frequency comparisons.

## 3. Where near 0% is expected: wide-only tier versus the fixed wide unit

Each family's first tier supports only the wide format, the same capability as the fixed
64-bit unit, so here a result near 0% would be expected if both were built the same way:

| FU | Wide-only tier vs fixed wide unit | Corner | Area saving | Static saving | Dynamic saving |
|---|---|---|---:|---:|---:|
| addsub | addsub_d1 vs standalone 64 | 1 GHz | -4.8% | -10.1% | -8.9% |
| addsub | addsub_d1 vs standalone 64 | 2 GHz | -10.1% | -25.1% | 0.3% |
| minmax | minmax_m1 vs fu_min_max 64 | 1 GHz | -12.9% | -61.2% | -33.4% |
| minmax | minmax_m1 vs fu_min_max 64 | 2 GHz | 11.0% | 10.5% | 6.2% |
| cmp | cmp_c1 vs standalone 64 | 1 GHz | 8.0% | 7.6% | 2.3% |
| cmp | cmp_c1 vs standalone 64 | 2 GHz | 3.9% | 7.8% | 2.5% |
| fp_cmp | fp_cmp_g1 vs DW FP64 | 1 GHz | 5.8% | 19.8% | 4.1% |
| fp_cmp | fp_cmp_g1 vs DW FP64 | 2 GHz | 15.6% | 3.9% | 22.2% |
| fp_minmax | fp_minmax_m1 vs DW FP64 | 1 GHz | 15.9% | 19.5% | 3.8% |
| fp_minmax | fp_minmax_m1 vs DW FP64 | 2 GHz | 7.5% | 8.3% | 7.6% |
| mult | mult_k64 vs DW 64 | 1 GHz | -112.6% | -172.4% | -106.0% |
| mult | mult_k64 vs DW 64 | 2 GHz | -45.7% | -38.8% | -78.7% |

- Compare, FP Compare, and FP MinMax are within about 4-16% in area (the hand-written tier is
  smaller than the fixed unit), and the FP units are smaller than DesignWare's.
- AddSub d1 is 5-10% larger than the standalone 64-bit adder: the tier carries the segmented
  8-block carry chain and mode inputs, tied off but structured for splitting.
- MinMax m1 against `fu_min_max` flips sign between corners (-12.9% at 1 GHz, +11.0% at 2 GHz).
  The monolithic `fu_min_max` changes size non-monotonically with the target
  (`tier_ladders/minmax_area_anomaly.md`), which is a synthesis result for that netlist.
- Karatsuba 64 is 2.1x the DesignWare 64-bit multiplier at 1 GHz: the Karatsuba structure
  (three 32x32 products plus the cross-term additions and subtractions) cannot drop the
  partial products that a multiply-low discards, which the DesignWare multiplier does.
- Abs, Barrel shift, and Rounding have no separate 64-bit standalone; their bank uses the
  wide-only tier itself, so this comparison is 0% by construction.

## 4. Overhead between capability tiers

Change in overhead, rerun minus original, in percentage points:

| FU | 1 GHz: max abs change area / static (pp) | 2 GHz: max abs change area / static (pp) | Negative 1 GHz rerun overheads |
|---|---:|---:|---|
| addsub | 3.3 / 6.0 | 0.0 / 0.0 | d1->d2 -1.9% |
| minmax | 7.4 / 25.3 | 0.0 / 0.0 | m1->m2 -4.4% |
| cmp | 3.0 / 8.0 | 0.0 / 0.0 | - |
| abs | 11.1 / 21.4 | 0.0 / 0.0 | a2->a3 -0.9% |
| barrel | 10.0 / 19.8 | 0.0 / 0.0 | - |
| fp_cmp | 3.1 / 27.1 | 0.0 / 0.0 | - |
| fp_minmax | 1.4 / 6.8 | 0.0 / 0.0 | - |
| rounding | 11.6 / 16.8 | 0.0 / 0.0 | - |
| mult | 6.4 / 9.5 | 0.0 / 0.0 | k64->32 -27.3% |


- 2 GHz overheads reproduce exactly (0.0 points) for every family.
- 1 GHz overheads move by up to 11.6 points in area and 27.1 points in static power. Three
  1 GHz overheads come out negative in the rerun (a tier that adds lanes synthesizing smaller
  than the tier before it), which cannot be structural because each tier contains the
  previous one; they are the same 1 GHz session noise.
- The Mult k64 -> k64_32 overhead is negative at both corners (-27.3% at 1 GHz, as in the
  original) because the first rung is a separate Karatsuba 64-bit design, not a subset of the
  64/32 unit.

## Conclusion

The data is correct: every 2 GHz value reproduces exactly, and no design shows an error. The
1 GHz corner is sensitive to the synthesis session, by about 2.4% in area and 5.9% in static
power on average and up to about 11% in area and 35% in static power for individual designs;
savings and overhead inherit that, most visibly in Rounding. For future reporting, the 2 GHz
numbers are exact, and 1 GHz numbers should come from one flow with a fixed session policy
(this rerun uses a fresh session per design) and be read with that uncertainty. The large
savings against the fixed banks are expected from sharing one datapath; the exceptions are
explained by the Rounding control structure and the Karatsuba algorithm.
