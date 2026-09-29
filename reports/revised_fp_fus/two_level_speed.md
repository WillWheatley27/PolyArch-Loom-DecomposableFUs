# FP Min/Max Two-Level Decomposition Speed-Corner Experiment

This experiment compares two separate decomposable min/max structures at the same 0.010 ns maximum-speed stress target:

1. `1xFP64 -> 2xFP32`
2. `1xFP32 -> 2xFP16`

The speed corner is an intentionally aggressive Synopsys Design Compiler target. It measures timing-driven optimized implementations and reports achieved Fmax; it is not an equal-frequency 1 GHz comparison. The library is SAED14nm RVT TT/0.8 V/25 C, with uniform synthetic activity (static probability 0.5, toggle rate 0.2).

## Results

| Experiment | Decomposable area (um2) | Fixed-bank area (um2) | Area saving | Decomposable power (mW) | Fixed-bank power (mW) | Power saving | Decomposable leakage (uW) | Fixed-bank leakage (uW) | Leakage saving | Decomp Fmax (GHz) | Bank Fmax (GHz) | Energy saving | Fmax change |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| FP64 -> FP32x2 | 700.987 | 1264.912 | 44.58% | 0.797816 | 1.443690 | 44.74% | 0.542438 | 1.000123 | 45.76% | 5.232315 | 5.399393 | 42.97% | -3.09% |
| FP32 -> FP16x2 | 402.175 | 728.782 | 44.82% | 0.450907 | 0.824979 | 45.34% | 0.311217 | 0.595335 | 47.72% | 5.713927 | 5.816794 | 44.36% | -1.77% |

Negative savings are penalties. Energy/op is dynamic power divided by achieved Fmax. The fixed-bank Fmax is the minimum of its component Fmax values.

## Raw sources

The new experiment's raw reports are under `reports/revised_fp_fus/two_level_speed/raw/`:

- `fp_minmax_rev64_32`: new revised FP64/FP32 decomposable synthesis.
- `fp_minmax_rev32_16`: new revised FP32/FP16 decomposable synthesis.
- `fp_minmax_fixed_32`: new scalar FP32 fixed baseline.
- `fp_minmax_fixed_16x2`: new packed FP16x2 fixed baseline.

The FP64 and packed FP32 fixed speed reports were reused from the existing normalized speed flow:

- `reports/synth_maxspeed_fixed/fp_minmax_64/`
- `reports/synth_maxspeed_fixed/fp_minmax_32x2/`

The machine-readable result is `two_level_speed.csv`. Synthesis entry points are `synth/run_fp_minmax_rev64_32_speed.sh` and `synth/run_fp_minmax_two_level_speed.sh`.

## Interpretation

Both decomposable units are the one sliced core of `rtl/fu_fp_min_max_gen.sv`
(`W=64` with 2xFP32 support, and `W=32` with 2xFP16 support). With the sliced
core both experiments save about 45% area, power, leakage, and energy/op against
their fixed banks, and the peak-speed loss shrinks to about 3% (FP64 -> FP32x2)
and 2% (FP32 -> FP16x2). Before the sliced core, the FP32 -> FP16x2 unit had a
power and energy penalty and both units lost 19-34% of peak speed; those rows are
in git history (commit 654b7f8). Regenerate `two_level_speed.csv` with
`collect_two_level_speed.py`.
