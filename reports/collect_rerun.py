#!/usr/bin/env python3
"""Collect the full SAED14nm PPA rerun and compare it with the original data.

The rerun (synth/syn_rerun.tcl, reports/rerun/raw) synthesizes every capability tier and
fixed-bank component of the nine decomposable FU families on the normalized flow, one
design per fresh dc_shell session, at 1.000 ns and 0.500 ns. Writes:

  PPA_rerun.csv       one row per design and corner: area, static (leakage) power first,
                      then dynamic power split into internal and switching, plus the
                      original values and the rerun-minus-original change;
  rerun_overhead.csv  adjacent capability-tier overhead (as tier_ladders/marginal.csv);
  rerun_savings.csv   decomposable unit versus the fixed bank (as savings_summary.csv),
                      plus each wide-only tier versus its fixed wide unit;
each with the original value and the change in percentage points.
"""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "rerun" / "raw"
PERIOD = {"one_ghz": 1.0, "two_ghz": 0.5}

# ---- Designs: name -> (family, role, capability) --------------------------------------
DESIGNS = {
    "addsub_d1": ("addsub", "tier", "64"), "addsub_d2": ("addsub", "tier", "64/32x2"),
    "addsub_d4": ("addsub", "tier", "64/32x2/16x4"), "addsub_d8": ("addsub", "tier", "64/32x2/16x4/8x8"),
    "addsub_fix_64": ("addsub", "fixed", "64"), "addsub_fix_32x2": ("addsub", "fixed", "32x2"),
    "addsub_fix_16x4": ("addsub", "fixed", "16x4"), "addsub_fix_8x8": ("addsub", "fixed", "8x8"),
    "minmax_m1": ("minmax", "tier", "64"), "minmax_m2": ("minmax", "tier", "64/32x2"),
    "minmax_m4": ("minmax", "tier", "64/32x2/16x4"),
    "minmax_fix_64": ("minmax", "fixed", "64"), "minmax_fix_32x2": ("minmax", "fixed", "32x2"),
    "minmax_fix_16x4": ("minmax", "fixed", "16x4"),
    "cmp_c1": ("cmp", "tier", "64"), "cmp_c2": ("cmp", "tier", "64/32x2"),
    "cmp_c4": ("cmp", "tier", "64/32x2/16x4"), "cmp_c8": ("cmp", "tier", "64/32x2/16x4/8x8"),
    "cmp_fix_64": ("cmp", "fixed", "64"), "cmp_fix_32x2": ("cmp", "fixed", "32x2"),
    "cmp_fix_16x4": ("cmp", "fixed", "16x4"), "cmp_fix_8x8": ("cmp", "fixed", "8x8"),
    "abs_a1": ("abs", "tier", "64"), "abs_a2": ("abs", "tier", "64/32x2"), "abs_a3": ("abs", "tier", "64/32x2/16x4"),
    "abs_fix_32x2": ("abs", "fixed", "32x2"), "abs_fix_16x4": ("abs", "fixed", "16x4"),
    "barrel_bs1": ("barrel", "tier", "64"), "barrel_bs2": ("barrel", "tier", "64/32x2"),
    "barrel_bs3": ("barrel", "tier", "64/32x2/16x4"),
    "barrel_fix_32x2": ("barrel", "fixed", "32x2"), "barrel_fix_16x4": ("barrel", "fixed", "16x4"),
    "fp_cmp_g1": ("fp_cmp", "tier", "FP64"), "fp_cmp_g2": ("fp_cmp", "tier", "FP64/FP32x2"),
    "fp_cmp_g3": ("fp_cmp", "tier", "FP64/FP32x2/FP16x4"),
    "fp_cmp_fix_64": ("fp_cmp", "fixed", "FP64"), "fp_cmp_fix_32x2": ("fp_cmp", "fixed", "FP32x2"),
    "fp_cmp_fix_16x4": ("fp_cmp", "fixed", "FP16x4"),
    "fp_minmax_m1": ("fp_minmax", "tier", "FP64"), "fp_minmax_m2": ("fp_minmax", "tier", "FP64/FP32x2"),
    "fp_minmax_m3": ("fp_minmax", "tier", "FP64/FP32x2/FP16x4"),
    "fp_minmax_fix_64": ("fp_minmax", "fixed", "FP64"), "fp_minmax_fix_32x2": ("fp_minmax", "fixed", "FP32x2"),
    "fp_minmax_fix_16x4": ("fp_minmax", "fixed", "FP16x4"),
    "rounding_g1": ("rounding", "tier", "FP64"), "rounding_g2": ("rounding", "tier", "FP64/FP32x2"),
    "rounding_g3": ("rounding", "tier", "FP64/FP32x2/FP16x4"),
    "rounding_fix_32x2": ("rounding", "fixed", "FP32x2"), "rounding_fix_16x4": ("rounding", "fixed", "FP16x4"),
    "mult_k64": ("mult", "tier", "64"), "mult_k64_32": ("mult", "tier", "64/32x2"),
    "mult_k64_32_16": ("mult", "tier", "64/32x2/16x4"),
    "mult_kfix_32x2": ("mult", "fixed_karatsuba", "32x2"), "mult_kfix_16x4": ("mult", "fixed_karatsuba", "16x4"),
    "mult_dwfix_64": ("mult", "fixed_designware", "64"), "mult_dwfix_32x2": ("mult", "fixed_designware", "32x2"),
    "mult_dwfix_16x4": ("mult", "fixed_designware", "16x4"),
    # AddSub with Min/Max as a side function of its carry chain (fu_add_sub_minmax_gen.sv)
    "addsub_minmax_d1": ("addsub_minmax", "tier", "64"), "addsub_minmax_d2": ("addsub_minmax", "tier", "64/32x2"),
    "addsub_minmax_d4": ("addsub_minmax", "tier", "64/32x2/16x4"),
    "addsub_minmax_d8": ("addsub_minmax", "tier", "64/32x2/16x4/8x8"),
    # FP32 -> 2xFP16 split of the FP min/max two-level experiment (the same sliced core at W=32)
    "fp_minmax_w32_m1": ("fp_minmax", "tier", "FP32"), "fp_minmax_w32_m2": ("fp_minmax", "tier", "FP32/FP16x2"),
    "fp_minmax_fix_32": ("fp_minmax", "fixed", "FP32"), "fp_minmax_fix_16x2": ("fp_minmax", "fixed", "FP16x2"),
}
TIERS = {  # family -> ordered capability ladder
    "addsub": ["addsub_d1", "addsub_d2", "addsub_d4", "addsub_d8"],
    "minmax": ["minmax_m1", "minmax_m2", "minmax_m4"],
    "cmp": ["cmp_c1", "cmp_c2", "cmp_c4", "cmp_c8"],
    "abs": ["abs_a1", "abs_a2", "abs_a3"],
    "barrel": ["barrel_bs1", "barrel_bs2", "barrel_bs3"],
    "fp_cmp": ["fp_cmp_g1", "fp_cmp_g2", "fp_cmp_g3"],
    "fp_minmax": ["fp_minmax_m1", "fp_minmax_m2", "fp_minmax_m3"],
    "rounding": ["rounding_g1", "rounding_g2", "rounding_g3"],
    "mult": ["mult_k64", "mult_k64_32", "mult_k64_32_16"],
    "addsub_minmax": ["addsub_minmax_d1", "addsub_minmax_d2", "addsub_minmax_d4", "addsub_minmax_d8"],
    "fp_minmax_w32": ["fp_minmax_w32_m1", "fp_minmax_w32_m2"],
}
# savings rows: (family, decomposable, bank components, bank label, original savings key)
SAVINGS = [
    ("addsub", "addsub_d4", ["addsub_fix_64", "addsub_fix_32x2", "addsub_fix_16x4"], "64 + 32x2 + 16x4", ("summary", "addsub_d4")),
    ("addsub", "addsub_d8", ["addsub_fix_64", "addsub_fix_32x2", "addsub_fix_16x4", "addsub_fix_8x8"], "64 + 32x2 + 16x4 + 8x8", None),
    ("minmax", "minmax_m4", ["minmax_fix_64", "minmax_fix_32x2", "minmax_fix_16x4"], "64 + 32x2 + 16x4", ("summary", "minmax_m4")),
    ("cmp", "cmp_c4", ["cmp_fix_64", "cmp_fix_32x2", "cmp_fix_16x4"], "64 + 32x2 + 16x4", ("summary", "cmp_c4")),
    ("cmp", "cmp_c8", ["cmp_fix_64", "cmp_fix_32x2", "cmp_fix_16x4", "cmp_fix_8x8"], "64 + 32x2 + 16x4 + 8x8", None),
    ("abs", "abs_a3", ["abs_a1", "abs_fix_32x2", "abs_fix_16x4"], "a1 + 32x2 + 16x4", ("summary", "abs_a3")),
    ("barrel", "barrel_bs3", ["barrel_bs1", "barrel_fix_32x2", "barrel_fix_16x4"], "bs1 + 32x2 + 16x4", ("summary", "barrel_bs3")),
    ("fp_cmp", "fp_cmp_g3", ["fp_cmp_fix_64", "fp_cmp_fix_32x2", "fp_cmp_fix_16x4"], "DW FP64 + FP32x2 + FP16x4", ("summary", "fp_cmp_g3")),
    ("fp_minmax", "fp_minmax_m3", ["fp_minmax_fix_64", "fp_minmax_fix_32x2", "fp_minmax_fix_16x4"], "DW FP64 + FP32x2 + FP16x4", ("summary", "fp_minmax_m3")),
    ("rounding", "rounding_g3", ["rounding_g1", "rounding_fix_32x2", "rounding_fix_16x4"], "g1 + FP32x2 + FP16x4", ("summary", "rounding_g3")),
    ("mult", "mult_k64_32_16", ["mult_dwfix_64", "mult_dwfix_32x2", "mult_dwfix_16x4"], "DW 64 + 32x2 + 16x4", ("summary", "mult_decomp")),
    ("mult", "mult_k64_32_16", ["mult_k64", "mult_kfix_32x2", "mult_kfix_16x4"], "Karatsuba 64 + 32x2 + 16x4", ("kara", "Karatsuba fixed bank")),
    ("mult", "mult_k64_32", ["mult_dwfix_64", "mult_dwfix_32x2"], "DW 64 + 32x2", ("kara6432", "fixed_designware")),
    ("mult", "mult_k64_32", ["mult_k64", "mult_kfix_32x2"], "Karatsuba 64 + 32x2", ("kara6432", "fixed_karatsuba")),
    # wide-only tier versus the fixed wide unit (same capability)
    ("addsub", "addsub_d1", ["addsub_fix_64"], "standalone 64", None),  # original banks use the standalone 64
    ("minmax", "minmax_m1", ["minmax_fix_64"], "fu_min_max 64", None),
    ("cmp", "cmp_c1", ["cmp_fix_64"], "standalone 64", None),
    ("fp_cmp", "fp_cmp_g1", ["fp_cmp_fix_64"], "DW FP64", ("revised", "fp_cmp_rev64")),
    ("fp_minmax", "fp_minmax_m1", ["fp_minmax_fix_64"], "DW FP64", ("revised", "fp_minmax_rev64")),
    ("mult", "mult_k64", ["mult_dwfix_64"], "DW 64", None),
    # FP min/max two-level experiment: one split at each width, and each wide-only tier
    ("fp_minmax", "fp_minmax_m2", ["fp_minmax_fix_64", "fp_minmax_fix_32x2"], "DW FP64 + FP32x2", None),
    ("fp_minmax", "fp_minmax_w32_m2", ["fp_minmax_fix_32", "fp_minmax_fix_16x2"], "DW FP32 + FP16x2", None),
    ("fp_minmax", "fp_minmax_w32_m1", ["fp_minmax_fix_32"], "DW FP32", None),
    # AddSub with a Min/Max side function versus separate AddSub and Min/Max units
    # (Min/Max has no 8x8 tier, so d8 pairs with m4)
    ("addsub_minmax", "addsub_minmax_d1", ["addsub_d1", "minmax_m1"], "AddSub d1 + MinMax m1", None),
    ("addsub_minmax", "addsub_minmax_d2", ["addsub_d2", "minmax_m2"], "AddSub d2 + MinMax m2", None),
    ("addsub_minmax", "addsub_minmax_d4", ["addsub_d4", "minmax_m4"], "AddSub d4 + MinMax m4", None),
    ("addsub_minmax", "addsub_minmax_d8", ["addsub_d8", "minmax_m4"], "AddSub d8 + MinMax m4", None),
]


# ---- Parsing ------------------------------------------------------------------------------
def number(pattern: str, text: str) -> float:
    m = re.search(pattern, text, re.MULTILINE)
    return float(m.group(1)) if m else float("nan")


def power_mw(label: str, text: str) -> float:
    m = re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW|pW)", text, re.MULTILINE)
    scale = {"W": 1e3, "mW": 1.0, "uW": 1e-3, "nW": 1e-6, "pW": 1e-9}
    return float(m.group(1)) * scale[m.group(2)] if m else float("nan")


def parse(path: Path, period: float) -> dict[str, float | bool]:
    res = (path / "result.txt").read_text()
    area = (path / "report_area.rpt").read_text()
    pwr = (path / "report_power.rpt").read_text()
    delay = number(r"ARRIVAL_NS=([0-9.eE+-]+)", res)
    return {"delay_ns": delay, "fmax_ghz": number(r"FMAX_GHZ=([0-9.eE+-]+)", res),
            "timing_met": delay <= period + 1e-6,
            "area_um2": number(r"Total cell area:\s+([0-9.eE+-]+)", area),
            "static_uw": power_mw("Cell Leakage Power", pwr) * 1e3,
            "internal_mw": power_mw("Cell Internal Power", pwr),
            "switching_mw": power_mw("Net Switching Power", pwr),
            "dynamic_mw": power_mw("Total Dynamic Power", pwr)}


def rows_of(name: str) -> list[dict[str, str]]:
    with (ROOT / name).open() as f:
        return list(csv.DictReader(f))


# ---- Original data --------------------------------------------------------------------------
def load_originals() -> dict[tuple[str, str], list[tuple[str, dict[str, float]]]]:
    """(design, corner) -> [(source, {area_um2, static_uw, dynamic_mw})], primary first."""
    orig: dict[tuple[str, str], list] = {}

    def add(design, corner, source, area, static, dynamic):
        orig.setdefault((design, corner), []).append(
            (source, {"area_um2": float(area), "static_uw": float(static), "dynamic_mw": float(dynamic)}))

    ladder = {"abs": ("abs", "a"), "cmp": ("cmp", "c"), "barrel_shift": ("barrel", "bs"),
              "rounding": ("rounding", "g"), "fp_cmp": ("fp_cmp", "g"), "fp_minmax": ("fp_minmax", "m")}
    for r in rows_of("tier_ladders/ppa.csv"):
        fam, _ = ladder[r["family"]]
        design = f"{fam}_{r['tier']}"
        add(design, r["corner"], "tier_ladders/ppa.csv", r["cell_area_um2"], r["leakage_power_uw"], r["dynamic_power_mw"])
    for r in rows_of("addsub_minmax_tier_ppa.csv"):
        name = r["name"].replace("minmax_fixed_", "minmax_fix_")
        if name in DESIGNS:
            add(name, r["corner"], "addsub_minmax_tier_ppa.csv", r["cell_area_um2"], r["leakage_power_uw"], r["dynamic_power_mw"])
    summary_map = {"addsub_64": "addsub_fix_64", "addsub_32x2": "addsub_fix_32x2", "addsub_16x4": "addsub_fix_16x4",
                   "minmax_64": "minmax_fix_64", "minmax_32x2": "minmax_fix_32x2", "minmax_16x4": "minmax_fix_16x4",
                   "cmp_64": "cmp_fix_64", "cmp_32x2": "cmp_fix_32x2", "cmp_16x4": "cmp_fix_16x4",
                   "abs_64": "abs_a1", "abs_32x2": "abs_fix_32x2", "abs_16x4": "abs_fix_16x4",
                   "barrel_64": "barrel_bs1", "barrel_32x2": "barrel_fix_32x2", "barrel_16x4": "barrel_fix_16x4",
                   "fp_cmp_64": "fp_cmp_fix_64", "fp_cmp_32x2": "fp_cmp_fix_32x2", "fp_cmp_16x4": "fp_cmp_fix_16x4",
                   "fp_minmax_64": "fp_minmax_fix_64", "fp_minmax_32x2": "fp_minmax_fix_32x2",
                   "fp_minmax_16x4": "fp_minmax_fix_16x4",
                   "rounding_64": "rounding_g1", "rounding_32x2": "rounding_fix_32x2", "rounding_16x4": "rounding_fix_16x4",
                   "mult_64": "mult_dwfix_64", "mult_32x2": "mult_dwfix_32x2", "mult_16x4": "mult_dwfix_16x4",
                   "addsub_d4": "addsub_d4", "minmax_m4": "minmax_m4", "cmp_c4": "cmp_c4", "abs_a3": "abs_a3",
                   "barrel_bs3": "barrel_bs3", "fp_cmp_g3": "fp_cmp_g3", "fp_minmax_m3": "fp_minmax_m3",
                   "rounding_g3": "rounding_g3", "mult_decomp": "mult_k64_32_16"}
    for r in rows_of("ppa_summary.csv"):
        if r["FU"] in summary_map and r["corner"] in PERIOD:
            add(summary_map[r["FU"]], r["corner"], "ppa_summary.csv", r["cell_area_um2"], r["leakage_power_uw"], r["dynamic_power_mw"])
    for r in rows_of("mult_karatsuba_64_32_ppa.csv"):
        name = {"karatsuba_decomposable": "mult_k64_32", "karatsuba_fixed_64": "mult_k64",
                "karatsuba_fixed_32x2": "mult_kfix_32x2"}.get(r["name"])
        if name and r["corner"] in PERIOD:
            add(name, r["corner"], "mult_karatsuba_64_32_ppa.csv", r["cell_area_um2"], r["leakage_power_uw"], r["dynamic_power_mw"])
    for r in rows_of("mult_karatsuba_ppa.csv"):
        name = {"karatsuba_decomposable": "mult_k64_32_16", "karatsuba_fixed_64": "mult_k64",
                "karatsuba_fixed_32x2": "mult_kfix_32x2", "karatsuba_fixed_16x4": "mult_kfix_16x4"}.get(r["name"])
        if name and r["corner"] in PERIOD:
            add(name, r["corner"], "mult_karatsuba_ppa.csv", r["cell_area_um2"], r["leakage_power_uw"], r["dynamic_power_mw"])
    return orig


def load_original_savings() -> dict[tuple, dict[str, float]]:
    out = {}
    for r in rows_of("savings_summary.csv"):
        if r["corner"] in PERIOD and r["area_saving_percent"]:
            out[("summary", r["FU"], r["corner"])] = r
    for r in rows_of("mult_karatsuba_savings.csv"):
        if r["corner"] in PERIOD:
            out[("kara", r["baseline"], r["corner"])] = r
    for r in rows_of("mult_karatsuba_64_32_savings.csv"):
        out[("kara6432", r["baseline"], r["corner"])] = r
    for r in rows_of("revised_fp_fus/savings.csv"):
        out[("revised", r["FU"], r["corner"])] = r
    return out


def pct(new: float, old: float) -> float:
    return 100.0 * (new - old) / old


def saving(bank: float, dec: float) -> float:
    return 100.0 * (bank - dec) / bank


def fmt(v, nd=6) -> str:
    return "" if v is None or v != v else f"{v:.{nd}f}"


def write(name: str, rows: list[dict]) -> None:
    with (ROOT / name).open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        w.writeheader(); w.writerows(rows)


def main() -> None:
    data = {(d, c): parse(RAW / d / c, p) for d in DESIGNS for c, p in PERIOD.items()
            if (RAW / d / c / "result.txt").exists()}
    orig = load_originals()

    ppa = []
    for (d, c), v in sorted(data.items(), key=lambda kv: (list(DESIGNS).index(kv[0][0]), kv[0][1])):
        fam, role, cap = DESIGNS[d]
        row = {"family": fam, "design": d, "role": role, "capability": cap, "corner": c,
               "target_period_ns": fmt(PERIOD[c], 3), "achieved_delay_ns": fmt(v["delay_ns"]),
               "fmax_ghz": fmt(v["fmax_ghz"]), "timing_met": str(v["timing_met"]).lower(),
               "cell_area_um2": fmt(v["area_um2"]), "static_leakage_power_uw": fmt(v["static_uw"]),
               "dynamic_power_mw": fmt(v["dynamic_mw"]), "dynamic_internal_mw": fmt(v["internal_mw"]),
               "dynamic_switching_mw": fmt(v["switching_mw"])}
        srcs = orig.get((d, c), [])
        for k, (src, o) in enumerate(srcs[:2]):
            tag = "orig" if k == 0 else "orig_alt"
            row.update({f"{tag}_source": src, f"{tag}_cell_area_um2": fmt(o["area_um2"]),
                        f"{tag}_static_leakage_power_uw": fmt(o["static_uw"]), f"{tag}_dynamic_power_mw": fmt(o["dynamic_mw"]),
                        f"{tag}_delta_area_percent": fmt(pct(v["area_um2"], o["area_um2"]), 2),
                        f"{tag}_delta_static_percent": fmt(pct(v["static_uw"], o["static_uw"]), 2),
                        f"{tag}_delta_dynamic_percent": fmt(pct(v["dynamic_mw"], o["dynamic_mw"]), 2)})
        ppa.append(row)
    keys = []
    for r in ppa:
        keys += [k for k in r if k not in keys]
    ppa = [{k: r.get(k, "") for k in keys} for r in ppa]
    write("PPA_rerun.csv", ppa)

    # Overhead between adjacent tiers.
    orig_marg = {(r["family"], r["from_tier"], r["to_tier"], r["corner"]): r for r in rows_of("tier_ladders/marginal.csv")}
    ladder_fam = {"barrel": "barrel_shift"}
    over = []
    for fam, tiers in TIERS.items():
        for a, b in zip(tiers, tiers[1:]):
            for c in PERIOD:
                if (a, c) not in data or (b, c) not in data:
                    continue
                A, B = data[(a, c)], data[(b, c)]
                row = {"family": fam, "from_tier": a, "to_tier": b, "capability_added": DESIGNS[b][2], "corner": c,
                       "prev_area_um2": fmt(A["area_um2"]), "new_area_um2": fmt(B["area_um2"]),
                       "area_overhead_percent": fmt(pct(B["area_um2"], A["area_um2"]), 3),
                       "static_overhead_percent": fmt(pct(B["static_uw"], A["static_uw"]), 3),
                       "dynamic_overhead_percent": fmt(pct(B["dynamic_mw"], A["dynamic_mw"]), 3),
                       "fmax_change_percent": fmt(pct(B["fmax_ghz"], A["fmax_ghz"]), 3),
                       "timing_met": str(A["timing_met"] and B["timing_met"]).lower()}
                # Original overhead: tier_ladders/marginal.csv, else the primary original PPA values.
                om = orig_marg.get((ladder_fam.get(fam, fam), a.split("_")[-1], b.split("_")[-1], c))
                if om:
                    o = (float(om["area_overhead_percent"]), float(om["leakage_overhead_percent"]),
                         float(om["power_overhead_percent"]), "tier_ladders/marginal.csv")
                elif (a, c) in orig and (b, c) in orig:
                    (sa, oa), (sb, ob) = orig[(a, c)][0], orig[(b, c)][0]
                    o = (pct(ob["area_um2"], oa["area_um2"]), pct(ob["static_uw"], oa["static_uw"]),
                         pct(ob["dynamic_mw"], oa["dynamic_mw"]), sa if sa == sb else f"{sa} -> {sb}")
                else:
                    o = None
                if o:
                    row.update({"orig_source": o[3], "orig_area_overhead_percent": fmt(o[0], 3),
                                "orig_static_overhead_percent": fmt(o[1], 3), "orig_dynamic_overhead_percent": fmt(o[2], 3),
                                "delta_area_pp": fmt(pct(B["area_um2"], A["area_um2"]) - o[0], 3),
                                "delta_static_pp": fmt(pct(B["static_uw"], A["static_uw"]) - o[1], 3),
                                "delta_dynamic_pp": fmt(pct(B["dynamic_mw"], A["dynamic_mw"]) - o[2], 3)})
                over.append(row)
    keys = []
    for r in over:
        keys += [k for k in r if k not in keys]
    write("rerun_overhead.csv", [{k: r.get(k, "") for k in keys} for r in over])

    # Savings against fixed banks.
    osav = load_original_savings()
    sav = []
    for fam, dec, bank, label, okey in SAVINGS:
        for c in PERIOD:
            if (dec, c) not in data or any((b, c) not in data for b in bank):
                continue
            D = data[(dec, c)]
            tot = {m: sum(data[(b, c)][m] for b in bank) for m in ("area_um2", "static_uw", "dynamic_mw")}
            met = D["timing_met"] and all(data[(b, c)]["timing_met"] for b in bank)
            row = {"family": fam, "decomposable": dec, "capability": DESIGNS[dec][2], "bank": label,
                   "bank_components": " + ".join(bank), "corner": c,
                   "bank_area_um2": fmt(tot["area_um2"]), "dec_area_um2": fmt(D["area_um2"]),
                   "area_saving_percent": fmt(saving(tot["area_um2"], D["area_um2"]), 3),
                   "bank_static_uw": fmt(tot["static_uw"]), "dec_static_uw": fmt(D["static_uw"]),
                   "static_saving_percent": fmt(saving(tot["static_uw"], D["static_uw"]), 3),
                   "bank_dynamic_mw": fmt(tot["dynamic_mw"]), "dec_dynamic_mw": fmt(D["dynamic_mw"]),
                   "dynamic_saving_percent": fmt(saving(tot["dynamic_mw"], D["dynamic_mw"]), 3),
                   "timing_met": str(met).lower()}
            o = osav.get((okey[0], okey[1], c)) if okey else None
            if o:
                oa, ol, od = (float(o["area_saving_percent"]), float(o["leakage_saving_percent"]),
                              float(o["power_saving_percent"]))
                row.update({"orig_source": {"summary": "savings_summary.csv", "kara": "mult_karatsuba_savings.csv",
                                            "kara6432": "mult_karatsuba_64_32_savings.csv",
                                            "revised": "revised_fp_fus/savings.csv"}[okey[0]],
                            "orig_area_saving_percent": fmt(oa, 3), "orig_static_saving_percent": fmt(ol, 3),
                            "orig_dynamic_saving_percent": fmt(od, 3),
                            "delta_area_pp": fmt(saving(tot["area_um2"], D["area_um2"]) - oa, 3),
                            "delta_static_pp": fmt(saving(tot["static_uw"], D["static_uw"]) - ol, 3),
                            "delta_dynamic_pp": fmt(saving(tot["dynamic_mw"], D["dynamic_mw"]) - od, 3)})
            sav.append(row)
    keys = []
    for r in sav:
        keys += [k for k in r if k not in keys]
    write("rerun_savings.csv", [{k: r.get(k, "") for k in keys} for r in sav])
    print(f"designs {len({d for d, _ in data})}/{len(DESIGNS)}, ppa rows {len(ppa)}, "
          f"overhead rows {len(over)}, savings rows {len(sav)}")


if __name__ == "__main__":
    main()
