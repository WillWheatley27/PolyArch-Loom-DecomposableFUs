#!/usr/bin/env python3
"""Collect revised FP compare/min/max DC reports and compute bank savings."""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "revised_fp_fus" / "raw"
OUTDIR = ROOT / "revised_fp_fus"
PPA_OUT = OUTDIR / "ppa.csv"
SAV_OUT = OUTDIR / "savings.csv"
MARG_OUT = OUTDIR / "marginal.csv"
MD_OUT = OUTDIR / "comparison.md"

JOBS = {
    "fp_cmp_rev64": ("fp_cmp", "FP64", ("fp_cmp_64",)),
    "fp_cmp_rev64_32": ("fp_cmp", "FP64/FP32x2", ("fp_cmp_64", "fp_cmp_32x2")),
    "fp_cmp_rev64_32_16": ("fp_cmp", "FP64/FP32x2/FP16x4", ("fp_cmp_64", "fp_cmp_32x2", "fp_cmp_16x4")),
    "fp_minmax_rev64": ("fp_minmax", "FP64", ("fp_minmax_64",)),
    "fp_minmax_rev64_32": ("fp_minmax", "FP64/FP32x2", ("fp_minmax_64", "fp_minmax_32x2")),
    "fp_minmax_rev64_32_16": ("fp_minmax", "FP64/FP32x2/FP16x4", ("fp_minmax_64", "fp_minmax_32x2", "fp_minmax_16x4")),
}
TIERS = ("rev64", "rev64_32", "rev64_32_16")
CORNER_PERIOD = {"one_ghz": 1.0, "two_ghz": 0.5}

PPA_FIELDS = [
    "FU", "family", "tier", "capability", "corner", "target_period_ns",
    "achieved_delay_ns", "fmax_ghz", "cell_area_um2", "total_area_um2",
    "dynamic_power_mw", "leakage_power_uw", "energy_per_operation_pj",
    "timing_met", "activity_source",
]
SAV_FIELDS = [
    "FU", "family", "tier", "capability", "corner",
    "fixed_bank_definition", "fixed_area_um2", "revised_area_um2", "area_saving_percent",
    "fixed_power_mw", "revised_power_mw", "power_saving_percent",
    "fixed_leakage_uw", "revised_leakage_uw", "leakage_saving_percent",
    "fixed_energy_pj", "revised_energy_pj", "energy_saving_percent",
    "fixed_fmax_ghz", "revised_fmax_ghz", "frequency_change_percent",
    "comparison_valid", "notes",
]
MARG_FIELDS = [
    "FU", "family", "from_tier", "to_tier", "capability", "corner",
    "previous_area_um2", "new_area_um2", "area_overhead_percent",
    "previous_power_mw", "new_power_mw", "power_overhead_percent",
    "previous_leakage_uw", "new_leakage_uw", "leakage_overhead_percent",
    "previous_fmax_ghz", "new_fmax_ghz", "frequency_change_percent",
    "comparison_valid", "notes",
]


def num(pattern: str, text: str, default: float = 0.0) -> float:
    m = re.search(pattern, text, re.MULTILINE)
    return float(m.group(1)) if m else default


def power_mw(label: str, text: str) -> float:
    m = re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)", text, re.MULTILINE)
    if not m:
        return 0.0
    scale = {"W": 1000.0, "mW": 1.0, "uW": 1e-3, "nW": 1e-6}
    return float(m.group(1)) * scale[m.group(2)]


def parse_dir(path: Path, period: float) -> dict[str, float | str]:
    result = (path / "result.txt").read_text(errors="replace")
    area = (path / "report_area.rpt").read_text(errors="replace")
    power = (path / "report_power.rpt").read_text(errors="replace")
    delay = num(r"ARRIVAL_NS=([0-9.eE+-]+)", result)
    fmax = num(r"FMAX_GHZ=([0-9.eE+-]+)", result)
    dynamic = power_mw("Total Dynamic Power", power)
    leakage = power_mw("Cell Leakage Power", power) * 1000.0
    return {
        "target_period_ns": period,
        "achieved_delay_ns": delay,
        "fmax_ghz": fmax,
        "cell_area_um2": num(r"Total cell area:\s+([0-9.eE+-]+)", area),
        "total_area_um2": num(r"Total area:\s+([0-9.eE+-]+)", area),
        "dynamic_power_mw": dynamic,
        "leakage_power_uw": leakage,
        "energy_per_operation_pj": dynamic / fmax if fmax else 0.0,
        "timing_met": delay <= period + 1e-6,
    }


def fixed_path(name: str, corner: str) -> Path:
    return ROOT / "synth_common_fixed" / name / corner


def pct(base: float, value: float) -> float:
    return 100.0 * (base - value) / base if base else 0.0


def signed_overhead(old: float, new: float) -> float:
    return 100.0 * (new - old) / old if old else 0.0


def main() -> None:
    ppa_rows: list[dict[str, object]] = []
    fixed_cache: dict[tuple[str, str], dict[str, float | str]] = {}
    for name, (family, capability, components) in JOBS.items():
        tier = name.removeprefix(f"{family}_")
        for corner, period in CORNER_PERIOD.items():
            raw = RAW / name / corner
            if not (raw / "result.txt").exists():
                continue
            m = parse_dir(raw, period)
            ppa_rows.append({"FU": name, "family": family, "tier": tier,
                             "capability": capability, "corner": corner,
                             "activity_source": "uniform_synthetic", **m})
            for component in components:
                key = (component, corner)
                if key not in fixed_cache:
                    fixed_cache[key] = parse_dir(fixed_path(component, corner), period)

    OUTDIR.mkdir(parents=True, exist_ok=True)
    with PPA_OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=PPA_FIELDS)
        w.writeheader(); w.writerows(ppa_rows)

    savings_rows: list[dict[str, object]] = []
    for row in ppa_rows:
        components = JOBS[row["FU"]][2]  # type: ignore[index]
        fixed = [fixed_cache[(c, row["corner"])] for c in components]  # type: ignore[index]
        valid = bool(row["timing_met"]) and all(bool(x["timing_met"]) for x in fixed)
        fa = sum(float(x["cell_area_um2"]) for x in fixed)
        fp = sum(float(x["dynamic_power_mw"]) for x in fixed)
        fl = sum(float(x["leakage_power_uw"]) for x in fixed)
        ff = min(float(x["fmax_ghz"]) for x in fixed)
        fe = fp / ff if ff else 0.0
        ra, rp, rl, rf, re = (float(row[k]) for k in ("cell_area_um2", "dynamic_power_mw", "leakage_power_uw", "fmax_ghz", "energy_per_operation_pj"))
        savings_rows.append({
            "FU": row["FU"], "family": row["family"], "tier": row["tier"], "capability": row["capability"], "corner": row["corner"],
            "fixed_bank_definition": " + ".join(components) + " (packed components counted once)",
            "fixed_area_um2": fa, "revised_area_um2": ra, "area_saving_percent": pct(fa, ra),
            "fixed_power_mw": fp, "revised_power_mw": rp, "power_saving_percent": pct(fp, rp),
            "fixed_leakage_uw": fl, "revised_leakage_uw": rl, "leakage_saving_percent": pct(fl, rl),
            "fixed_energy_pj": fe, "revised_energy_pj": re, "energy_saving_percent": pct(fe, re),
            "fixed_fmax_ghz": ff, "revised_fmax_ghz": rf, "frequency_change_percent": signed_overhead(ff, rf),
            "comparison_valid": valid,
            "notes": "common-frequency comparison; uniform synthetic activity; negative savings are penalties",
        })
    with SAV_OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=SAV_FIELDS); w.writeheader(); w.writerows(savings_rows)

    marginal_rows: list[dict[str, object]] = []
    for family in ("fp_cmp", "fp_minmax"):
        for corner in CORNER_PERIOD:
            rows = [r for r in ppa_rows if r["family"] == family and r["corner"] == corner]
            by_tier = {r["tier"]: r for r in rows}
            for old_tier, new_tier in (("rev64", "rev64_32"), ("rev64_32", "rev64_32_16")):
                if old_tier not in by_tier or new_tier not in by_tier: continue
                old, new = by_tier[old_tier], by_tier[new_tier]
                marginal_rows.append({
                    "FU": new["FU"], "family": family, "from_tier": old_tier, "to_tier": new_tier,
                    "capability": new["capability"], "corner": corner,
                    "previous_area_um2": old["cell_area_um2"], "new_area_um2": new["cell_area_um2"], "area_overhead_percent": signed_overhead(float(old["cell_area_um2"]), float(new["cell_area_um2"])),
                    "previous_power_mw": old["dynamic_power_mw"], "new_power_mw": new["dynamic_power_mw"], "power_overhead_percent": signed_overhead(float(old["dynamic_power_mw"]), float(new["dynamic_power_mw"])),
                    "previous_leakage_uw": old["leakage_power_uw"], "new_leakage_uw": new["leakage_power_uw"], "leakage_overhead_percent": signed_overhead(float(old["leakage_power_uw"]), float(new["leakage_power_uw"])),
                    "previous_fmax_ghz": old["fmax_ghz"], "new_fmax_ghz": new["fmax_ghz"], "frequency_change_percent": signed_overhead(float(old["fmax_ghz"]), float(new["fmax_ghz"])),
                    "comparison_valid": bool(old["timing_met"]) and bool(new["timing_met"]),
                    "notes": "marginal capability overhead; uniform synthetic activity",
                })
    with MARG_OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=MARG_FIELDS); w.writeheader(); w.writerows(marginal_rows)

    with MD_OUT.open("w") as f:
        f.write("# Revised FP compare/min/max PPA\n\n")
        f.write("Synopsys DC Y-2026.03-SP1, SAED14nm RVT TT/0.8 V/25 C, identical compile settings and uniform synthetic activity (static probability 0.5, toggle rate 0.2). Area is total cell area; power is dynamic power; energy/op is dynamic power/Fmax.\n\n")
        f.write("The revised wrappers elaborate only the advertised capability. `rev64` is FP64-only, `rev64_32` adds 2xFP32, and `rev64_32_16` adds 4xFP16. Reserved modes fall back to FP64.\n\n")
        f.write("## PPA and savings\n\n")
        f.write("| FU | Corner | Area (um2) | Power (mW) | Leakage (uW) | Fmax (GHz) | Bank area | Area saving | Power saving | Leakage saving | Valid |\n|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|\n")
        for r in savings_rows:
            f.write(f"| {r['FU']} | {r['corner']} | {r['revised_area_um2']:.3f} | {r['revised_power_mw']:.6f} | {r['revised_leakage_uw']:.6f} | {r['revised_fmax_ghz']:.6f} | {r['fixed_area_um2']:.3f} | {r['area_saving_percent']:.2f}% | {r['power_saving_percent']:.2f}% | {r['leakage_saving_percent']:.2f}% | {str(r['comparison_valid']).lower()} |\n")
        f.write("\n## Marginal capability overhead\n\n")
        f.write("| FU | Corner | Added capability | Area overhead | Power overhead | Leakage overhead | Fmax change |\n|---|---|---|---:|---:|---:|---:|\n")
        for r in marginal_rows:
            f.write(f"| {r['FU']} | {r['corner']} | {r['from_tier']} -> {r['to_tier']} | {r['area_overhead_percent']:.2f}% | {r['power_overhead_percent']:.2f}% | {r['leakage_overhead_percent']:.2f}% | {r['frequency_change_percent']:.2f}% |\n")
        f.write("\nNegative savings are penalties. These are pre-layout synthetic DC estimates, not workload-based power claims. Raw reports are under `raw/`; CSV data are in `ppa.csv`, `savings.csv`, and `marginal.csv`.\n")
    print(f"wrote {len(ppa_rows)} PPA rows, {len(savings_rows)} savings rows, {len(marginal_rows)} marginal rows")


if __name__ == "__main__":
    main()
