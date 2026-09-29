# Capability Tier Ladders

Synopsys DC Y-2026.03-SP1, SAED14nm RVT TT/0.8 V/25 C, identical `compile_ultra -area_high_effort_script -no_autoungroup` flow, 1.000 ns and 0.500 ns max-delay targets, and uniform synthetic activity (static probability 0.5, toggle rate 0.2). Area is total cell area; energy/op is dynamic power divided by achieved Fmax.

Each row is a capability wrapper synthesized independently. Marginal overhead is measured against the preceding rung in the same family and corner.

## abs

| Tier | Capability | Corner | Area (um2) | Power (mW) | Leakage (uW) | Delay (ns) | Fmax (GHz) | Energy/op (pJ) |
|---|---|---|---:|---:|---:|---:|---:|---:|
| a1 | 64 | one_ghz | 133.466 | 0.215481 | 0.052010 | 0.995457 | 1.004564 | 0.214502 |
| a1 | 64 | two_ghz | 174.270 | 0.220780 | 0.082706 | 0.499731 | 2.001077 | 0.110331 |
| a2 | 64/32x2 | one_ghz | 141.325 | 0.220840 | 0.055420 | 0.999863 | 1.000137 | 0.220810 |
| a2 | 64/32x2 | two_ghz | 175.691 | 0.247035 | 0.085916 | 0.499997 | 2.000012 | 0.123517 |
| a3 | 64/32x2/16x4 | one_ghz | 155.134 | 0.268606 | 0.065369 | 0.999996 | 1.000004 | 0.268605 |
| a3 | 64/32x2/16x4 | two_ghz | 201.443 | 0.301127 | 0.105446 | 0.499909 | 2.000364 | 0.150536 |

## cmp

| Tier | Capability | Corner | Area (um2) | Power (mW) | Leakage (uW) | Delay (ns) | Fmax (GHz) | Energy/op (pJ) |
|---|---|---|---:|---:|---:|---:|---:|---:|
| c1 | 64 | one_ghz | 83.250 | 0.202380 | 0.023742 | 0.997995 | 1.002009 | 0.201974 |
| c1 | 64 | two_ghz | 117.038 | 0.240319 | 0.045501 | 0.499846 | 2.000616 | 0.120122 |
| c2 | 64/32x2 | one_ghz | 88.223 | 0.222309 | 0.025416 | 0.998771 | 1.001231 | 0.222036 |
| c2 | 64/32x2 | two_ghz | 119.392 | 0.244183 | 0.047004 | 0.499929 | 2.000284 | 0.122074 |
| c4 | 64/32x2/16x4 | one_ghz | 144.122 | 0.305136 | 0.055501 | 0.999158 | 1.000843 | 0.304879 |
| c4 | 64/32x2/16x4 | two_ghz | 222.133 | 0.356930 | 0.106841 | 0.499709 | 2.001165 | 0.178361 |
| c8 | 64/32x2/16x4/8x8 | one_ghz | 145.854 | 0.326448 | 0.057404 | 0.999377 | 1.000623 | 0.326245 |
| c8 | 64/32x2/16x4/8x8 | two_ghz | 244.555 | 0.383492 | 0.124740 | 0.499972 | 2.000112 | 0.191735 |

## barrel_shift

| Tier | Capability | Corner | Area (um2) | Power (mW) | Leakage (uW) | Delay (ns) | Fmax (GHz) | Energy/op (pJ) |
|---|---|---|---:|---:|---:|---:|---:|---:|
| bs1 | 64 | one_ghz | 315.240 | 1.222300 | 0.119859 | 0.999814 | 1.000186 | 1.222073 |
| bs1 | 64 | two_ghz | 643.978 | 1.511600 | 0.341512 | 0.499981 | 2.000076 | 0.755771 |
| bs2 | 64/32x2 | one_ghz | 368.831 | 1.304400 | 0.154621 | 0.999940 | 1.000060 | 1.304322 |
| bs2 | 64/32x2 | two_ghz | 607.703 | 1.444300 | 0.318039 | 0.499953 | 2.000188 | 0.722082 |
| bs3 | 64/32x2/16x4 | one_ghz | 404.351 | 1.436800 | 0.162481 | 0.999865 | 1.000135 | 1.436606 |
| bs3 | 64/32x2/16x4 | two_ghz | 762.259 | 1.710900 | 0.417944 | 0.499985 | 2.000060 | 0.855424 |

## rounding

| Tier | Capability | Corner | Area (um2) | Power (mW) | Leakage (uW) | Delay (ns) | Fmax (GHz) | Energy/op (pJ) |
|---|---|---|---:|---:|---:|---:|---:|---:|
| g1 | FP64 | one_ghz | 613.253 | 0.493619 | 0.302167 | 0.999956 | 1.000044 | 0.493597 |
| g1 | FP64 | two_ghz | 1384.126 | 0.894544 | 0.965000 | 0.597832 | 1.672711 | 0.534787 |
| g2 | FP64/FP32x2 | one_ghz | 1028.482 | 0.883716 | 0.531672 | 0.999729 | 1.000271 | 0.883477 |
| g2 | FP64/FP32x2 | two_ghz | 1805.260 | 1.339600 | 1.216400 | 0.551408 | 1.813539 | 0.738666 |
| g3 | FP64/FP32x2/FP16x4 | one_ghz | 1256.786 | 1.324400 | 0.650348 | 0.999835 | 1.000165 | 1.324181 |
| g3 | FP64/FP32x2/FP16x4 | two_ghz | 2156.686 | 1.645500 | 1.454600 | 0.550626 | 1.816115 | 0.906055 |

## fp_cmp

| Tier | Capability | Corner | Area (um2) | Power (mW) | Leakage (uW) | Delay (ns) | Fmax (GHz) | Energy/op (pJ) |
|---|---|---|---:|---:|---:|---:|---:|---:|
| g1 | FP64 | one_ghz | 105.139 | 0.222308 | 0.031126 | 0.999970 | 1.000030 | 0.222301 |
| g1 | FP64 | two_ghz | 129.515 | 0.244003 | 0.054254 | 0.499605 | 2.001581 | 0.121905 |
| g2 | FP64/FP32x2 | one_ghz | 107.182 | 0.223308 | 0.028534 | 0.999890 | 1.000110 | 0.223284 |
| g2 | FP64/FP32x2 | two_ghz | 138.306 | 0.267977 | 0.052455 | 0.499857 | 2.000572 | 0.133950 |
| g3 | FP64/FP32x2/FP16x4 | one_ghz | 124.586 | 0.274507 | 0.038685 | 0.999949 | 1.000051 | 0.274493 |
| g3 | FP64/FP32x2/FP16x4 | two_ghz | 161.394 | 0.294370 | 0.061669 | 0.499973 | 2.000108 | 0.147177 |

## fp_minmax

| Tier | Capability | Corner | Area (um2) | Power (mW) | Leakage (uW) | Delay (ns) | Fmax (GHz) | Energy/op (pJ) |
|---|---|---|---:|---:|---:|---:|---:|---:|
| m1 | FP64 | one_ghz | 116.772 | 0.327904 | 0.037837 | 0.998490 | 1.001512 | 0.327409 |
| m1 | FP64 | two_ghz | 147.985 | 0.338439 | 0.063124 | 0.499010 | 2.003968 | 0.168884 |
| m2 | FP64/FP32x2 | one_ghz | 145.765 | 0.364782 | 0.055063 | 0.999638 | 1.000362 | 0.364650 |
| m2 | FP64/FP32x2 | two_ghz | 176.490 | 0.385277 | 0.081588 | 0.499177 | 2.003297 | 0.192321 |
| m3 | FP64/FP32x2/FP16x4 | one_ghz | 163.570 | 0.427995 | 0.059992 | 0.998931 | 1.001070 | 0.427537 |
| m3 | FP64/FP32x2/FP16x4 | two_ghz | 215.651 | 0.467891 | 0.097747 | 0.499587 | 2.001653 | 0.233752 |

## MinMax constraint anomaly

The integer fixed `minmax_32x2` and `minmax_64` rows in `reports/synth_common_fixed` were produced by separate `compile_ultra -area_high_effort_script` runs at 1.000 ns and 0.500 ns. The tighter constraint can select a different mapped implementation and cell sizing; area is not mathematically monotonic with timing pressure. Therefore `minmax_32x2` shrinking from 138.128398 to 111.088801 um2 while `minmax_64` grows from 103.407600 to 130.491600 um2 is a synthesis result, not evidence of a physical law. Compare each corner using its own report set and do not mix 1 GHz and 2 GHz bank baselines.
