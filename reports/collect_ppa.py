#!/usr/bin/env python3
"""Collect normalized Design Compiler reports into reports/ppa_summary.csv.

The collector deliberately records only reports produced by synth_common_decomp.tcl.
Legacy reports are not silently mixed into this table because they may use different
timing targets, libraries, or activity assumptions.
"""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPORT_ROOT = ROOT / "synth_common"
FIXED_ROOT = ROOT / "synth_common_fixed"
FEASIBLE_ROOT = ROOT / "synth_feasible"
OUT = ROOT / "ppa_summary.csv"

FIELDS = [
    "FU", "capability", "implementation", "corner", "target_period_ns",
    "achieved_delay_ns", "fmax_ghz", "cell_area_um2", "total_area_um2",
    "dynamic_power_mw", "leakage_power_uw", "energy_per_operation_pj",
    "timing_met", "activity_source", "fixed_bank_definition",
]

CAPABILITY = {
    "addsub_d4": "64/32x2/16x4",
    "mult_decomp": "64/32x2/16x4",
    "minmax_m4": "64/32x2/16x4",
    "fp_minmax_m3": "FP64/FP32x2/FP16x4",
    "fp_cmp_g3": "FP64/FP32x2/FP16x4",
    "cmp_c4": "64/32x2/16x4",
    "rounding_g3": "FP64/FP32x2/FP16x4",
    "barrel_bs3": "64/32x2/16x4",
    "abs_a3": "64/32x2/16x4",
}


def number(pattern: str, text: str, default: float = 0.0) -> float:
    match = re.search(pattern, text, re.MULTILINE)
    return float(match.group(1)) if match else default


def power_mw(label: str, text: str) -> float:
    """Read a DC power line and normalize W/mW/uW/nW to mW."""
    match = re.search(
        rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)", text,
        re.MULTILINE,
    )
    if not match:
        return 0.0
    value = float(match.group(1))
    scale = {"W": 1000.0, "mW": 1.0, "uW": 1e-3, "nW": 1e-6}
    return value * scale[match.group(2)]


def collect():
    rows = []
    roots = [(REPORT_ROOT, "decomposable"), (FIXED_ROOT, "fixed"), (FEASIBLE_ROOT, "feasible")]
    for report_root, implementation in roots:
      if not report_root.exists():
        continue
      for fu_dir in sorted(p for p in report_root.iterdir() if p.is_dir()):
        for corner_dir in sorted(p for p in fu_dir.iterdir() if p.is_dir()):
            row_implementation = implementation
            result_path = corner_dir / "result.txt"
            area_path = corner_dir / "report_area.rpt"
            power_path = corner_dir / "report_power.rpt"
            if not (result_path.exists() and area_path.exists() and power_path.exists()):
                continue
            result = result_path.read_text(errors="replace")
            area = area_path.read_text(errors="replace")
            power = power_path.read_text(errors="replace")
            period = number(r"TARGET_PERIOD_NS=([0-9.eE+-]+)", result)
            delay = number(r"ARRIVAL_NS=([0-9.eE+-]+)", result)
            fmax = number(r"FMAX_GHZ=([0-9.eE+-]+)", result)
            cell_area = number(r"Total cell area:\s+([0-9.eE+-]+)", area)
            total_area = number(r"Total area:\s+([0-9.eE+-]+)", area)
            dynamic = power_mw("Total Dynamic Power", power)
            leakage_uw = power_mw("Cell Leakage Power", power) * 1000.0
            energy = dynamic / fmax if fmax > 0 else 0.0
            if row_implementation == "fixed":
                # Fixed capability is encoded in the directory name and result
                # metadata; use a small deterministic suffix mapping.
                suffix = fu_dir.name.rsplit("_", 1)[-1]
                capability = {"64": "64", "32x2": "32x2", "16x4": "16x4"}.get(suffix, "fixed")
                if fu_dir.name.startswith(("fp_minmax", "fp_cmp", "rounding")):
                    capability = {"64": "FP64", "32x2": "FP32x2", "16x4": "FP16x4"}.get(suffix, capability)
                bank_def = "fixed_bank_component"
            elif row_implementation == "feasible":
                # The feasible flow contains both fixed components and the
                # decomposable top. Metadata in result.txt identifies the
                # family; use the job name to classify implementation.
                row_implementation = "decomposable" if fu_dir.name in CAPABILITY else "fixed"
                suffix = fu_dir.name.rsplit("_", 1)[-1]
                capability = CAPABILITY.get(fu_dir.name, {"64": "64", "32x2": "32x2", "16x4": "16x4"}.get(suffix, "fixed"))
                if fu_dir.name.startswith(("fp_minmax", "fp_cmp", "rounding")):
                    capability = {"64": "FP64", "32x2": "FP32x2", "16x4": "FP16x4"}.get(suffix, capability)
                bank_def = "feasible_family_target"
            else:
                capability = CAPABILITY.get(fu_dir.name, "unknown")
                bank_def = "pending_normalized_fixed_bank"
            rows.append({
                "FU": fu_dir.name,
                "capability": capability,
                "implementation": row_implementation,
                "corner": corner_dir.name,
                "target_period_ns": f"{period:.6f}",
                "achieved_delay_ns": f"{delay:.6f}",
                "fmax_ghz": f"{fmax:.9f}",
                "cell_area_um2": f"{cell_area:.6f}",
                "total_area_um2": f"{total_area:.6f}",
                "dynamic_power_mw": f"{dynamic:.6f}",
                "leakage_power_uw": f"{leakage_uw:.6f}",
                "energy_per_operation_pj": f"{energy:.6f}",
                "timing_met": str(delay <= period + 1e-6).lower(),
                "activity_source": "uniform_synthetic",
                "fixed_bank_definition": bank_def,
            })
    return rows


if __name__ == "__main__":
    rows = collect()
    with OUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} rows to {OUT}")
