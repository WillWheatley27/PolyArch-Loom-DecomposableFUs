#!/usr/bin/env python3
"""Collect the FP min/max two-level decomposition experiment.

Two single-level splits of the same sliced core are compared with the fixed banks that
cover the same formats:
  FP64 -> 2xFP32: dec_64_32 (fu_fp_min_max_m2)            vs fix_64 + fix_32x2
  FP32 -> 2xFP16: dec_32_16 (fu_fp_minmax_revised_32_16)  vs fix_32 + fix_16x2
Fixed-frequency corners (one_ghz, two_ghz) have three configurations (canonical job
order, reversed order, fresh session per design); maxspeed is canonical only.

The cost model: with W = wide scalar unit, N = packed narrow unit, D = decomposable unit,
r = N/W and ovh = D/W - 1, the saving is 1 - D/(W + N) = 1 - (1 + ovh)/(1 + r).
The no-split control H (the same sliced core supporting only the wide format) splits
ovh into the cost of adding the split, D/H - 1, and the implementation-style gap between
the hand-written core and the DesignWare scalar unit, H/W - 1.
Writes fp_minmax_two_level/{ppa,savings,model}.csv, comparison.md, and ppa_summary.md.
"""
from __future__ import annotations

import csv
import statistics
from pathlib import Path

from collect_tier_ladders import parse

ROOT = Path(__file__).resolve().parent / "fp_minmax_two_level"
RAW = ROOT / "raw"
PERIOD = {"one_ghz": 1.0, "two_ghz": 0.5, "maxspeed": 0.010}
CONFIGS = ["canonical", "reverse", "fresh"]
SPLITS = {  # name -> (decomposable, wide fixed, packed narrow fixed, no-split control)
    "fp64_to_2xfp32": ("dec_64_32", "fix_64", "fix_32x2", "hand_64"),
    "fp32_to_2xfp16": ("dec_32_16", "fix_32", "fix_16x2", "hand_32"),
}
DESIGNS = [d for s in SPLITS.values() for d in s]
METRICS = {"area": "cell_area_um2", "power": "dynamic_power_mw", "leakage": "leakage_power_uw"}


def saving(fixed: float, decomp: float) -> float:
    return 100.0 * (fixed - decomp) / fixed


def write(name: str, fields: list[str], rows: list[dict]) -> None:
    with (ROOT / name).open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader(); w.writerows(rows)


def main() -> None:
    data = {}
    for cfg in CONFIGS:
        for d in DESIGNS:
            for corner, period in PERIOD.items():
                path = RAW / cfg / d / corner
                if (path / "result.txt").exists():
                    data[(cfg, d, corner)] = parse(path, period)

    ppa = [{"config": c, "design": d, "corner": k, **{m: f"{float(v[f]):.6f}" for m, f in METRICS.items()},
            "fmax_ghz": f"{float(v['fmax_ghz']):.6f}", "timing_met": v["timing_met"]}
           for (c, d, k), v in sorted(data.items())]
    write("ppa.csv", ["config", "design", "corner", *METRICS, "fmax_ghz", "timing_met"], ppa)

    sav, model = [], []
    for split, (dec, wide, narrow, hand) in SPLITS.items():
        for corner in PERIOD:
            per_cfg = {}
            for cfg in CONFIGS:
                if not all((cfg, x, corner) in data for x in (dec, wide, narrow)):
                    continue
                D, Wd, N = (data[(cfg, x, corner)] for x in (dec, wide, narrow))
                row = {"split": split, "corner": corner, "config": cfg}
                for m, f in METRICS.items():
                    bank = float(Wd[f]) + float(N[f])
                    row[f"bank_{m}"] = bank
                    row[f"dec_{m}"] = float(D[f])
                    row[f"{m}_saving_percent"] = saving(bank, float(D[f]))
                bank_fmax = min(float(Wd["fmax_ghz"]), float(N["fmax_ghz"]))
                row["bank_fmax_ghz"] = bank_fmax
                row["dec_fmax_ghz"] = float(D["fmax_ghz"])
                row["energy_saving_percent"] = saving(row["bank_power"] / bank_fmax,
                                                      row["dec_power"] / float(D["fmax_ghz"]))
                row["timing_met"] = all(bool(x["timing_met"]) for x in (D, Wd, N))
                per_cfg[cfg] = row
                a_w, a_n, a_d = (float(x["cell_area_um2"]) for x in (Wd, N, D))
                m = {"split": split, "corner": corner, "config": cfg,
                     "wide_area_um2": f"{a_w:.3f}", "narrow_area_um2": f"{a_n:.3f}",
                     "dec_area_um2": f"{a_d:.3f}", "r_narrow_over_wide": f"{a_n / a_w:.4f}",
                     "ovh_dec_over_wide_percent": f"{100 * (a_d / a_w - 1):.2f}",
                     "predicted_saving_percent": f"{100 * (1 - (a_d / a_w) / (1 + a_n / a_w)):.2f}"}
                if (cfg, hand, corner) in data:
                    H = data[(cfg, hand, corner)]
                    m["hand_area_um2"] = f"{float(H['cell_area_um2']):.3f}"
                    for mt, f in METRICS.items():
                        m[f"split_cost_{mt}_percent"] = f"{100 * (float(D[f]) / float(H[f]) - 1):.2f}"
                        m[f"hand_vs_dw_{mt}_percent"] = f"{100 * (float(H[f]) / float(Wd[f]) - 1):.2f}"
                model.append(m)
            sav += per_cfg.values()
            if len(per_cfg) > 1:
                keys = [k for k in next(iter(per_cfg.values())) if k.endswith(("percent", "area", "power", "leakage", "ghz"))]
                for stat, agg in (("min", min), ("median", statistics.median), ("max", max)):
                    sav.append({"split": split, "corner": corner, "config": stat,
                                **{k: agg(r[k] for r in per_cfg.values()) for k in keys},
                                "timing_met": all(r["timing_met"] for r in per_cfg.values())})
    fields = ["split", "corner", "config"] + [f"{p}_{m}" for m in METRICS for p in ("bank", "dec")] + \
             [f"{m}_saving_percent" for m in METRICS] + \
             ["bank_fmax_ghz", "dec_fmax_ghz", "energy_saving_percent", "timing_met"]
    for r in sav:
        for k, v in r.items():
            if isinstance(v, float):
                r[k] = f"{v:.6f}"
    write("savings.csv", fields, sav)
    write("model.csv", list(max(model, key=len)), model)

    with (ROOT / "comparison.md").open("w") as f:
        f.write("# FP Min/Max Two-Level Decomposition: Results\n\n")
        f.write("Generated by `reports/collect_fp_minmax_two_level.py`; analysis in "
                "`reports/fp_minmax_two_level.md`. SAED14nm RVT TT/0.8 V/25 C, Synopsys DC "
                "Y-2026.03-SP1; fixed-frequency corners use `compile_ultra -area_high_effort_script "
                "-no_autoungroup`, maxspeed uses `compile_ultra -no_autoungroup`; uniform synthetic "
                "activity. Ranges are min-max over the canonical, reversed, and fresh-session "
                "configurations.\n\n")
        f.write("## Savings versus the fixed bank\n\n| Split | Corner | Bank area | Dec area | Area saving | "
                "Power saving | Leakage saving | Energy saving | Bank / dec Fmax (GHz) |\n"
                "|---|---|---:|---:|---:|---:|---:|---:|---:|\n")
        by = {(r["split"], r["corner"], r["config"]): r for r in sav}
        for split in SPLITS:
            for corner in PERIOD:
                med = by.get((split, corner, "median")) or by.get((split, corner, "canonical"))
                if med is None:
                    continue
                lo, hi = by.get((split, corner, "min"), med), by.get((split, corner, "max"), med)
                rng = lambda k: (f"{float(med[k]):.2f}%" if lo is med else
                                 f"{float(med[k]):.2f}% ({float(lo[k]):.2f}..{float(hi[k]):.2f})")
                f.write(f"| {split} | {corner} | {float(med['bank_area']):.1f} | {float(med['dec_area']):.1f} | "
                        f"{rng('area_saving_percent')} | {rng('power_saving_percent')} | "
                        f"{rng('leakage_saving_percent')} | {rng('energy_saving_percent')} | "
                        f"{float(med['bank_fmax_ghz']):.2f} / {float(med['dec_fmax_ghz']):.2f} |\n")
        f.write("\nFixed-frequency rows show the median configuration (range in parentheses); "
                "maxspeed is canonical only.\n\n## Cost model (canonical)\n\n| Split | Corner | W (um2) | "
                "N (um2) | D (um2) | r = N/W | ovh = D/W - 1 | 1 - (1+ovh)/(1+r) |\n"
                "|---|---|---:|---:|---:|---:|---:|---:|\n")
        for m in model:
            if m["config"] == "canonical":
                f.write(f"| {m['split']} | {m['corner']} | {m['wide_area_um2']} | {m['narrow_area_um2']} | "
                        f"{m['dec_area_um2']} | {m['r_narrow_over_wide']} | {m['ovh_dec_over_wide_percent']}% | "
                        f"{m['predicted_saving_percent']}% |\n")
    with (ROOT / "comparison.md").open("a") as f:
        f.write("\n## Split cost versus the no-split control\n\nD/H - 1 is the cost of adding the "
                "split to the same sliced core; H/W - 1 is the hand-written core against the "
                "DesignWare scalar unit. Range over the configurations that include the control.\n\n"
                "| Split | Corner | Split cost: area | power | leakage | Hand vs DW: area | power | leakage |\n"
                "|---|---|---:|---:|---:|---:|---:|---:|\n")
        for split in SPLITS:
            for corner in PERIOD:
                ms = [m for m in model if m["split"] == split and m["corner"] == corner and "hand_area_um2" in m]
                if not ms:
                    continue
                def rng(k):
                    v = sorted(float(m[k]) for m in ms)
                    return f"{v[0]:+.1f}%" if len(v) == 1 or v[0] == v[-1] else f"{v[0]:+.1f}..{v[-1]:+.1f}%"
                f.write(f"| {split} | {corner} | " + " | ".join(rng(f"split_cost_{mt}_percent") for mt in METRICS)
                        + " | " + " | ".join(rng(f"hand_vs_dw_{mt}_percent") for mt in METRICS) + " |\n")
    roles = {"dec_64_32": ("FP64 -> 2xFP32", "decomposable (fu_fp_min_max_m2)"),
             "fix_64": ("FP64 -> 2xFP32", "fixed FP64 (DesignWare)"),
             "fix_32x2": ("FP64 -> 2xFP32", "fixed packed 2xFP32 (DesignWare)"),
             "hand_64": ("FP64 -> 2xFP32", "no-split control, FP64 only (fu_fp_min_max_m1)"),
             "dec_32_16": ("FP32 -> 2xFP16", "decomposable (fu_fp_minmax_revised_32_16)"),
             "fix_32": ("FP32 -> 2xFP16", "fixed FP32 (DesignWare)"),
             "fix_16x2": ("FP32 -> 2xFP16", "fixed packed 2xFP16 (DesignWare)"),
             "hand_32": ("FP32 -> 2xFP16", "no-split control, FP32 only (core W=32)")}
    with (ROOT / "ppa_summary.md").open("w") as f:
        f.write("# FP Min/Max Two-Level Experiment: PPA Data\n\n"
                "Generated by `reports/collect_fp_minmax_two_level.py` from `raw/`; analysis in "
                "`reports/fp_minmax_two_level.md`. SAED14nm RVT TT/0.8 V/25 C, Synopsys DC "
                "Y-2026.03-SP1, uniform synthetic activity, pre-layout. Values are the canonical run; "
                "brackets give the min..max over the canonical, reversed, and fresh-session "
                "configurations where they differ. Energy/op is dynamic power divided by achieved "
                "Fmax.\n\n")
        for corner, title in (("one_ghz", "1 GHz (1.000 ns target)"), ("two_ghz", "2 GHz (0.500 ns target)"),
                              ("maxspeed", "Max-speed stress (0.010 ns target, canonical only, target not met)")):
            f.write(f"## {title}\n\n| Split | Design | Area (um2) | Power (mW) | Leakage (uW) | Fmax (GHz) | "
                    "Energy/op (pJ) | Timing met |\n|---|---|---:|---:|---:|---:|---:|:---:|\n")
            for d, (split, role) in roles.items():
                vs = [data[(c, d, corner)] for c in CONFIGS if (c, d, corner) in data]
                if not vs:
                    continue
                can = data.get(("canonical", d, corner), vs[0])
                def cell(field, fmt):
                    vals = [float(v[field]) for v in vs]
                    txt = fmt.format(float(can[field]))
                    return txt if max(vals) == min(vals) else f"{txt} [{fmt.format(min(vals))}..{fmt.format(max(vals))}]"
                energy = float(can["dynamic_power_mw"]) / float(can["fmax_ghz"])
                f.write(f"| {split} | {role} | {cell('cell_area_um2', '{:.1f}')} | {cell('dynamic_power_mw', '{:.4f}')} | "
                        f"{cell('leakage_power_uw', '{:.4f}')} | {float(can['fmax_ghz']):.3f} | {energy:.4f} | "
                        f"{'yes' if can['timing_met'] else 'no'} |\n")
            f.write("\n")
        f.write("## Bank savings and split cost\n\nSavings, cost model, and the split cost relative to the "
                "no-split control are tabulated in `comparison.md`; machine-readable rows are in `ppa.csv`, "
                "`savings.csv`, and `model.csv`.\n")
    print(f"wrote {len(ppa)} ppa rows, {len(sav)} savings rows, {len(model)} model rows")


if __name__ == "__main__":
    main()
