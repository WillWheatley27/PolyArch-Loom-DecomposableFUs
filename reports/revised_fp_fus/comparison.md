# Revised FP compare/min/max PPA

Synopsys DC Y-2026.03-SP1, SAED14nm RVT TT/0.8 V/25 C, identical compile settings and uniform synthetic activity (static probability 0.5, toggle rate 0.2). Area is total cell area; power is dynamic power; energy/op is dynamic power/Fmax.

The revised wrappers elaborate only the advertised capability. `rev64` is FP64-only, `rev64_32` adds 2xFP32, and `rev64_32_16` adds 4xFP16. Reserved modes fall back to FP64.

## PPA and savings

| FU | Corner | Area (um2) | Power (mW) | Leakage (uW) | Fmax (GHz) | Bank area | Area saving | Power saving | Leakage saving | Valid |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| fp_cmp_rev64 | one_ghz | 178.710 | 0.641242 | 0.074319 | 1.001056 | 111.133 | -60.81% | -178.29% | -93.41% | true |
| fp_cmp_rev64 | two_ghz | 243.623 | 0.488646 | 0.114743 | 2.001053 | 153.402 | -58.81% | -55.83% | -103.35% | true |
| fp_cmp_rev64_32 | one_ghz | 214.452 | 0.562704 | 0.091014 | 1.000173 | 233.189 | 8.04% | -16.50% | -19.68% | true |
| fp_cmp_rev64_32 | two_ghz | 338.905 | 0.622736 | 0.186544 | 2.000652 | 309.956 | -9.34% | -4.89% | -62.06% | true |
| fp_cmp_rev64_32_16 | one_ghz | 279.365 | 0.746590 | 0.126002 | 1.000622 | 342.502 | 18.43% | -2.12% | -14.63% | true |
| fp_cmp_rev64_32_16 | two_ghz | 459.407 | 0.813777 | 0.261345 | 2.000344 | 449.150 | -2.28% | 7.31% | -53.80% | true |
| fp_minmax_rev64 | one_ghz | 116.772 | 0.327904 | 0.037837 | 1.001512 | 133.644 | 12.62% | 7.49% | 24.50% | true |
| fp_minmax_rev64 | two_ghz | 147.985 | 0.338439 | 0.063124 | 2.003968 | 159.929 | 7.47% | 7.56% | 8.31% | true |
| fp_minmax_rev64_32 | one_ghz | 137.329 | 0.368360 | 0.052769 | 1.001386 | 261.516 | 47.49% | 45.91% | 44.25% | true |
| fp_minmax_rev64_32 | two_ghz | 170.008 | 0.380035 | 0.075092 | 2.002247 | 336.685 | 49.51% | 48.45% | 48.66% | true |
| fp_minmax_rev64_32_16 | one_ghz | 163.570 | 0.427995 | 0.059992 | 1.001070 | 368.254 | 55.58% | 56.00% | 52.04% | true |
| fp_minmax_rev64_32_16 | two_ghz | 215.651 | 0.467891 | 0.097747 | 2.001653 | 472.682 | 54.38% | 56.02% | 52.43% | true |

## Marginal capability overhead

| FU | Corner | Added capability | Area overhead | Power overhead | Leakage overhead | Fmax change |
|---|---|---|---:|---:|---:|---:|
| fp_cmp_rev64_32 | one_ghz | rev64 -> rev64_32 | 20.00% | -12.25% | 22.46% | -0.09% |
| fp_cmp_rev64_32_16 | one_ghz | rev64_32 -> rev64_32_16 | 30.27% | 32.68% | 38.44% | 0.04% |
| fp_cmp_rev64_32 | two_ghz | rev64 -> rev64_32 | 39.11% | 27.44% | 62.58% | -0.02% |
| fp_cmp_rev64_32_16 | two_ghz | rev64_32 -> rev64_32_16 | 35.56% | 30.68% | 40.10% | -0.02% |
| fp_minmax_rev64_32 | one_ghz | rev64 -> rev64_32 | 17.60% | 12.34% | 39.46% | -0.01% |
| fp_minmax_rev64_32_16 | one_ghz | rev64_32 -> rev64_32_16 | 19.11% | 16.19% | 13.69% | -0.03% |
| fp_minmax_rev64_32 | two_ghz | rev64 -> rev64_32 | 14.88% | 12.29% | 18.96% | -0.09% |
| fp_minmax_rev64_32_16 | two_ghz | rev64_32 -> rev64_32_16 | 26.85% | 23.12% | 30.17% | -0.03% |

Negative savings are penalties. These are pre-layout synthetic DC estimates, not workload-based power claims. Raw reports are under `raw/`; CSV data are in `ppa.csv`, `savings.csv`, and `marginal.csv`.
