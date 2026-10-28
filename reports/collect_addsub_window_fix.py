#!/usr/bin/env python3
"""Collect the AddSub window-fix experiment: three rewrites of the decomposable AddSub
(rtl/fu_add_sub_window_fix.sv) aimed at the 500-900 MHz gated-bank power window found by the
isolation experiment, each as tiers d2, d4 and d8, synthesized at every target
(synth/syn_rerun.tcl, NETLIST=1 CLOSURE=1) into addsub_window_fix_experiment/raw and simulated
timed and without delays (synth/run_primepower.py, plain and ZERO_DELAY=1):

  partitioned      fu_add_sub_part: one `+` with a guard bit at each breakable lane boundary;
  block-increment  fu_add_sub_blkinc: lane-width blocks, block generate/propagate carries and a
                   per-block incrementer;
  pipelined-64     fu_add_sub_pipe: the partitioned adder with 64-bit operations finished in a
                   second, clock-gated cycle.

The DesignWare bank and the original segmented tiers are read from the isolation experiment
(and the third run). A diagnostic run with every op held at add (run_primepower.py, HOLD_OPS=1;
primepower_ops_held/) covers d4, d8, their fixes and the bank, and fills the ops_held_* columns.
Writes, in addsub_window_fix_experiment/ (the isolation tables' columns, from
collect_addsub_isolation.collect, plus ops_held_*):

  addsub_window_fix_ppa.csv      area, leakage, timing and cell counts per design and target;
  addsub_window_fix_power.csv    timed and zero-delay PrimePower per design, target and mode;
  addsub_window_fix_savings.csv  each fix (and the original segmented tiers) against the
                                 DesignWare bank per target and mode, and mode-weighted.
"""
from __future__ import annotations

from collect_addsub_isolation import FIXED, RAW as ISO_RAW, ROOT, THIRD, TIERS, collect

OUT = "addsub_window_fix_experiment"
FIXES = {"partitioned": "part", "block-increment": "blkinc", "pipelined-64": "pipe"}
TIERS_OF = {label: [f"addsub_{v}_d{d}" for d in (2, 4, 8)] for label, v in FIXES.items()}
BANKS = (FIXED[:2], FIXED[:3], FIXED)   # banks of the d2, d4 and d8 tiers


def main() -> None:
    comparisons = {"segmented vs DesignWare bank": dict(zip(TIERS[1:], BANKS))}
    comparisons |= {f"{label} vs DesignWare bank": dict(zip(tiers, BANKS)) for label, tiers in TIERS_OF.items()}
    adder = {d: label for label, tiers in TIERS_OF.items() for d in tiers}
    adder |= {**dict.fromkeys(TIERS, "segmented"), **dict.fromkeys(FIXED, "DesignWare")}
    collect(OUT, "addsub_window_fix", [d for t in TIERS_OF.values() for d in t], comparisons, adder,
            [ROOT / OUT / "raw", ISO_RAW, THIRD], extra={"ops_held": "ops_held"})


if __name__ == "__main__":
    main()
