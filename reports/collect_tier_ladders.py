#!/usr/bin/env python3
"""Collect normalized tier-ladder reports and compute adjacent-rung overhead."""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "tier_ladders" / "raw"
OUT = ROOT / "tier_ladders"
PPA = OUT / "ppa.csv"
MARGINAL = OUT / "marginal.csv"
MARKDOWN = OUT / "comparison.md"

PPA_FIELDS = [
    "family", "tier", "capability", "corner", "target_period_ns",
    "achieved_delay_ns", "fmax_ghz", "cell_area_um2", "total_area_um2",
    "dynamic_power_mw", "leakage_power_uw", "energy_per_operation_pj",
    "timing_met", "activity_source",
]
MARGINAL_FIELDS = [
    "family", "from_tier", "to_tier", "capability", "corner",
    "previous_area_um2", "new_area_um2", "area_overhead_percent",
    "previous_power_mw", "new_power_mw", "power_overhead_percent",
    "previous_leakage_uw", "new_leakage_uw", "leakage_overhead_percent",
    "previous_fmax_ghz", "new_fmax_ghz", "frequency_change_percent",
    "comparison_valid", "notes",
]
ORDER = {
    "abs": ["a1", "a2", "a3"],
    "cmp": ["c1", "c2", "c4", "c8"],
    "barrel_shift": ["bs1", "bs2", "bs3"],
    "rounding": ["g1", "g2", "g3"],
    "fp_cmp": ["g1", "g2", "g3"],
    "fp_minmax": ["m1", "m2", "m3"],
}
CAPS = {
    ("abs", "a1"): "64", ("abs", "a2"): "64/32x2", ("abs", "a3"): "64/32x2/16x4",
    ("cmp", "c1"): "64", ("cmp", "c2"): "64/32x2", ("cmp", "c4"): "64/32x2/16x4", ("cmp", "c8"): "64/32x2/16x4/8x8",
    ("barrel_shift", "bs1"): "64", ("barrel_shift", "bs2"): "64/32x2", ("barrel_shift", "bs3"): "64/32x2/16x4",
    ("rounding", "g1"): "FP64", ("rounding", "g2"): "FP64/FP32x2", ("rounding", "g3"): "FP64/FP32x2/FP16x4",
    ("fp_cmp", "g1"): "FP64", ("fp_cmp", "g2"): "FP64/FP32x2", ("fp_cmp", "g3"): "FP64/FP32x2/FP16x4",
    ("fp_minmax", "m1"): "FP64", ("fp_minmax", "m2"): "FP64/FP32x2", ("fp_minmax", "m3"): "FP64/FP32x2/FP16x4",
}
PERIOD = {"one_ghz": 1.0, "two_ghz": 0.5}


def number(pattern: str, text: str, default: float = 0.0) -> float:
    match = re.search(pattern, text, re.MULTILINE)
    return float(match.group(1)) if match else default


def power_mw(label: str, text: str) -> float:
    match = re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)", text, re.MULTILINE)
    if not match:
        return 0.0
    scale = {"W": 1000.0, "mW": 1.0, "uW": 1e-3, "nW": 1e-6}
    return float(match.group(1)) * scale[match.group(2)]


def parse(path: Path, period: float) -> dict[str, object]:
    result = (path / "result.txt").read_text(errors="replace")
    area = (path / "report_area.rpt").read_text(errors="replace")
    power = (path / "report_power.rpt").read_text(errors="replace")
    delay = number(r"ARRIVAL_NS=([0-9.eE+-]+)", result)
    fmax = number(r"FMAX_GHZ=([0-9.eE+-]+)", result)
    dynamic = power_mw("Total Dynamic Power", power)
    leakage = power_mw("Cell Leakage Power", power) * 1000.0
    return {
        "target_period_ns": period,
        "achieved_delay_ns": delay,
        "fmax_ghz": fmax,
        "cell_area_um2": number(r"Total cell area:\s+([0-9.eE+-]+)", area),
        "total_area_um2": number(r"Total area:\s+([0-9.eE+-]+)", area),
        "dynamic_power_mw": dynamic,
        "leakage_power_uw": leakage,
        "energy_per_operation_pj": dynamic / fmax if fmax else 0.0,
        "timing_met": delay <= period + 1e-6,
        "activity_source": "uniform_synthetic",
    }


def overhead(old: float, new: float) -> float:
    return 100.0 * (new - old) / old if old else 0.0


def main() -> None:
    rows: list[dict[str, object]] = []
    for family, tiers in ORDER.items():
        for tier in tiers:
            for corner, period in PERIOD.items():
                path = RAW / family / tier / corner
                if not (path / "result.txt").exists():
                    continue
                rows.append({"family": family, "tier": tier,
                             "capability": CAPS[(family, tier)],
                             "corner": corner, **parse(path, period)})
    OUT.mkdir(parents=True, exist_ok=True)
    with PPA.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=PPA_FIELDS)
        writer.writeheader(); writer.writerows(rows)

    by_key = {(r["family"], r["tier"], r["corner"]): r for r in rows}
    marginal: list[dict[str, object]] = []
    for family, tiers in ORDER.items():
        for old_tier, new_tier in zip(tiers, tiers[1:]):
            for corner in PERIOD:
                old = by_key.get((family, old_tier, corner))
                new = by_key.get((family, new_tier, corner))
                if old is None or new is None:
                    continue
                marginal.append({
                    "family": family, "from_tier": old_tier, "to_tier": new_tier,
                    "capability": new["capability"], "corner": corner,
                    "previous_area_um2": old["cell_area_um2"], "new_area_um2": new["cell_area_um2"],
                    "area_overhead_percent": overhead(float(old["cell_area_um2"]), float(new["cell_area_um2"])),
                    "previous_power_mw": old["dynamic_power_mw"], "new_power_mw": new["dynamic_power_mw"],
                    "power_overhead_percent": overhead(float(old["dynamic_power_mw"]), float(new["dynamic_power_mw"])),
                    "previous_leakage_uw": old["leakage_power_uw"], "new_leakage_uw": new["leakage_power_uw"],
                    "leakage_overhead_percent": overhead(float(old["leakage_power_uw"]), float(new["leakage_power_uw"])),
                    "previous_fmax_ghz": old["fmax_ghz"], "new_fmax_ghz": new["fmax_ghz"],
                    "frequency_change_percent": overhead(float(old["fmax_ghz"]), float(new["fmax_ghz"])),
                    "comparison_valid": bool(old["timing_met"]) and bool(new["timing_met"]),
                    "notes": "adjacent capability overhead; uniform synthetic activity",
                })
    with MARGINAL.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=MARGINAL_FIELDS)
        writer.writeheader(); writer.writerows(marginal)

    with MARKDOWN.open("w") as f:
        f.write("# Capability Tier Ladders\n\n")
        f.write("Synopsys DC Y-2026.03-SP1, SAED14nm RVT TT/0.8 V/25 C, identical `compile_ultra -area_high_effort_script -no_autoungroup` flow, 1.000 ns and 0.500 ns max-delay targets, and uniform synthetic activity (static probability 0.5, toggle rate 0.2). Area is total cell area; energy/op is dynamic power divided by achieved Fmax.\n\n")
        f.write("Each row is a capability wrapper synthesized independently. Marginal overhead is measured against the preceding rung in the same family and corner.\n\n")
        for family, tiers in ORDER.items():
            f.write(f"## {family}\n\n")
            f.write("| Tier | Capability | Corner | Area (um2) | Power (mW) | Leakage (uW) | Delay (ns) | Fmax (GHz) | Energy/op (pJ) |\n|---|---|---|---:|---:|---:|---:|---:|---:|\n")
            for tier in tiers:
                for corner in PERIOD:
                    r = by_key.get((family, tier, corner))
                    if r is None: continue
                    f.write(f"| {tier} | {r['capability']} | {corner} | {float(r['cell_area_um2']):.3f} | {float(r['dynamic_power_mw']):.6f} | {float(r['leakage_power_uw']):.6f} | {float(r['achieved_delay_ns']):.6f} | {float(r['fmax_ghz']):.6f} | {float(r['energy_per_operation_pj']):.6f} |\n")
            f.write("\n")
        f.write("## MinMax constraint anomaly\n\n")
        f.write("The integer fixed `minmax_32x2` and `minmax_64` rows in `reports/synth_common_fixed` were produced by separate `compile_ultra -area_high_effort_script` runs at 1.000 ns and 0.500 ns. The tighter constraint can select a different mapped implementation and cell sizing; area is not mathematically monotonic with timing pressure. Therefore `minmax_32x2` shrinking from 138.128398 to 111.088801 um2 while `minmax_64` grows from 103.407600 to 130.491600 um2 is a synthesis result, not evidence of a physical law. Compare each corner using its own report set and do not mix 1 GHz and 2 GHz bank baselines.\n")
    print(f"wrote {len(rows)} PPA rows and {len(marginal)} marginal rows")


if __name__ == "__main__":
    main()
