# FP Min/Max Two-Level Decomposition Experiment

## Question

Does one decomposition step still pay off when the unit being split is already narrow?
The capability ladders always start from 64 bits. This experiment splits two widths once
each and compares every split with the fixed bank that covers the same formats:

| Split | Decomposable unit | Fixed bank | Wide-only tier (same RTL) |
|---|---|---|---|
| FP64 -> 2xFP32 | `fu_fp_min_max_m2` (sliced core, W=64) | `fu_fp_min_max_64` + `fu_fp_min_max_32x2` | `fu_fp_min_max_m1` (W=64, FP64 only) |
| FP32 -> 2xFP16 | `fu_fp_minmax_revised_32_16` (sliced core, W=32) | `fu_fp_min_max_32` + `fu_fp_min_max_16x2` | sliced core with W=32, MIN_LANE_W=32 (FP32 only) |

Both decomposable units are the same RTL (`rtl/fu_fp_min_max_gen.sv`, one lane evaluator per
slice) with the same 1-bit mode port, so width is the only variable. The fixed units are
DesignWare `DW_fp_cmp` wrappers; all eight designs pass self-checking testbenches. The
wide-only tier measures the overhead of adding the narrow lanes in the same way as the
capability ladders (`tier_ladders/marginal.csv`).

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

## Overhead of adding the narrow lanes

Overhead is measured from the wide-only tier of the same core to the decomposable unit,
the metric used for the capability ladders. The FP64 -> 2xFP32 unit is the 64-bit
ladder's m1 -> m2 step (same designs, same result), so the table lines both experiments
up against the ladder:

| Step | Corner | Area | Power | Leakage |
|---|---|---:|---:|---:|
| FP64 -> +2xFP32 (ladder m1 -> m2) | 1 GHz | +12.9..+14.7% | +13.8..+15.3% | +8.0..+17.0% |
| FP32 -> +2xFP16 | 1 GHz | +11.6..+13.3% | +5.9..+20.4% | +14.7..+20.4% |
| FP64/32 -> +4xFP16 (ladder m2 -> m3) | 1 GHz | +18.4..+20.9% | +11.8..+12.5% | +38.0..+44.9% |
| FP64 -> +2xFP32 (ladder m1 -> m2) | 2 GHz | +15.7% | +14.2% | +20.9% |
| FP32 -> +2xFP16 | 2 GHz | +23.7% | +14.4% | +36.0% |
| FP64/32 -> +4xFP16 (ladder m2 -> m3) | 2 GHz | +17.8% | +9.2% | +25.0% |

Ranges are over the three configurations; Fmax changes by at most 0.2% in every step.

- At 1 GHz, adding one level of narrow lanes costs the same fraction of the unit at both
  widths: about 13% area (+15 to +17 um2 on the 64-bit unit, +8 to +9 um2 on the 32-bit
  unit). Power overhead is about 14% for the 64-bit unit; the 32-bit unit's power overhead
  varies between 6% and 20% across configurations, so it is not resolved at this corner.
- At 2 GHz, the overhead rises for the narrow unit (+23.7% area versus +15.7%) while power
  overhead stays equal (about 14%). The 32-bit wide-only tier has timing slack at 2 GHz
  (it grows only from 67.4 to 68.1 um2 between the corners), and adding the narrow lanes
  places the level selects and evaluator input mux on its critical path, so they are
  upsized; the 64-bit wide-only tier is already timing-limited.
- The 64-bit ladder's second step (+4xFP16) costs +18..21% area at 1 GHz, more than
  either single split, because it adds two lanes' worth of evaluators, fp16 exponent
  detectors, and a third select input on every slice.

## Why the savings differ

With W the wide DesignWare unit, N the packed narrow DesignWare unit, and D the decomposable
unit, the saving is `1 - D/(W + N) = 1 - (1 + ovh)/(1 + r)`, where `r = N/W` and
`ovh = D/W - 1` is the overhead against the DesignWare wide unit. r is close to 1 for both
widths (0.76 to 1.11), so a single split saves at most about 50% and every point of
overhead against W costs about half a point of saving.

The overhead against W is the overhead of adding the narrow lanes compounded with how the
wide-only tier compares with the DesignWare unit, `1 + ovh = (D/H)(H/W)`:

| Split | Corner | Overhead vs DesignWare wide unit | = adding narrow lanes | x wide-only tier vs DesignWare |
|---|---|---:|---:|---:|
| FP64 -> 2xFP32 | 1 GHz | -5.1..-0.4% | +12.9..+14.7% | -15.9..-13.2% |
| FP32 -> 2xFP16 | 1 GHz | +18.6..+21.1% | +11.6..+13.3% | +6.3..+7.7% |
| FP64 -> 2xFP32 | 2 GHz | +7.1% | +15.7% | -7.5% |
| FP32 -> 2xFP16 | 2 GHz | -3.9% | +23.7% | -22.3% |

At 1 GHz both splits add the same overhead, but the FP64-only tier is 13-16% smaller than
the DesignWare FP64 unit while the FP32-only tier is 6-8% larger than the DesignWare FP32
unit. So the 64-bit decomposable unit is no bigger than the fixed FP64 unit (saving about
50%), and the 32-bit one is about 20% bigger than the fixed FP32 unit (saving about 35%).
At 2 GHz the DesignWare FP32 unit grows under the tighter target and the FP32-only tier is
22% smaller than it, which absorbs the narrow split's higher overhead; the savings
converge (45.5% versus 49.2%).

## Conclusion

A narrow split pays off: an FP32 unit that also runs as 2xFP16 saves 35-45% area and 38-43%
power against a fixed FP32 + packed FP16x2 bank at equal frequency, against 49-50% area and
44-48% power for FP64 -> 2xFP32. The overhead of adding one level of narrow lanes is about
13% area at 1 GHz for both widths and rises to 24% for the 32-bit unit at 2 GHz (16% for the
64-bit unit); power overhead is about 14% wherever it is resolved. The difference between
the two bank savings at 1 GHz is set by how the fixed DesignWare units compare with the
wide-only tiers, not by a difference in overhead.

The earlier version of this experiment (commit 715d543) concluded that the narrow split saved
little (19% area, 6.5% more power, 31% worse energy/op). That came from a non-decomposable
FP32 / 2xFP16 unit (a separate FP32 comparator, two FP16 comparators, and a mux) measured only
at the stress corner. At the stress corner the sliced unit now saves 32% area and 40%
energy/op and exceeds the bank's peak frequency (6.35 versus 5.82 GHz).

## Limitations

- The banks are DesignWare-based. A bank of hand-written fixed units would change the
  savings; how the wide-only tiers compare with DesignWare changes sign between widths
  and corners.
- Power is uniform synthetic activity, pre-layout.
- The FP32 -> 2xFP16 leakage saving at 1 GHz (15-20%) is low because the hand-written FP32
  core leaks 21-27% more than the DesignWare FP32 unit at that corner.
