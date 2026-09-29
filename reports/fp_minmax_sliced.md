# Sliced FP Min/Max: Capability Ladder Before and After

`rtl/fu_fp_min_max_gen.sv` now builds FP min/max from four identical 16-bit
slices combined by a radix-2 tree (architecture in the top-level README,
"fu_fp_min_max_gen"). This note compares the capability ladder of that core with
the previous per-format implementation (commit 654b7f8). Both use the same flow:
Synopsys DC Y-2026.03-SP1, SAED14nm RVT TT/0.8 V/25 C,
`compile_ultra -area_high_effort_script -no_autoungroup`, uniform synthetic
activity. Rows come from `tier_ladders/ppa.csv` (new) and the same file at
654b7f8 (old).

## Ladder

| Corner | Tier | Area old -> new (um2) | Power old -> new (mW) | Leakage old -> new (uW) |
|---|---|---:|---:|---:|
| one_ghz | m1 | 230.8 -> **116.8** | 0.668 -> **0.328** | 0.1062 -> **0.0378** |
| one_ghz | m2 | 253.6 -> **145.8** | 0.622 -> **0.365** | 0.1017 -> **0.0551** |
| one_ghz | m3 | 304.5 -> **163.6** | 0.756 -> **0.428** | 0.1305 -> **0.0600** |
| two_ghz | m1 | 301.0 -> **148.0** | 0.701 -> **0.338** | 0.1462 -> **0.0631** |
| two_ghz | m2 | 346.5 -> **176.5** | 0.720 -> **0.385** | 0.1770 -> **0.0816** |
| two_ghz | m3 | 461.4 -> **215.7** | 0.960 -> **0.468** | 0.2645 -> **0.0977** |

| Corner | Metric | Old steps m1->m2 / m2->m3 | New steps m1->m2 / m2->m3 |
|---|---|---:|---:|
| one_ghz | area (um2) | +22.7 / +50.9 | +29.0 / +17.8 |
| one_ghz | power (mW) | -0.0457 / +0.1335 | +0.0369 / +0.0632 |
| one_ghz | leakage (uW) | -0.0045 / +0.0288 | +0.0172 / +0.0049 |
| two_ghz | area (um2) | +45.4 / +115.0 | +28.5 / +39.2 |
| two_ghz | power (mW) | +0.0189 / +0.2406 | +0.0468 / +0.0826 |
| two_ghz | leakage (uW) | +0.0308 / +0.0875 | +0.0185 / +0.0162 |

## Cost model

Each added tier taps one more level of the tree: one more input on every slice's
level select plus one lane evaluator (sign fixup and NaN combine) per new lane.
The first split (m1 -> m2) also pays once for the runtime mode network, because
m1 has no mode input: at 1 GHz, buffer and AO221 cells go from 0 to 7.6 and
4.4 um2 at m2, and m3 reuses them. Tier steps are therefore roughly constant
rather than proportional to lane count.

`check_tier_ladder.py fp_minmax` gates on this: monotonic area, power, and leakage,
m1->m2 and m2->m3 steps within 2x of each other, and timing met. The canonical
new ladder passes 5 of 6 metric/corner checks and the old ladder fails all 6
(power and leakage fell from m1 to m2 at 1 GHz, and the 2 GHz power step grew
12.8x). The repeatability trials below show that only part of the new result
is robust.

DC variance between small, logically different netlists is about 6% here: the
revised `rev64_32` wrapper uses the same core parameters as m2 and differs only
in its mode decode, yet synthesizes to 137.3 um2 versus m2's 145.8 um2 at 1 GHz.
Identical RTL compiled in the same job order reproduces exactly (`rev64` = m1 =
116.772 um2, `rev64_32_16` = m3 = 163.570 um2). The separate `synth_common` run of
m3 at 1 GHz lands at 163.0 um2 and 0.446 mW against the ladder's 163.6 um2 and
0.428 mW (0.3% area, 4% power), so small power differences between runs are
within tool variance; the 2 GHz runs match exactly.

## Bank comparison

Against the fixed DesignWare-based bank (FP64 + FP32x2 + FP16x4), m3 saves
55.7% area, 54.2% power, and 53.2% leakage at 1 GHz, and 54.4% / 56.0% / 52.4%
at 2 GHz (previously 17.3% / 22.3% / -4.3% and 2.4% / 9.8% / -28.7%); see
`savings_summary.csv`. At the 0.010 ns stress target the m3 peak-speed loss
against the bank shrinks from 42.3% to 19.1% and energy/op goes from a 2.9%
penalty to a 52.4% saving (`maxspeed_savings.csv`).

Caveats:

- The fixed bank uses DesignWare `DW_fp_cmp` components. The hand-written
  FP64-only tier (m1, 116.8 um2) is already 12.6% smaller than the DesignWare
  FP64 (133.6 um2), so a bank of hand-written fixed units would be smaller and
  the saving against it lower. That bank has not been synthesized.
- With probability-weighted, selected-only bank power (inactive fixed units
  gated), the bank still uses less power (0.325 vs 0.446 mW at 1 GHz;
  `power_mode_summary.csv`). The area saving is the robust result.
- Power is uniform synthetic activity, not workload traces, and all results
  are pre-layout.

## Repeatability (three trials)

Design Compiler is deterministic for identical input, so repeating the same
script cannot measure uncertainty. The trials therefore vary what should not
matter: `t1_repeat` reruns the canonical flow, `t2_reverse` reverses the job
order inside one session, and `t3_fresh` compiles every design in a fresh
session (`synth/syn_tier_ladders.tcl` with `OUTROOT`, `JOB_REVERSE`, `JOB_FILTER`).
`collect_ladder_trials.py` writes every row plus min / median / max / spread
to `tier_ladders/trials.csv`; statistics use the three distinct configurations
(canonical, t2, t3), because t1 reproduces the canonical run bit-for-bit.

- 2 GHz: all trials are identical for every tier (0% spread).
- 1 GHz: session state changes the mapped netlist. Spread is at most 1.3% in
  area, 4.0% in power, and 7.5% in leakage (m1).

Robust in every trial:

- area, power, and leakage grow monotonically m1 -> m2 -> m3 at both corners;
- all 2 GHz step checks pass;
- m3 saves 55.6-55.7% area, 54.2-56.0% power, and 52.0-53.2% leakage against
  the fixed bank at 1 GHz (54.4% / 56.0% / 52.4% at 2 GHz);
- at 1 GHz the first split costs more area than the second (+29.0-30.9 vs
  +15.4-17.8 um2) and more leakage (+0.014-0.018 vs +0.003-0.005 uW), while
  the second costs more power (+0.063-0.083 vs +0.033-0.037 mW).

Not robust: the 1 GHz step-ratio verdicts. Depending on the trial, 3 to 5 of
the 6 checks pass (canonical 5, t2 4, t3 3, median 4); 1 GHz leakage fails in
every trial, and 1 GHz area and power pass or fail with job order. The steady
per-tier step is therefore established at 2 GHz only. At 1 GHz the ladder is
monotonic but uneven, consistent with the one-time mode network landing in the
first split.

Reported values stay the canonical flow (same flow as every other family in
`tier_ladders/`); use the trial range above as their uncertainty, and do not
treat differences smaller than it as findings.
