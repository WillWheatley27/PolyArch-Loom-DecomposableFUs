#!/usr/bin/env python3
"""Compare repeated SAED14nm synthesis trials of capability ladders.

Design Compiler is deterministic for identical input, so the trials vary only
what should not matter: t1 repeats the canonical flow, t2 reverses the job
order within one session, t3 compiles every design in a fresh session. The
canonical run is reports/tier_ladders/raw. t1 must reproduce it bit-for-bit, so
the statistics use only the distinct configurations (canonical, t2, t3).
Writes tier_ladders/trials.csv with every trial row plus the min / median / max
and spread per family, tier and corner, for every family that has trials.
"""
from __future__ import annotations

import csv
import statistics
from pathlib import Path

from collect_tier_ladders import parse

ROOT = Path(__file__).resolve().parent / "tier_ladders"
RUNS = {"canonical": ROOT / "raw", "t1_repeat": ROOT / "trials" / "t1_repeat",
        "t2_reverse": ROOT / "trials" / "t2_reverse", "t3_fresh": ROOT / "trials" / "t3_fresh"}
PERIOD = {"one_ghz": 1.0, "two_ghz": 0.5}
DISTINCT = ["canonical", "t2_reverse", "t3_fresh"]
FAMILIES = {"fp_minmax": ["m1", "m2", "m3"], "fp_cmp": ["g1", "g2", "g3"]}
METRICS = ["cell_area_um2", "dynamic_power_mw", "leakage_power_uw", "fmax_ghz"]
OUT = ROOT / "trials.csv"


def main() -> None:
    families = {f: t for f, t in FAMILIES.items() if (RUNS["t3_fresh"] / f).is_dir()}
    data = {(run, f, t, c): parse(path / f / t / c, p)
            for f, tiers in families.items() for run, path in RUNS.items()
            for t in tiers for c, p in PERIOD.items()}
    for (run, f, t, c), d in data.items():
        if run == "t1_repeat":
            same = all(d[m] == data[("canonical", f, t, c)][m] for m in METRICS)
            print(f"t1 reproduces canonical {f} {t} {c}: {same}")
    rows = []
    for f, tiers in families.items():
        for c in PERIOD:
            for t in tiers:
                for run in RUNS:
                    d = data[(run, f, t, c)]
                    rows.append({"family": f, "corner": c, "tier": t, "run": run,
                                 "timing_met": d["timing_met"],
                                 **{m: f"{float(d[m]):.6f}" for m in METRICS}})
                vals = {m: [float(data[(r, f, t, c)][m]) for r in DISTINCT] for m in METRICS}
                for stat, agg in (("min", min), ("median", statistics.median), ("max", max),
                                  ("spread_percent",
                                   lambda v: 100.0 * (max(v) - min(v)) / statistics.median(v))):
                    rows.append({"family": f, "corner": c, "tier": t, "run": stat, "timing_met": "",
                                 **{m: f"{agg(vals[m]):.6f}" for m in METRICS}})
    with OUT.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["family", "corner", "tier", "run", "timing_met", *METRICS],
                           lineterminator="\n")
        w.writeheader(); w.writerows(rows)
    for r in rows:
        if r["run"] in ("median", "spread_percent"):
            print(f"{r['family']:9s} {r['corner']:8s} {r['tier']} {r['run']:14s} "
                  f"area {float(r['cell_area_um2']):9.3f} power {float(r['dynamic_power_mw']):.5f} "
                  f"leak {float(r['leakage_power_uw']):.5f}")


if __name__ == "__main__":
    main()
