# Integer Multiply Karatsuba Comparison

This comparison separates the algorithm effect from the decomposability effect.
All rows were synthesized with Synopsys Design Compiler Y-2026.03-SP1 using
`saed14rvt_base_tt0p8v25c.db` at `tt0p8v25c` (0.8 V, 25 C), identical
wire-load/compile settings, and uniform synthetic input activity
(`static_probability=0.5`, `toggle_rate=0.2`). Power is therefore comparable
synthetic DC power, not a workload-trace claim.

## Implementations

- `karatsuba_decomposable`: existing runtime-selectable `fu_mult_decomp`, with
  1x64, 2x32, and 4x16 multiply-low modes. 16-bit products are the terminal
  leaves; the same leaves are reused by the wider Karatsuba levels.
- `karatsuba_fixed_64`, `karatsuba_fixed_32x2`, `karatsuba_fixed_16x4`:
  mode-free fixed Karatsuba components. Together they form the matched fixed
  Karatsuba bank.
- `designware_fixed_64`, `designware_fixed_32x2`, `designware_fixed_16x4`:
  the existing fixed DesignWare baselines. Together they form the practical
  DesignWare bank.

Packed components are counted once. The bank equations are:

```text
Bank_Karatsuba = Area(K64) + Area(K32x2) + Area(K16x4)
Bank_DesignWare = Area(DW64) + Area(DW32x2) + Area(DW16x4)
```

The same sum is used for power and leakage. Bank frequency is the minimum
component Fmax. Savings are calculated as:

```text
Saving (%) = 100 * (Fixed_bank - Decomposable) / Fixed_bank
```

Negative values are penalties, not savings.

## Primary equal-target result: 1 GHz

All seven designs meet the 1.000 ns target, so this is the apples-to-apples
comparison. The primary machine-readable results are in
`mult_karatsuba_ppa.csv` and `mult_karatsuba_savings.csv`.

| Baseline | Fixed area (um2) | Decomp area (um2) | Area saving | Fixed power (mW) | Decomp power (mW) | Power saving | Fixed leakage (uW) | Decomp leakage (uW) | Leakage saving | Energy saving | Fmax change |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fixed Karatsuba bank | 7134.325 | 5206.966 | 27.02% | 28.651 | 21.373 | 25.40% | 4.073 | 3.279 | 19.50% | 25.40% | +0.006% |
| Fixed DesignWare bank | 4028.545 | 5206.966 | **-29.25%** | 15.362 | 21.373 | **-39.14%** | 1.758 | 3.279 | **-86.48%** | **-39.13%** | +0.006% |

### Interpretation

Against a fixed Karatsuba bank, sharing is beneficial in this implementation:
the decomposable unit removes duplicated 64/32/16 datapaths and saves 27.02%
area, 25.40% dynamic power, 19.50% leakage, and 25.40% energy/op at essentially
the same 1 GHz operating point.

Against the fixed DesignWare bank, the result is unfavorable: area is 29.25%
higher, dynamic power is 39.14% higher, leakage is 86.48% higher, and energy/op
is 39.13% higher. This is because DesignWare maps each fixed multiplier to a
more efficient implementation than the RTL Karatsuba hierarchy, while the
decomposable unit retains all Karatsuba cross-product, reconstruction, and mode
routing logic. The comparison therefore says that sharing helps relative to
the same Karatsuba algorithm, but the current Karatsuba implementation is not
competitive with the library's optimized multiplier macros.

The frequency difference is effectively zero because every design was compiled
to the same 1 GHz target. It is not evidence that the designs have identical
unconstrained peak speed.

## Secondary maximum-speed stress

The `maxspeed` rows use the same 0.010 ns stress target for every design. This
target is intentionally infeasible; use it only for timing-driven sizing and
achieved-frequency tradeoffs. At this stress point, the decomposable unit versus
the fixed Karatsuba bank is 40.27% smaller, 32.21% lower raw synthetic power,
40.15% lower leakage, and 36.30% lower energy/op, with a 6.41% higher achieved
Fmax. Versus the DesignWare bank it is 26.37% smaller but 52.67% slower; its
energy/op is 109.42% worse. These stress results must not replace the 1 GHz
equal-target comparison for power claims.

## Verification

`./run.sh karatsuba_mult_standalones` passes strict Verilator 5.044 lint and
simulation for all three new fixed Karatsuba tops. Each test includes directed
low-product/lane-isolation and backpressure cases plus 20,000 randomized
vectors. `./run.sh fu_mult_decomp` also passes its existing 20,000-vector
all-mode test.

## Files

- RTL: `rtl/standalone/mult_karatsuba_standalones/`
- Synthesis: `synth/syn_mult_karatsuba_comparison.tcl`
- PPA rows: `reports/mult_karatsuba_ppa.csv`
- Savings rows: `reports/mult_karatsuba_savings.csv`
- Raw SAED14nm reports: `reports/mult_karatsuba_comparison/`
