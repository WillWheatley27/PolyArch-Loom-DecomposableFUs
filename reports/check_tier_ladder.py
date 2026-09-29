#!/usr/bin/env python3
"""Acceptance check: a capability ladder must grow steadily.

For each corner and metric (area, dynamic power, leakage) of a three-rung ladder
(1 lane -> 2 lanes -> 4 lanes) this requires
  1. monotonic growth: every rung costs more than the previous one;
  2. a steady step: the rung1->rung2 and rung2->rung3 increments agree within
     MAX_RATIO.
Every rung must also meet its timing target. Per-added-lane increments are
printed for reference (rung 1 -> 2 adds one lane, rung 2 -> 3 adds two).

Usage: check_tier_ladder.py <family> [--trials]
  families: see FAMILIES (tier_ladders rows, or the revised FP tiers).
  --trials: check every repeatability trial in tier_ladders/trials.csv
            (collect_ladder_trials.py) and their median, instead of the canonical run.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LADDERS = ROOT / "tier_ladders" / "ppa.csv"
REVISED = ROOT / "revised_fp_fus" / "ppa.csv"
# family -> (source csv, family column value, rung tier names)
FAMILIES = {
    "fp_minmax": (LADDERS, "fp_minmax", ["m1", "m2", "m3"]),
    "fp_cmp": (LADDERS, "fp_cmp", ["g1", "g2", "g3"]),
    "fp_minmax_revised": (REVISED, "fp_minmax", ["rev64", "rev64_32", "rev64_32_16"]),
    "fp_cmp_revised": (REVISED, "fp_cmp", ["rev64", "rev64_32", "rev64_32_16"]),
}
LANES = [1, 2, 4]
METRICS = {"cell_area_um2": "area", "dynamic_power_mw": "power", "leakage_power_uw": "leakage"}
MAX_RATIO = 2.0


def check(rows: dict[tuple[str, str], dict[str, str]], tiers: list[str], label: str) -> int:
    """rows: (tier, corner) -> row with METRICS fields and optional timing_met."""
    failures = []
    for corner in sorted({c for _, c in rows}):
        rungs = [rows[(t, corner)] for t in tiers]
        for r in rungs:
            if r.get("timing_met", "True") not in ("True", ""):
                failures.append(f"{corner}: timing not met")
        for field, name in METRICS.items():
            v = [float(r[field]) for r in rungs]
            step = [v[1] - v[0], v[2] - v[1]]
            per_lane = [step[0] / (LANES[1] - LANES[0]), step[1] / (LANES[2] - LANES[1])]
            line = (f"{corner:8s} {name:8s} {tiers[0]}={v[0]:.4f} {tiers[1]}={v[1]:.4f} "
                    f"{tiers[2]}={v[2]:.4f} step +{step[0]:.4f} / +{step[1]:.4f} "
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
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1 or args[0] not in FAMILIES:
        sys.exit(f"usage: check_tier_ladder.py <{'|'.join(FAMILIES)}> [--trials]")
    family = args[0]
    source, column, tiers = FAMILIES[family]
    if "--trials" in sys.argv[1:]:
        runs: dict[str, dict] = {}
        for r in csv.DictReader((ROOT / "tier_ladders" / "trials.csv").open()):
            if r["family"] != column or r["run"] in ("min", "max", "spread_percent"):
                continue
            runs.setdefault(r["run"], {})[(r["tier"], r["corner"])] = r
        if not runs:
            sys.exit(f"no trials for {family} in tier_ladders/trials.csv")
        return max(check(rows, tiers, f"{family} {run}") for run, rows in runs.items())
    rows = {(r["tier"], r["corner"]): r for r in csv.DictReader(source.open())
            if r["family"] == column and r["tier"] in tiers}
    return check(rows, tiers, family)


if __name__ == "__main__":
    sys.exit(main())
