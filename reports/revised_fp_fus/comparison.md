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
| fp_minmax_rev64 | one_ghz | 213.386 | 0.684265 | 0.090627 | 1.000853 | 133.644 | -59.67% | -93.04% | -80.84% | true |
| fp_minmax_rev64 | two_ghz | 262.315 | 0.587327 | 0.117603 | 2.003747 | 159.929 | -64.02% | -60.42% | -70.82% | true |
| fp_minmax_rev64_32 | one_ghz | 268.220 | 0.724998 | 0.121541 | 1.000962 | 261.516 | -2.56% | -6.46% | -28.42% | true |
| fp_minmax_rev64_32 | two_ghz | 330.958 | 0.657216 | 0.175684 | 2.000464 | 336.685 | 1.70% | 10.85% | -20.11% | true |
| fp_minmax_rev64_32_16 | one_ghz | 306.005 | 0.787643 | 0.132442 | 1.000659 | 368.254 | 16.90% | 19.02% | -5.87% | true |
| fp_minmax_rev64_32_16 | two_ghz | 434.987 | 0.895082 | 0.252591 | 2.000808 | 472.682 | 7.97% | 15.87% | -22.93% | true |

## Marginal capability overhead

| FU | Corner | Added capability | Area overhead | Power overhead | Leakage overhead | Fmax change |
|---|---|---|---:|---:|---:|---:|
| fp_cmp_rev64_32 | one_ghz | rev64 -> rev64_32 | 20.00% | -12.25% | 22.46% | -0.09% |
| fp_cmp_rev64_32_16 | one_ghz | rev64_32 -> rev64_32_16 | 30.27% | 32.68% | 38.44% | 0.04% |
| fp_cmp_rev64_32 | two_ghz | rev64 -> rev64_32 | 39.11% | 27.44% | 62.58% | -0.02% |
| fp_cmp_rev64_32_16 | two_ghz | rev64_32 -> rev64_32_16 | 35.56% | 30.68% | 40.10% | -0.02% |
| fp_minmax_rev64_32 | one_ghz | rev64 -> rev64_32 | 25.70% | 5.95% | 34.11% | 0.01% |
| fp_minmax_rev64_32_16 | one_ghz | rev64_32 -> rev64_32_16 | 14.09% | 8.64% | 8.97% | -0.03% |
| fp_minmax_rev64_32 | two_ghz | rev64 -> rev64_32 | 26.17% | 11.90% | 49.39% | -0.16% |
| fp_minmax_rev64_32_16 | two_ghz | rev64_32 -> rev64_32_16 | 31.43% | 36.19% | 43.78% | 0.02% |

Negative savings are penalties. These are pre-layout synthetic DC estimates, not workload-based power claims. Raw reports are under `raw/`; CSV data are in `ppa.csv`, `savings.csv`, and `marginal.csv`.
