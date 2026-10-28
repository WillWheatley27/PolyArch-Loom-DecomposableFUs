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
  dwcselrep           the DesignWare carry-select with op_sel replicated per block (d2, d4).

The DesignWare bank and the original segmented tiers come from the isolation and window-fix
experiments (and the third run). Writes, in addsub_spike_experiment/ (the isolation tables'
columns, from collect_addsub_isolation.collect, plus ops_held_*):

  addsub_spike_ppa.csv      area, leakage, timing and cell counts per variant and target;
  addsub_spike_power.csv    timed, zero-delay and ops-held PrimePower per variant, target and mode;
  addsub_spike_savings.csv  each variant (and the original segmented tiers) against the
                            DesignWare bank per target and mode, and mode-weighted;
  addsub_spike_selected.csv per tier and target, the replicated-op variant whose worse saving
                            against the gated bank (random ops or ops held) is highest (select);
  addsub_spike_static_mode_*.csv  the same for variants synthesized with mode as a static input
                            (syn_rerun.tcl STATIC_MODE=1; raw_static_mode/).
"""
from __future__ import annotations

import csv

from collect_addsub_isolation import FIXED, RAW as ISO_RAW, ROOT, THIRD, TIERS, collect
from collect_rerun import DESIGNS, PERIOD, write

OUT = "addsub_spike_experiment"
VARIANTS = {"segser": "segmented, serial decode", "segflat": "segmented, flat decode",
            "cselser": "carry-select 32, serial decode", "csel": "carry-select 32, flat decode",
            "dwcselser": "DesignWare carry-select 32, serial decode",
            "dwcsel": "DesignWare carry-select 32, flat decode",
            "segrep": "segmented, op replicated per block", "cselrep": "carry-select 32, op replicated per block",
            "csel16rep": "carry-select 16, op replicated per block",
            "dwcselrep": "DesignWare carry-select 32, op replicated per block"}
BANKS = (FIXED[:2], FIXED[:3], FIXED)   # banks of the d2, d4 and d8 tiers
# candidates for the per-target selection: the variants with op_sel replicated per block
SELECT_FROM = ("segrep", "cselrep", "csel16rep")


def select(savings: list[dict]) -> list[dict]:
    """Per tier and target, the candidate whose worse mode-weighted saving against the gated bank,
    over random ops (timed) and ops held at add, is highest: a choice that does not depend on how
    often the op changes."""
    rows = {}
    for r in savings:
        v = r["decomposable"].split("_")[1]
        if r["mode"] != "weighted" or v not in SELECT_FROM or not r.get("ops_held_saving_vs_gated_percent"):
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
        write(f"{OUT}/addsub_spike_selected.csv", select(list(csv.DictReader(f))))
    # the same variants synthesized with mode as a static input (STATIC_MODE=1); the bank has no mode
    static = ROOT / OUT / "raw_static_mode"
    srun = [d for d in run if (static / d).is_dir()]
    scomp = {label: {d: b for d, b in banks.items() if d in srun} for label, banks in comparisons.items()}
    collect(OUT, "addsub_spike_static_mode", srun, {k: v for k, v in scomp.items() if v}, adder,
            [static] + bank_raws, extra={"ops_held": "ops_held"})


if __name__ == "__main__":
    main()
