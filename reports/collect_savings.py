#!/usr/bin/env python3
"""Create the required savings table from normalized PPA rows.

Rows are marked invalid until all fixed-bank components for the same FU and
corner have been synthesized by the normalized fixed flow. This prevents old
area/speed-corner reports from being accidentally presented as apples-to-apples
savings.
"""
from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PPA = ROOT / "ppa_summary.csv"
OUT = ROOT / "savings_summary.csv"
FIELDS = [
    "FU", "capability", "corner", "fixed_area_um2", "decomposable_area_um2",
    "area_saving_percent", "fixed_power_mw", "decomposable_power_mw",
    "power_saving_percent", "fixed_leakage_uw", "decomposable_leakage_uw",
    "leakage_saving_percent", "fixed_energy_pj", "decomposable_energy_pj",
    "energy_saving_percent", "fixed_fmax_ghz", "decomposable_fmax_ghz",
    "frequency_change_percent", "comparison_valid", "notes",
]

# Normalized fixed flow names for packed bank components. A fixed bank is one
# 64-bit component + one already-packed 2x32 component + one already-packed
# 4x16 component; packed components must not be multiplied again.
BANK = {
    "addsub_d4": ("addsub_64", "addsub_32x2", "addsub_16x4"),
    "mult_decomp": ("mult_64", "mult_32x2", "mult_16x4"),
    "minmax_m4": ("minmax_64", "minmax_32x2", "minmax_16x4"),
    "fp_minmax_m3": ("fp_minmax_64", "fp_minmax_32x2", "fp_minmax_16x4"),
    "fp_cmp_g3": ("fp_cmp_64", "fp_cmp_32x2", "fp_cmp_16x4"),
    "cmp_c4": ("cmp_64", "cmp_32x2", "cmp_16x4"),
    "rounding_g3": ("rounding_64", "rounding_32x2", "rounding_16x4"),
    "barrel_bs3": ("barrel_64", "barrel_32x2", "barrel_16x4"),
    "abs_a3": ("abs_64", "abs_32x2", "abs_16x4"),
}


def pct(fixed: float, new: float) -> float:
    return 100.0 * (fixed - new) / fixed if fixed else 0.0


def main() -> None:
    rows = list(csv.DictReader(PPA.open())) if PPA.exists() else []
    # Fixed rows will be appended by collect_ppa.py once normalized fixed
    # synthesis completes. Until then, every savings row is explicit pending.
    fixed = {(r["FU"], r["corner"]): r for r in rows if r["implementation"] == "fixed"}
    out_rows = []
    for dec in (r for r in rows if r["implementation"] == "decomposable"):
        fu, corner = dec["FU"], dec["corner"]
        components = BANK.get(fu, ())
        comps = [fixed.get((c, corner)) for c in components]
        valid = all(comps) and all(c["timing_met"] == "true" for c in comps) and dec["timing_met"] == "true"
        notes = "normalized fixed-bank components pending"
        if dec["timing_met"] != "true":
            notes += "; decomposable design misses target"
        vals = {k: "" for k in FIELDS}
        vals.update({"FU": fu, "capability": dec["capability"], "corner": corner,
                     "decomposable_area_um2": dec["cell_area_um2"],
                     "decomposable_power_mw": dec["dynamic_power_mw"],
                     "decomposable_leakage_uw": dec["leakage_power_uw"],
                     "decomposable_energy_pj": dec["energy_per_operation_pj"],
                     "decomposable_fmax_ghz": dec["fmax_ghz"],
                     "comparison_valid": str(valid).lower(), "notes": notes})
        if valid:
            # Use Design Compiler Total cell area for the Area(FU) formula.
            # Total area includes wire-load interconnect estimation and is kept
            # separately in ppa_summary.csv but is not the standard cell-area
            # PPA metric used by the source tables.
            area = sum(float(c["cell_area_um2"]) for c in comps)
            power = sum(float(c["dynamic_power_mw"]) for c in comps)
            leak = sum(float(c["leakage_power_uw"]) for c in comps)
            # Bank frequency is limited by its slowest component.
            fmax = min(float(c["fmax_ghz"]) for c in comps)
            energy = power / fmax if fmax else 0.0
            vals.update({"fixed_area_um2": f"{area:.6f}", "area_saving_percent": f"{pct(area, float(dec['cell_area_um2'])):.6f}",
                         "fixed_power_mw": f"{power:.6f}", "power_saving_percent": f"{pct(power, float(dec['dynamic_power_mw'])):.6f}",
                         "fixed_leakage_uw": f"{leak:.6f}", "leakage_saving_percent": f"{pct(leak, float(dec['leakage_power_uw'])):.6f}",
                         "fixed_energy_pj": f"{energy:.6f}", "energy_saving_percent": f"{pct(energy, float(dec['energy_per_operation_pj'])):.6f}",
                         "fixed_fmax_ghz": f"{fmax:.9f}",
                         "frequency_change_percent": f"{100.0 * (float(dec['fmax_ghz']) - fmax) / fmax if fmax else 0.0:.6f}",
                         "notes": ("normalized fixed bank; packed FU32/FU16 counted once; "
                                   + ("family feasible-frequency target" if corner == "feasible" else "common operating-point target"))})
        out_rows.append(vals)
    with OUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(out_rows)
    print(f"wrote {len(out_rows)} rows to {OUT}")


if __name__ == "__main__":
    main()
