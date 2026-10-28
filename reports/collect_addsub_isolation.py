#!/usr/bin/env python3
"""Collect the AddSub isolation experiment (why AddSub's gated-bank power was worst at 500 MHz).

The AddSub tiers (d1, d2, d4, d8) and fixed bank (64, 32x2, 16x4, 8x8) were added at 400 MHz and
600 MHz (synth/syn_rerun.tcl, NETLIST=1 CLOSURE=1) into addsub_isolation_experiment/raw; d4, d8 and
every fixed unit were also run at 450, 550, 700, 800 and 900 MHz to bracket where their adder
structure changes. The look-ahead set (addsub_la_*: d2, d4, d8 and the four fixed units on one
explicit parallel-prefix adder, rtl/fu_add_sub_prefix.sv) was run at every target, so the same
adder architecture is compared throughout. Every run was also simulated without delays
(run_primepower.py, ZERO_DELAY=1): the timed-minus-zero-delay difference is glitch power. Timed
results for 100 MHz, 500 MHz, 1 GHz, 1.5 GHz and 2 GHz come from the third run (3rd_run/raw);
cells.txt holds each netlist's cell-type histogram (ADDF = ripple-carry full-adder cells).
collect() is shared with collect_addsub_window_fix.py. Writes, in addsub_isolation_experiment/:

  addsub_isolation_ppa.csv      area, leakage, timing and adder structure per design and target;
  addsub_isolation_power.csv    timed and zero-delay PrimePower per design, target and mode, with
                                the glitch power and glitch share;
  addsub_isolation_savings.csv  decomposable unit vs fixed bank (COMPARISONS) per target and mode
                                (and mode-weighted): DC area and leakage, and PrimePower against a
                                gated and an all-active bank, timed and zero-delay.
"""
from __future__ import annotations

import re
from pathlib import Path

from collect_mode_left import lane_width, pp_parse, probs
from collect_rerun import DESIGNS, PERIOD, fmt, parse, saving, write

ROOT = Path(__file__).resolve().parent
OUT = "addsub_isolation_experiment"
RAW = ROOT / OUT / "raw"                 # 400-900 MHz runs, the look-ahead set, every zero-delay run
THIRD = ROOT / "3rd_run" / "raw"         # timed runs at the other targets
TIERS = ["addsub_d1", "addsub_d2", "addsub_d4", "addsub_d8"]
FIXED = ["addsub_fix_64", "addsub_fix_32x2", "addsub_fix_16x4", "addsub_fix_8x8"]
# the same units on one explicit parallel-prefix adder at every target (rtl/fu_add_sub_prefix.sv)
LA_TIERS = ["addsub_la_d2", "addsub_la_d4", "addsub_la_d8"]
LA_FIXED = ["addsub_la_fix_64", "addsub_la_fix_32x2", "addsub_la_fix_16x4", "addsub_la_fix_8x8"]
ADDER = {**dict.fromkeys(TIERS, "segmented"), **dict.fromkeys(FIXED, "DesignWare"),
         **dict.fromkeys(LA_TIERS + LA_FIXED, "look-ahead")}
# comparison -> decomposable unit -> bank (fixed units for the modes it supports)
COMPARISONS = {
    "segmented vs DesignWare bank": dict(zip(TIERS[1:], (FIXED[:2], FIXED[:3], FIXED))),
    "look-ahead vs look-ahead bank": dict(zip(LA_TIERS, (LA_FIXED[:2], LA_FIXED[:3], LA_FIXED))),
    "look-ahead vs DesignWare bank": dict(zip(LA_TIERS, (FIXED[:2], FIXED[:3], FIXED))),
}


def find(raws: list[Path], d: str, c: str, entry: str) -> Path | None:
    """The first raw directory holding <design>/<corner>/<entry>."""
    return next((r for r in raws if (r / d / c / entry).exists()), None)


def cells(raws: list[Path], d: str, c: str) -> dict[str, int]:
    r = find(raws, d, c, "cells.txt")
    f = r / d / c / "cells.txt" if r else None
    return {k: int(v) for v, k in (l.split() for l in f.read_text().splitlines())} if f else {}


def collect(out: str, stem: str, designs: list[str], comparisons: dict[str, dict[str, list[str]]],
            adder: dict[str, str], raws: list[Path], extra: dict[str, str] | None = None) -> None:
    """Write <out>/<stem>_{ppa,power,savings}.csv: per-design PPA and power for `designs`, and
    each comparison's decomposable unit against its bank. Each design and target is read from the
    first directory in `raws` that has it (each PrimePower run separately). `extra` adds PrimePower
    runs beyond timed and zero-delay: column tag -> run (primepower_<run>/)."""
    need = list(dict.fromkeys(designs + [x for cmp in comparisons.values() for dec, bank in cmp.items()
                                         for x in (dec, *bank)]))
    timed = {(d, c): r for d in need for c in PERIOD if (r := find(raws, d, c, "result.txt"))}
    have = list(timed)
    corners = [c for c in PERIOD if any(k[1] == c for k in have)]
    dc = {(d, c): parse(timed[(d, c)] / d / c, PERIOD[c]) for d, c in have}
    tp = {(d, c): pp_parse(d, c, "", timed[(d, c)]) for d, c in have}
    runs = {"zero_delay": "zero", **(extra or {})}
    pp = {tag: {(d, c): pp_parse(d, c, run, r) if (r := find(raws, d, c, f"primepower_{run}")) else {}
                for d, c in have} for tag, run in runs.items()}
    zp = pp["zero_delay"]

    ppa = []
    for d, c in [k for k in have if k[0] in designs]:
        v, h = dc[(d, c)], cells(raws, d, c)
        ppa.append({"design": d, "adder": adder[d], "role": DESIGNS[d][1], "capability": DESIGNS[d][2],
                    "corner": c,
                    "target_period_ns": fmt(PERIOD[c], 3), "source": timed[(d, c)].parent.name,
                    "achieved_delay_ns": fmt(v["delay_ns"]), "timing_met": str(v["timing_met"]).lower(),
                    "cell_area_um2": fmt(v["area_um2"]), "static_leakage_power_uw": fmt(v["static_uw"]),
                    "cells": sum(h.values()) if h else "",
                    "ripple_full_adder_cells": sum(n for k, n in h.items() if k.startswith("ADDF")) if h else ""})
    write(f"{out}/{stem}_ppa.csv", ppa)

    pw = []
    for d, c in [k for k in have if k[0] in designs]:
        for m, t in tp[(d, c)].items():
            z = zp[(d, c)].get(m)
            g = t["total_mw"] - z["total_mw"] if z else float("nan")
            row = {"design": d, "adder": adder[d], "capability": DESIGNS[d][2], "corner": c, "mode": m,
                   "lane_width": lane_width(DESIGNS[d][2], m), "lanes": t["lanes"],
                   "timed_total_mw": fmt(t["total_mw"]), "timed_dynamic_mw": fmt(t["dynamic_mw"]),
                   "leakage_uw": fmt(t["leakage_uw"]), "timed_energy_per_op_pj": fmt(t["energy_pj"]),
                   "zero_delay_total_mw": fmt(z["total_mw"]) if z else "",
                   "zero_delay_energy_per_op_pj": fmt(z["energy_pj"]) if z else "",
                   "glitch_mw": fmt(g), "glitch_share_percent": fmt(100 * g / t["total_mw"], 2),
                   "nets_annotated_percent": fmt(t["annotated_pct"], 2)}
            for tag in extra or {}:
                x = pp[tag][(d, c)].get(m)
                row[f"{tag}_total_mw"] = fmt(x["total_mw"]) if x else ""
                row[f"{tag}_energy_per_op_pj"] = fmt(x["energy_pj"]) if x else ""
            pw.append(row)
    write(f"{out}/{stem}_power.csv", pw)

    sav = []
    for label, banks in comparisons.items():
        for dec, bank in banks.items():
            for c in [c for c in corners if all((x, c) in dc for x in (dec, *bank))]:
                D = dc[(dec, c)]
                area = saving(sum(dc[(b, c)]["area_um2"] for b in bank), D["area_um2"])
                leak = saving(sum(dc[(b, c)]["static_uw"] for b in bank), D["static_uw"])
                ok = all(dc[(x, c)]["timing_met"] for x in (dec, *bank))
                acc, wsum = {}, 0.0
                for m in tp[(dec, c)]:
                    width = lane_width(DESIGNS[dec][2], m)
                    comp = {lane_width(DESIGNS[b][2]): b for b in bank}
                    if width not in comp:
                        continue
                    row = {"comparison": label, "decomposable": dec, "bank": " + ".join(bank), "corner": c,
                           "mode": f"mode{m}",
                           "lane_width": width, "active_bank_unit": comp[width], "timing_met": str(ok).lower(),
                           "area_saving_percent": fmt(area, 3), "static_saving_percent": fmt(leak, 3)}
                    vals = {}
                    for tag, P in (("timed", tp), *pp.items()):
                        if not P[(dec, c)].get(m) or any(not P[(b, c)] for b in bank):
                            continue
                        dec_mw = P[(dec, c)][m]["total_mw"]
                        act = P[(comp[width], c)][0]["total_mw"]
                        idle = sum(P[(b, c)][0]["leakage_uw"] for b in bank if b != comp[width]) * 1e-3
                        every = sum(P[(b, c)][0]["total_mw"] for b in bank)
                        vals[tag] = (dec_mw, act + idle, every)
                        row.update({f"{tag}_dec_mw": fmt(dec_mw), f"{tag}_gated_bank_mw": fmt(act + idle),
                                    f"{tag}_all_active_bank_mw": fmt(every),
                                    f"{tag}_saving_vs_gated_percent": fmt(saving(act + idle, dec_mw), 3),
                                    f"{tag}_saving_vs_all_active_percent": fmt(saving(every, dec_mw), 3)})
                    sav.append(row)
                    p = probs(dec).get(width, 0.0)
                    if p:
                        wsum += p
                        for tag, v in vals.items():
                            acc[tag] = [a + p * x for a, x in zip(acc.get(tag, [0.0, 0.0, 0.0]), v)]
                if wsum:
                    row = {"comparison": label, "decomposable": dec, "bank": " + ".join(bank), "corner": c,
                           "mode": "weighted",
                           "lane_width": "mode probabilities", "active_bank_unit": "", "timing_met": str(ok).lower(),
                           "area_saving_percent": fmt(area, 3), "static_saving_percent": fmt(leak, 3)}
                    for tag, (d_mw, g_mw, a_mw) in acc.items():
                        d_mw, g_mw, a_mw = d_mw / wsum, g_mw / wsum, a_mw / wsum
                        row.update({f"{tag}_dec_mw": fmt(d_mw), f"{tag}_gated_bank_mw": fmt(g_mw),
                                    f"{tag}_all_active_bank_mw": fmt(a_mw),
                                    f"{tag}_saving_vs_gated_percent": fmt(saving(g_mw, d_mw), 3),
                                    f"{tag}_saving_vs_all_active_percent": fmt(saving(a_mw, d_mw), 3)})
                    sav.append(row)
    keys = []
    for r in sav:
        keys += [k for k in r if k not in keys]
    write(f"{out}/{stem}_savings.csv", [{k: r.get(k, "") for k in keys} for r in sav])
    print(f"corners {corners}; ppa {len(ppa)}, power {len(pw)}, savings {len(sav)}")


def main() -> None:
    collect(OUT, "addsub_isolation", TIERS + FIXED + LA_TIERS + LA_FIXED, COMPARISONS, ADDER, [RAW, THIRD])


if __name__ == "__main__":
    main()
