# FP Min/Max Two-Level Decomposition Speed-Corner Experiment

This experiment compares two separate decomposable min/max structures at the same 0.010 ns maximum-speed stress target:

1. `1xFP64 -> 2xFP32`
2. `1xFP32 -> 2xFP16`

The speed corner is an intentionally aggressive Synopsys Design Compiler target. It measures timing-driven optimized implementations and reports achieved Fmax; it is not an equal-frequency 1 GHz comparison. The library is SAED14nm RVT TT/0.8 V/25 C, with uniform synthetic activity (static probability 0.5, toggle rate 0.2).

## Results

| Experiment | Decomposable area (um2) | Fixed-bank area (um2) | Area saving | Decomposable power (mW) | Fixed-bank power (mW) | Power saving | Decomposable leakage (uW) | Fixed-bank leakage (uW) | Leakage saving | Decomp Fmax (GHz) | Bank Fmax (GHz) | Energy saving | Fmax change |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| FP64 -> FP32x2 | 701.431 | 1264.912 | 44.55% | 1.131500 | 1.443690 | 21.62% | 0.506752 | 1.000123 | 49.33% | 3.558529 | 5.399393 | -18.92% | -34.09% |
| FP32 -> FP16x2 | 587.900 | 728.782 | 19.33% | 0.878770 | 0.824979 | -6.52% | 0.426344 | 0.595335 | 28.39% | 4.726054 | 5.816794 | -31.10% | -18.75% |

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

The FP64->FP32 design saves more area and power than the FP32->FP16 design because its fixed baseline includes a substantially larger FP64 component. Both decomposable designs lose peak speed at this stress target. The FP32->FP16 case has a dynamic-power and energy penalty despite area/leakage savings, so it should not be described as a universal PPA win.
