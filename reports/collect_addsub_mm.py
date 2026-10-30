#!/usr/bin/env python3
"""Collect the AddSub + Min/Max side-function experiment (rtl/fu_add_sub_mm.sv), synthesized into
addsub_minmax_experiment/raw (synth/syn_rerun.tcl NETLIST=1 CLOSURE=1, one session per design and
target; RETIME=1 for the retimed pipelines) and simulated with PrimePower (synth/run_primepower.py;
the fused unit once per function):

  mm_<adder>_<tier>       AddSub with the Min/Max side function, combinational;
  mm_<adder>o_<tier>      the same with an output register (PIPE 1, latency 1);
  mm_<adder>p_<tier>      the same register retimed into the logic (PIPE 1, RETIME=1);
  mm_<adder>l_<tier>      the Min/Max choice behind the register (PIPE 2, latency 1);
  as_<adder>[o|p]_<tier>  the AddSub alone (MINMAX 0): combinational, output register, retimed;
  minmax_m2/m4 o and p    the decomposable Min/Max (fu_min_max_gen.sv), output register, retimed;
  mmr_<adder>[o|l]_<tier> the fused unit behind the original interface, its controls copied per block
                          and registered in the FU (fu_add_sub_mm_reg, FAST_OP_REGS=1): combinational
                          datapath, output register, late select;
  asr_<adder>[o]_<tier>   the AddSub alone the same way;
  adder: seg (segmented) or csel (carry-select at bit 32); tier: d2, d4, d8.

The separate pair of a tier is its AddSub alone and the decomposable Min/Max (m2 for d2, m4 for d4
and d8): combinational from 3rd_run/raw, registered from this experiment. Every pipelining has
latency 1 on both sides; for the late-select fused unit each unit of the pair takes the lower-energy
of its output-register and retimed forms. The original side-function
unit (fu_add_sub_minmax_gen.sv) is compared the same way against addsub_dN + minmax_mM, all from
3rd_run/raw. Energy is mode-weighted by reports/mode_probabilities.csv, per function. Writes, in
addsub_minmax_experiment/:

  addsub_minmax_ppa.csv       area, leakage, timing, cells, full adders, flops and clock-gate latches
                              per design and target;
  addsub_minmax_power.csv     PrimePower energy per operation per design, target, function and mode;
  addsub_minmax_savings.csv   per tier, target, pipelining and adder: the fused unit against the
                              separate pair (area; energy per function against the gated pair, the
                              unit serving the function alone, and against both units switching);
  addsub_minmax_selected.csv  the same with each unit on its own better adder (lower energy: the
                              AddSub alone in AddSub, the fused unit summed over its two functions)
                              and, for the late-select pair, its better register form;
  addsub_minmax_reg_savings.csv, addsub_minmax_reg_selected.csv
                              the same for mmr/asr (controls registered in the FU); the pair's Min/Max
                              is m2/m4 (single-cycle) or m2o/m4o (registered), the late-select pair's
                              AddSub is asr_*o.
cells.txt (each netlist's cell-type histogram) is written next to every netlist.v found.
"""
from __future__ import annotations

import re
from pathlib import Path

from collect_mode_left import lane_width, pp_parse, probs
from collect_rerun import DESIGNS, PERIOD, fmt, parse, saving, write

ROOT = Path(__file__).resolve().parent
OUT = "addsub_minmax_experiment"
RAW = ROOT / OUT / "raw"
THIRD = ROOT / "3rd_run" / "raw"
TIERS = ("d2", "d4", "d8")
MINMAX = {"d2": "minmax_m2", "d4": "minmax_m4", "d8": "minmax_m4"}
ADDERS = ("seg", "csel")
# pipelining -> (fused suffix, AddSub-alone suffixes, Min/Max suffixes): each unit of the separate
# pair takes the lower-energy of its suffixes
PIPELINES = {"none": ("", ("",), ("",)), "output register": ("o", ("o",), ("o",)),
             "retimed register": ("p", ("p",), ("p",)), "late select": ("l", ("o", "p"), ("o", "p"))}
# controls registered in the FU: no retimed form (retiming would move the control registers)
PIPELINES_REG = {"none": ("", ("",), ("",)), "output register": ("o", ("o",), ("o",)),
                 "late select": ("l", ("o",), ("o",))}


def raw_of(d: str, c: str) -> Path:
    return RAW if (RAW / d / c).is_dir() else THIRD


def cells(d: str, c: str) -> dict[str, int]:
    """Cell-type histogram of the netlist (cells.txt, refreshed from netlist.v when present)."""
    path = raw_of(d, c) / d / c
    if (path / "netlist.v").exists():
        hist: dict[str, int] = {}
        for ref in re.findall(r"^\s+SAEDRVT14_(\w+?)_\w*\s+\S+\s*\(", (path / "netlist.v").read_text(), re.M):
            hist[ref] = hist.get(ref, 0) + 1
        (path / "cells.txt").write_text("".join(f"{n} {k}\n" for k, n in sorted(hist.items())))
    f = path / "cells.txt"
    return {k: int(v) for v, k in (l.split() for l in f.read_text().splitlines())} if f.exists() else {}


def weighted_energy(d: str, c: str, func: str, modes: set[int] | None = None) -> float:
    """Mode-weighted energy per operation (pJ) of a function, over `modes` (default: all run)."""
    pp = pp_parse(d, c, func, raw_of(d, c))
    w = {m: probs(d, func).get(lane_width(DESIGNS[d][2], m), 0.0) for m in pp if modes is None or m in modes}
    tot = sum(w.values())
    return sum(pp[m]["energy_pj"] * w[m] for m in w) / tot if tot else float("nan")


def leakage_pj(d: str, c: str) -> float:
    """Leakage energy per operation of an idle unit (pJ), from its PrimePower run."""
    pp = pp_parse(d, c, "", raw_of(d, c))
    return next(iter(pp.values()))["leakage_uw"] * PERIOD[c] * 1e-3 if pp else float("nan")


def cheapest(designs: list[str], c: str) -> str | None:
    """The design with the lowest mode-weighted energy (single-function units) among those run."""
    run = [d for d in designs if (raw_of(d, c) / d / c / "result.txt").exists()]
    return min(run, key=lambda d: weighted_energy(d, c, "")) if run else None


def comparison(tier: str, c: str, pipeline: str, adder: str, fused: str, alone: str | None,
               minmax: str | None) -> dict | None:
    if alone is None or minmax is None:
        return None
    if not all((raw_of(d, c) / d / c / "result.txt").exists() for d in (fused, alone, minmax)):
        return None
    dc = {d: parse(raw_of(d, c) / d / c, PERIOD[c]) for d in (fused, alone, minmax)}
    row = {"tier": tier, "corner": c, "pipelining": pipeline, "adder": adder, "fused": fused, "addsub_alone": alone,
           "minmax_alone": minmax, "timing_met": str(all(v["timing_met"] for v in dc.values())).lower(),
           "fused_area_um2": fmt(dc[fused]["area_um2"]), "addsub_area_um2": fmt(dc[alone]["area_um2"]),
           "minmax_area_um2": fmt(dc[minmax]["area_um2"]),
           "area_saving_vs_pair_percent": fmt(saving(dc[alone]["area_um2"] + dc[minmax]["area_um2"],
                                                     dc[fused]["area_um2"]), 3),
           "side_function_area_cost_percent": fmt(-saving(dc[alone]["area_um2"], dc[fused]["area_um2"]), 3)}
    mm_modes = set(pp_parse(minmax, c, "", raw_of(minmax, c)))   # lane widths the separate Min/Max runs
    for func, active, idle in (("addsub", alone, minmax), ("minmax", minmax, alone)):
        modes = None if func == "addsub" else mm_modes
        e_fused = weighted_energy(fused, c, func, modes)
        e_active = weighted_energy(active, c, "", modes)
        e_idle = weighted_energy(idle, c, "", mm_modes)   # the other unit switching in the same modes
        gated = e_active + leakage_pj(idle, c)
        row |= {f"{func}_fused_pj": fmt(e_fused), f"{func}_alone_pj": fmt(e_active),
                f"{func}_saving_vs_gated_percent": fmt(saving(gated, e_fused), 3),
                f"{func}_saving_vs_both_percent": fmt(saving(e_active + e_idle, e_fused), 3)}
    return row


def main() -> None:
    designs = sorted(d for d in DESIGNS if (RAW / d).is_dir())
    corners = [c for c in PERIOD if any((RAW / d / c).is_dir() for d in designs)]

    ppa, power = [], []
    for d in designs:
        for c in corners:
            if not (RAW / d / c / "result.txt").exists():
                continue
            v, h = parse(RAW / d / c, PERIOD[c]), cells(d, c)
            ppa.append({"design": d, "capability": DESIGNS[d][2], "corner": c, "target_period_ns": fmt(PERIOD[c], 3),
                        "achieved_delay_ns": fmt(v["delay_ns"]), "timing_met": str(v["timing_met"]).lower(),
                        "cell_area_um2": fmt(v["area_um2"]), "static_leakage_power_uw": fmt(v["static_uw"]),
                        "cells": sum(h.values()), "full_adder_cells": h.get("ADDF", 0),
                        "flops": sum(n for k, n in h.items() if k.startswith("FD")),
                        "clock_gate_latches": sum(n for k, n in h.items() if k.startswith("LD"))})
            for func in (["addsub", "minmax"] if DESIGNS[d][0] == "addsub_mm" else [""]):
                for m, e in pp_parse(d, c, func, RAW).items():
                    power.append({"design": d, "corner": c, "function": func or DESIGNS[d][0], "mode": m,
                                  "lane_width": lane_width(DESIGNS[d][2], m), "energy_per_op_pj": fmt(e["energy_pj"]),
                                  "dynamic_mw": fmt(e["dynamic_mw"]), "leakage_uw": fmt(e["leakage_uw"]),
                                  "nets_annotated_percent": fmt(e["annotated_pct"], 2)})
    write(f"{OUT}/addsub_minmax_ppa.csv", ppa)
    write(f"{OUT}/addsub_minmax_power.csv", power)

    for tag, fused_pre, alone_pre, pipelines, original in (("", "mm", "as", PIPELINES, True),
                                                           ("_reg", "mmr", "asr", PIPELINES_REG, False)):
        sav, sel = [], []
        for tier in TIERS:
            for c in corners:
                orig = comparison(tier, c, "original", "segmented (original)", f"addsub_minmax_{tier}",
                                  f"addsub_{tier}", MINMAX[tier]) if original else None
                sav += [orig] if orig else []
                for pipeline, (fp, aps, mps) in pipelines.items():
                    minmax = cheapest([MINMAX[tier] + mp for mp in mps], c)
                    for a in ADDERS:
                        alone = cheapest([f"{alone_pre}_{a}{ap}_{tier}" for ap in aps], c)
                        r = comparison(tier, c, pipeline, a, f"{fused_pre}_{a}{fp}_{tier}", alone, minmax)
                        sav += [r] if r else []
                    fused = [f"{fused_pre}_{a}{fp}_{tier}" for a in ADDERS]
                    if not all((RAW / d / c / "result.txt").exists() for d in fused):
                        continue
                    f = min(fused, key=lambda d: sum(weighted_energy(d, c, fn) for fn in ("addsub", "minmax")))
                    alone = cheapest([f"{alone_pre}_{a}{ap}_{tier}" for a in ADDERS for ap in aps], c)
                    r = comparison(tier, c, pipeline, "selected", f, alone, minmax)
                    sel += [r] if r else []
        write(f"{OUT}/addsub_minmax{tag}_savings.csv", sav)
        write(f"{OUT}/addsub_minmax{tag}_selected.csv", sel)


if __name__ == "__main__":
    main()
