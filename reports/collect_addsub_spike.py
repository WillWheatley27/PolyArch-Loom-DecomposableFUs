#!/usr/bin/env python3
"""Collect the AddSub spike experiment: decomposable AddSub variants against the 500-900 MHz
gated-bank power spike (rtl/fu_add_sub_spike.sv), synthesized into addsub_spike_experiment/raw
(synth/syn_rerun.tcl, NETLIST=1 CLOSURE=1) and simulated timed, without delays and with every op
held at add (synth/run_primepower.py; plain, ZERO_DELAY=1, HOLD_OPS=1):

  segser   segmented adder, serial lane-op decode (the original structure, rebuilt as a check);
  segflat  segmented adder, flat lane-op decode;
  cselser  carry-select at bit 32, serial lane-op decode;
  csel     carry-select at bit 32, flat lane-op decode;
  dwcselser / dwcsel  the carry-select built from DesignWare duplex adders (d2 and d4 only);
  segrep / cselrep    segmented / carry-select with op_sel replicated per block (REP_OP);
  csel16rep           carry-select at every 16 bits, op_sel replicated per block;
  dwcselrep           the DesignWare carry-select with op_sel replicated per block (d2, d4);
  segreg / cselreg / csel16reg  the selected structures with the per-block op copy made in the FU
                      (OP_REG: lane-start op_sel and mode a cycle ahead, decoded and registered in
                      the FU), simulated with inputs one flop clock-to-output after each edge
                      (run_primepower.py INPUT_CLK_Q): light (the netlist's fastest CK->Q, an
                      upstream data register with a light load; the main runs) and matched (the
                      mean CK->Q of its flops; primepower_matched/, primepower_ops_held_matched/);
  segfast / cselfast / csel16fast  the same with the op registers kept per block and sized to their
                      strongest flop (syn_rerun.tcl FAST_OP_REGS=1), every target, light timing.

The DesignWare bank and the original segmented tiers come from the isolation and window-fix
experiments (and the third run). Writes, in addsub_spike_experiment/ (the isolation tables'
columns, from collect_addsub_isolation.collect, plus ops_held_*):

  addsub_spike_ppa.csv      area, leakage, timing and cell counts per variant and target;
  addsub_spike_power.csv    timed, zero-delay and ops-held PrimePower per variant, target and mode;
  addsub_spike_savings.csv  each variant (and the original segmented tiers) against the
                            DesignWare bank per target and mode, and mode-weighted;
  addsub_spike_selected.csv per tier and target, the replicated-op variant whose worse saving
                            against the gated bank (random ops or ops held) is highest (select);
  addsub_spike_selected_fast.csv  the same choice among the fast-op-register variants (SELECT_FAST);
  addsub_spike_op_copy.csv  per tier and target, the original tier, the selected structure with the
                            op copy upstream, the same structure with the copy in the FU, and the
                            copy in the FU with fast op registers on its own choice: energy, savings
                            against the gated and all-active bank, area;
  addsub_spike_static_mode_*.csv  the same for variants synthesized with mode as a static input
                            (syn_rerun.tcl STATIC_MODE=1; raw_static_mode/).
"""
from __future__ import annotations

import csv

from collect_addsub_isolation import FIXED, RAW as ISO_RAW, ROOT, THIRD, TIERS, collect
from collect_mode_left import lane_width, pp_parse, probs
from collect_rerun import DESIGNS, PERIOD, saving, write

OUT = "addsub_spike_experiment"
VARIANTS = {"segser": "segmented, serial decode", "segflat": "segmented, flat decode",
            "cselser": "carry-select 32, serial decode", "csel": "carry-select 32, flat decode",
            "dwcselser": "DesignWare carry-select 32, serial decode",
            "dwcsel": "DesignWare carry-select 32, flat decode",
            "segrep": "segmented, op replicated per block", "cselrep": "carry-select 32, op replicated per block",
            "csel16rep": "carry-select 16, op replicated per block",
            "dwcselrep": "DesignWare carry-select 32, op replicated per block",
            "segreg": "segmented, op copied in the FU", "cselreg": "carry-select 32, op copied in the FU",
            "csel16reg": "carry-select 16, op copied in the FU",
            "segfast": "segmented, op copied in the FU, fast op registers",
            "cselfast": "carry-select 32, op copied in the FU, fast op registers",
            "csel16fast": "carry-select 16, op copied in the FU, fast op registers"}
BANKS = (FIXED[:2], FIXED[:3], FIXED)   # banks of the d2, d4 and d8 tiers
# candidates for the per-target selection: the variants with op_sel replicated per block
SELECT_FROM = ("segrep", "cselrep", "csel16rep")
# the same choice for the op copy made in the FU with fast per-block op registers
SELECT_FAST = ("segfast", "cselfast", "csel16fast")


def select(savings: list[dict], candidates: tuple[str, ...] = SELECT_FROM) -> list[dict]:
    """Per tier and target, the candidate whose worse mode-weighted saving against the gated bank,
    over random ops (timed) and ops held at add, is highest: a choice that does not depend on how
    often the op changes."""
    rows = {}
    for r in savings:
        v = r["decomposable"].split("_")[1]
        if r["mode"] != "weighted" or v not in candidates or not r.get("ops_held_saving_vs_gated_percent"):
            continue
        worst = min(float(r["timed_saving_vs_gated_percent"]), float(r["ops_held_saving_vs_gated_percent"]))
        key = (r["decomposable"].rsplit("_", 1)[1], r["corner"])
        if key not in rows or worst > rows[key][0]:
            rows[key] = (worst, r)
    out = []
    for (tier, c), (worst, r) in sorted(rows.items(), key=lambda kv: (kv[0][0], list(PERIOD).index(kv[0][1]))):
        out.append({"tier": tier, "corner": c, "selected": r["decomposable"],
                    "saving_vs_gated_random_ops_percent": r["timed_saving_vs_gated_percent"],
                    "saving_vs_gated_ops_held_percent": r["ops_held_saving_vs_gated_percent"],
                    "worse_of_the_two_percent": f"{worst:.3f}",
                    "saving_vs_all_active_random_ops_percent": r["timed_saving_vs_all_active_percent"],
                    "area_saving_percent": r["area_saving_percent"]})
    return out


def matched_mw(d: str, c: str, run: str) -> float | None:
    """Mode-weighted total power (mW) of a design's primepower_<run>/ (the INPUT_CLK_Q=matched runs)."""
    pp = pp_parse(d, c, run, ROOT / OUT / "raw")
    w = {m: probs(d).get(lane_width(DESIGNS[d][2], m), 0.0) for m in pp}
    return sum(pp[m]["total_mw"] * w[m] for m in pp) / sum(w.values()) if pp else None


def op_copy(selected: list[dict], fast: list[dict], savings: list[dict]) -> list[dict]:
    """Per selected tier and target: the original tier, the selected structure (op copy upstream), the
    same structure with the copy in the FU, and the copy in the FU with fast per-block op registers on
    its own per-target choice (fast), mode-weighted against the DesignWare bank; for the copy in the
    FU also with its inputs matched to its flops' clock-to-output."""
    weighted = {(r["decomposable"], r["corner"]): r for r in savings if r["mode"] == "weighted"}
    fast_pick = {(s["tier"], s["corner"]): s["selected"] for s in fast}
    out = []
    for s in selected:
        c, up = s["corner"], s["selected"]
        designs = {"original": f"addsub_{s['tier']}", "copy upstream": up, "copy in the FU": up.replace("rep_", "reg_"),
                   "copy in the FU, fast op registers": fast_pick.get((s["tier"], c), "")}
        for version, d in designs.items():
            r = weighted.get((d, c))
            if not r:
                continue
            e = lambda k: float(r[k]) * PERIOD[c] if r[k] else float("nan")   # mW * ns = pJ
            out.append({"tier": s["tier"], "corner": c, "version": version, "design": d,
                        "energy_random_ops_pj": f"{e('timed_dec_mw'):.4f}",
                        "energy_ops_held_pj": f"{e('ops_held_dec_mw'):.4f}",
                        "saving_vs_gated_random_ops_percent": r["timed_saving_vs_gated_percent"],
                        "saving_vs_gated_ops_held_percent": r["ops_held_saving_vs_gated_percent"],
                        "saving_vs_all_active_random_ops_percent": r["timed_saving_vs_all_active_percent"],
                        "area_saving_percent": r["area_saving_percent"]})
            row = out[-1]
            for tag, run, gated in (("random_ops", "matched", "timed"), ("ops_held", "ops_held_matched", "ops_held")):
                mw = matched_mw(d, c, run) if version == "copy in the FU" else None
                row[f"matched_energy_{tag}_pj"] = f"{mw * PERIOD[c]:.4f}" if mw else ""
                row[f"matched_saving_vs_gated_{tag}_percent"] = (
                    f"{saving(float(r[f'{gated}_gated_bank_mw']), mw):.3f}" if mw else "")
    return out


def main() -> None:
    raw = ROOT / OUT / "raw"
    tiers = {v: [f"addsub_{v}_d{d}" for d in (2, 4, 8)] for v in VARIANTS}
    run = [d for t in tiers.values() for d in t if (raw / d).is_dir()]
    comparisons = {"segmented (original) vs DesignWare bank": dict(zip(TIERS[1:], BANKS))}
    comparisons |= {f"{label} vs DesignWare bank": {d: b for d, b in zip(tiers[v], BANKS) if d in run}
                    for v, label in VARIANTS.items()}
    adder = {d: VARIANTS[d.split("_")[1]] for d in run}
    adder |= {**dict.fromkeys(TIERS, "segmented (original)"), **dict.fromkeys(FIXED, "DesignWare")}
    assert all(d in DESIGNS for d in run)
    bank_raws = [ROOT / "addsub_window_fix_experiment" / "raw", ISO_RAW, THIRD]
    collect(OUT, "addsub_spike", run, comparisons, adder, [raw] + bank_raws, extra={"ops_held": "ops_held"})
    with open(ROOT / OUT / "addsub_spike_savings.csv") as f:
        savings = list(csv.DictReader(f))
    selected = select(savings)
    fast = select(savings, SELECT_FAST)
    write(f"{OUT}/addsub_spike_selected.csv", selected)
    write(f"{OUT}/addsub_spike_selected_fast.csv", fast)
    write(f"{OUT}/addsub_spike_op_copy.csv", op_copy(selected, fast, savings))
    # the same variants synthesized with mode as a static input (STATIC_MODE=1); the bank has no mode
    static = ROOT / OUT / "raw_static_mode"
    srun = [d for d in run if (static / d).is_dir()]
    scomp = {label: {d: b for d, b in banks.items() if d in srun} for label, banks in comparisons.items()}
    collect(OUT, "addsub_spike_static_mode", srun, {k: v for k, v in scomp.items() if v}, adder,
            [static] + bank_raws, extra={"ops_held": "ops_held"})


if __name__ == "__main__":
    main()
