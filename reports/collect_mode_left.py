#!/usr/bin/env python3
"""Collect the left-edge mode-decode rerun: DC PPA plus PrimePower simulation power.

Every design in the full rerun is resynthesized after moving mode selection to the left edge
(one mode decode at the input, AND-OR selects on its one-hot lane-width bus) with
`NETLIST=1 CLOSURE=1 synth/syn_rerun.tcl` into reports/3rd_run/raw, and simulated with
synth/run_primepower.py. The previous rerun (PPA_rerun.csv, rerun_overhead.csv,
rerun_savings.csv) is the expected data. Writes:

  3rd_run/PPA_mode_left.csv             DC area, static and dynamic power, timing, closure factor,
                                and the change against PPA_rerun.csv;
  3rd_run/mode_left_overhead.csv        adjacent capability-tier overhead, against rerun_overhead.csv, plus
                                the PrimePower overhead of the 64-bit operation;
  3rd_run/mode_left_savings.csv         decomposable unit versus fixed bank (DC), against rerun_savings.csv;
  3rd_run/mode_left_primepower.csv      PrimePower power per design, corner, and mode, with energy per
                                operation and per lane result;
  3rd_run/mode_left_power_savings.csv   PrimePower savings per mode and mode-weighted: the decomposable
                                unit against a gated bank (the component serving the mode
                                active, the others idle and leaking) and an all-active bank.
A comparison is marked comparable only when every design in it meets the corner's target.
"""
from __future__ import annotations

import re
from pathlib import Path

from collect_rerun import (DESIGNS, PERIOD, SAVINGS, TIERS, fmt, parse, pct, rows_of, saving,
                           write)

ROOT = Path(__file__).resolve().parent
OUT = "3rd_run"  # tables and raw reports live in reports/3rd_run/
RAW = ROOT / OUT / "raw"
SYN = ROOT.parent / "synth" / "syn_rerun.tcl"
# RTL edited to move the mode decode to the left edge (the others already had one input decode).
LEFT_EDGE_RTL = {"rtl/fu_cmp_gen.sv", "rtl/fu_abs_gen.sv", "rtl/fu_barrel_shift_gen.sv",
                 "rtl/fu_fp_cmp_gen.sv", "rtl/fu_fp_min_max_gen.sv", "rtl/fu_rounding_gen.sv",
                 "rtl/fu_mult_decomp.sv", "rtl/fu_mult_karatsuba_64_32.sv"}
PROB_FU = {"addsub": "AddSub", "mult": "IntegerMult", "minmax": "IntegerMinMax", "fp_minmax": "FPMinMax",
           "fp_cmp": "FPCmp", "cmp": "IntegerCmp", "rounding": "Rounding", "barrel": "BarrelShift", "abs": "Abs"}


def rtl_of() -> dict[str, str]:
    """design -> RTL file, from the synthesis job list."""
    return {n: r for n, r in re.findall(r"^\s*\{(\S+) (\S+) \S+\}", SYN.read_text(), re.MULTILINE)}


def lane_width(cap: str) -> int:
    """Lane width of a fixed component's capability ("64", "32x2", "FP16x4")."""
    return int(re.match(r"(?:FP)?(\d+)", cap).group(1))


def pp_parse(d: str, c: str) -> dict[int, dict[str, float]]:
    """mode -> PrimePower power (mW, leakage uW), energy, and annotation."""
    pp = RAW / d / c / "primepower"
    if not (pp / "info.txt").exists():
        return {}
    info = dict(kv.split("=") for kv in (pp / "info.txt").read_text().split())
    out = {}
    for m, lanes in zip(map(int, info["MODES"].split(",")), map(int, info["LANES"].split(","))):
        rpt = (pp / f"power_mode{m}.rpt").read_text()
        w = {k: float(re.search(rf"^\s*{k}\s*=\s*([0-9.eE+-]+)", rpt, re.MULTILINE).group(1))
             for k in ("Net Switching Power", "Cell Internal Power", "Cell Leakage Power", "Total Power")}
        ann = re.search(r"^\s*Nets\s+\d+\((\d+\.\d+)%\)", (pp / f"activity_mode{m}.rpt").read_text(), re.MULTILINE)
        total_pj = w["Total Power"] * PERIOD[c] * 1e3  # W * ns = nJ -> pJ
        out[m] = {"lanes": lanes, "switching_mw": w["Net Switching Power"] * 1e3,
                  "internal_mw": w["Cell Internal Power"] * 1e3, "leakage_uw": w["Cell Leakage Power"] * 1e6,
                  "dynamic_mw": (w["Net Switching Power"] + w["Cell Internal Power"]) * 1e3,
                  "total_mw": w["Total Power"] * 1e3, "energy_pj": total_pj, "energy_lane_pj": total_pj / lanes,
                  "annotated_pct": float(ann.group(1)) if ann else float("nan"), "nvec": int(info["NVEC"])}
    return out


def merged(rows: list[dict], keys: list[str]) -> dict[tuple, dict]:
    return {tuple(r[k] for k in keys): r for r in rows}


def tidy(rows: list[dict]) -> list[dict]:
    keys = []
    for r in rows:
        keys += [k for k in r if k not in keys]
    return [{k: r.get(k, "") for k in keys} for r in rows]


def main() -> None:
    rtl = rtl_of()
    data = {}
    for d in DESIGNS:
        for c, p in PERIOD.items():
            if (RAW / d / c / "result.txt").exists():
                v = parse(RAW / d / c, p)
                v["closure"] = float(re.search(r"CLOSURE_FACTOR=(\S+)", (RAW / d / c / "result.txt").read_text()).group(1))
                data[(d, c)] = v
    met = lambda ds, c: all(data[(x, c)]["timing_met"] for x in ds)

    # ---- DC PPA against the previous rerun ----------------------------------------------
    prev = merged(rows_of("PPA_rerun.csv"), ["design", "corner"])
    ppa = []
    for (d, c), v in data.items():
        fam, role, cap = DESIGNS[d]
        row = {"family": fam, "design": d, "role": role, "capability": cap, "corner": c,
               "rtl": rtl[d], "rtl_edited_left_edge": str(rtl[d] in LEFT_EDGE_RTL).lower(),
               "target_period_ns": fmt(PERIOD[c], 3), "closure_factor": fmt(v["closure"], 1),
               "achieved_delay_ns": fmt(v["delay_ns"]), "fmax_ghz": fmt(v["fmax_ghz"]),
               "timing_met": str(v["timing_met"]).lower(),
               "cell_area_um2": fmt(v["area_um2"]), "static_leakage_power_uw": fmt(v["static_uw"]),
               "dynamic_power_mw": fmt(v["dynamic_mw"]), "dynamic_internal_mw": fmt(v["internal_mw"]),
               "dynamic_switching_mw": fmt(v["switching_mw"])}
        o = prev.get((d, c))
        if o:
            row.update({"prev_timing_met": o["timing_met"], "prev_achieved_delay_ns": o["achieved_delay_ns"],
                        "prev_cell_area_um2": o["cell_area_um2"],
                        "prev_static_leakage_power_uw": o["static_leakage_power_uw"],
                        "prev_dynamic_power_mw": o["dynamic_power_mw"],
                        "delta_area_percent": fmt(pct(v["area_um2"], float(o["cell_area_um2"])), 2),
                        "delta_static_percent": fmt(pct(v["static_uw"], float(o["static_leakage_power_uw"])), 2),
                        "delta_dynamic_percent": fmt(pct(v["dynamic_mw"], float(o["dynamic_power_mw"])), 2)})
        ppa.append(row)
    write(f"{OUT}/PPA_mode_left.csv", tidy(ppa))

    # ---- Overhead between adjacent tiers ----------------------------------------------------
    prev = merged(rows_of("rerun_overhead.csv"), ["from_tier", "to_tier", "corner"])
    over = []
    for fam, tiers in TIERS.items():
        for a, b in zip(tiers, tiers[1:]):
            for c in PERIOD:
                if (a, c) not in data or (b, c) not in data:
                    continue
                A, B = data[(a, c)], data[(b, c)]
                ov = {m: pct(B[k], A[k]) for m, k in (("area", "area_um2"), ("static", "static_uw"), ("dynamic", "dynamic_mw"))}
                row = {"family": fam, "from_tier": a, "to_tier": b, "capability_added": DESIGNS[b][2], "corner": c,
                       "prev_area_um2": fmt(A["area_um2"]), "new_area_um2": fmt(B["area_um2"]),
                       **{f"{m}_overhead_percent": fmt(x, 3) for m, x in ov.items()},
                       "fmax_change_percent": fmt(pct(B["fmax_ghz"], A["fmax_ghz"]), 3),
                       "comparable": str(met([a, b], c)).lower()}
                pa, pb = pp_parse(a, c).get(0), pp_parse(b, c).get(0)  # same 64-bit operation on both tiers
                if pa and pb:
                    row["primepower_64bit_op_total_overhead_percent"] = fmt(pct(pb["total_mw"], pa["total_mw"]), 3)
                o = prev.get((a, b, c))
                if o:
                    row.update({f"rerun_{m}_overhead_percent": o[f"{m}_overhead_percent"] for m in ov})
                    row.update({f"delta_{m}_pp": fmt(x - float(o[f"{m}_overhead_percent"]), 3) for m, x in ov.items()})
                over.append(row)
    write(f"{OUT}/mode_left_overhead.csv", tidy(over))

    # ---- DC savings against fixed banks ---------------------------------------------------
    prev = merged(rows_of("rerun_savings.csv"), ["decomposable", "bank", "corner"])
    sav = []
    for fam, dec, bank, label, _ in SAVINGS:
        for c in PERIOD:
            if (dec, c) not in data or any((b, c) not in data for b in bank):
                continue
            D = data[(dec, c)]
            tot = {k: sum(data[(b, c)][k] for b in bank) for k in ("area_um2", "static_uw", "dynamic_mw")}
            s = {m: saving(tot[k], D[k]) for m, k in (("area", "area_um2"), ("static", "static_uw"), ("dynamic", "dynamic_mw"))}
            row = {"family": fam, "decomposable": dec, "capability": DESIGNS[dec][2], "bank": label,
                   "bank_components": " + ".join(bank), "corner": c,
                   "bank_area_um2": fmt(tot["area_um2"]), "dec_area_um2": fmt(D["area_um2"]),
                   "area_saving_percent": fmt(s["area"], 3),
                   "bank_static_uw": fmt(tot["static_uw"]), "dec_static_uw": fmt(D["static_uw"]),
                   "static_saving_percent": fmt(s["static"], 3),
                   "bank_dynamic_mw": fmt(tot["dynamic_mw"]), "dec_dynamic_mw": fmt(D["dynamic_mw"]),
                   "dynamic_saving_percent": fmt(s["dynamic"], 3),
                   "comparable": str(met([dec, *bank], c)).lower()}
            o = prev.get((dec, label, c))
            if o:
                row.update({f"rerun_{m}_saving_percent": o[f"{m}_saving_percent"] for m in s})
                row.update({f"delta_{m}_pp": fmt(x - float(o[f"{m}_saving_percent"]), 3) for m, x in s.items()})
            sav.append(row)
    write(f"{OUT}/mode_left_savings.csv", tidy(sav))

    # ---- PrimePower per design and mode ------------------------------------------------------
    pp = {(d, c): pp_parse(d, c) for d, c in data}
    prow = []
    for (d, c), modes in pp.items():
        for m, v in modes.items():
            prow.append({"family": DESIGNS[d][0], "design": d, "role": DESIGNS[d][1], "capability": DESIGNS[d][2],
                         "corner": c, "mode": m, "lane_width": 64 // v["lanes"] if "/" in DESIGNS[d][2] else
                         lane_width(DESIGNS[d][2]), "lanes": v["lanes"], "vectors": v["nvec"],
                         "timing_met": str(data[(d, c)]["timing_met"]).lower(),
                         "switching_mw": fmt(v["switching_mw"]), "internal_mw": fmt(v["internal_mw"]),
                         "dynamic_mw": fmt(v["dynamic_mw"]), "leakage_uw": fmt(v["leakage_uw"]),
                         "total_mw": fmt(v["total_mw"]), "energy_per_op_pj": fmt(v["energy_pj"]),
                         "energy_per_lane_result_pj": fmt(v["energy_lane_pj"]),
                         "nets_annotated_percent": fmt(v["annotated_pct"], 2),
                         "dc_uniform_dynamic_mw": fmt(data[(d, c)]["dynamic_mw"]),
                         "primepower_over_dc_dynamic": fmt(v["dynamic_mw"] / data[(d, c)]["dynamic_mw"], 3)})
    write(f"{OUT}/mode_left_primepower.csv", prow)

    # ---- PrimePower savings: per mode and mode-weighted ----------------------------------------
    probs = {r["FU"]: {64: float(r["mode_64_probability"]), 32: float(r["mode_32_probability"]),
                       16: float(r["mode_16_probability"]), 8: float(r["mode_8_probability"])}
             for r in rows_of("mode_probabilities.csv")}
    psav = []
    for fam, dec, bank, label, _ in SAVINGS:
        for c in PERIOD:
            if not pp.get((dec, c)) or any(not pp.get((b, c)) for b in bank):
                continue
            comp = {lane_width(DESIGNS[b][2]): pp[(b, c)][0] for b in bank}
            ok = met([dec, *bank], c)
            weights = {m: probs[PROB_FU[fam]][64 >> m] for m in pp[(dec, c)] if (64 >> m) in comp}
            wsum = sum(weights.values())
            acc = {k: 0.0 for k in ("dec", "dec_dyn", "gated", "gated_dyn", "all")}
            for m, D in pp[(dec, c)].items():
                width = 64 >> m
                if width not in comp:
                    continue
                act = comp[width]
                idle_leak_mw = sum(v["leakage_uw"] for w, v in comp.items() if w != width) * 1e-3
                gated, all_on = act["total_mw"] + idle_leak_mw, sum(v["total_mw"] for v in comp.values())
                vals = {"dec": D["total_mw"], "dec_dyn": D["dynamic_mw"], "gated": gated,
                        "gated_dyn": act["dynamic_mw"], "all": all_on}
                for k in acc:
                    acc[k] += vals[k] * weights[m] / wsum if wsum else 0.0
                psav.append(row_ps(fam, dec, label, bank, c, f"mode{m}", width, D["lanes"], vals, ok))
            if len(weights) > 1 and wsum:
                wl = " ".join(f"{64 >> m}:{weights[m] / wsum:.3f}" for m in weights)
                psav.append(row_ps(fam, dec, label, bank, c, "weighted", wl, "", acc, ok))
    write(f"{OUT}/mode_left_power_savings.csv", psav)
    print(f"designs {len({d for d, _ in data})}/{len(DESIGNS)}, ppa {len(ppa)}, overhead {len(over)}, "
          f"savings {len(sav)}, primepower {len(prow)}, power savings {len(psav)}")


def row_ps(fam, dec, label, bank, c, mode, width, lanes, v, ok) -> dict:
    period = PERIOD[c]
    return {"family": fam, "decomposable": dec, "bank": label, "bank_components": " + ".join(bank), "corner": c,
            "mode": mode, "lane_width_or_weights": width, "lanes": lanes,
            "dec_total_mw": fmt(v["dec"]), "dec_dynamic_mw": fmt(v["dec_dyn"]),
            "gated_bank_total_mw": fmt(v["gated"]), "gated_bank_dynamic_mw": fmt(v["gated_dyn"]),
            "all_active_bank_total_mw": fmt(v["all"]),
            "dec_energy_per_op_pj": fmt(v["dec"] * period), "gated_bank_energy_per_op_pj": fmt(v["gated"] * period),
            "total_saving_vs_gated_percent": fmt(saving(v["gated"], v["dec"]), 3),
            "dynamic_saving_vs_gated_percent": fmt(saving(v["gated_dyn"], v["dec_dyn"]), 3),
            "total_saving_vs_all_active_percent": fmt(saving(v["all"], v["dec"]), 3),
            "comparable": str(ok).lower()}


if __name__ == "__main__":
    main()
