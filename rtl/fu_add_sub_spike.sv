// fu_add_sub_spike.sv -- Decomposable AddSub variants for the 500-900 MHz gated-bank power spike
// (reports/addsub_spike_experiment). The window-fix experiment traced the spike to two causes:
//
//   A. the add/subtract select: each 8-bit block's lane op comes through a serial decode chain
//      (block i copies block i-1's op unless it starts a lane), so the upper blocks' operand
//      inversion arrives after the operands and a fast adder evaluates twice;
//   B. the speed class: a single-cycle 64-bit carry forces a fast adder from about 450 MHz,
//      while the bank's 32x2 and 16x4 units stay ripple adders until 0.9-1.5 GHz.
//
// fu_add_sub_spike is one wrapper with two independent knobs:
//   FLAT = 0  serial lane-op decode (the original structure); 1: flat decode, each block's op is
//             its lane-start bit through one mode-selected mux (targets A).
//   REP_OP = 1  op_sel arrives replicated per block (op_sel[i] = the op of the lane containing
//             block i, prepared before the FU like the left-edge mode decode), so each block's
//             operand inversion and carry-in come straight from an input pin (targets A; FLAT is
//             then unused). With REP_OP = 0, op_sel[i] is the op of the lane starting at block i.
//   ARCH = 0  segmented adder: eight 8-bit adds joined by carry-in muxes (the original
//             fu_add_sub_segmented datapath).
//   ARCH = 1  carry-select at bit 32 (targets B): the halves are separate partitioned adders (a
//             guard bit below each block that can start a lane), and a 64-bit lane's upper half
//             is also added with carry-in 1 by a duplicate adder whose operands are gated to zero
//             in every other mode, so it only switches for 64-bit operations. No path is longer
//             than 32 bits plus the select.
//   ARCH = 3  carry-select at every 16 bits: four 16-bit partitioned segments, and for each upper
//             segment a duplicate with carry-in 1, gated to zero unless the segment lies inside a
//             wider lane; carries select through the segments. The longest ripple is one segment.
//   ARCH = 2  the same carry-select built from the bank's DesignWare primitives: each half is a
//             duplex adder DW_addsub_dx split at bit 16 (16-bit lanes), the gated duplicate is a
//             DW01_add, and each lane's op inverts its operand outside the adder as in the bank's
//             32x2 unit. Tiers d2 and d4 only (the duplex adder has no 8-bit split).
// Tiers are parameters (EN32/EN16/EN8 as in fu_add_sub_gen.sv: d2 = 1,0,0, d4 = 1,1,0,
// d8 = 1,1,1). Ports, mode and op_sel encoding match fu_add_sub_d2/d4/d8:
//   mode: 00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> 8x8
//         (a mode whose tier is disabled falls back to 1x64)
//   op_sel[i]: op of the lane whose start is 8-bit block i (0 add, 1 sub); with REP_OP, op of
//              the lane containing block i.
// Combinational, latency 0.

// Lane starts and each 8-bit block's lane op (block 0 is always a start).
module fu_add_sub_spike_decode #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1,
  parameter bit FLAT = 1,
  parameter bit REP_OP = 0
) (
  input  logic [1:0] mode,
  input  logic [7:0] op_sel,
  output logic [7:0] is_start,
  output logic [7:0] sub
);
  always_comb begin
    logic cur;
    case (mode)
      2'b01:   is_start = EN32 ? 8'b0001_0001 : 8'b0000_0001;
      2'b10:   is_start = EN16 ? 8'b0101_0101 : 8'b0000_0001;
      2'b11:   is_start = EN8  ? 8'b1111_1111 : 8'b0000_0001;
      default: is_start = 8'b0000_0001;   // 1x64
    endcase
    cur = op_sel[0];
    for (int i = 0; i < 8; i++) begin
      if (REP_OP) begin
        sub[i] = op_sel[i];
      end else if (FLAT) begin
        case (mode)   // the lane-start block of block i: 0, i & 4, i & 6 or i
          2'b01:   sub[i] = EN32 ? op_sel[i & 4] : op_sel[0];
          2'b10:   sub[i] = EN16 ? op_sel[i & 6] : op_sel[0];
          2'b11:   sub[i] = EN8  ? op_sel[i]     : op_sel[0];
          default: sub[i] = op_sel[0];
        endcase
      end else begin
        if (is_start[i]) cur = op_sel[i];
        sub[i] = cur;
      end
    end
  end
endmodule : fu_add_sub_spike_decode

// Partitioned add over NBLK 8-bit blocks: a guard bit below each block in BRK (block 0 always has
// one, the segment's carry-in). A guard bit passes the carry on (1, 0), or, when brk[k], replaces
// it with cin[k] (cin, cin).
module fu_add_sub_spike_seg #(
  parameter int         NBLK = 4,
  parameter logic [3:0] BRK  = 4'b0001
) (
  input  logic [8*NBLK-1:0] a,
  input  logic [8*NBLK-1:0] be,
  // verilator lint_off UNUSEDSIGNAL
  input  logic [NBLK-1:0]   brk,     // read only at the guard bits in BRK
  input  logic [NBLK-1:0]   cin,
  // verilator lint_on UNUSEDSIGNAL
  output logic [8*NBLK-1:0] s,
  output logic              co
);
  function automatic int guards_upto(int k);   // guard bits at or below block k
    int n = 0;
    for (int i = 0; i <= k; i++) n += int'(BRK[i]);
    return n;
  endfunction
  localparam int W = 8*NBLK + guards_upto(NBLK-1);
  logic [W-1:0] xa, xb;
  // verilator lint_off UNUSEDSIGNAL
  logic [W-1:0] xs;   // guard-bit sums are dropped
  // verilator lint_on UNUSEDSIGNAL
  for (genvar k = 0; k < NBLK; k++) begin : blk
    localparam int OFF = 8*k + guards_upto(k);
    if (BRK[k]) begin : guard
      assign xa[OFF-1] = brk[k] ? cin[k] : 1'b1;
      assign xb[OFF-1] = brk[k] ? cin[k] : 1'b0;
    end
    assign xa[OFF +: 8] = a[8*k +: 8];
    assign xb[OFF +: 8] = be[8*k +: 8];
    assign s[8*k +: 8] = xs[OFF +: 8];
  end
  assign {co, xs} = {1'b0, xa} + {1'b0, xb};
endmodule : fu_add_sub_spike_seg

module fu_add_sub_spike #(
  parameter int ARCH = 1,
  parameter bit FLAT = 1,
  parameter bit REP_OP = 0,
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  logic [7:0] sub;
  // verilator lint_off UNUSEDSIGNAL
  logic [7:0] is_start;   // ARCH 2 reads only the lane starts at bits 16 and 32
  // verilator lint_on UNUSEDSIGNAL
  fu_add_sub_spike_decode #(.EN32(EN32), .EN16(EN16), .EN8(EN8), .FLAT(FLAT), .REP_OP(REP_OP)) decode (
    .mode(mode), .op_sel(op_sel), .is_start(is_start), .sub(sub));

  logic [63:0] be;
  for (genvar i = 0; i < 8; i++) begin : invert
    assign be[8*i +: 8] = in_data_1[8*i +: 8] ^ {8{sub[i]}};
  end

  if (ARCH == 0) begin : segmented
    always_comb begin
      logic carry, co_i, cin_i;
      carry = 1'b0;
      for (int i = 0; i < 8; i++) begin
        cin_i = is_start[i] ? sub[i] : carry;
        {co_i, out_data[8*i +: 8]} = {1'b0, in_data_0[8*i +: 8]} + {1'b0, be[8*i +: 8]} + {8'b0, cin_i};
        carry = co_i;
      end
    end
  end else if (ARCH == 1) begin : carry_select
    // Blocks that can start a lane within each half (block 0 of a half always has a guard).
    localparam logic [3:0] BRK_LO = {EN8, EN8 | EN16, EN8, 1'b1};
    localparam logic [3:0] BRK_HI = BRK_LO;
    logic [7:0] cin;
    logic       lane64, c32;
    logic [31:0] s_lo, s_hi0, s_hi1;
    assign cin    = is_start & sub;      // a lane start injects its op's +1
    assign lane64 = ~is_start[4];        // bit 32 starts no lane: one 64-bit lane
    fu_add_sub_spike_seg #(.BRK(BRK_LO)) lo (
      .a(in_data_0[31:0]), .be(be[31:0]), .brk(is_start[3:0]), .cin(cin[3:0]), .s(s_lo), .co(c32));
    // upper half with the lane's carry-in (0 for a 64-bit lane)
    logic co_hi0_unused;
    fu_add_sub_spike_seg #(.BRK(BRK_HI)) hi0 (
      .a(in_data_0[63:32]), .be(be[63:32]), .brk({is_start[7:5], 1'b1}), .cin(cin[7:4]),
      .s(s_hi0), .co(co_hi0_unused));
    // upper half of a 64-bit lane with carry-in 1; operands gated to zero in other modes
    logic co_hi1_unused;
    fu_add_sub_spike_seg #(.BRK(4'b0001)) hi1 (
      .a(in_data_0[63:32] & {32{lane64}}), .be(be[63:32] & {32{lane64}}), .brk(4'b0001),
      .cin({3'b0, lane64}), .s(s_hi1), .co(co_hi1_unused));
    assign out_data = {(lane64 & c32) ? s_hi1 : s_hi0, s_lo};
  end else if (ARCH == 3) begin : carry_select16
    localparam logic [3:0] BRK_Q = {2'b00, EN8, 1'b1};   // guard below each segment's second block
    logic [3:0]  cin, take1;            // segment carry-in, duplicate selected
    // verilator lint_off UNUSEDSIGNAL
    logic [3:0]  c, in_lane;            // carry into segment, segment continues a lane (not segment 0)
    logic [3:0]  co0, co1;              // segment carry-outs (carry-in 0 / 1); the top's are unused
    // verilator lint_on UNUSEDSIGNAL
    logic [15:0] s0 [4];
    logic [15:0] s1 [4];
    assign cin = {is_start[6] & sub[6], is_start[4] & sub[4], is_start[2] & sub[2], sub[0]};
    assign in_lane = {~is_start[6], ~is_start[4], ~is_start[2], 1'b0};   // segment continues a lane
    for (genvar q = 0; q < 4; q++) begin : seg
      // segment with its lane's carry-in (0 inside a lane)
      fu_add_sub_spike_seg #(.NBLK(2), .BRK(BRK_Q)) a0 (
        .a(in_data_0[16*q +: 16]), .be(be[16*q +: 16]), .brk({is_start[2*q+1], 1'b1}),
        .cin({sub[2*q+1], cin[q]}), .s(s0[q]), .co(co0[q]));
      if (q == 0) begin : first
        assign c[q] = 1'b0;
        assign take1[q] = 1'b0;
        assign s1[q] = '0;
        assign co1[q] = 1'b0;
      end else begin : upper
        // duplicate with carry-in 1, operands gated to zero unless the segment is inside a lane
        // (then its second block starts no lane, so its guard passes)
        fu_add_sub_spike_seg #(.NBLK(2), .BRK(4'b0001)) a1 (
          .a(in_data_0[16*q +: 16] & {16{in_lane[q]}}), .be(be[16*q +: 16] & {16{in_lane[q]}}),
          .brk(2'b01), .cin({1'b0, in_lane[q]}), .s(s1[q]), .co(co1[q]));
        assign c[q] = take1[q-1] ? co1[q-1] : co0[q-1];
        assign take1[q] = in_lane[q] & c[q];
      end
      assign out_data[16*q +: 16] = take1[q] ? s1[q] : s0[q];
    end
  end else begin : dw_carry_select
    logic        lane64, m16, c32;
    logic [31:0] s_lo, s_hi0, s_hi1;
    // verilator lint_off UNUSEDSIGNAL
    logic        co1_lo_unused, co1_hi_unused, co2_hi_unused, co_hi1_unused;
    // verilator lint_on UNUSEDSIGNAL
    assign lane64 = ~is_start[4];        // bit 32 starts no lane: one 64-bit lane
    assign m16    = is_start[2];         // 16-bit lanes: both halves split at their bit 16
    DW_addsub_dx #(.width(32), .p1_width(16)) lo (
      .a(in_data_0[31:0]), .b(be[31:0]), .ci1(sub[0]), .ci2(sub[2]), .addsub(1'b0), .tc(1'b0),
      .sat(1'b0), .avg(1'b0), .dplx(m16), .sum(s_lo), .co1(co1_lo_unused), .co2(c32));
    // upper half with the lane's carry-in (0 for a 64-bit lane)
    DW_addsub_dx #(.width(32), .p1_width(16)) hi0 (
      .a(in_data_0[63:32]), .b(be[63:32]), .ci1(is_start[4] & sub[4]), .ci2(sub[6]), .addsub(1'b0),
      .tc(1'b0), .sat(1'b0), .avg(1'b0), .dplx(m16), .sum(s_hi0), .co1(co1_hi_unused), .co2(co2_hi_unused));
    // upper half of a 64-bit lane with carry-in 1; operands gated to zero in other modes
    DW01_add #(.width(32)) hi1 (
      .A(in_data_0[63:32] & {32{lane64}}), .B(be[63:32] & {32{lane64}}), .CI(lane64),
      .SUM(s_hi1), .CO(co_hi1_unused));
    assign out_data = {(lane64 & c32) ? s_hi1 : s_hi0, s_lo};
  end
endmodule : fu_add_sub_spike

// Probe: the bank's fixed 32x2 function (ports of rtl/standalone/fu_add_sub_32x2.sv) built on
// different adder primitives, to measure how much the primitive alone switches.
//   PRIM = 0  inferred a + (b ^ op) + op per lane (the segmented form: three operands)
//   PRIM = 1  inferred {a, op} + {b ^ op, op} per lane (the guard-bit form: two operands)
//   PRIM = 2  DW01_add per lane, B = b ^ op, CI = op
//   PRIM = 3  DW01_addsub per lane, ADD_SUB = op
//   PRIM = 4  DW_addsub_dx split at bit 32, as in the bank's 32x2 unit
module fu_add_sub_spike_probe32x2 #(
  parameter int PRIM = 4
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;
  logic [63:0] be;
  assign be = in_data_1 ^ {{32{op_sel[1]}}, {32{op_sel[0]}}};
  if (PRIM == 4) begin : duplex
    // verilator lint_off UNUSEDSIGNAL
    logic co1_unused, co2_unused;
    // verilator lint_on UNUSEDSIGNAL
    DW_addsub_dx #(.width(64), .p1_width(32)) u (
      .a(in_data_0), .b(be), .ci1(op_sel[0]), .ci2(op_sel[1]), .addsub(1'b0), .tc(1'b0), .sat(1'b0),
      .avg(1'b0), .dplx(1'b1), .sum(out_data), .co1(co1_unused), .co2(co2_unused));
  end else begin : per_lane
    for (genvar i = 0; i < 2; i++) begin : lane
      logic [31:0] a, s;
      // verilator lint_off UNUSEDSIGNAL
      logic [31:0] b;   // the inverted operand; PRIM 3 inverts inside DW01_addsub instead
      logic co_unused, g_unused;
      // verilator lint_on UNUSEDSIGNAL
      assign a = in_data_0[32*i +: 32];
      assign b = be[32*i +: 32];
      if (PRIM == 0) begin : three_operand
        assign {co_unused, s} = {1'b0, a} + {1'b0, b} + {32'b0, op_sel[i]};
        assign g_unused = 1'b0;
      end else if (PRIM == 1) begin : guard
        assign {co_unused, s, g_unused} = {1'b0, a, op_sel[i]} + {1'b0, b, op_sel[i]};
      end else if (PRIM == 2) begin : dw_add
        DW01_add #(.width(32)) u (.A(a), .B(b), .CI(op_sel[i]), .SUM(s), .CO(co_unused));
        assign g_unused = 1'b0;
      end else begin : dw_addsub
        DW01_addsub #(.width(32)) u (.A(a), .B(in_data_1[32*i +: 32]), .CI(1'b0), .ADD_SUB(op_sel[i]),
                                     .SUM(s), .CO(co_unused));
        assign g_unused = 1'b0;
      end
      assign out_data[32*i +: 32] = s;
    end
  end
endmodule : fu_add_sub_spike_probe32x2
