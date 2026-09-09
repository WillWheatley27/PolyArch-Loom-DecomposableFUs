#!/usr/bin/env python3
"""Collect the 0.010 ns decomposable timing-stress reports."""
from pathlib import Path
import csv, re

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "synth_maxspeed_decomp"
OUT = ROOT / "maxspeed_summary.csv"
FIELDS = ["FU", "target_period_ns", "achieved_delay_ns", "fmax_ghz",
          "cell_area_um2", "total_area_um2", "dynamic_power_mw",
          "leakage_power_uw", "timing_met", "activity_source", "notes"]

def n(pattern, text):
    m = re.search(pattern, text, re.M)
    return float(m.group(1)) if m else 0.0

def power(label, text):
    m = re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)", text, re.M)
    if not m: return 0.0
    return float(m.group(1)) * {"W":1000.0, "mW":1.0, "uW":1e-3, "nW":1e-6}[m.group(2)]

rows = []
for d in sorted(p for p in SRC.iterdir() if p.is_dir()):
    result = (d / "result.txt").read_text(errors="replace")
    area = (d / "report_area.rpt").read_text(errors="replace")
    pwr = (d / "report_power.rpt").read_text(errors="replace")
    period = n(r"TARGET_PERIOD_NS=([0-9.eE+-]+)", result)
    delay = n(r"ARRIVAL_NS=([0-9.eE+-]+)", result)
    fmax = n(r"FMAX_GHZ=([0-9.eE+-]+)", result)
    cell_area = n(r"Total cell area:\s+([0-9.eE+-]+)", area)
    total_area = n(r"Total area:\s+([0-9.eE+-]+)", area)
    rows.append({"FU": d.name, "target_period_ns": f"{period:.6f}",
                 "achieved_delay_ns": f"{delay:.6f}", "fmax_ghz": f"{fmax:.9f}",
                 "cell_area_um2": f"{cell_area:.6f}",
                 "total_area_um2": f"{total_area:.6f}",
                 "dynamic_power_mw": f"{power('Total Dynamic Power', pwr):.6f}",
                 "leakage_power_uw": f"{power('Cell Leakage Power', pwr)*1000:.6f}",
                 "timing_met": str(delay <= period + 1e-6).lower(),
                 "activity_source": "uniform_synthetic",
                 "notes": "maximum-speed stress run; not primary equal-frequency comparison"})
with OUT.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=FIELDS); w.writeheader(); w.writerows(rows)
print(f"wrote {len(rows)} rows to {OUT}")
