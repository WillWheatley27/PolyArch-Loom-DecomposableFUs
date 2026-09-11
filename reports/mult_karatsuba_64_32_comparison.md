# 64/32-Only Karatsuba Comparison

This is the normalized apples-to-apples comparison for the runtime-selectable
Karatsuba multiplier supporting only 1x64 and 2x32 multiply-low modes.

All designs use Synopsys Design Compiler Y-2026.03-SP1, SAED14 RVT typical
`saed14rvt_base_tt0p8v25c.db`, identical compile settings, and uniform synthetic
activity (`static_probability=0.5`, `toggle_rate=0.2`).

Banks are packed and counted once:

```text
Karatsuba bank = K64 + K32x2
DesignWare bank = DW64 + DW32x2
```

## Valid 1 GHz result

| Baseline | Fixed area | Decomposable area | Area saving | Fixed power | Decomposable power | Power saving | Leakage saving | Energy saving | Fmax change |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fixed Karatsuba bank | 6,534.304 um2 | 3,525.449 um2 | 46.05% | 26.937 mW | 14.015 mW | 47.97% | 50.47% | 47.99% | +0.031% |
| Fixed DesignWare bank | 3,428.524 um2 | 3,525.449 um2 | -2.83% | 13.647 mW | 14.015 mW | -2.69% | -25.68% | -2.66% | +0.031% |

The 64/32 decomposable unit therefore saves nearly half of PPA relative to a
fixed Karatsuba bank, but is slightly worse than the optimized DesignWare bank.

Measured decomposable unit:

```text
Area:    3,525.449 um2
Power:   14.0150 mW
Leakage: 1.8920 uW
Delay:   0.999689 ns
Fmax:    1.000311 GHz
Energy:  14.0106 pJ/op
```

## 2 GHz target

The 0.500 ns target is not met:

```text
Decomposable achieved delay: 0.745928 ns
Decomposable achieved Fmax: 1.340612 GHz
```

The fixed Karatsuba and DesignWare components also miss the target. Therefore,
the 2 GHz rows are not valid equal-frequency savings and should not be used as
primary PPA claims. They are useful only as timing stress data:

- Versus fixed Karatsuba, achieved-frequency stress results show 45.46% area,
  45.62% raw power, and 44.77% leakage savings, but `comparison_valid=false`.
- Versus fixed DesignWare, the decomposable unit has 14.64% lower area but
  2.54% higher raw power and 46.41% worse energy/op; `comparison_valid=false`.

## Interpretation

The 46.05% area saving versus the fixed Karatsuba bank comes from sharing the
two 32-bit diagonal products between modes. The 2x32 mode reuses the low and
high 32-bit products directly, while the 64-bit mode adds the Karatsuba cross
product and reconstruction path.

The DesignWare bank remains slightly better because its fixed multipliers map to
optimized library structures. The current RTL Karatsuba implementation retains
cross-product, addition/subtraction, reconstruction, and runtime mode-selection
logic.

The 64/32-only result is more favorable than the 64/32/16 result against a fixed
Karatsuba bank because it removes the additional 16-bit leaf/output path while
retaining most of the useful 32-bit product sharing.

## Verification

`./run.sh fu_mult_karatsuba_64_32` passed strict Verilator lint and 20,000
randomized vectors plus directed mode, truncation, and handshake tests.

Files:

- RTL: `rtl/fu_mult_karatsuba_64_32.sv`
- Synthesis: `synth/syn_mult_karatsuba_64_32_comparison.tcl`
- PPA: `reports/mult_karatsuba_64_32_ppa.csv`
- Savings: `reports/mult_karatsuba_64_32_savings.csv`
- Raw reports: `reports/mult_karatsuba_64_32_comparison/`
