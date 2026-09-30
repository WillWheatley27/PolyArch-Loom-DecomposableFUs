# Sliced FP Min/Max: Capability Ladder Before and After

`rtl/fu_fp_min_max_gen.sv` builds FP min/max from four identical 16-bit slices combined by a
radix-2 tree, with one lane evaluator per slice (architecture in the top-level README,
"fu_fp_min_max_gen"). This note compares its capability ladder with the original
per-format implementation (commit 654b7f8). Same flow for both: Synopsys DC Y-2026.03-SP1,
SAED14nm RVT TT/0.8 V/25 C, `compile_ultra -area_high_effort_script -no_autoungroup`,
uniform synthetic activity. Rows come from `tier_ladders/ppa.csv` (new) and the same file
at 654b7f8 (old).

## Ladder

| Corner | Tier | Area old -> new (um2) | Power old -> new (mW) | Leakage old -> new (uW) |
|---|---|---:|---:|---:|
| one_ghz | m1 | 230.8 -> **116.8** | 0.668 -> **0.328** | 0.1062 -> **0.0378** |
| one_ghz | m2 | 253.6 -> **133.2** | 0.622 -> **0.380** | 0.1017 -> **0.0439** |
| one_ghz | m3 | 304.5 -> **161.0** | 0.756 -> **0.427** | 0.1305 -> **0.0637** |
| two_ghz | m1 | 301.0 -> **148.0** | 0.701 -> **0.338** | 0.1462 -> **0.0631** |
| two_ghz | m2 | 346.5 -> **171.2** | 0.720 -> **0.386** | 0.1770 -> **0.0763** |
| two_ghz | m3 | 461.4 -> **201.8** | 0.960 -> **0.422** | 0.2645 -> **0.0954** |

## Steps

| Corner | Metric | Old steps m1->m2 / m2->m3 | New steps m1->m2 / m2->m3 |
|---|---|---:|---:|
| one_ghz | area (um2) | +22.7 / +50.9 | +16.4 / +27.9 |
| one_ghz | power (mW) | -0.0457 / +0.1335 | +0.0521 / +0.0475 |
| one_ghz | leakage (uW) | -0.0045 / +0.0288 | +0.0061 / +0.0197 |
| two_ghz | area (um2) | +45.4 / +115.0 | +23.2 / +30.5 |
| two_ghz | power (mW) | +0.0189 / +0.2406 | +0.0480 / +0.0356 |
| two_ghz | leakage (uW) | +0.0308 / +0.0875 | +0.0132 / +0.0191 |

## Evaluators: per slice, not per tree node

A slice is the top of at most one lane in any mode, so each slice holds one lane evaluator
(sign fixup and NaN combine) and `mode` selects which tree level feeds it; evaluator count
follows the finest supported mode (1 / 2 / 4 across m1 / m2 / m3). The previous version
(commits 3788330 and 4fd0321) built one evaluator per tree node (1 / 3 / 7), a sum over the
supported formats. That version synthesized to 116.8 / 145.8 / 163.6 um2 at 1 GHz and
148.0 / 176.5 / 215.7 um2 at 2 GHz; the per-slice version is 8.6% smaller at m2 and 1.6% at
m3 at 1 GHz, 6.4% smaller at m3 at 2 GHz, and 10% lower in m3 power at 2 GHz.

## Checker result and repeatability

`check_tier_ladder.py fp_minmax` passes 5 of 6 metric-corner checks in the canonical run
and in every repeatability trial (`--trials`; data in `tier_ladders/trials.csv`). The
original ladder failed all 6 (power and leakage fell from m1 to m2 at 1 GHz, and the
2 GHz power step grew 12.8x).

- 2 GHz: identical in every trial (0% spread); steps +23.2 / +30.5 um2 and
  +0.048 / +0.036 mW.
- 1 GHz: area steps +15.1..+17.1 then +24.5..+27.9 um2, power steps +0.048..+0.052 then
  +0.045..+0.048 mW across trials; spread at most 2.1% in area and 1.4% in power.
- The remaining failure is 1 GHz leakage in every trial: the fp32 step (+0.003..+0.006 uW)
  is 3-5x smaller than the fp16 step, and m1's leakage varies 7.6% between trials.

Reported values are the canonical flow; use the trial range as their uncertainty.

## Bank comparison

Against the fixed DesignWare-based bank (FP64 + FP32x2 + FP16x4), m3 saves 57.2% area,
56.3% power, and 51.2% leakage at 1 GHz, and 57.3% / 60.3% / 53.6% at 2 GHz (originally
17.3% / 22.3% / -4.3% and 2.4% / 9.8% / -28.7%); see `savings_summary.csv`. At the
0.010 ns stress target the peak-speed loss against the bank is 16.3% (originally 42.3%)
and energy/op saves 52.7% (originally a 2.9% penalty).

Caveats:

- The bank uses DesignWare `DW_fp_cmp`; the hand-written FP64-only tier (m1, 116.8 um2)
  is 12.6% smaller than the DesignWare FP64 (133.6 um2), so a hand-written bank would
  reduce the saving. `fp_minmax_two_level.md` separates this style effect from the cost
  of the split itself.
- Against a gated bank (probability-weighted, selected-only power) the bank still uses
  less power: 0.325 vs 0.425 mW at 1 GHz, 0.359 vs 0.422 mW at 2 GHz
  (`power_mode_summary.csv`).
- Power is uniform synthetic activity, pre-layout.
