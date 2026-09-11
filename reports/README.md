# Normalized PPA reports

`ppa_summary.csv` is generated from `synth/syn_common_decomp.tcl` by
`collect_ppa.py`. The run uses the SAED14 RVT typical library
`saed14rvt_base_tt0p8v25c.db`, identical wire-load and compile settings, and
two common operating-point targets (1.000 ns and 0.500 ns).

The present run uses uniform synthetic switching (`static_probability=0.5`,
`toggle_rate=0.2`) because no common workload SAIF/VCD traces have yet been
provided. Therefore these power values are comparable estimates, not workload
power claims. Designs that miss a target have `timing_met=false`; their lower
power must not be interpreted as a benefit at that target.

The reported delay/Fmax values are the critical path after compiling against
the stated max-delay target. They are achieved operating-point values, not an
unconstrained natural-speed measurement; use the separate maximum-speed flow
for peak-frequency tradeoffs.

The fixed-bank fields in `ppa_summary.csv` and the percentages in
`savings_summary.csv` are marked invalid until the fixed 64-bit and packed
32/16-bit baselines are synthesized with the same scripts and targets. Existing
legacy reports use different settings and are not silently mixed into the
normalized comparison. The fixed run has now completed; 16 of 18 savings rows
are valid. Mult and Rounding at 2 GHz remain invalid because the decomposable
implementations miss the 0.500 ns target.

Savings use `Total cell area` (not wire-load `Total area`) because that is the
area metric used by the original source tables. Both metrics remain available
in `ppa_summary.csv`.

The fixed-bank launch script is `synth/syn_common_fixed.tcl`. During this run,
the SAED14 Design Compiler license server (`pyrito.cs.ucla.edu:27000`) was
temporarily unreachable after the decomposable pass. The run subsequently
completed through an escalated license connection.

The fixed script uses true packed standalone RTL for 2x32 and 4x16. Where a
dedicated 64-bit source was not already present, it uses a mode-tied 64-only
wrapper from the existing generator (with synthesis pruning) and records that
choice in the report metadata. `fu_mult_64.sv` was added as a true standalone
64-bit multiply-low baseline.

Mode probabilities are recorded in `mode_probabilities.csv` (64-bit 25%,
32-bit 50%, 16-bit 25%). They are not yet applied to SAIF/VCD because the
repository has no common workload trace generator; the current DC power rows
therefore use the explicitly labeled uniform synthetic activity.

The 0.010 ns timing-stress results are in `maxspeed_summary.csv`. All nine
decomposable cores miss that intentionally aggressive target; the table reports
their achieved peak Fmax and marks `timing_met=false`. These values are useful
for showing timing-driven upsizing, but are not the primary savings comparison.

The per-family feasible-frequency run is in `reports/synth_feasible` and is
included in `ppa_summary.csv`/`savings_summary.csv` with `corner=feasible`.
Targets are 0.80 times the slowest observed family Fmax (1.600 GHz for most
families, 0.824 GHz for Mult, and 1.337 GHz for Rounding). All 36 feasible-flow
rows meet their family target.

The symmetric 0.010 ns fixed-versus-decomposable stress comparison is in
`maxspeed_savings.csv`. It uses achieved Fmax and energy/op; it is intentionally
separate from the equal-frequency savings rows.

Machine-readable outputs:

- `ppa_summary.csv`: 108 normalized rows, including fixed, decomposable, and feasible-family runs.
- `savings_summary.csv`: 27 rows: 9 FU families × three comparison corners.
- `maxspeed_summary.csv`: nine decomposable stress rows.
- `maxspeed_savings.csv`: nine symmetric fixed-bank/decomposable stress comparisons.
- `power_mode_summary.csv`: all-active versus probability-weighted selected-only fixed-bank estimates.
- `verification_summary.csv`: 35 Verilator PASS records.

The controlled integer-multiply algorithm comparison is kept separate in
`mult_karatsuba_ppa.csv` and `mult_karatsuba_savings.csv`. It compares the
runtime-decomposable Karatsuba unit against both a matched fixed Karatsuba bank
and the practical fixed DesignWare bank at 1 GHz, plus a secondary symmetric
maximum-speed stress run. See `mult_karatsuba_comparison.md` for the bank
definitions, verification evidence, results, and interpretation.

DC also emitted VHD-300 array-index warnings for generated AddSub and FP
MinMax expressions during elaboration. Verilator passes, but these warnings
should be resolved before treating the synthesis results as sign-off quality.
