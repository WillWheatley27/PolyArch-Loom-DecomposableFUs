# Sliced FP Compare: Capability Ladder Before and After

`rtl/fu_fp_cmp_gen.sv` now uses the slice-and-tree datapath of the sliced FP min/max
(`fp_minmax_sliced.md`, README "fu_fp_cmp_gen"), and the revised compare tiers in
`rtl/revised_fp_fus/` are thin wrappers over it. Old values are the original `*_gen` core
and the previous revised core at commit 3788330. Same flow as every ladder: Synopsys DC
Y-2026.03-SP1, SAED14nm RVT TT/0.8 V/25 C,
`compile_ultra -area_high_effort_script -no_autoungroup`, uniform synthetic activity.

## Ladder

| Corner | Tier | Original gen (um2) | Old revised (um2) | New (um2) | New power (mW) | New leakage (uW) |
|---|---|---:|---:|---:|---:|---:|
| one_ghz | g1 / rev64 | 168.3 | 178.7 | **105.1** | 0.222 | 0.0311 |
| one_ghz | g2 / rev64_32 | 205.3 | 214.5 | **107.2** | 0.223 | 0.0285 |
| one_ghz | g3 / rev64_32_16 | 257.7 | 279.4 | **124.6** | 0.275 | 0.0387 |
| two_ghz | g1 / rev64 | 221.6 | 243.6 | **129.5** | 0.244 | 0.0543 |
| two_ghz | g2 / rev64_32 | 350.1 | 338.9 | **138.3** | 0.268 | 0.0525 |
| two_ghz | g3 / rev64_32_16 | 410.1 | 459.4 | **161.4** | 0.294 | 0.0617 |

The revised wrappers (2-bit mode port with FP64 fallback) land within 1.4 um2 of the
same-capability `g` tier; the revised FP64-only tier (`rev64`) is identical to `g1`.

## Steps

| Corner | Metric | Old revised steps | New steps | New per added lane |
|---|---|---:|---:|---:|
| one_ghz | area (um2) | +35.7 / +64.9 | +2.0 / +17.4 | +2.0 / +8.7 |
| one_ghz | power (mW) | -0.0785 / +0.1839 | +0.0010 / +0.0512 | +0.0010 / +0.0256 |
| one_ghz | leakage (uW) | +0.0167 / +0.0350 | -0.0026 / +0.0102 | -0.0026 / +0.0051 |
| two_ghz | area (um2) | +95.3 / +120.5 | +8.8 / +23.1 | +8.8 / +11.5 |
| two_ghz | power (mW) | +0.1341 / +0.1910 | +0.0240 / +0.0264 | +0.0240 / +0.0132 |
| two_ghz | leakage (uW) | +0.0718 / +0.0748 | -0.0018 / +0.0092 | -0.0018 / +0.0046 |

## Cost model

The fp32 lanes are intermediate nodes of the fp64 compare tree, so FP64 + 2xFP32
support only adds one lane evaluator (slice 1) and a 2:1 input select on slice 3's
evaluator. The fp16 tier adds two evaluators (slices 0 and 2), the fp16 exponent
detectors of those slices, and one more select input on slices 1 and 3. Evaluators sit
one per slice (1 / 2 / 4 across the tiers, the finest mode's lane count), so the cost
follows the number of added lanes. At the deterministic 2 GHz corner the cost per added
lane is +8.8 then +11.5 um2 (1.3x apart), and the power steps are +0.024 and +0.026 mW.

An earlier variant with one evaluator per tree node (7 in the full tier) synthesized
to 105.1 / 109.0 / 126.9 um2 at 1 GHz and 129.5 / 135.8 / 168.5 um2 at 2 GHz: 4% larger
at the full tier and with a 2.6x per-lane step ratio at 2 GHz.

## Checker result and repeatability

`check_tier_ladder.py fp_cmp` fails (1 of 6 checks pass canonically, 1-2 across trials):
the per-tier step ratio is undefined in practice because the fp32 step is almost zero.
The three trials (`check_tier_ladder.py fp_cmp --trials`, data in `tier_ladders/trials.csv`)
show:

- 2 GHz: identical in every trial (0% spread).
- 1 GHz: area is monotonic in every trial; the fp32 area step (+2.0 to +6.1 um2) is no
  larger than g1's own trial spread (3.9%), and the fp32 power and leakage steps straddle
  zero. The fp16 step is +14.4 to +17.4 um2.
- The fp32 leakage step at 2 GHz is -0.0018 uW (-3%), deterministic but negligible.

So area grows monotonically and the fp16 cost per lane is stable, but the ladder is not
evenly stepped per tier: adding FP32 lanes costs almost nothing measurable.

## Bank comparison

Against the fixed DesignWare-based bank (`fu_fp_cmp_64` + `32x2` + `16x4`), g3 saves
63.7% area, 61.5% power, and 64.3% leakage at 1 GHz, and 64.1% / 66.5% / 63.7% at 2 GHz
(previously 24.7% / 0.6% / -2.6% and 8.7% / 13.7% / -34.0%); see `savings_summary.csv`.
At the 0.010 ns stress target the peak-speed loss against the bank shrinks from 42.0% to
4.5% and energy/op goes from an 8.7% penalty to a 60.2% saving. Against a gated bank
(probability-weighted selected-only power) the decomposable unit is now within 2% at
2 GHz (0.294 vs 0.290 mW) and 14% higher at 1 GHz (0.281 vs 0.246 mW), previously about 3x.

Caveats: the bank uses DesignWare `DW_fp_cmp`, and the hand-written FP64-only tier is
already 5.4% smaller than it at 1 GHz, so a hand-written bank would reduce the saving;
power is uniform synthetic activity, pre-layout.
