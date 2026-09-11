#!/usr/bin/env python3
"""Collect the controlled Karatsuba/DesignWare multiplier comparison."""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "mult_karatsuba_comparison"
PPA_OUT = ROOT / "mult_karatsuba_ppa.csv"
SAVINGS_OUT = ROOT / "mult_karatsuba_savings.csv"

PPA_FIELDS = [
    "FU", "name", "implementation", "capability", "corner",
    "target_period_ns", "achieved_delay_ns", "fmax_ghz", "cell_area_um2",
    "total_area_um2", "dynamic_power_mw", "leakage_power_uw",
    "energy_per_operation_pj", "timing_met", "activity_source", "notes",
]
SAVINGS_FIELDS = [
    "FU", "corner", "baseline", "fixed_bank_definition",
    "fixed_area_um2", "decomposable_area_um2", "area_saving_percent",
    "fixed_power_mw", "decomposable_power_mw", "power_saving_percent",
    "fixed_leakage_uw", "decomposable_leakage_uw", "leakage_saving_percent",
    "fixed_energy_pj", "decomposable_energy_pj", "energy_saving_percent",
    "fixed_fmax_ghz", "decomposable_fmax_ghz", "frequency_change_percent",
    "comparison_valid", "notes",
]


def number(pattern: str, text: str) -> float:
    match = re.search(pattern, text, re.MULTILINE)
    return float(match.group(1)) if match else 0.0


def metadata(key: str, text: str) -> str:
    match = re.search(rf"(?:^|\s){key}=([^\s]+)", text)
    return match.group(1) if match else ""


def power_mw(label: str, text: str) -> float:
    match = re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)", text)
    if not match:
        return 0.0
    return float(match.group(1)) * {"W": 1000.0, "mW": 1.0, "uW": 1e-3, "nW": 1e-6}[match.group(2)]


def pct(fixed: float, decomposable: float) -> float:
    return 100.0 * (fixed - decomposable) / fixed if fixed else 0.0


def collect_ppa() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for corner_dir in sorted(p for p in SRC.iterdir() if p.is_dir()):
        for design_dir in sorted(p for p in corner_dir.iterdir() if p.is_dir()):
            result = (design_dir / "result.txt").read_text(errors="replace")
            area = (design_dir / "report_area.rpt").read_text(errors="replace")
            power = (design_dir / "report_power.rpt").read_text(errors="replace")
            period = number(r"TARGET_PERIOD_NS=([0-9.eE+-]+)", result)
            delay = number(r"ARRIVAL_NS=([0-9.eE+-]+)", result)
            fmax = number(r"FMAX_GHZ=([0-9.eE+-]+)", result)
            dynamic = power_mw("Total Dynamic Power", power)
            cell_area = number(r"Total cell area:\s+([0-9.eE+-]+)", area)
            total_area = number(r"Total area:\s+([0-9.eE+-]+)", area)
            rows.append({
                "FU": "Mult",
                "name": design_dir.name,
                "implementation": metadata("IMPLEMENTATION", result),
                "capability": metadata("CAPABILITY", result),
                "corner": corner_dir.name,
                "target_period_ns": f"{period:.6f}",
                "achieved_delay_ns": f"{delay:.6f}",
                "fmax_ghz": f"{fmax:.9f}",
                "cell_area_um2": f"{cell_area:.6f}",
                "total_area_um2": f"{total_area:.6f}",
                "dynamic_power_mw": f"{dynamic:.6f}",
                "leakage_power_uw": f"{power_mw('Cell Leakage Power', power)*1000.0:.6f}",
                "energy_per_operation_pj": f"{dynamic/fmax if fmax else 0.0:.6f}",
                "timing_met": str(delay <= period + 1e-6).lower(),
                "activity_source": "uniform_synthetic",
                "notes": ("primary equal-target comparison" if corner_dir.name == "one_ghz"
                          else "0.010 ns timing stress; power is not equal-achieved-frequency"),
            })
    return rows


def collect_savings(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    by_key = {(r["corner"], r["name"]): r for r in rows}
    banks = {
        "Karatsuba fixed bank": (
            "karatsuba_fixed_64", "karatsuba_fixed_32x2", "karatsuba_fixed_16x4"
        ),
        "DesignWare fixed bank": (
            "designware_fixed_64", "designware_fixed_32x2", "designware_fixed_16x4"
        ),
    }
    out: list[dict[str, str]] = []
    for corner in sorted({r["corner"] for r in rows}):
        dec = by_key[(corner, "karatsuba_decomposable")]
        for baseline, names in banks.items():
            components = [by_key[(corner, name)] for name in names]
            area = sum(float(c["cell_area_um2"]) for c in components)
            power = sum(float(c["dynamic_power_mw"]) for c in components)
            leakage = sum(float(c["leakage_power_uw"]) for c in components)
            bank_fmax = min(float(c["fmax_ghz"]) for c in components)
            bank_energy = power / bank_fmax if bank_fmax else 0.0
            dec_area = float(dec["cell_area_um2"])
            dec_power = float(dec["dynamic_power_mw"])
            dec_leak = float(dec["leakage_power_uw"])
            dec_fmax = float(dec["fmax_ghz"])
            dec_energy = dec_power / dec_fmax if dec_fmax else 0.0
            equal_target_valid = corner == "one_ghz" and dec["timing_met"] == "true" and all(
                c["timing_met"] == "true" for c in components
            )
            out.append({
                "FU": "Mult",
                "corner": corner,
                "baseline": baseline,
                "fixed_bank_definition": f"{names[0]} + {names[1]} + {names[2]}",
                "fixed_area_um2": f"{area:.6f}",
                "decomposable_area_um2": f"{dec_area:.6f}",
                "area_saving_percent": f"{pct(area, dec_area):.6f}",
                "fixed_power_mw": f"{power:.6f}",
                "decomposable_power_mw": f"{dec_power:.6f}",
                "power_saving_percent": f"{pct(power, dec_power):.6f}",
                "fixed_leakage_uw": f"{leakage:.6f}",
                "decomposable_leakage_uw": f"{dec_leak:.6f}",
                "leakage_saving_percent": f"{pct(leakage, dec_leak):.6f}",
                "fixed_energy_pj": f"{bank_energy:.6f}",
                "decomposable_energy_pj": f"{dec_energy:.6f}",
                "energy_saving_percent": f"{pct(bank_energy, dec_energy):.6f}",
                "fixed_fmax_ghz": f"{bank_fmax:.9f}",
                "decomposable_fmax_ghz": f"{dec_fmax:.9f}",
                "frequency_change_percent": f"{100.0*(dec_fmax-bank_fmax)/bank_fmax if bank_fmax else 0.0:.6f}",
                "comparison_valid": str(equal_target_valid).lower(),
                "notes": ("valid 1 GHz equal-target comparison; packed 32x2/16x4 counted once; synthetic all-active bank power"
                          if equal_target_valid else
                          "maximum-speed stress comparison only; use area/leakage/Fmax, not raw power as equal-frequency savings"),
            })
    return out


def main() -> None:
    rows = collect_ppa()
    with PPA_OUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=PPA_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    savings = collect_savings(rows)
    with SAVINGS_OUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=SAVINGS_FIELDS)
        writer.writeheader()
        writer.writerows(savings)
    print(f"wrote {len(rows)} rows to {PPA_OUT}")
    print(f"wrote {len(savings)} rows to {SAVINGS_OUT}")


if __name__ == "__main__":
    main()
