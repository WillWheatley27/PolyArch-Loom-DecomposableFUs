#!/usr/bin/env python3
"""Acceptance check: the FP min/max capability ladder must grow steadily.

In the sliced tree core each added tier taps one more tree level: one more input
on every slice's level select plus one lane evaluator per new lane (the first
split also adds the one-time mode network). For each corner and metric (area,
dynamic power, leakage) this requires
  1. monotonic growth: every rung costs more than the previous one;
  2. a steady step: the m1->m2 and m2->m3 increments agree within MAX_RATIO.
Every rung must also meet its timing target. Per-added-lane increments are
printed for reference (m1 -> m2 adds one lane, m2 -> m3 adds two).

Default: checks tier_ladders/ppa.csv. With --trials, checks every run in
tier_ladders/trials.csv (see collect_fp_minmax_trials.py) and its median.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "tier_ladders"
LANES = {"m1": 1, "m2": 2, "m3": 4}
METRICS = {"cell_area_um2": "area", "dynamic_power_mw": "power", "leakage_power_uw": "leakage"}
MAX_RATIO = 2.0


def check(rows: dict[tuple[str, str], dict[str, str]], label: str) -> int:
    """rows: (tier, corner) -> row with METRICS fields and optional timing_met."""
    failures = []
    for corner in sorted({c for _, c in rows}):
        tiers = [rows[(t, corner)] for t in LANES]
        for r in tiers:
            if r.get("timing_met", "True") not in ("True", ""):
                failures.append(f"{corner}: timing not met")
        for field, name in METRICS.items():
            v = [float(r[field]) for r in tiers]
            step = [v[1] - v[0], v[2] - v[1]]
            per_lane = [step[0] / (LANES["m2"] - LANES["m1"]), step[1] / (LANES["m3"] - LANES["m2"])]
            line = (f"{corner:8s} {name:8s} m1={v[0]:.4f} m2={v[1]:.4f} m3={v[2]:.4f} "
                    f"step +{step[0]:.4f} / +{step[1]:.4f} "
                    f"(per lane +{per_lane[0]:.4f} / +{per_lane[1]:.4f})")
            if min(step) <= 0:
                failures.append(f"{line}  <- not monotonic")
            elif max(step) / min(step) > MAX_RATIO:
                failures.append(f"{line}  <- step ratio {max(step) / min(step):.2f} > {MAX_RATIO}")
            else:
                print(f"ok   [{label}] {line}")
    for f in failures:
        print(f"FAIL [{label}] {f}")
    print(f"{'PASS' if not failures else 'FAIL'} [{label}] "
          f"{6 - sum('<-' in f for f in failures)}/6 metric-corner checks pass")
    return 1 if failures else 0


def main() -> int:
    if "--trials" in sys.argv[1:]:
        runs: dict[str, dict] = {}
        for r in csv.DictReader((ROOT / "trials.csv").open()):
            if r["run"] in ("min", "max", "spread_percent"):
                continue
            runs.setdefault(r["run"], {})[(r["tier"], r["corner"])] = r
        return max(check(rows, run) for run, rows in runs.items())
    rows = {(r["tier"], r["corner"]): r for r in csv.DictReader((ROOT / "ppa.csv").open())
            if r["family"] == "fp_minmax"}
    return check(rows, "canonical")


if __name__ == "__main__":
    sys.exit(main())
