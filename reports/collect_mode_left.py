#!/usr/bin/env python3
"""Collect the left-edge mode-decode rerun: DC PPA plus PrimePower simulation power.

Every design in the full rerun is resynthesized after moving mode selection to the left edge
(one mode decode at the input, AND-OR selects on its one-hot lane-width bus) with
`NETLIST=1 CLOSURE=1 synth/syn_rerun.tcl` into reports/3rd_run/raw, and simulated with
synth/run_primepower.py. The previous rerun (PPA_rerun.csv, rerun_overhead.csv,
rerun_savings.csv) is the expected data. Writes:

  3rd_run/PPA_mode_left.csv             DC area, static and dynamic power, timing, closure factor,
                                and the change against PPA_rerun.csv, plus PrimePower power in
                                the widest-format mode and mode-weighted;
  3rd_run/mode_left_overhead.csv        adjacent capability-tier overhead, against rerun_overhead.csv, plus
                                the PrimePower overhead of the 64-bit operation;
  3rd_run/mode_left_savings.csv         decomposable unit versus fixed bank (DC), against rerun_savings.csv,
                                plus the PrimePower savings of the same comparison;
  3rd_run/mode_left_primepower.csv      PrimePower power per design, corner, and mode, with energy per
                                operation and per lane result;
  3rd_run/mode_left_power_savings.csv   PrimePower savings per mode and mode-weighted: the decomposable
                                unit against a gated bank (the component serving the mode
                                active, the others idle and leaking) and an all-active bank;
  3rd_run/mode_left_side_function_power.csv
                                PrimePower of AddSub with a Min/Max side function, per function
                                and mode, against separate AddSub and Min/Max units (gated: the
                                unit serving the function active, the other idle and leaking).
A comparison is marked comparable only when every design in it meets the corner's target.
A multi-function unit (AddSub+MinMax) has one row per function in every table.
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
# RTL edited to move the mode decode to the left edge (the others already had one input decode);
# fu_fp_minmax_32_16.sv wraps the edited sliced FP min/max core.
LEFT_EDGE_RTL = {"rtl/revised_fp_fus/fu_fp_minmax_32_16.sv", "rtl/fu_cmp_gen.sv", "rtl/fu_abs_gen.sv", "rtl/fu_barrel_shift_gen.sv",
                 "rtl/fu_fp_cmp_gen.sv", "rtl/fu_fp_min_max_gen.sv", "rtl/fu_rounding_gen.sv",
                 "rtl/fu_mult_decomp.sv", "rtl/fu_mult_karatsuba_64_32.sv"}
# mode_probabilities.csv row per family (per function for the AddSub+MinMax unit)
PROB_FU = {"addsub_minmax:addsub": "AddSub", "addsub_minmax:minmax": "IntegerMinMax", "addsub": "AddSub", "mult": "IntegerMult", "minmax": "IntegerMinMax", "fp_minmax": "FPMinMax",
           "fp_cmp": "FPCmp", "cmp": "IntegerCmp", "rounding": "Rounding", "barrel": "BarrelShift", "abs": "Abs"}


def rtl_of() -> dict[str, str]:
    """design -> RTL file, from the synthesis job list."""
    return {n: r for n, r in re.findall(r"^\s*\{(\S+) (rtl/\S+) ", SYN.read_text(), re.MULTILINE)}


def lane_width(cap: str, mode: int = 0) -> int:
    """Lane width in a mode of a capability ("64", "32x2", "FP64/FP32x2/FP16x4")."""
    return int(re.match(r"(?:FP)?(\d+)", cap.split("/")[mode]).group(1))


def functions(d: str, c: str) -> list[str]:
    """PrimePower runs of a design: "" for a single-function unit, else each held function."""
    return sorted(p.name.partition("_")[2] for p in (RAW / d / c).glob("primepower*"))


def pp_parse(d: str, c: str, func: str = "") -> dict[int, dict[str, float]]:
    """mode -> PrimePower power (mW, leakage uW), energy, and annotation."""
    pp = RAW / d / c / ("primepower_" + func if func else "primepower")
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


PROBS = {r["FU"]: {64: float(r["mode_64_probability"]), 32: float(r["mode_32_probability"]),
                  16: float(r["mode_16_probability"]), 8: float(r["mode_8_probability"])}
         for r in rows_of("mode_probabilities.csv")}


def probs(d: str, func: str = "") -> dict[int, float]:
    """lane width -> mode probability for design d (and function)."""
    fam = DESIGNS[d][0]
    return PROBS[PROB_FU[f"{fam}:{func}" if func else fam]]


def weighted(d: str, c: str, func: str = "") -> dict[str, float]:
    """PrimePower power weighted by mode probability, renormalized over the supported modes;
    a single-mode design (every fixed unit) is its one mode."""
    modes = pp_parse(d, c, func)
    if len(modes) == 1:
        return next(iter(modes.values()))
    w = {m: probs(d, func).get(lane_width(DESIGNS[d][2], m), 0.0) for m in modes}
    tot = sum(w.values())
    return {k: sum(modes[m][k] * w[m] for m in modes) / tot
            for k in ("dynamic_mw", "leakage_uw", "total_mw")}


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
    for d, c, func in [(d, c, f) for d, c in data for f in functions(d, c) or [""]]:
        v = data[(d, c)]
        fam, role, cap = DESIGNS[d]
        row = {"family": fam, "design": d, "role": role, "capability": cap, "function": func, "corner": c,
               "rtl": rtl[d], "rtl_edited_left_edge": str(rtl[d] in LEFT_EDGE_RTL).lower(),
               "target_period_ns": fmt(PERIOD[c], 3), "closure_factor": fmt(v["closure"], 1),
               "achieved_delay_ns": fmt(v["delay_ns"]), "fmax_ghz": fmt(v["fmax_ghz"]),
               "timing_met": str(v["timing_met"]).lower(),
               "cell_area_um2": fmt(v["area_um2"]), "static_leakage_power_uw": fmt(v["static_uw"]),
               "dynamic_power_mw": fmt(v["dynamic_mw"]), "dynamic_internal_mw": fmt(v["internal_mw"]),
               "dynamic_switching_mw": fmt(v["switching_mw"])}
        wide, wt = pp_parse(d, c, func).get(0), weighted(d, c, func) if functions(d, c) else None
        if wide:   # PrimePower: widest-format mode, and mode-weighted over the supported modes
            row.update({"primepower_wide_mode_dynamic_mw": fmt(wide["dynamic_mw"]),
                        "primepower_wide_mode_leakage_uw": fmt(wide["leakage_uw"]),
                        "primepower_wide_mode_total_mw": fmt(wide["total_mw"]),
                        "primepower_weighted_dynamic_mw": fmt(wt["dynamic_mw"]),
                        "primepower_weighted_total_mw": fmt(wt["total_mw"]),
                        "primepower_weighted_energy_per_op_pj": fmt(wt["total_mw"] * PERIOD[c])})
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
            for c, func in [(c, f) for c in PERIOD for f in functions(a, c) or [""]]:
                if (a, c) not in data or (b, c) not in data:
                    continue
                A, B = data[(a, c)], data[(b, c)]
                ov = {m: pct(B[k], A[k]) for m, k in (("area", "area_um2"), ("static", "static_uw"), ("dynamic", "dynamic_mw"))}
                row = {"family": fam, "from_tier": a, "to_tier": b, "capability_added": DESIGNS[b][2],
                       "function": func, "corner": c,
                       "prev_area_um2": fmt(A["area_um2"]), "new_area_um2": fmt(B["area_um2"]),
                       **{f"{m}_overhead_percent": fmt(x, 3) for m, x in ov.items()},
                       "fmax_change_percent": fmt(pct(B["fmax_ghz"], A["fmax_ghz"]), 3),
                       "comparable": str(met([a, b], c)).lower()}
                pa, pb = pp_parse(a, c, func).get(0), pp_parse(b, c, func).get(0)  # same widest operation
                if pa and pb:
                    row["primepower_wide_op_dynamic_overhead_percent"] = fmt(pct(pb["dynamic_mw"], pa["dynamic_mw"]), 3)
                    row["primepower_wide_op_total_overhead_percent"] = fmt(pct(pb["total_mw"], pa["total_mw"]), 3)
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
            sav.append(row)   # PrimePower savings are attached below

    # ---- PrimePower per design and mode ------------------------------------------------------
    pp = {(d, c): pp_parse(d, c) for d, c in data}
    prow = []
    for d, c, func in [(d, c, f) for d, c in data for f in functions(d, c)]:
        for m, v in pp_parse(d, c, func).items():
            prow.append({"family": DESIGNS[d][0], "design": d, "role": DESIGNS[d][1], "capability": DESIGNS[d][2],
                         "function": func, "corner": c, "mode": m, "lane_width": lane_width(DESIGNS[d][2], m),
                         "lanes": v["lanes"], "vectors": v["nvec"],
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
    psav = []
    for fam, dec, bank, label, _ in SAVINGS:
        for c in PERIOD:
            if not pp.get((dec, c)) or any(not pp.get((b, c)) for b in bank):
                continue
            comp = {lane_width(DESIGNS[b][2]): pp[(b, c)][0] for b in bank}
            ok = met([dec, *bank], c)
            width_of = {m: lane_width(DESIGNS[dec][2], m) for m in pp[(dec, c)]}
            weights = {m: probs(dec)[width_of[m]] for m in pp[(dec, c)] if width_of[m] in comp}
            wsum = sum(weights.values())
            acc = {k: 0.0 for k in ("dec", "dec_dyn", "gated", "gated_dyn", "all")}
            for m, D in pp[(dec, c)].items():
                width = width_of[m]
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
                wl = " ".join(f"{width_of[m]}:{weights[m] / wsum:.3f}" for m in weights)
                psav.append(row_ps(fam, dec, label, bank, c, "weighted", wl, "", acc, ok))
    write(f"{OUT}/mode_left_power_savings.csv", psav)

    # ---- PrimePower: AddSub with a Min/Max side function vs separate units -----------------
    side = []
    for fam, dec, bank, label, _ in SAVINGS:
        if fam != "addsub_minmax":
            continue
        unit = dict(zip(("addsub", "minmax"), bank))
        for c in PERIOD:
            if (dec, c) not in data:
                continue
            for func in functions(dec, c):
                act, idle = unit[func], unit["minmax" if func == "addsub" else "addsub"]
                pa, pi = pp.get((act, c), {}), pp.get((idle, c), {})
                acc, wsum = {"dec": 0.0, "gated": 0.0, "both": 0.0}, 0.0
                for m, D in pp_parse(dec, c, func).items():
                    if m not in pa or not pi:   # the separate unit cannot run this lane width
                        continue
                    gated = pa[m]["total_mw"] + pi[0]["leakage_uw"] * 1e-3
                    both = pa[m]["total_mw"] + pi[m]["total_mw"] if m in pi else float("nan")
                    side.append({"decomposable": dec, "separate_units": label, "corner": c, "function": func,
                                 "mode": m, "lane_width": lane_width(DESIGNS[dec][2], m), "lanes": D["lanes"],
                                 "dec_total_mw": fmt(D["total_mw"]), "dec_dynamic_mw": fmt(D["dynamic_mw"]),
                                 "dec_leakage_uw": fmt(D["leakage_uw"]),
                                 "active_unit": act, "active_total_mw": fmt(pa[m]["total_mw"]),
                                 "idle_unit": idle, "idle_leakage_uw": fmt(pi[0]["leakage_uw"]),
                                 "gated_pair_total_mw": fmt(gated), "both_active_total_mw": fmt(both),
                                 "dec_energy_per_op_pj": fmt(D["total_mw"] * PERIOD[c]),
                                 "gated_pair_energy_per_op_pj": fmt(gated * PERIOD[c]),
                                 "total_saving_vs_gated_percent": fmt(saving(gated, D["total_mw"]), 3),
                                 "total_saving_vs_both_active_percent": fmt(saving(both, D["total_mw"]), 3),
                                 "comparable": str(met([dec, *bank], c)).lower()})
                    p = probs(dec, func).get(lane_width(DESIGNS[dec][2], m), 0.0)
                    if p:
                        wsum += p
                        for k, x in (("dec", D["total_mw"]), ("gated", gated), ("both", both)):
                            acc[k] += p * x
                if wsum and len(pp_parse(dec, c, func)) > 1:
                    v = {k: x / wsum for k, x in acc.items()}
                    side.append({"decomposable": dec, "separate_units": label, "corner": c, "function": func,
                                 "mode": "weighted", "lane_width": "mode probabilities",
                                 "dec_total_mw": fmt(v["dec"]), "gated_pair_total_mw": fmt(v["gated"]),
                                 "both_active_total_mw": fmt(v["both"]),
                                 "dec_energy_per_op_pj": fmt(v["dec"] * PERIOD[c]),
                                 "gated_pair_energy_per_op_pj": fmt(v["gated"] * PERIOD[c]),
                                 "total_saving_vs_gated_percent": fmt(saving(v["gated"], v["dec"]), 3),
                                 "total_saving_vs_both_active_percent": fmt(saving(v["both"], v["dec"]), 3),
                                 "comparable": str(met([dec, *bank], c)).lower()})
    side = tidy(side)
    write(f"{OUT}/mode_left_side_function_power.csv", side)

    # ---- DC savings table, with the PrimePower savings of the same comparison ---------------
    # A row's PrimePower figure is its mode-weighted row (its only row for a single-mode unit).
    ppk = {}
    for r in psav:
        ppk[(r["decomposable"], r["bank"], r["corner"], "")] = r
    for r in side:
        ppk[(r["decomposable"], r["separate_units"], r["corner"], r["function"])] = r
    out = []
    for r in sav:
        for func in functions(r["decomposable"], r["corner"]) or [""]:
            p = ppk.get((r["decomposable"], r["bank"], r["corner"], func), {})
            row = dict(r)
            row["function"] = func
            row["primepower_basis"] = ("" if not p else "mode-weighted" if p["mode"] == "weighted" else p["mode"])
            row["primepower_dec_total_mw"] = p.get("dec_total_mw", "")
            row["primepower_gated_bank_total_mw"] = p.get("gated_bank_total_mw", p.get("gated_pair_total_mw", ""))
            row["primepower_all_active_bank_total_mw"] = p.get("all_active_bank_total_mw", p.get("both_active_total_mw", ""))
            row["primepower_saving_vs_gated_percent"] = p.get("total_saving_vs_gated_percent", "")
            row["primepower_saving_vs_all_active_percent"] = p.get("total_saving_vs_all_active_percent",
                                                                   p.get("total_saving_vs_both_active_percent", ""))
            out.append(row)
    write(f"{OUT}/mode_left_savings.csv", tidy(out))
    print(f"designs {len({d for d, _ in data})}/{len(DESIGNS)}, ppa {len(ppa)}, overhead {len(over)}, "
          f"savings {len(sav)}, primepower {len(prow)}, power savings {len(psav)}, side function {len(side)}")


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
