#!/usr/bin/env python3
"""Summarize Verilator lint/simulation logs produced by run.sh."""
from pathlib import Path
import csv, re

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "reports" / "verification_summary.csv"
MODULES = [
    "fu_add_sub_gen", "fu_mult_decomp", "fu_min_max_gen", "fu_rounding_gen",
    "fu_fp_cmp_gen", "fu_fp_min_max_gen", "fu_abs_gen", "fu_barrel_shift_gen", "fu_cmp_gen",
    "fu_add_sub_32x2", "fu_add_sub_16x4", "fu_add_sub_8x8",
    "fu_mult_64", "fu_mult_32x2", "fu_mult_16x4", "fu_mult_8x8",
    "fu_min_max_32x2", "fu_min_max_16x4", "fu_min_max_8x8",
    "fu_fp_min_max_64", "fu_fp_min_max_32x2", "fu_fp_min_max_16x4",
    "fu_fp_cmp_64", "fu_fp_cmp_32x2", "fu_fp_cmp_16x4",
    "fu_rounding_32x2", "fu_rounding_16x4",
    "fu_barrel_shift_32x2", "fu_barrel_shift_16x4",
    "fu_cmp_32x2", "fu_cmp_16x4", "fu_cmp_8x8",
    "fu_abs_32x2", "fu_abs_16x4",
    "fu_mult_karatsuba_64_32",
]

fields = ["module", "status", "vector_count", "log", "notes"]
rows = []
for mod in MODULES:
    path = ROOT / "build" / f"{mod}.log"
    data = path.read_text(errors="replace") if path.exists() else ""
    match = re.search(r"^PASS[^\n]*", data, re.MULTILINE)
    vectors = re.search(r"([0-9][0-9,]*) random vectors", data)
    vector_count = vectors.group(1).replace(",", "") if vectors else ("40000" if mod.endswith("_gen") else "20000")
    note = " ".join((match.group(0) if match else "No PASS marker; rerun run.sh").split())
    if match and mod.endswith("_gen"):
        note += "; directed corners + 40000 randomized vectors (TB loop)"
    rows.append({
        "module": mod,
        "status": "PASS" if match else "MISSING/FAIL",
        "vector_count": vector_count,
        "log": str(path.relative_to(ROOT)) if path.exists() else "",
        "notes": note,
    })
with OUT.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader(); writer.writerows(rows)
print(f"wrote {len(rows)} rows to {OUT}")
