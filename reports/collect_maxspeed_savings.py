#!/usr/bin/env python3
"""Compare symmetric 0.010 ns stress runs using achieved Fmax and energy/op."""
from pathlib import Path
import csv, re

ROOT = Path(__file__).resolve().parent
DEC = ROOT / "synth_maxspeed_decomp"
FIX = ROOT / "synth_maxspeed_fixed"
OUT = ROOT / "maxspeed_savings.csv"
BANK = {
    "addsub_d4": ("addsub_64", "addsub_32x2", "addsub_16x4"),
    "mult_decomp": ("mult_64", "mult_32x2", "mult_16x4"),
    "minmax_m4": ("minmax_64", "minmax_32x2", "minmax_16x4"),
    "fp_minmax_m3": ("fp_minmax_64", "fp_minmax_32x2", "fp_minmax_16x4"),
    "fp_cmp_g3": ("fp_cmp_64", "fp_cmp_32x2", "fp_cmp_16x4"),
    "cmp_c4": ("cmp_64", "cmp_32x2", "cmp_16x4"),
    "rounding_g3": ("rounding_64", "rounding_32x2", "rounding_16x4"),
    "barrel_bs3": ("barrel_64", "barrel_32x2", "barrel_16x4"),
    "abs_a3": ("abs_64", "abs_32x2", "abs_16x4"),
}
FIELDS = ["FU", "fixed_area_um2", "decomposable_area_um2", "area_saving_percent",
          "fixed_power_mw", "decomposable_power_mw", "power_saving_percent",
          "fixed_leakage_uw", "decomposable_leakage_uw", "leakage_saving_percent",
          "fixed_energy_pj", "decomposable_energy_pj", "energy_saving_percent",
          "fixed_fmax_ghz", "decomposable_fmax_ghz", "frequency_change_percent",
          "comparison_valid", "notes"]

def read(d):
    result = (d / "result.txt").read_text(errors="replace")
    area = (d / "report_area.rpt").read_text(errors="replace")
    power = (d / "report_power.rpt").read_text(errors="replace")
    def n(p, t):
        m = re.search(p, t, re.M); return float(m.group(1)) if m else 0.0
    def pw(label):
        m = re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)", power, re.M)
        if not m: return 0.0
        return float(m.group(1))*{"W":1000,"mW":1,"uW":1e-3,"nW":1e-6}[m.group(2)]
    return {"area": n(r"Total cell area:\s+([0-9.eE+-]+)", area),
            "power": pw("Total Dynamic Power"), "leak": pw("Cell Leakage Power")*1000,
            "fmax": n(r"FMAX_GHZ=([0-9.eE+-]+)", result)}

def pct(a,b): return 100*(a-b)/a if a else 0
out=[]
for fu, comps in BANK.items():
    d = read(DEC / fu)
    c = [read(FIX / x) for x in comps]
    area=sum(x["area"] for x in c); power=sum(x["power"] for x in c); leak=sum(x["leak"] for x in c)
    fmax=min(x["fmax"] for x in c); de=d["power"]/d["fmax"] if d["fmax"] else 0; fe=power/fmax if fmax else 0
    out.append({"FU":fu,"fixed_area_um2":f"{area:.6f}","decomposable_area_um2":f"{d['area']:.6f}","area_saving_percent":f"{pct(area,d['area']):.6f}",
      "fixed_power_mw":f"{power:.6f}","decomposable_power_mw":f"{d['power']:.6f}","power_saving_percent":f"{pct(power,d['power']):.6f}",
      "fixed_leakage_uw":f"{leak:.6f}","decomposable_leakage_uw":f"{d['leak']:.6f}","leakage_saving_percent":f"{pct(leak,d['leak']):.6f}",
      "fixed_energy_pj":f"{fe:.6f}","decomposable_energy_pj":f"{de:.6f}","energy_saving_percent":f"{pct(fe,de):.6f}",
      "fixed_fmax_ghz":f"{fmax:.9f}","decomposable_fmax_ghz":f"{d['fmax']:.9f}","frequency_change_percent":f"{100*(d['fmax']-fmax)/fmax:.6f}",
      "comparison_valid":"true","notes":"symmetric 0.010 ns stress; achieved Fmax and energy/op shown, not primary equal-frequency result"})
with OUT.open("w",newline="") as f:
    w=csv.DictWriter(f,fieldnames=FIELDS); w.writeheader(); w.writerows(out)
print(f"wrote {len(out)} rows to {OUT}")
