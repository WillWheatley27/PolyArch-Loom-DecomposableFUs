# fu_add_sub_decomp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a decomposable (subword-SIMD) add/sub function unit: one 64-bit datapath that also runs as 2×32-bit or 4×16-bit independent lanes, selected at runtime.

**Architecture:** One shared 64-bit carry-propagate adder viewed as four 16-bit blocks; carries across the 16/32/48-bit boundaries are gated by a `mode` input, and each lane's add/sub is chosen by a per-lane `op_sel` bit. Purely combinational, latency 0, 2-input join handshake — identical skeleton to the existing `fu_add_sub`.

**Tech Stack:** SystemVerilog (synthesizable), Verilator 5.044 (lint `-Wall` + `--binary` sim) as the verification gate. No generator/Jinja involvement (hand-authored).

## Global Constraints

- Verification gate: `verilator --lint-only -Wall` clean **and** testbench prints `PASS:`.
- DUT is combinational, intrinsic latency 0. Handshake = 2-input join: `out_valid = in_valid_0 & in_valid_1; in_ready_0 = in_ready_1 = out_ready & out_valid;`.
- Fixed 64-bit base, 16-bit lane granularity (four blocks). Not parameterized by width.
- Lane packing little-endian by lane: lane *i* occupies the *i*-th contiguous slice (lane0 = LSBs).
- `mode`: `2'b00`=1×64, `2'b01`=2×32, `2'b10`=4×16, `2'b11`=reserved → behaves as 1×64.
- `op_sel[i]`: 0=add, 1=subtract (subtract = `~B + carry_in`). No flag/overflow outputs.
- Commit identity: `WillWheatley27 <willwheatley27@g.ucla.edu>`. **Commit messages carry a subject line only, with no trailer lines.**
- Remote: `origin` = `https://github.com/WillWheatley27/PolyArch-Loom-DecomposableFUs.git`, branch `main`.

---

### Task 1: Testbench + run.sh + interface stub (RED)

Establishes the interface, the lint+sim harness, and a self-checking testbench whose golden model splits operands into lanes per `mode`. Runs against a deliberately incomplete stub (1×64 only) that lints clean but fails multi-lane vectors — proving the testbench actually detects lane bugs.

**Files:**
- Create: `rtl/fu_add_sub_decomp.sv` (stub)
- Create: `tb/tb_fu_add_sub_decomp.sv`
- Create: `run.sh`

**Interfaces:**
- Produces: module `fu_add_sub_decomp` with ports `clk, rst_n, mode[1:0], op_sel[3:0], in_data_0[63:0], in_valid_0, in_ready_0, in_data_1[63:0], in_valid_1, in_ready_1, out_data[63:0], out_valid, out_ready`.
- Produces: TB `tb_fu_add_sub_decomp #(parameter int unsigned NRAND=20000)` printing `PASS:`/`FAIL:`.

- [ ] **Step 1: Write the interface stub** (`rtl/fu_add_sub_decomp.sv`)

```systemverilog
// fu_add_sub_decomp.sv -- Decomposable (subword-SIMD) FU for share group add_sub.
// STUB (Task 1): 1x64 add/sub only; ignores mode and per-lane op_sel[3:1].
// Correct interface so the testbench compiles; intentionally wrong for 2x32/4x16.
module fu_add_sub_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
  input  logic [3:0]  op_sel,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,

  input  logic [63:0] in_data_1,
  input  logic        in_valid_1,
  output logic        in_ready_1,

  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // STUB datapath: whole-word add/sub only.
  assign out_data = op_sel[0] ? (in_data_0 - in_data_1) : (in_data_0 + in_data_1);
endmodule : fu_add_sub_decomp
```

- [ ] **Step 2: Write the self-checking testbench** (`tb/tb_fu_add_sub_decomp.sv`)

```systemverilog
// tb_fu_add_sub_decomp.sv -- Self-checking TB for fu_add_sub_decomp.
// Combinational DUT; drive (mode, op_sel, a, b), settle, compare to a golden
// model that splits operands into subword lanes per mode. Directed corners
// (carry/borrow isolation, mode equivalence, mixed ops) + randomized. All modes
// exercised in one run (mode is a runtime input). Testbench only.
`timescale 1ns/1ps

module tb_fu_add_sub_decomp #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [3:0]  op_sel;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_add_sub_decomp dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  function automatic logic [63:0] golden(input logic [1:0]  m,
                                         input logic [3:0]  op,
                                         input logic [63:0] a,
                                         input logic [63:0] b);
    logic [63:0] r;
    begin : golden_body
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = op[0] ? (a[31:0]  - b[31:0])  : (a[31:0]  + b[31:0]);
          r[63:32] = op[2] ? (a[63:32] - b[63:32]) : (a[63:32] + b[63:32]);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = op[0] ? (a[15:0]  - b[15:0])  : (a[15:0]  + b[15:0]);
          r[31:16] = op[1] ? (a[31:16] - b[31:16]) : (a[31:16] + b[31:16]);
          r[47:32] = op[2] ? (a[47:32] - b[47:32]) : (a[47:32] + b[47:32]);
          r[63:48] = op[3] ? (a[63:48] - b[63:48]) : (a[63:48] + b[63:48]);
        end : g4x16
        default: begin : g1x64   // 2'b00 and reserved 2'b11
          r = op[0] ? (a - b) : (a + b);
        end : g1x64
      endcase
      golden = r;
    end : golden_body
  endfunction

  task automatic check_vec(input logic [1:0]  m,
                           input logic [3:0]  op,
                           input logic [63:0] a,
                           input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, op, a, b);
      if (out_data !== exp) begin : mism
        $display("FAIL data: mode=%02b op=%04b a=%h b=%h got=%h exp=%h",
                 m, op, a, b, out_data, exp);
        error_count = error_count + 1;
      end : mism
      if (out_valid !== 1'b1) begin : vlo
        $display("FAIL out_valid low (mode=%02b a=%h b=%h)", m, a, b);
        error_count = error_count + 1;
      end : vlo
      if ((in_ready_0 !== 1'b1) || (in_ready_1 !== 1'b1)) begin : rlo
        $display("FAIL in_ready low with out_ready & out_valid (a=%h b=%h)", a, b);
        error_count = error_count + 1;
      end : rlo
    end : cv
  endtask

  task automatic check_backpressure(input logic [1:0]  m, input logic [3:0]  op,
                                    input logic [63:0] a, input logic [63:0] b);
    begin : bp
      mode = m; op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0;
      #1;
      if (out_valid !== 1'b1) begin : bpv
        $display("FAIL backpressure: out_valid must stay high");
        error_count = error_count + 1;
      end : bpv
      if ((in_ready_0 !== 1'b0) || (in_ready_1 !== 1'b0)) begin : bpr
        $display("FAIL backpressure: in_ready must be low when out_ready=0");
        error_count = error_count + 1;
      end : bpr
    end : bp
  endtask

  task automatic check_input_invalid;
    begin : ii
      mode = 2'b00; op_sel = 4'b0000; in_data_0 = '0; in_data_1 = '0;
      in_valid_0 = 1'b0; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      if (out_valid !== 1'b0) begin : iiv
        $display("FAIL: out_valid high when in_valid_0 low");
        error_count = error_count + 1;
      end : iiv
      if (in_ready_1 !== 1'b0) begin : iir
        $display("FAIL: in_ready_1 high when join incomplete");
        error_count = error_count + 1;
      end : iir
    end : ii
  endtask

  initial begin : main
    integer      i;
    logic [63:0] a, b;
    logic [1:0]  m;
    logic [3:0]  op;

    error_count = 0;
    mode = 2'b00; op_sel = 4'b0000; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed: 1x64 equivalence ----
    check_vec(2'b00, 4'b0000, 64'h0000_0000_0000_0000, 64'h0000_0000_0000_0000);
    check_vec(2'b00, 4'b0000, 64'h0123_4567_89AB_CDEF, 64'h0000_0000_0000_0001);
    check_vec(2'b00, 4'b0001, 64'h0000_0000_0000_0000, 64'h0000_0000_0000_0001); // 0-1 -> all ones
    check_vec(2'b00, 4'b0001, 64'hFFFF_FFFF_FFFF_FFFF, 64'hFFFF_FFFF_FFFF_FFFF); // a-a -> 0

    // ---- Directed: 4x16 carry isolation (add): lane0 FFFF+0001 wraps, no leak into lane1 ----
    check_vec(2'b10, 4'b0000, 64'h0001_0001_0001_FFFF, 64'h0000_0000_0000_0001);
    // ---- Directed: 4x16 borrow isolation (sub lane0 only): 0000-0001=FFFF, no borrow into lane1 ----
    check_vec(2'b10, 4'b0001, 64'h0005_0005_0005_0000, 64'h0002_0002_0002_0001);
    // ---- Directed: 4x16 mixed per-lane ops (op=1010) ----
    check_vec(2'b10, 4'b1010, 64'h0010_0010_0010_0010, 64'h0003_0003_0003_0003);

    // ---- Directed: 2x32 break vs 1x64 propagate (identical operands, different mode) ----
    check_vec(2'b01, 4'b0000, 64'h0000_0001_FFFF_FFFF, 64'h0000_0000_0000_0001); // -> 0000_0001_0000_0000
    check_vec(2'b00, 4'b0000, 64'h0000_0001_FFFF_FFFF, 64'h0000_0000_0000_0001); // -> 0000_0002_0000_0000
    // ---- Directed: 2x32 mixed ops (lane0 add, lane1 sub via op[2]) ----
    check_vec(2'b01, 4'b0100, 64'h0000_000A_0000_000A, 64'h0000_0003_0000_0003);

    // ---- Handshake corners ----
    check_backpressure(2'b10, 4'b0101, 64'h1111_2222_3333_4444, 64'h0001_0001_0001_0001);
    check_input_invalid();

    // ---- Randomized (all modes incl reserved 11) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a  = {$random, $random};
      b  = {$random, $random};
      m  = $random;   // low 2 bits; includes reserved 11 (== 1x64)
      op = $random;   // low 4 bits
      check_vec(m, op, a, b);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_add_sub_decomp all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_add_sub_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_add_sub_decomp
```

- [ ] **Step 3: Write run.sh** (`run.sh`)

```bash
#!/usr/bin/env bash
# Lint + simulate fu_add_sub_decomp (all modes run in one sim; mode is runtime).
set -euo pipefail
cd "$(dirname "$0")"

command -v verilator >/dev/null 2>&1 || module load verilator/5.044 2>/dev/null || true

RTL=rtl/fu_add_sub_decomp.sv
TB=tb/tb_fu_add_sub_decomp.sv
mkdir -p build

echo "== lint (-Wall) =="
verilator --lint-only -Wall "$RTL"

echo "== build + sim =="
verilator --binary --timing \
  -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module tb_fu_add_sub_decomp \
  --Mdir build/obj_dir \
  "$RTL" "$TB"

build/obj_dir/Vtb_fu_add_sub_decomp | tee build/sim.log
grep -q '^PASS:' build/sim.log && echo "run.sh: OK" || { echo "run.sh: FAIL"; exit 1; }
```

- [ ] **Step 4: Make run.sh executable and run it — expect lint clean, sim FAIL**

Run:
```bash
chmod +x run.sh && ./run.sh
```
Expected: `== lint (-Wall) ==` passes with no errors; sim runs and prints `FAIL: fu_add_sub_decomp <N> mismatches` (the stub is wrong for 2×32/4×16 and mixed ops), `$fatal` fires, and `run.sh: FAIL` / nonzero exit. This confirms the testbench catches lane bugs (valid RED).

- [ ] **Step 5: Commit**

```bash
git add rtl/fu_add_sub_decomp.sv tb/tb_fu_add_sub_decomp.sv run.sh
git commit -m "test: add fu_add_sub_decomp testbench + harness against stub (RED)"
```

---

### Task 2: Implement the segmented datapath (GREEN)

Replace the stub datapath with the full mode-decode + per-lane op governance + carry-break adder. Testbench must pass all modes; lint stays clean.

**Files:**
- Modify: `rtl/fu_add_sub_decomp.sv` (replace body; keep the port list, drop mode/op_sel from the unused-waiver since they are now used)

**Interfaces:**
- Consumes: TB and run.sh from Task 1 (unchanged).
- Produces: fully functional `fu_add_sub_decomp`.

- [ ] **Step 1: Replace the module with the full implementation** (`rtl/fu_add_sub_decomp.sv`)

```systemverilog
// fu_add_sub_decomp.sv -- Decomposable (subword-SIMD) FU for share group add_sub.
// op_list: arith.addi, arith.subi, decomposed across subword lanes.
//
//   mode = 2'b00 -> 1x64 : one 64-bit lane
//   mode = 2'b01 -> 2x32 : two independent 32-bit lanes
//   mode = 2'b10 -> 4x16 : four independent 16-bit lanes
//   mode = 2'b11 -> reserved, behaves as 1x64
//
//   op_sel[i] selects per-lane op: 0 -> add, 1 -> subtract (~B + carry-in).
//
// One shared 64-bit adder viewed as four 16-bit blocks; carries across the
// 16/32/48-bit boundaries are gated by mode. Combinational, intrinsic latency 0.
module fu_add_sub_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic [3:0]  op_sel,

  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,

  input  logic [63:0] in_data_1,
  input  logic        in_valid_1,
  output logic        in_ready_1,

  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready
);

  // Handshake: 2-input join, combinational, lossless backpressure.
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  localparam logic [1:0] M_1X64 = 2'b00;
  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // ---- Mode decode: boundary carry breaks + per-block op governance ----
  logic brk16, brk32, brk48;
  logic gov0, gov1, gov2, gov3;   // op controlling each 16-bit block's lane
  always_comb begin : decode
    brk16 = 1'b0; brk32 = 1'b0; brk48 = 1'b0;
    gov0  = op_sel[0]; gov1 = op_sel[0]; gov2 = op_sel[0]; gov3 = op_sel[0];
    case (mode)
      M_2X32: begin : d2x32
        brk32 = 1'b1;
        gov2  = op_sel[2]; gov3 = op_sel[2];
      end : d2x32
      M_4X16: begin : d4x16
        brk16 = 1'b1; brk32 = 1'b1; brk48 = 1'b1;
        gov1  = op_sel[1]; gov2 = op_sel[2]; gov3 = op_sel[3];
      end : d4x16
      default: ;  // M_1X64 and reserved 2'b11 -> defaults (single 64-bit lane)
    endcase
  end : decode

  // ---- Split operands into four 16-bit blocks (little-endian by lane) ----
  logic [15:0] a0, a1, a2, a3;
  logic [15:0] b0, b1, b2, b3;
  assign {a3, a2, a1, a0} = in_data_0;
  assign {b3, b2, b1, b0} = in_data_1;

  // Per-block operand-B invert (subtract = ~B).
  logic [15:0] be0, be1, be2, be3;
  assign be0 = gov0 ? ~b0 : b0;
  assign be1 = gov1 ? ~b1 : b1;
  assign be2 = gov2 ? ~b2 : b2;
  assign be3 = gov3 ? ~b3 : b3;

  // ---- Segmented carry-propagate: carry-in per block is either the propagated
  //      carry-out of the block below, or a fresh lane-start seed (= gov = +1 for sub).
  logic       c0i, c1i, c2i, c3i;
  logic       co0, co1, co2;
  logic [15:0] sum0, sum1, sum2, sum3;

  assign c0i            = gov0;                       // block 0 is always a lane start
  assign {co0, sum0}    = {1'b0, a0} + {1'b0, be0} + {16'b0, c0i};

  assign c1i            = brk16 ? gov1 : co0;
  assign {co1, sum1}    = {1'b0, a1} + {1'b0, be1} + {16'b0, c1i};

  assign c2i            = brk32 ? gov2 : co1;
  assign {co2, sum2}    = {1'b0, a2} + {1'b0, be2} + {16'b0, c2i};

  assign c3i            = brk48 ? gov3 : co2;
  assign sum3           = a3 + be3 + {15'b0, c3i};    // top block carry-out discarded (no flags)

  assign out_data = {sum3, sum2, sum1, sum0};

endmodule : fu_add_sub_decomp
```

- [ ] **Step 2: Run — expect lint clean and sim PASS**

Run:
```bash
./run.sh
```
Expected: lint clean; sim prints `PASS: fu_add_sub_decomp all modes, 20000 random vectors, 0 mismatches`; `run.sh: OK`; exit 0.

- [ ] **Step 3: Commit**

```bash
git add rtl/fu_add_sub_decomp.sv
git commit -m "feat: implement decomposable add/sub datapath (1x64/2x32/4x16)"
```

---

### Task 3: README + push

Document the module and record the synthesis-area follow-up, then publish.

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md** (`README.md`)

```markdown
# PolyArch-Loom Decomposable FUs

Decomposable (subword-SIMD) function units for the loom `fabric` share groups: a
single wide datapath that also operates as narrower independent lanes, selected at
runtime, so one unit replaces a bank of fixed-width units.

## Contents

- `DECOMPOSABILITY_ANALYSIS.md` — which of the 19 share-group FUs can decompose, and why.
- `docs/specs/` — per-FU design specs.
- `docs/plans/` — per-FU implementation plans.
- `rtl/` — synthesizable SystemVerilog modules.
- `tb/` — self-checking Verilator testbenches.

## fu_add_sub_decomp

64-bit add/sub that runs as 1×64, 2×32, or 4×16 lanes via a runtime `mode` input,
with a per-lane `op_sel` (add/sub) bit. One shared adder segmented at the
16/32/48-bit boundaries by mode-gated carries. Combinational, latency 0.

```bash
./run.sh          # verilator --lint-only -Wall, then build + sim (all modes)
```

## Verification gate

`verilator --lint-only -Wall` clean + testbench `PASS:`. All three modes run in one
simulation (mode is a runtime input), covering carry/borrow isolation, mode
equivalence, mixed per-lane ops, handshake corners, and ~20k random vectors.

## Follow-up: area validation

Functional decomposition is verified here. The motivating area inequality —
`Area(one decomposable FU64) < Area(FU64) + 2·FU32 + 4·FU16)` — is a synthesis
result and is tracked as a separate task (Yosys/DC), not claimed from RTL.
```

- [ ] **Step 2: Commit and push**

```bash
git add README.md
git commit -m "docs: add repo README describing decomposable FUs and add/sub module"
git push origin main
```
Expected: push succeeds to `origin/main`.

---

## Notes for the implementer

- Load Verilator first if `verilator` is not on PATH: `module load verilator/5.044`.
- The DUT is combinational; the clock in the TB exists only for reset/settle convention.
- If lint flags an unused top-block carry, confirm `sum3` uses `a3 + be3 + {15'b0,c3i}` (16-bit, no carry-out captured) rather than a 17-bit form — the top carry is intentionally discarded (no flag outputs).
- Keep commit messages to a subject line only, with no trailer lines (see Global Constraints).
