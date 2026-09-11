#!/usr/bin/env python3
"""Compare combined AddSub/MinMax against separate decomposable units."""
from pathlib import Path
import csv, re

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "addsub_minmax"
PPA = ROOT / "ppa_summary.csv"
OUT = ROOT / "addsub_minmax_savings.csv"
FIELDS = ["corner", "separate_area_um2", "combined_area_um2", "area_saving_percent",
          "separate_power_mw", "combined_power_mw", "power_saving_percent",
          "separate_leakage_uw", "combined_leakage_uw", "leakage_saving_percent",
          "separate_energy_pj", "combined_energy_pj", "energy_saving_percent",
          "separate_fmax_ghz", "combined_fmax_ghz", "frequency_change_percent",
          "comparison_valid", "notes"]

def n(pattern, text):
    m = re.search(pattern, text, re.M); return float(m.group(1)) if m else 0.0
def pw(label, text):
    m = re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)", text, re.M)
    if not m: return 0.0
    return float(m.group(1))*{"W":1000,"mW":1,"uW":1e-3,"nW":1e-6}[m.group(2)]
def read(d):
    result=(d/"result.txt").read_text(errors="replace")
    area=(d/"report_area.rpt").read_text(errors="replace")
    power=(d/"report_power.rpt").read_text(errors="replace")
    return {"area":n(r"Total cell area:\s+([0-9.eE+-]+)",area),
            "power":pw("Total Dynamic Power",power),
            "leak":pw("Cell Leakage Power",power)*1000,
            "fmax":n(r"FMAX_GHZ=([0-9.eE+-]+)",result),
            "valid":n(r"ARRIVAL_NS=([0-9.eE+-]+)",result) <= n(r"TARGET_PERIOD_NS=([0-9.eE+-]+)",result)+1e-6}
def pct(a,b): return 100*(a-b)/a if a else 0.0

ppa=list(csv.DictReader(PPA.open())) if PPA.exists() else []
out=[]
for tag, corner in (("one_ghz","one_ghz"),("feasible","feasible")):
    combined=read(SRC/tag)
    rows=[r for r in ppa if r["implementation"]=="decomposable" and r["corner"]==corner]
    add=next((r for r in rows if r["FU"]=="addsub_d4"),None)
    mm=next((r for r in rows if r["FU"]=="minmax_m4"),None)
    if not add or not mm:
        continue
    area=float(add["cell_area_um2"])+float(mm["cell_area_um2"])
    power=float(add["dynamic_power_mw"])+float(mm["dynamic_power_mw"])
    leak=float(add["leakage_power_uw"])+float(mm["leakage_power_uw"])
    fmax=min(float(add["fmax_ghz"]),float(mm["fmax_ghz"]))
    sep_energy=power/fmax if fmax else 0.0
    comb_energy=combined["power"]/combined["fmax"] if combined["fmax"] else 0.0
    valid=combined["valid"] and add["timing_met"]=="true" and mm["timing_met"]=="true"
    out.append({"corner":corner,"separate_area_um2":f"{area:.6f}","combined_area_um2":f"{combined['area']:.6f}","area_saving_percent":f"{pct(area,combined['area']):.6f}",
      "separate_power_mw":f"{power:.6f}","combined_power_mw":f"{combined['power']:.6f}","power_saving_percent":f"{pct(power,combined['power']):.6f}",
      "separate_leakage_uw":f"{leak:.6f}","combined_leakage_uw":f"{combined['leak']:.6f}","leakage_saving_percent":f"{pct(leak,combined['leak']):.6f}",
      "separate_energy_pj":f"{sep_energy:.6f}","combined_energy_pj":f"{comb_energy:.6f}","energy_saving_percent":f"{pct(sep_energy,comb_energy):.6f}",
      "separate_fmax_ghz":f"{fmax:.9f}","combined_fmax_ghz":f"{combined['fmax']:.9f}","frequency_change_percent":f"{100*(combined['fmax']-fmax)/fmax:.6f}" if fmax else "0",
      "comparison_valid":str(valid).lower(),"notes":"separate = decomposable AddSub d4 + decomposable integer MinMax m4; combined reuses one segmented AddSub chain"})
with OUT.open("w",newline="") as f:
    w=csv.DictWriter(f,fieldnames=FIELDS); w.writeheader(); w.writerows(out)
print(f"wrote {len(out)} rows to {OUT}")
