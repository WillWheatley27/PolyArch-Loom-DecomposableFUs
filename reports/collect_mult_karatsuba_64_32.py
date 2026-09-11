#!/usr/bin/env python3
from __future__ import annotations
import csv, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "mult_karatsuba_64_32_comparison"
PPA_OUT = ROOT / "mult_karatsuba_64_32_ppa.csv"
SAVINGS_OUT = ROOT / "mult_karatsuba_64_32_savings.csv"
FIELDS = ["name","kind","capability","corner","target_period_ns","achieved_delay_ns","fmax_ghz","cell_area_um2","total_area_um2","dynamic_power_mw","leakage_power_uw","energy_per_operation_pj","timing_met","activity_source"]
SFIELDS = ["corner","baseline","baseline_definition","fixed_area_um2","decomposable_area_um2","area_saving_percent","fixed_power_mw","decomposable_power_mw","power_saving_percent","fixed_leakage_uw","decomposable_leakage_uw","leakage_saving_percent","fixed_energy_pj","decomposable_energy_pj","energy_saving_percent","fixed_fmax_ghz","decomposable_fmax_ghz","frequency_change_percent","comparison_valid","notes"]

def n(p,t):
    m=re.search(p,t,re.M); return float(m.group(1)) if m else 0.0
def meta(k,t):
    m=re.search(rf"(?:^|\s){k}=([^\s]+)",t); return m.group(1) if m else ""
def power(label,t):
    m=re.search(rf"{label}\s*=\s*([0-9.eE+-]+)\s*(W|mW|uW|nW)",t,re.M)
    return float(m.group(1))*{"W":1000,"mW":1,"uW":1e-3,"nW":1e-6}[m.group(2)] if m else 0.0
def pct(a,b): return 100*(a-b)/a if a else 0.0

def collect():
    rows=[]
    for corner in sorted(p for p in SRC.iterdir() if p.is_dir()):
        for d in sorted(p for p in corner.iterdir() if p.is_dir()):
            result=(d/'result.txt').read_text(errors='replace'); area=(d/'report_area.rpt').read_text(errors='replace'); pwr=(d/'report_power.rpt').read_text(errors='replace')
            period=n(r'TARGET_PERIOD_NS=([0-9.eE+-]+)',result); delay=n(r'ARRIVAL_NS=([0-9.eE+-]+)',result); fmax=n(r'FMAX_GHZ=([0-9.eE+-]+)',result); dyn=power('Total Dynamic Power',pwr)
            cell_area=n(r'Total cell area:\s+([0-9.eE+-]+)',area); total_area=n(r'Total area:\s+([0-9.eE+-]+)',area); leak=power('Cell Leakage Power',pwr)*1000
            rows.append({'name':d.name,'kind':meta('KIND',result),'capability':meta('CAPABILITY',result),'corner':corner.name,'target_period_ns':f'{period:.6f}','achieved_delay_ns':f'{delay:.6f}','fmax_ghz':f'{fmax:.9f}','cell_area_um2':f'{cell_area:.6f}','total_area_um2':f'{total_area:.6f}','dynamic_power_mw':f'{dyn:.6f}','leakage_power_uw':f'{leak:.6f}','energy_per_operation_pj':f'{dyn/fmax if fmax else 0:.6f}','timing_met':str(delay<=period+1e-6).lower(),'activity_source':'uniform_synthetic'})
    return rows

def main():
    rows=collect(); by={(r['corner'],r['name']):r for r in rows}
    banks={'fixed_karatsuba':('karatsuba_fixed_64','karatsuba_fixed_32x2'),'fixed_designware':('designware_fixed_64','designware_fixed_32x2')}
    out=[]
    for corner in sorted({r['corner'] for r in rows}):
        dec=by[(corner,'karatsuba_decomposable')]
        for baseline,names in banks.items():
            cs=[by[(corner,x)] for x in names]; area=sum(float(x['cell_area_um2']) for x in cs); pwr=sum(float(x['dynamic_power_mw']) for x in cs); leak=sum(float(x['leakage_power_uw']) for x in cs); fmax=min(float(x['fmax_ghz']) for x in cs); energy=pwr/fmax if fmax else 0; df=float(dec['dynamic_power_mw']); darea=float(dec['cell_area_um2']); dleak=float(dec['leakage_power_uw']); dfmax=float(dec['fmax_ghz']); de=df/dfmax if dfmax else 0; valid=dec['timing_met']=='true' and all(x['timing_met']=='true' for x in cs)
            out.append({'corner':corner,'baseline':baseline,'baseline_definition':' + '.join(names),'fixed_area_um2':f'{area:.6f}','decomposable_area_um2':f'{darea:.6f}','area_saving_percent':f'{pct(area,darea):.6f}','fixed_power_mw':f'{pwr:.6f}','decomposable_power_mw':f'{df:.6f}','power_saving_percent':f'{pct(pwr,df):.6f}','fixed_leakage_uw':f'{leak:.6f}','decomposable_leakage_uw':f'{dleak:.6f}','leakage_saving_percent':f'{pct(leak,dleak):.6f}','fixed_energy_pj':f'{energy:.6f}','decomposable_energy_pj':f'{de:.6f}','energy_saving_percent':f'{pct(energy,de):.6f}','fixed_fmax_ghz':f'{fmax:.9f}','decomposable_fmax_ghz':f'{dfmax:.9f}','frequency_change_percent':f'{100*(dfmax-fmax)/fmax if fmax else 0:.6f}','comparison_valid':str(valid).lower(),'notes':'packed 32x2 counted once; synthetic all-active bank power; same timing target'} )
    with PPA_OUT.open('w',newline='') as f: csv.DictWriter(f,fieldnames=FIELDS).writeheader();
    with PPA_OUT.open('a',newline='') as f: csv.DictWriter(f,fieldnames=FIELDS).writerows(rows)
    with SAVINGS_OUT.open('w',newline='') as f: w=csv.DictWriter(f,fieldnames=SFIELDS); w.writeheader(); w.writerows(out)
    print(f'wrote {len(rows)} rows to {PPA_OUT}'); print(f'wrote {len(out)} rows to {SAVINGS_OUT}')
if __name__=='__main__': main()
