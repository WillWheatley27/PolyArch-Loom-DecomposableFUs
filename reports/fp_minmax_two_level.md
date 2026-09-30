# FP Min/Max Two-Level Decomposition Experiment

## Question

Does one decomposition step still pay off when the unit being split is already narrow?
The capability ladders always start from 64 bits. This experiment splits two widths once
each and compares every split with the fixed bank that covers the same formats:

| Split | Decomposable unit | Fixed bank | No-split control |
|---|---|---|---|
| FP64 -> 2xFP32 | `fu_fp_min_max_m2` (sliced core, W=64) | `fu_fp_min_max_64` + `fu_fp_min_max_32x2` | `fu_fp_min_max_m1` (W=64, FP64 only) |
| FP32 -> 2xFP16 | `fu_fp_minmax_revised_32_16` (sliced core, W=32) | `fu_fp_min_max_32` + `fu_fp_min_max_16x2` | sliced core with W=32, MIN_LANE_W=32 (FP32 only) |

Both decomposable units are the same RTL (`rtl/fu_fp_min_max_gen.sv`, one lane evaluator per
slice) with the same 1-bit mode port, so width is the only variable. The fixed units are
DesignWare `DW_fp_cmp` wrappers; all eight designs pass self-checking testbenches. The
no-split control separates the cost of the split itself from the difference between the
hand-written core and DesignWare.

## Method

- Synopsys DC Y-2026.03-SP1, SAED14nm RVT TT/0.8 V/25 C, uniform synthetic activity.
- Primary: fixed 1.000 ns and 0.500 ns targets with `compile_ultra -area_high_effort_script
  -no_autoungroup`. Every design meets both targets, so these are equal-frequency
  comparisons and energy/op savings equal power savings.
- Three configurations per fixed-frequency corner: canonical job order, reversed order, and
  a fresh session per design. The canonical run reproduces bit-for-bit when repeated; 2 GHz
  results are identical across configurations; at 1 GHz individual designs vary by up to 3.9%
  in area (the DesignWare FP64 unit) and the savings by at most 1.5 points.
- Secondary: the 0.010 ns stress corner (`compile_ultra -no_autoungroup`, canonical only),
  where designs trade area for speed and no design meets the target.
- Script `synth/syn_fp_minmax_two_level.tcl`; data and generated tables in
  `fp_minmax_two_level/` (`ppa.csv`, `savings.csv`, `model.csv`, `comparison.md`), produced
  by `collect_fp_minmax_two_level.py`.

## Results at fixed frequency

| Split | Corner | Area saving | Power saving | Leakage saving |
|---|---|---:|---:|---:|
| FP64 -> 2xFP32 | 1 GHz | 49.1..50.5% | 44.2..44.5% | 50.9..53.6% |
| FP64 -> 2xFP32 | 2 GHz | 49.2% | 47.6% | 47.8% |
| FP32 -> 2xFP16 | 1 GHz | 35.2..36.1% | 38.2..39.0% | 15.5..19.6% |
| FP32 -> 2xFP16 | 2 GHz | 45.5% | 43.1% | 44.8% |

Ranges are over the three configurations. Both splits pay off at both frequencies.

## Why the savings differ

With W the wide scalar unit, N the packed narrow unit, and D the decomposable unit, the
saving is `1 - D/(W + N) = 1 - (1 + ovh)/(1 + r)`, where `r = N/W` and `ovh = D/W - 1`.

- r is close to 1 for both widths (0.76 to 1.11): two narrow lanes cost about as much as
  one wide lane. A single split therefore saves at most about 50%, and every point of
  overhead costs about half a point of saving.
- The no-split control splits ovh into two parts:

| Split | Corner | Split cost (D vs control) | Control vs DesignWare wide unit |
|---|---|---:|---:|
| FP64 -> 2xFP32 | 1 GHz | +12.9..+14.7% | -15.9..-13.2% |
| FP64 -> 2xFP32 | 2 GHz | +15.7% | -7.5% |
| FP32 -> 2xFP16 | 1 GHz | +11.6..+13.3% | +6.3..+7.7% |
| FP32 -> 2xFP16 | 2 GHz | +23.7% | -22.3% |

At 1 GHz the split costs the same fraction of the unit at both widths (about 12-15% area).
The lower FP32 -> 2xFP16 saving at 1 GHz comes from the baseline: the DesignWare FP32 compare
is 6-8% smaller than the hand-written FP32 core, while the DesignWare FP64 compare is 13-16%
larger than the hand-written FP64 core. At 2 GHz the narrow split costs relatively more
(+23.7% versus +15.7%), because part of the split logic does not shrink with width (the mode
network and the per-slice selects are upsized to meet timing on a smaller unit), but the
DesignWare FP32 unit grows even more under the tighter target, so the savings converge
(45.5% versus 49.2%).

## Conclusion

A narrow split pays off: an FP32 unit that also runs as 2xFP16 saves 35-45% area and 38-43%
power against a fixed FP32 + packed FP16x2 bank at equal frequency, against 49-50% area and
44-48% power for FP64 -> 2xFP32. The cost of adding the split is about 12-15% of the unit at
relaxed timing regardless of width, and rises for the narrower unit under tight timing. The
remaining difference between the two splits is set by how efficient the fixed baseline is at
each width, not by decomposition.

The earlier version of this experiment (commit 715d543) concluded that the narrow split saved
little (19% area, 6.5% more power, 31% worse energy/op). That came from a non-decomposable
FP32 / 2xFP16 unit (a separate FP32 comparator, two FP16 comparators, and a mux) measured only
at the stress corner. At the stress corner the sliced unit now saves 32% area and 40%
energy/op and exceeds the bank's peak frequency (6.35 versus 5.82 GHz).

## Limitations

- The banks are DesignWare-based. A bank of hand-written fixed units would change the
  savings, and the control shows the style gap changes sign between widths and corners.
- Power is uniform synthetic activity, pre-layout.
- The FP32 -> 2xFP16 leakage saving at 1 GHz (15-20%) is low because the hand-written FP32
  core leaks 21-27% more than the DesignWare FP32 unit at that corner.
