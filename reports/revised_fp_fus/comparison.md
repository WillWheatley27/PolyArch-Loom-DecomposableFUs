# Revised FP compare/min/max PPA

Synopsys DC Y-2026.03-SP1, SAED14nm RVT TT/0.8 V/25 C, identical compile settings and uniform synthetic activity (static probability 0.5, toggle rate 0.2). Area is total cell area; power is dynamic power; energy/op is dynamic power/Fmax.

The revised wrappers elaborate only the advertised capability. `rev64` is FP64-only, `rev64_32` adds 2xFP32, and `rev64_32_16` adds 4xFP16. Reserved modes fall back to FP64.

## PPA and savings

| FU | Corner | Area (um2) | Power (mW) | Leakage (uW) | Fmax (GHz) | Bank area | Area saving | Power saving | Leakage saving | Valid |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| fp_cmp_rev64 | one_ghz | 105.139 | 0.222308 | 0.031126 | 1.000030 | 111.133 | 5.39% | 3.52% | 19.00% | true |
| fp_cmp_rev64 | two_ghz | 129.515 | 0.244003 | 0.054254 | 2.001581 | 153.402 | 15.57% | 22.19% | 3.85% | true |
| fp_cmp_rev64_32 | one_ghz | 108.558 | 0.226641 | 0.029477 | 1.000484 | 233.189 | 53.45% | 53.08% | 61.24% | true |
| fp_cmp_rev64_32 | two_ghz | 137.951 | 0.250198 | 0.050657 | 2.000112 | 309.956 | 55.49% | 57.86% | 55.99% | true |
| fp_cmp_rev64_32_16 | one_ghz | 124.586 | 0.274507 | 0.038685 | 1.000051 | 342.502 | 63.62% | 62.45% | 64.81% | true |
| fp_cmp_rev64_32_16 | two_ghz | 161.394 | 0.294370 | 0.061669 | 2.000108 | 449.150 | 64.07% | 66.47% | 63.71% | true |
| fp_minmax_rev64 | one_ghz | 116.772 | 0.327904 | 0.037837 | 1.001512 | 133.644 | 12.62% | 7.49% | 24.50% | true |
| fp_minmax_rev64 | two_ghz | 147.985 | 0.338439 | 0.063124 | 2.003968 | 159.929 | 7.47% | 7.56% | 8.31% | true |
| fp_minmax_rev64_32 | one_ghz | 132.179 | 0.374005 | 0.048227 | 1.000258 | 261.516 | 49.46% | 45.08% | 49.04% | true |
| fp_minmax_rev64_32 | two_ghz | 191.231 | 0.425269 | 0.087496 | 2.000800 | 336.685 | 43.20% | 42.31% | 40.18% | true |
| fp_minmax_rev64_32_16 | one_ghz | 161.039 | 0.427467 | 0.063666 | 1.000595 | 368.254 | 56.27% | 56.05% | 49.10% | true |
| fp_minmax_rev64_32_16 | two_ghz | 201.754 | 0.422023 | 0.095383 | 2.000392 | 472.682 | 57.32% | 60.33% | 53.58% | true |

## Marginal capability overhead

| FU | Corner | Added capability | Area overhead | Power overhead | Leakage overhead | Fmax change |
|---|---|---|---:|---:|---:|---:|
| fp_cmp_rev64_32 | one_ghz | rev64 -> rev64_32 | 3.25% | 1.95% | -5.30% | 0.05% |
| fp_cmp_rev64_32_16 | one_ghz | rev64_32 -> rev64_32_16 | 14.76% | 21.12% | 31.24% | -0.04% |
| fp_cmp_rev64_32 | two_ghz | rev64 -> rev64_32 | 6.51% | 2.54% | -6.63% | -0.07% |
| fp_cmp_rev64_32_16 | two_ghz | rev64_32 -> rev64_32_16 | 16.99% | 17.65% | 21.74% | -0.00% |
| fp_minmax_rev64_32 | one_ghz | rev64 -> rev64_32 | 13.19% | 14.06% | 27.46% | -0.13% |
| fp_minmax_rev64_32_16 | one_ghz | rev64_32 -> rev64_32_16 | 21.83% | 14.29% | 32.01% | 0.03% |
| fp_minmax_rev64_32 | two_ghz | rev64 -> rev64_32 | 29.22% | 25.66% | 38.61% | -0.16% |
| fp_minmax_rev64_32_16 | two_ghz | rev64_32 -> rev64_32_16 | 5.50% | -0.76% | 9.01% | -0.02% |

Negative savings are penalties. These are pre-layout synthetic DC estimates, not workload-based power claims. Raw reports are under `raw/`; CSV data are in `ppa.csv`, `savings.csv`, and `marginal.csv`.
