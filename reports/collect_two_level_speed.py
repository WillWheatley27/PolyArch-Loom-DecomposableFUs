#!/usr/bin/env python3
"""Collect the two-level FP min/max speed-corner experiment into two_level_speed.csv.

Decomposable reports and the new fixed FP32 / FP16x2 baselines are under
revised_fp_fus/two_level_speed/raw; the FP64 and packed FP32 fixed speed reports
are reused from synth_maxspeed_fixed. Bank Fmax is the slowest component.
"""
from __future__ import annotations

import csv
from pathlib import Path

from collect_tier_ladders import parse

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "revised_fp_fus" / "two_level_speed" / "raw"
FIXED = ROOT / "synth_maxspeed_fixed"
OUT = ROOT / "revised_fp_fus" / "two_level_speed.csv"
PERIOD = 0.010

EXPERIMENTS = [
    ("fp64_to_fp32x2", "fp_minmax_rev64_32", RAW / "fp_minmax_rev64_32",
     "fp_minmax_64 + fp_minmax_32x2", [FIXED / "fp_minmax_64", FIXED / "fp_minmax_32x2"]),
    ("fp32_to_fp16x2", "fp_minmax_rev32_16", RAW / "fp_minmax_rev32_16",
     "fp_minmax_fixed_32 + fp_minmax_fixed_16x2", [RAW / "fp_minmax_fixed_32", RAW / "fp_minmax_fixed_16x2"]),
]
FIELDS = [
    "experiment", "decomposable_fu", "fixed_bank_definition",
    "fixed_area_um2", "decomposable_area_um2", "area_saving_percent",
    "fixed_power_mw", "decomposable_power_mw", "power_saving_percent",
    "fixed_leakage_uw", "decomposable_leakage_uw", "leakage_saving_percent",
    "fixed_fmax_ghz", "decomposable_fmax_ghz", "fixed_energy_pj", "decomposable_energy_pj",
    "energy_saving_percent", "frequency_change_percent", "timing_target_ns",
    "comparison_valid", "activity_source",
]


def saving(fixed: float, decomp: float) -> float:
    return 100.0 * (fixed - decomp) / fixed


def main() -> None:
    rows = []
    for name, fu, decomp_dir, bank_def, bank_dirs in EXPERIMENTS:
        d = parse(decomp_dir, PERIOD)
        bank = [parse(p, PERIOD) for p in bank_dirs]
        area = sum(float(b["cell_area_um2"]) for b in bank)
        power = sum(float(b["dynamic_power_mw"]) for b in bank)
        leak = sum(float(b["leakage_power_uw"]) for b in bank)
        fmax = min(float(b["fmax_ghz"]) for b in bank)
        d_area, d_power = float(d["cell_area_um2"]), float(d["dynamic_power_mw"])
        d_leak, d_fmax = float(d["leakage_power_uw"]), float(d["fmax_ghz"])
        energy, d_energy = power / fmax, d_power / d_fmax
        rows.append({
            "experiment": name, "decomposable_fu": fu, "fixed_bank_definition": bank_def,
            "fixed_area_um2": f"{area:.6f}", "decomposable_area_um2": f"{d_area:.6f}",
            "area_saving_percent": f"{saving(area, d_area):.6f}",
            "fixed_power_mw": f"{power:.7f}", "decomposable_power_mw": f"{d_power:.7f}",
            "power_saving_percent": f"{saving(power, d_power):.6f}",
            "fixed_leakage_uw": f"{leak:.7f}", "decomposable_leakage_uw": f"{d_leak:.7f}",
            "leakage_saving_percent": f"{saving(leak, d_leak):.6f}",
            "fixed_fmax_ghz": f"{fmax:.9f}", "decomposable_fmax_ghz": f"{d_fmax:.9f}",
            "fixed_energy_pj": f"{energy:.7f}", "decomposable_energy_pj": f"{d_energy:.7f}",
            "energy_saving_percent": f"{saving(energy, d_energy):.6f}",
            "frequency_change_percent": f"{100.0 * (d_fmax - fmax) / fmax:.6f}",
            "timing_target_ns": f"{PERIOD:.3f}", "comparison_valid": "true",
            "activity_source": "uniform_synthetic",
        })
    with OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, lineterminator="\n")
        w.writeheader(); w.writerows(rows)
    for r in rows:
        print(r["experiment"], r["decomposable_area_um2"], r["area_saving_percent"])


if __name__ == "__main__":
    main()
