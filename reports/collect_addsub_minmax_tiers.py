#!/usr/bin/env python3
"""Collect and compare AddSub-MinMax decomposability tiers."""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "addsub_minmax_tiers"
PPA_OUT = ROOT / "addsub_minmax_tier_ppa.csv"
SAVINGS_OUT = ROOT / "addsub_minmax_tier_savings.csv"
MARGINAL_OUT = ROOT / "addsub_minmax_tier_marginal.csv"

PPA_FIELDS = ["name", "kind", "tier", "corner", "target_period_ns",
              "achieved_delay_ns", "fmax_ghz", "cell_area_um2",
              "total_area_um2", "dynamic_power_mw", "leakage_power_uw",
              "energy_per_operation_pj", "timing_met", "activity_source"]
SAVINGS_FIELDS = ["tier", "corner", "baseline", "baseline_definition",
                  "baseline_area_um2", "combined_area_um2", "area_saving_percent",
                  "baseline_power_mw", "combined_power_mw", "power_saving_percent",
                  "baseline_leakage_uw", "combined_leakage_uw", "leakage_saving_percent",
                  "baseline_energy_pj", "combined_energy_pj", "energy_saving_percent",
                  "baseline_fmax_ghz", "combined_fmax_ghz", "frequency_change_percent",
                  "comparison_valid", "notes"]
MARGINAL_FIELDS = ["tier", "corner", "reference", "reference_definition",
                   "reference_area_um2", "side_function_area_um2", "area_saving_percent",
                   "reference_power_mw", "side_function_power_mw", "power_saving_percent",
                   "reference_leakage_uw", "side_function_leakage_uw", "leakage_saving_percent",
                   "comparison_valid", "notes"]


def n(pattern: str, text: str) -> float:
    match = re.search(pattern, text, re.MULTILINE)
    return float(match.group(1)) if match else 0.0


def meta(key: str, text: str) -> str:
    match = re.search(rf"(?:^|\s){key}=([^\s]+)", text)
    return match.group(1) if match else ""


def power_mw(label: str, text: str) -> float:
    match = re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)", text)
    if not match:
        return 0.0
    return float(match.group(1)) * {"W": 1000, "mW": 1, "uW": 1e-3, "nW": 1e-6}[match.group(2)]


def pct(reference: float, combined: float) -> float:
    return 100.0 * (reference - combined) / reference if reference else 0.0


def collect_ppa() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for corner_dir in sorted(path for path in SRC.iterdir() if path.is_dir()):
        for design_dir in sorted(path for path in corner_dir.iterdir() if path.is_dir()):
 
            result = (design_dir / "result.txt").read_text(errors="replace")
            area = (design_dir / "report_area.rpt").read_text(errors="replace")
            power = (design_dir / "report_power.rpt").read_text(errors="replace")
            period = n(r"TARGET_PERIOD_NS=([0-9.eE+-]+)", result)
            delay = n(r"ARRIVAL_NS=([0-9.eE+-]+)", result)
            fmax = n(r"FMAX_GHZ=([0-9.eE+-]+)", result)
            dynamic = power_mw("Total Dynamic Power", power)
            cell_area = n(r"Total cell area:\s+([0-9.eE+-]+)", area)
            total_area = n(r"Total area:\s+([0-9.eE+-]+)", area)
            rows.append({
                "name": design_dir.name, "kind": meta("KIND", result),
                "tier": meta("TIER", result), "corner": corner_dir.name,
                "target_period_ns": f"{period:.6f}",
                "achieved_delay_ns": f"{delay:.6f}", "fmax_ghz": f"{fmax:.9f}",
                "cell_area_um2": f"{cell_area:.6f}", "total_area_um2": f"{total_area:.6f}",
                "dynamic_power_mw": f"{dynamic:.6f}",
                "leakage_power_uw": f"{power_mw('Cell Leakage Power', power)*1000:.6f}",
                "energy_per_operation_pj": f"{dynamic/fmax if fmax else 0.0:.6f}",
                "timing_met": str(delay <= period + 1e-6).lower(),
                "activity_source": "uniform_synthetic",
            })
    return rows


def add_values(*rows: dict[str, str]) -> dict[str, float | bool]:
    power = sum(float(row["dynamic_power_mw"]) for row in rows)
    fmax = min(float(row["fmax_ghz"]) for row in rows)
    return {
        "area": sum(float(row["cell_area_um2"]) for row in rows),
        "power": power,
        "leakage": sum(float(row["leakage_power_uw"]) for row in rows),
        "fmax": fmax, "energy": power/fmax if fmax else 0.0,
        "valid": all(row["timing_met"] == "true" for row in rows),
    }


def comparisons(rows: list[dict[str, str]]) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    by_key = {(row["corner"], row["name"]): row for row in rows}
    tiers = {
        "64": ("combined_d1", "addsub_d1", "minmax_m1", ("minmax_fixed_64",)),
        "64_32": ("combined_d2", "addsub_d2", "minmax_m2",
                  ("minmax_fixed_64", "minmax_fixed_32x2")),
        "64_32_16": ("combined_d4", "addsub_d4", "minmax_m4",
                     ("minmax_fixed_64", "minmax_fixed_32x2", "minmax_fixed_16x4")),
    }
    savings: list[dict[str, str]] = []
    marginal: list[dict[str, str]] = []
    for corner in sorted({row["corner"] for row in rows}):
        for tier, (combined_name, add_name, mm_name, fixed_names) in tiers.items():
            combined_row = by_key[(corner, combined_name)]
            add_row = by_key[(corner, add_name)]
            mm_row = by_key[(corner, mm_name)]
            fixed_rows = [by_key[(corner, name)] for name in fixed_names]
            combined = add_values(combined_row)
            baselines = {
                "separate_decomposable": (
                    add_values(add_row, mm_row), f"{add_name} + {mm_name}",
                    "same-tier decomposable AddSub plus decomposable MinMax"),
                "decomposable_addsub_plus_fixed_minmax_bank": (
                    add_values(add_row, *fixed_rows), f"{add_name} + " + " + ".join(fixed_names),
                    "packed fixed MinMax components counted once; synthetic all-active bank power"),
            }
            for baseline_name, (baseline, definition, notes) in baselines.items():
                valid = bool(combined["valid"] and baseline["valid"])
                savings.append({
                    "tier": tier, "corner": corner, "baseline": baseline_name,
                    "baseline_definition": definition,
                    "baseline_area_um2": f"{baseline['area']:.6f}",
                    "combined_area_um2": f"{combined['area']:.6f}",
                    "area_saving_percent": f"{pct(float(baseline['area']), float(combined['area'])):.6f}",
                    "baseline_power_mw": f"{baseline['power']:.6f}",
                    "combined_power_mw": f"{combined['power']:.6f}",
                    "power_saving_percent": f"{pct(float(baseline['power']), float(combined['power'])):.6f}",
                    "baseline_leakage_uw": f"{baseline['leakage']:.6f}",
                    "combined_leakage_uw": f"{combined['leakage']:.6f}",
                    "leakage_saving_percent": f"{pct(float(baseline['leakage']), float(combined['leakage'])):.6f}",
                    "baseline_energy_pj": f"{baseline['energy']:.6f}",
                    "combined_energy_pj": f"{combined['energy']:.6f}",
                    "energy_saving_percent": f"{pct(float(baseline['energy']), float(combined['energy'])):.6f}",
                    "baseline_fmax_ghz": f"{baseline['fmax']:.9f}",
                    "combined_fmax_ghz": f"{combined['fmax']:.9f}",
                    "frequency_change_percent": f"{100*(float(combined['fmax'])-float(baseline['fmax']))/float(baseline['fmax']):.6f}",
                    "comparison_valid": str(valid).lower(), "notes": notes,
                })

            side = {
                "area": float(combined_row["cell_area_um2"]) - float(add_row["cell_area_um2"]),
                "power": float(combined_row["dynamic_power_mw"]) - float(add_row["dynamic_power_mw"]),
                "leakage": float(combined_row["leakage_power_uw"]) - float(add_row["leakage_power_uw"]),
            }
            references = {
                "decomposable_minmax": (add_values(mm_row), mm_name,
                    "marginal combined-minus-AddSub cost versus same-tier decomposable MinMax"),
                "fixed_minmax_bank": (add_values(*fixed_rows), " + ".join(fixed_names),
                    "marginal combined-minus-AddSub cost versus fixed MinMax bank"),
            }
            for reference_name, (reference, definition, notes) in references.items():
                valid = bool(combined["valid"] and add_row["timing_met"] == "true" and reference["valid"])
                marginal.append({
                    "tier": tier, "corner": corner, "reference": reference_name,
                    "reference_definition": definition,
                    "reference_area_um2": f"{reference['area']:.6f}",
                    "side_function_area_um2": f"{side['area']:.6f}",
                    "area_saving_percent": f"{pct(float(reference['area']), side['area']):.6f}",
                    "reference_power_mw": f"{reference['power']:.6f}",
                    "side_function_power_mw": f"{side['power']:.6f}",
                    "power_saving_percent": f"{pct(float(reference['power']), side['power']):.6f}",
                    "reference_leakage_uw": f"{reference['leakage']:.6f}",
                    "side_function_leakage_uw": f"{side['leakage']:.6f}",
                    "leakage_saving_percent": f"{pct(float(reference['leakage']), side['leakage']):.6f}",
                    "comparison_valid": str(valid).lower(), "notes": notes,
                })
    return savings, marginal


def write(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader(); writer.writerows(rows)


def main() -> None:
    ppa = collect_ppa()
    savings, marginal = comparisons(ppa)
    write(PPA_OUT, PPA_FIELDS, ppa)
    write(SAVINGS_OUT, SAVINGS_FIELDS, savings)
    write(MARGINAL_OUT, MARGINAL_FIELDS, marginal)
    print(f"wrote {len(ppa)} rows to {PPA_OUT}")
    print(f"wrote {len(savings)} rows to {SAVINGS_OUT}")
    print(f"wrote {len(marginal)} rows to {MARGINAL_OUT}")


if __name__ == "__main__":
    main()
