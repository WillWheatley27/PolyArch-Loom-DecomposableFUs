#!/usr/bin/env python3
"""Simulation-based dynamic power for every synthesized design (VCS + PrimePower).

For each design and corner synthesized with `NETLIST=1` (synth/syn_rerun.tcl):
  1. build a gate-level testbench from the netlist's own port list;
  2. simulate it in VCS with the SDF delays, once per supported mode (and per function of a
     multi-function unit, see FUNCTIONS), applying one new
     operation per clock period from a shared stimulus file (identical operands and control
     bits for every design) with `mode` held, and record switching activity (SAIF) for the
     design only, after a one-operation warm-up;
  3. run PrimePower (averaged mode) with the wire-load model Design Compiler used, reading
     each mode's SAIF, and keep report_power and the annotation report.

Usage: run_primepower.py <raw_dir> <work_dir> [design ...]   (default: every design)
PrimePower reports land in <raw_dir>/<design>/<corner>/primepower/ (primepower_<function>/ for a
multi-function unit); SAIFs and builds stay in <work_dir>.
"""
from __future__ import annotations

import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "reports"))
from collect_rerun import DESIGNS, PERIOD  # noqa: E402  single design catalog

CELLS = Path("/mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/verilog/base")
LIB_DIR = "/mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base"
LIB = "saed14rvt_base_tt0p8v25c.db"
NVEC = 20000
SEED = 20260930
# Multi-function units: family -> function -> control inputs held for the whole run.
FUNCTIONS = {"addsub_minmax": {"addsub": {"is_min_max": 0}, "minmax": {"is_min_max": 1}}}
ENV = ("module load synopsys/vcs/Y-2026.03-SP1 synopsys/prime/Y-2026.03-SP1 >/dev/null 2>&1; "
       "export SNPS_CONTAINER_BIND=/mnt/nas0,/edata1,/tmp; ")


def modes_of(design: str, has_mode: bool) -> list[int]:
    """Supported mode encodings: mode i selects (64 >> i)-bit lanes."""
    cap = DESIGNS[design][2]
    if not has_mode or "/" not in cap:
        return [0]
    return list(range(cap.count("/") + 1))


def lanes(design: str, mode: int) -> int:
    cap = DESIGNS[design][2]
    if "/" in cap or DESIGNS[design][1] == "tier":
        return 1 << mode
    m = re.search(r"x(\d+)$", cap)
    return int(m.group(1)) if m else 1


def ports(netlist: Path, top: str) -> list[tuple[str, str, int]]:
    """(direction, name, width) of the top module."""
    text = netlist.read_text()
    body = text[text.index(f"module {top} "):]
    body = body[:body.index(");") + 2] + body[body.index(");") + 2:].split("endmodule")[0]
    out = []
    for d, rng, names in re.findall(r"\b(input|output)\s+(\[\d+:\d+\])?\s*([^;]+);", body):
        w = 1
        if rng:
            hi, lo = map(int, rng[1:-1].split(":"))
            w = hi - lo + 1
        for n in names.split(","):
            out.append((d, n.strip(), w))
    return out


def testbench(top: str, plist: list[tuple[str, str, int]], held: set[str]) -> str:
    conns, decls, drive, cbit = [], [], [], 0
    for d, n, w in plist:
        rng = f"[{w - 1}:0] " if w > 1 else ""
        if d == "output":
            decls.append(f"  wire {rng}{n};")
        elif n == "clk":
            decls.append(f"  wire {n} = 1'b0;")
        elif n == "rst_n" or n.startswith("in_valid") or n == "out_ready":
            decls.append(f"  wire {n} = 1'b1;")
        elif n == "mode" or n in held:  # held for the whole run, set by plusarg
            v = "mode_val" if n == "mode" else f"held_{n}"
            decls.append(f"  logic {rng}{n};")
            drive.append(f"    {n} = {w}'({v});")
        elif n in ("in_data_0", "in_data_1"):
            decls.append(f"  logic {rng}{n};")
            drive.append(f"    {n} = {'a' if n.endswith('0') else 'b'}[i][{w - 1}:0];")
        else:  # control inputs: distinct bits of the shared control word
            decls.append(f"  logic {rng}{n};")
            drive.append(f"    {n} = c[i][{cbit + w - 1}:{cbit}];")
            cbit += w
        conns.append(f".{n}({n})")
    assert cbit <= 32, top
    return f"""`timescale 1ns/1ps
module tb;
  localparam int N = {NVEC};
  logic [63:0] a [N], b [N];
  logic [31:0] c [N];
  int mode_val; real period; string saif;
{"".join(f"  int held_{n};{chr(10)}" for n in sorted(held))}
{chr(10).join(decls)}
  {top} dut ({", ".join(conns)});
  task automatic apply(input int i);
{chr(10).join(drive)}
  endtask
  initial begin
    if (!$value$plusargs("MODE=%d", mode_val)) mode_val = 0;
    if (!$value$plusargs("PERIOD=%f", period)) period = 1.0;
    if (!$value$plusargs("SAIF=%s", saif)) $fatal(1, "SAIF");
{"".join(f'    if (!$value$plusargs("{n}=%d", held_{n})) $fatal(1, "{n}");{chr(10)}' for n in sorted(held))}
    $readmemh("{{STIM_A}}", a); $readmemh("{{STIM_B}}", b); $readmemh("{{STIM_C}}", c);
    $sdf_annotate("{{SDF}}", dut);
    apply(0); #(period);
    $set_gate_level_monitoring("on");
    $set_toggle_region(tb.dut);
    $toggle_start;
    for (int i = 1; i < N; i++) begin apply(i); #(period); end
    $toggle_stop;
    $toggle_report(saif, 1.0e-9, "tb.dut");
    $finish;
  end
endmodule
"""


def stimulus(work: Path) -> dict[str, Path]:
    rng = random.Random(SEED)
    files = {}
    for key, bits in (("A", 64), ("B", 64), ("C", 32)):
        p = work / f"stim_{key.lower()}.hex"
        p.write_text("".join(f"{rng.getrandbits(bits):0{bits // 4}x}\n" for _ in range(NVEC)))
        files[key] = p
    return files


def wire_load(dc_power: Path, top: str) -> str:
    m = re.search(rf"^{re.escape(top)}\s+(\S+)\s+saed14", dc_power.read_text(), re.MULTILINE)
    return m.group(1) if m else "8000"


def run(cmd: str, cwd: Path, log: Path) -> int:
    with log.open("w") as f:
        return subprocess.call(["bash", "-lc", ENV + cmd], cwd=cwd, stdout=f, stderr=subprocess.STDOUT)


def one(design: str, corner: str, raw: Path, work: Path, stim: dict[str, Path]) -> str:
    src = raw / design / corner
    top = re.search(r"TOP=(\S+)", (src / "result.txt").read_text()).group(1)
    w = work / design / corner
    w.mkdir(parents=True, exist_ok=True)
    plist = ports(src / "netlist.v", top)
    has_mode = any(n == "mode" for _, n, _ in plist)
    funcs = FUNCTIONS.get(DESIGNS[design][0], {"": {}})
    held = {n for hold in funcs.values() for n in hold}
    tb = testbench(top, plist, held).replace("{SDF}", str(src / "netlist.sdf"))
    for k, p in stim.items():
        tb = tb.replace("{STIM_" + k + "}", str(p))
    (w / "tb.sv").write_text(tb)
    if run(f"vcs -full64 -sverilog -timescale=1ns/1ps +neg_tchk -o simv tb.sv {src / 'netlist.v'} "
           f"{CELLS / 'saed14rvt_base.v'} {CELLS / 'saed14rvt_base_udp.v'}", w, w / "vcs.log"):
        return f"{design} {corner} VCS COMPILE FAILED"
    modes = modes_of(design, has_mode)
    lic = True
    for func, hold in funcs.items():
        tag = f"{func}_" if func else ""
        plus = "".join(f" +{n}={v}" for n, v in hold.items())
        for m in modes:
            if run(f"./simv +MODE={m} +PERIOD={PERIOD[corner]} +SAIF={tag}mode{m}.saif{plus}", w, w / f"sim_{tag}{m}.log"):
                return f"{design} {corner} SIM {func} mode {m} FAILED"
        out = src / ("primepower_" + func if func else "primepower")
        out.mkdir(exist_ok=True)
        tcl = [f"set search_path [list . {LIB_DIR}]", f"set link_library [list * {LIB}]",
               "set power_enable_analysis true", "set power_analysis_mode averaged",
               f"read_verilog {src / 'netlist.v'}", f"current_design {top}", "link",
               "set_wire_load_mode top",
               f"set_wire_load_model -name {wire_load(src / 'report_power.rpt', top)} -library saed14rvt_base_tt0p8v25c",
               f"read_sdc {src / 'netlist.sdc'}"]
        for m in modes:
            tcl += ["reset_switching_activity", f"read_saif {w / f'{tag}mode{m}.saif'} -strip_path tb/dut",
                    f"report_switching_activity > {out / f'activity_mode{m}.rpt'}", "update_power",
                    f"report_power > {out / f'power_mode{m}.rpt'}"]
        (w / f"{tag}power.tcl").write_text("\n".join(tcl + ["quit"]) + "\n")
        if run(f"pt_shell -f {tag}power.tcl", w, w / f"{tag}pt.log"):
            return f"{design} {corner} PRIMEPOWER {func} FAILED"
        lic = lic and "PrimePower" in (w / f"{tag}pt.log").read_text()
        (out / "info.txt").write_text(f"TOP={top} MODES={','.join(map(str, modes))} "
                                      f"LANES={','.join(str(lanes(design, m)) for m in modes)} NVEC={NVEC} "
                                      f"PERIOD_NS={PERIOD[corner]} SEED={SEED}"
                                      + "".join(f" {n}={v}" for n, v in hold.items()) + "\n")
    return f"{design} {corner} ok modes={modes} functions={list(funcs)} license={'yes' if lic else 'NO'}"


def main() -> None:
    raw, work = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    designs = sys.argv[3:] or list(DESIGNS)
    work.mkdir(parents=True, exist_ok=True)
    stim = stimulus(work)
    jobs = [(d, c) for d in designs for c in PERIOD if (raw / d / c / "netlist.v").exists()]
    with ThreadPoolExecutor(max_workers=6) as ex:
        for msg in ex.map(lambda dc: one(dc[0], dc[1], raw, work, stim), jobs):
            print(msg, flush=True)


if __name__ == "__main__":
    main()
