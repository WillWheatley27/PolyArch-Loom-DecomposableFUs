#!/usr/bin/env python3
"""Compute explicit fixed-bank power assumptions from normalized PPA rows.

The DC runs use uniform synthetic activity. This file does not pretend to turn
that into workload power; it only exposes the two fixed-bank interpretations
requested by the methodology: every bank component active versus only the
selected component active under the documented mode probabilities.
"""
from pathlib import Path
import csv

ROOT = Path(__file__).resolve().parent
PPA = ROOT / "ppa_summary.csv"
OUT = ROOT / "power_mode_summary.csv"
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
OUT_FIELDS = ["FU", "corner", "p64", "p32", "p16", "fixed_all_active_mw",
              "fixed_selected_only_estimate_mw", "decomposable_uniform_mw",
              "notes"]
rows = list(csv.DictReader(PPA.open())) if PPA.exists() else []
by_key = {(r["FU"], r["corner"]): r for r in rows if r["implementation"] == "fixed"}
decomp = {(r["FU"], r["corner"]): r for r in rows if r["implementation"] == "decomposable"}
out = []
for (fu, corner), d in sorted(decomp.items()):
    comps = [by_key.get((name, corner)) for name in BANK.get(fu, ())]
    if not all(comps):
        continue
    powers = [float(c["dynamic_power_mw"]) for c in comps]
    all_active = sum(powers)
    selected = 0.25 * powers[0] + 0.50 * powers[1] + 0.25 * powers[2]
    out.append({"FU": fu, "corner": corner, "p64": "0.25", "p32": "0.50", "p16": "0.25",
                "fixed_all_active_mw": f"{all_active:.6f}",
                "fixed_selected_only_estimate_mw": f"{selected:.6f}",
                "decomposable_uniform_mw": d["dynamic_power_mw"],
                "notes": "fixed selected-only is probability-weighted synthetic estimate; decomposable remains uniform synthetic"})
with OUT.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=OUT_FIELDS); w.writeheader(); w.writerows(out)
print(f"wrote {len(out)} rows to {OUT}")
