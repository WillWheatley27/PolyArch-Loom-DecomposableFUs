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
Optional: ZERO_DELAY=1 simulates without SDF or cell delays (no glitches) and writes
primepower_zero/ (primepower_zero_<function>/); the difference from the timed run is glitch power.
Optional: HOLD_OPS=1 holds every control input other than mode at 0 (for AddSub: every lane adds)
and writes primepower_ops_held/; the difference from the plain run is the cost of ops that change
with every operation.
A netlist with flops or latches (fu_add_sub_pipe) is also reset and clocked at the corner's period,
with an ideal clock network (see CYCLE and ideal_clock).
Optional: INPUT_CLK_Q applies a clocked design's inputs one flop clock-to-output after each edge, as
an upstream register would, for a design whose controls come from its own flops (fu_add_sub_spike
OP_REG). INPUT_CLK_Q=light: the fastest CK->Q among the netlist's flops (a lightly loaded upstream
register; writes primepower*/ as usual); INPUT_CLK_Q=matched: their mean CK->Q (inputs arriving with
the design's own flop outputs; writes primepower*_matched/).
"""
from __future__ import annotations

import os
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
ZERO = os.environ.get("ZERO_DELAY") == "1"   # zero-delay simulation: functional switching only
HOLD = os.environ.get("HOLD_OPS") == "1"     # control inputs other than mode held at 0
CLK_Q = os.environ.get("INPUT_CLK_Q", "")   # "light" | "matched": clocked inputs a CK->Q after the edge
assert CLK_Q in ("", "light", "matched"), CLK_Q
SEED = 20260930
# Multi-function units: family -> function -> control inputs held for the whole run. An input held
# in only some functions takes its stimulus bits in the others (fu_add_sub_mm: every lane subtracts
# for Min/Max, sub_sel follows the stimulus for AddSub).
FUNCTIONS = {"addsub_minmax": {"addsub": {"is_min_max": 0}, "minmax": {"is_min_max": 1}},
             "addsub_mm": {"addsub": {"is_min_max": 0}, "minmax": {"is_min_max": 1, "sub_sel": 255}}}
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


# Registered designs: reset for the first period, then one clock cycle per operation, its rising
# edge where the operation is applied (timed: the netlist's delays separate the capture of one
# operation from the arrival of the next) or half a period later (zero-delay: with no delays, a
# capture at the instant the inputs change would race them). Each cycle ends at an absolute time
# so the clock cannot drift from the operations when the half period is not a whole picosecond.
CYCLE = f"""  task automatic cycle;
    realtime t = $realtime;
    clk = 1'b{0 if ZERO else 1}; #(period / 2); clk = 1'b{1 if ZERO else 0}; #(t + period - $realtime);
  endtask
"""
CLOCK_START = """
    #(period / 2) rst_n = 1'b1; #(period / 2);"""


def ideal_clock(sdf: str) -> str:
    """The SDF with zero delay on the clock network (the clock-gate cells DC inserted, and every
    interconnect leaving the clock port or a clock gate): an ideal clock, as DC timed it. Without
    clock-tree synthesis the gates' delays to their flops would let operands race the capture.
    A clock gate may sit in a sub-design (<instance>/clk_gate_...) when the hierarchy is kept."""
    zero = lambda t: re.sub(r"\([-\d.]+:[-\d.]+:[-\d.]+\)", "(0.000:0.000:0.000)", t)
    cells = re.split(r"(?=\(CELL\b)", sdf)
    out = []
    for c in cells:
        if re.search(r"\(INSTANCE\s+(?:\S*/)?clk_gate_", c):
            c = zero(c)
        else:
            c = re.sub(r"\(INTERCONNECT\s+(?:clk|(?:\S*/)?clk_gate_\S*)\s.*", lambda m: zero(m.group(0)), c)
        out.append(c)
    return "".join(out)


# Controls taken per 8-bit block (op_sel of fu_add_sub_spike REP_OP=1; sub_sel and max_sel of
# fu_add_sub_mm): block i gets the stimulus bit of its lane's start, so every lane sees the same op
# as in every other design.
REP_OP = """  function automatic logic [7:0] rep_op(input logic [7:0] op, input int m);
    for (int i = 0; i < 8; i++) rep_op[i] = op[m == 1 ? i & 4 : m == 2 ? i & 6 : m == 3 ? i : 0];
  endfunction
"""


def testbench(top: str, plist: list[tuple[str, str, int]], held: set[str], partly: set[str],
              clocked: bool) -> str:
    """held: inputs set by plusarg in every function; partly: by plusarg when given, else stimulus."""
    conns, decls, drive, cbit = [], [], [], 0
    per_block = {"sub_sel", "max_sel"} | ({"op_sel"} if "REP_OP1" in top else set())
    rep = any(n in per_block for _, n, _ in plist)
    for d, n, w in plist:
        rng = f"[{w - 1}:0] " if w > 1 else ""
        if d == "output":
            decls.append(f"  wire {rng}{n};")
        elif n in ("clk", "rst_n") and clocked:
            decls.append(f"  logic {n} = 1'b0;")
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
            bits = f"c[i][{cbit + w - 1}:{cbit}]"
            value = f"rep_op({bits}, mode_val)" if n in per_block else bits
            if n in partly:
                value = f"use_held_{n} ? {w}'(held_{n}) : {value}"
            drive.append(f"    {n} = {value};")
            cbit += w
        conns.append(f".{n}({n})")
    assert cbit <= 32, top
    wait = "cycle();" if clocked else "#(period);"
    late = clocked and CLK_Q   # inputs follow each edge by the flops' clock-to-output (tcq)
    step = lambda i: f"fork begin #(tcq); apply({i}); end join_none {wait}" if late else f"apply({i}); {wait}"
    return f"""`timescale 1ns/1ps
module tb;
  localparam int N = {NVEC};
  logic [63:0] a [N], b [N];
  logic [31:0] c [N];
  int mode_val; real period; string saif;{chr(10) + "  real tcq;" if late else ""}
{"".join(f"  int held_{n};{chr(10)}" for n in sorted(held))}{"".join(f"  int held_{n}; bit use_held_{n};{chr(10)}" for n in sorted(partly))}
{chr(10).join(decls)}
  {top} dut ({", ".join(conns)});
  task automatic apply(input int i);
{chr(10).join(drive)}
  endtask
{CYCLE if clocked else ""}{REP_OP if rep else ""}  initial begin
    if (!$value$plusargs("MODE=%d", mode_val)) mode_val = 0;
    if (!$value$plusargs("PERIOD=%f", period)) period = 1.0;
    if (!$value$plusargs("SAIF=%s", saif)) $fatal(1, "SAIF");{chr(10) + '    if (!$value$plusargs("TCQ=%f", tcq)) $fatal(1, "TCQ");' if late else ""}
{"".join(f'    if (!$value$plusargs("{n}=%d", held_{n})) $fatal(1, "{n}");{chr(10)}' for n in sorted(held))}{"".join(f'    use_held_{n} = $value$plusargs("{n}=%d", held_{n});{chr(10)}' for n in sorted(partly))}
    $readmemh("{{STIM_A}}", a); $readmemh("{{STIM_B}}", b); $readmemh("{{STIM_C}}", c);
    $sdf_annotate("{{SDF}}", dut);{CLOCK_START if clocked else ""}
    {step(0)}
    $set_gate_level_monitoring("on");
    $set_toggle_region(tb.dut);
    $toggle_start;
    for (int i = 1; i < N; i++) begin {step("i")} end
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
    if HOLD:
        files["C"] = work / "stim_c_ops_held.hex"
        files["C"].write_text("00000000\n" * NVEC)
    return files


def clock_to_q(sdf: str) -> float:
    """CK->Q delay (ns) of the netlist's flops (typical rise and fall of every flop's IOPATH): the
    fastest for INPUT_CLK_Q=light, the mean for INPUT_CLK_Q=matched."""
    d = [float(x) for r, f in re.findall(r"\(IOPATH \(posedge CK\) Q \([-\d.]+:([-\d.]+):[-\d.]+\) \([-\d.]+:([-\d.]+):[-\d.]+\)\)", sdf)
         for x in (r, f)]
    return min(d) if CLK_Q == "light" else sum(d) / len(d)


def wire_load(dc_power: Path, top: str) -> str:
    m = re.search(rf"^{re.escape(top)}\s+(\S+)\s+saed14", dc_power.read_text(), re.MULTILINE)
    return m.group(1) if m else "8000"


def run(cmd: str, cwd: Path, log: Path) -> int:
    # Under parallel load `module load` occasionally leaves the tool off PATH; retry that case.
    for _ in range(3):
        with log.open("w") as f:
            rc = subprocess.call(["bash", "-lc", ENV + cmd], cwd=cwd, stdout=f, stderr=subprocess.STDOUT)
        if "command not found" not in log.read_text():
            return rc
    return rc


def one(design: str, corner: str, raw: Path, work: Path, stim: dict[str, Path]) -> str:
    src = raw / design / corner
    top = re.search(r"TOP=(\S+)", (src / "result.txt").read_text()).group(1)
    w = work / design / corner / ("zero" if ZERO else "") / ("ops_held" if HOLD else "")
    w.mkdir(parents=True, exist_ok=True)
    plist = ports(src / "netlist.v", top)
    clocked = re.search(r"^\s+SAEDRVT14_(FD|LD)", (src / "netlist.v").read_text(), re.MULTILINE) is not None
    has_mode = any(n == "mode" for _, n, _ in plist)
    funcs = FUNCTIONS.get(DESIGNS[design][0], {"": {}})
    held = set.intersection(*(set(hold) for hold in funcs.values()))
    partly = {n for hold in funcs.values() for n in hold} - held
    sdf = src / "netlist.sdf"
    if clocked and not ZERO:
        sdf = w / "netlist_ideal_clock.sdf"
        sdf.write_text(ideal_clock((src / "netlist.sdf").read_text()))
    tb = testbench(top, plist, held, partly, clocked).replace("{SDF}", str(sdf))
    if ZERO:
        tb = "\n".join(l for l in tb.splitlines() if "$sdf_annotate" not in l) + "\n"
    for k, p in stim.items():
        tb = tb.replace("{STIM_" + k + "}", str(p))
    (w / "tb.sv").write_text(tb)
    # Timing checks are off for registered designs: the testbench changes the operands at the
    # capture edge itself (no upstream clock-to-output delay), which hold checks would only report.
    delays = "+nospecify +notimingcheck" if ZERO else "+notimingcheck" if clocked else "+neg_tchk"
    if run(f"vcs -full64 -sverilog -timescale=1ns/1ps {delays} -o simv tb.sv {src / 'netlist.v'} "
           f"{CELLS / 'saed14rvt_base.v'} {CELLS / 'saed14rvt_base_udp.v'}", w, w / "vcs.log"):
        return f"{design} {corner} VCS COMPILE FAILED"
    modes = modes_of(design, has_mode)
    tcq = f" +TCQ={clock_to_q((src / 'netlist.sdf').read_text()):.4f}" if clocked and CLK_Q else ""
    lic = True
    for func, hold in funcs.items():
        tag = f"{func}_" if func else ""
        plus = "".join(f" +{n}={v}" for n, v in hold.items())
        for m in modes:
            if run(f"./simv +MODE={m} +PERIOD={PERIOD[corner]} +SAIF={tag}mode{m}.saif{plus}{tcq}", w, w / f"sim_{tag}{m}.log"):
                return f"{design} {corner} SIM {func} mode {m} FAILED"
        out = src / ("primepower" + ("_zero" if ZERO else "") + ("_ops_held" if HOLD else "")
                     + ("_matched" if clocked and CLK_Q == "matched" else "") + ("_" + func if func else ""))
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
                                      + "".join(f" {n}={v}" for n, v in hold.items())
                                      + tcq.replace(" +TCQ=", " INPUT_CLK_Q_NS=") + "\n")
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
