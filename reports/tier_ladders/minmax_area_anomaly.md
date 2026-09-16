# Integer MinMax Area Reversal Audit

The normalized fixed reports show two opposite area responses when the timing target tightens from 1.000 ns to 0.500 ns:

| Design | 1 GHz area (um2) | 2 GHz area (um2) | Change |
|---|---:|---:|---:|
| MinMax32x2 | 138.128398 | 111.088801 | -19.58% |
| MinMax64 | 103.407600 | 130.491600 | +26.29% |

This is a real Design Compiler mapping result, not a calculated estimate. Both runs use separate `compile_ultra -area_high_effort_script -no_autoungroup` invocations, the same SAED14nm TT/0.8 V/25 C library, and the same wire-load/activity setup. The target constraint changes the optimization solution; cell area is not required to be monotonic with a tighter max-delay target.

The report evidence shows that DC selected materially different mapped netlists:

- MinMax32x2: 392 cells / 156 buffer-inverter cells / 56 references at 1 GHz versus 394 / 72 / 25 at 2 GHz. Buffer/inverter area falls from 41.114399 to 17.982000 um2, and total cell area falls from 138.128398 to 111.088801 um2.
- MinMax64: 316 cells / 104 buffer-inverter cells / 34 references at 1 GHz versus 401 / 134 / 48 at 2 GHz. Total cell area rises from 103.407600 to 130.491600 um2.

The fixed 1 GHz and 2 GHz bank rows must therefore remain corner-specific. It is invalid to use the 1 GHz MinMax32x2 area as the 2 GHz bank component or to infer a monotonic physical area trend from these independent timing-constrained compilations. The raw reports are under `reports/synth_common_fixed/minmax_32x2/` and `reports/synth_common_fixed/minmax_64/`.
