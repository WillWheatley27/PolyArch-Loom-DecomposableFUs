// fu_add_sub_mm.sv -- Decomposable AddSub with integer Min/Max as a side function of the same
// carry network (reports/addsub_minmax_experiment). Min/Max computes A - B in every lane, as
// AddSub's subtract does, and reads the comparison from the lane's carry out: for A + ~B + 1 the
// carry out of a lane is A >= B (unsigned); a signed lane whose top bits differ is decided by B's
// sign. No sum bit, equality test or extra adder is needed: the side function adds the lane compare
// and the choice of each output byte among the sum, A and B.
//
// One parameterized unit is both sides of the comparison: MINMAX = 0 is the AddSub alone, MINMAX = 1
// adds the side function, so their difference is the side function's cost.
//   ARCH = 0  segmented adder: eight 8-bit adds joined by carry-in muxes;
//   ARCH = 1  carry-select at bit 32: two partitioned 32-bit halves and a duplicate upper half with
//             carry-in 1 whose operands are gated to zero except for 64-bit lanes
//             (as in rtl/fu_add_sub_spike.sv ARCH 0 and 1).
//   PIPE = 0  combinational (latency 0);
//   PIPE = 1  one output register stage (latency 1), which synthesis may retime into the logic;
//   PIPE = 2  (MINMAX only) latency 1 with the Min/Max choice behind the register: the register holds
//             the sum, or A for Min/Max, and, loaded only for Min/Max, B and each byte's choice; one
//             2:1 mux per bit follows. Ahead of the register the unit is the AddSub plus the lane
//             compare, so the side function adds nothing to the adder's path.
// Tiers: EN32/EN16/EN8 as in fu_add_sub_gen.sv (d2 = 1,0,0, d4 = 1,1,0, d8 = 1,1,1).
//   mode:       00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> 8x8 (a mode whose tier is disabled -> 1x64)
//   is_min_max: 0 AddSub, 1 Min/Max; is_signed: Min/Max lanes are signed (AddSub ignores it).
//   sub_sel[i]: block i's lane subtracts (invert B, carry-in 1); Min/Max needs every lane to
//               subtract, so the issuing logic sets it to all ones for Min/Max.
//   max_sel[i]: block i's lane takes the maximum (Min/Max only).
// sub_sel and max_sel arrive per 8-bit block (the lane's control replicated to each of its blocks),
// prepared before the FU like the left-edge mode decode, so the operand inversion is driven straight
// from an input pin. All controls are runtime inputs; the circuit is the same in every mode.
//
// fu_add_sub_mm_reg is the same unit behind the original fused unit's interface
// (fu_add_sub_minmax_gen.sv): op_sel[i] is the op of the lane starting at block i (AddSub: 0 add,
// 1 sub; Min/Max: 0 min, 1 max), and the per-block copy is made in the FU, so its cost is the FU's.
// Every control arrives one cycle ahead of its operands and is registered here, as in
// fu_add_sub_spike OP_REG: the operand inversion is driven from a flop per block (sub_reg*, sized
// by synthesis with FAST_OP_REGS=1). The control register loads when an upstream operand register
// would: when the operation at the inputs is accepted, or there is none.
`include "fu_min_max_gen.sv"
`include "fu_add_sub_spike.sv"

module fu_add_sub_mm #(
  parameter int ARCH   = 0,
  parameter bit MINMAX = 1,
  parameter int PIPE   = 0,
  parameter bit EN32   = 1,
  parameter bit EN16   = 1,
  parameter bit EN8    = 1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
  input  logic [7:0]  sub_sel,
  // verilator lint_off UNUSEDSIGNAL
  input  logic [7:0]  max_sel,      // read only with MINMAX
  input  logic        is_signed,
  input  logic        is_min_max,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  logic [63:0] a, b;
  assign a = in_data_0;
  assign b = in_data_1;

  // ---- Left-edge mode decode: one-hot lane width, and the blocks that start a lane ----
  logic l64, l32, l16, l8;
  assign l32 = EN32 && mode == 2'b01;
  assign l16 = EN16 && mode == 2'b10;
  assign l8  = EN8  && mode == 2'b11;
  assign l64 = ~(l32 | l16 | l8);
  logic [7:0] is_start;
  for (genvar i = 0; i < 8; i++) begin : start
    if (i == 0)          begin : b0   assign is_start[i] = 1'b1;           end
    else if (i % 4 == 0) begin : b32  assign is_start[i] = l32 | l16 | l8; end
    else if (i % 2 == 0) begin : b16  assign is_start[i] = l16 | l8;       end
    else                 begin : b8   assign is_start[i] = l8;             end
  end

  // ---- Operand inversion, straight from the per-block pins ----
  logic [63:0] be;
  for (genvar i = 0; i < 8; i++) begin : invert
    assign be[8*i +: 8] = b[8*i +: 8] ^ {8{sub_sel[i]}};
  end

  // ---- Adder: the sum and the carry out of every block that can end a lane ----
  logic [63:0] s;
  // verilator lint_off UNUSEDSIGNAL
  logic [7:0]  bco;   // read only at lane tops, and only with MINMAX
  // verilator lint_on UNUSEDSIGNAL
  if (ARCH == 0) begin : segmented
    always_comb begin
      logic c;
      c = 1'b0;
      for (int i = 0; i < 8; i++) begin
        {bco[i], s[8*i +: 8]} = {1'b0, a[8*i +: 8]} + {1'b0, be[8*i +: 8]}
                              + {8'b0, is_start[i] ? sub_sel[i] : c};
        c = bco[i];
      end
    end
  end else begin : carry_select
    // blocks that can start a lane within each half (block 0 of a half always has a guard)
    localparam logic [3:0] BRK = {EN8, EN8 | EN16, EN8, 1'b1};
    logic [7:0]  cin;
    logic        lane64, hi1_sel;
    logic [31:0] s_lo, s_hi0, s_hi1;
    logic [3:0]  bco_lo, bco_hi0;
    // verilator lint_off UNUSEDSIGNAL
    logic [3:0]  bco_hi1;   // only its top block's carry is read
    // verilator lint_on UNUSEDSIGNAL
    assign cin    = is_start & sub_sel;   // a lane start injects its subtract's +1
    assign lane64 = ~is_start[4];         // bit 32 starts no lane: one 64-bit lane
    fu_add_sub_mm_seg #(.BRK(BRK)) lo (
      .a(a[31:0]), .be(be[31:0]), .brk(is_start[3:0]), .cin(cin[3:0]), .s(s_lo), .bco(bco_lo));
    // upper half with the lane's carry-in (0 for a 64-bit lane)
    fu_add_sub_mm_seg #(.BRK(BRK)) hi0 (
      .a(a[63:32]), .be(be[63:32]), .brk({is_start[7:5], 1'b1}), .cin(cin[7:4]),
      .s(s_hi0), .bco(bco_hi0));
    // upper half of a 64-bit lane with carry-in 1; operands gated to zero in other modes
    fu_add_sub_mm_seg #(.BRK(4'b0001)) hi1 (
      .a(a[63:32] & {32{lane64}}), .be(be[63:32] & {32{lane64}}), .brk(4'b0001),
      .cin({3'b0, lane64}), .s(s_hi1), .bco(bco_hi1));
    assign hi1_sel = lane64 & bco_lo[3];
    assign s   = {hi1_sel ? s_hi1 : s_hi0, s_lo};
    assign bco = {hi1_sel ? bco_hi1[3] : bco_hi0[3], bco_hi0[2:0], bco_lo};
  end

  // ---- Min/Max side function: compare from the lane carry, one AND-OR per output bit ----
  // verilator lint_off UNUSEDSIGNAL
  logic [7:0]  take_b;   // byte i's lane takes B (Min/Max); read by PIPE 2
  logic [63:0] y;        // the result ahead of the output stage; not read by PIPE 2
  // verilator lint_on UNUSEDSIGNAL
  if (MINMAX) begin : minmax
    logic [7:0] ge, lane_ge;
    for (genvar i = 0; i < 8; i++) begin : blk
      // A >= B: the lane's carry out of A + ~B + 1; a signed lane whose top bits differ: B's sign
      assign ge[i] = (is_signed & (a[8*i+7] ^ b[8*i+7])) ? b[8*i+7] : bco[i];
      // each block takes the result of its lane's top block
      assign lane_ge[i] = (l8 & ge[i]) | (l16 & ge[i | 1]) | (l32 & ge[i | 3]) | (l64 & ge[7]);
      // min takes B when A >= B, max when A < B (on equality A and B are the same value)
      assign take_b[i] = lane_ge[i] ^ max_sel[i];
      // AddSub: the sum; Min/Max: A or B (the unused sources are gated off)
      assign y[8*i +: 8] = (s[8*i +: 8] & {8{~is_min_max}})
                         | (a[8*i +: 8] & {8{is_min_max & ~take_b[i]}})
                         | (b[8*i +: 8] & {8{is_min_max &  take_b[i]}});
    end
  end else begin : addsub_only
    assign take_b = '0;
    assign y      = s;
  end

  if (PIPE == 2) begin : late_select
    // the register holds the sum (AddSub) or A (Min/Max); B and the choices load only for Min/Max
    logic [64:0] q;
    logic [63:0] b_q;
    logic [7:0]  take_b_q;
    fu_out_stage #(.W(65), .PIPE(1)) stage (
      .clk(clk), .rst_n(rst_n), .d({is_min_max, is_min_max ? a : s}), .d_valid(in_valid_0 & in_valid_1),
      .d_ready(in_ready_0), .q(q), .q_valid(out_valid), .q_ready(out_ready));
    always_ff @(posedge clk)
      if (in_ready_0 & is_min_max) begin
        b_q      <= b;
        take_b_q <= take_b;
      end
    for (genvar i = 0; i < 8; i++) begin : choose
      assign out_data[8*i +: 8] = q[64] & take_b_q[i] ? b_q[8*i +: 8] : q[8*i +: 8];
    end
  end else begin : output_stage
    fu_out_stage #(.W(64), .PIPE(PIPE == 1)) stage (
      .clk(clk), .rst_n(rst_n), .d(y), .d_valid(in_valid_0 & in_valid_1), .d_ready(in_ready_0),
      .q(out_data), .q_valid(out_valid), .q_ready(out_ready));
  end
  assign in_ready_1 = in_ready_0;
endmodule : fu_add_sub_mm

module fu_add_sub_mm_reg #(
  parameter int ARCH   = 0,
  parameter bit MINMAX = 1,
  parameter int PIPE   = 0,
  parameter bit EN32   = 1,
  parameter bit EN16   = 1,
  parameter bit EN8    = 1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,         // of the next operation, as are the other controls
  input  logic        is_min_max,
  input  logic        is_signed,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  // each block's lane op: op_sel at its lane's start
  logic [7:0] lane_op;
  // verilator lint_off UNUSEDSIGNAL
  logic [7:0] is_start_unused;   // the core decodes the lane starts from the registered mode
  // verilator lint_on UNUSEDSIGNAL
  fu_add_sub_spike_decode #(.EN32(EN32), .EN16(EN16), .EN8(EN8), .FLAT(1), .REP_OP(0)) decode (
    .mode(mode), .op_sel(op_sel), .is_start(is_start_unused), .sub(lane_op));

  logic [1:0] mode_q;
  logic       is_min_max_q, is_signed_q;
  logic [7:0] sub, mx;   // per block: the lane subtracts (every lane for Min/Max); the lane takes the max
  always_ff @(posedge clk)
    if (~(in_valid_0 & in_valid_1) | in_ready_0) begin
      mode_q       <= mode;
      is_min_max_q <= is_min_max;
      is_signed_q  <= is_signed;
      sub          <= lane_op | {8{MINMAX & is_min_max}};
      mx           <= lane_op;
    end

  fu_add_sub_mm #(.ARCH(ARCH), .MINMAX(MINMAX), .PIPE(PIPE), .EN32(EN32), .EN16(EN16), .EN8(EN8)) core (
    .clk(clk), .rst_n(rst_n), .mode(mode_q), .sub_sel(sub), .max_sel(mx), .is_signed(is_signed_q),
    .is_min_max(is_min_max_q),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule : fu_add_sub_mm_reg

// Partitioned add over NBLK 8-bit blocks (rtl/fu_add_sub_spike.sv fu_add_sub_spike_seg): a guard
// bit below each block in BRK (block 0 always has one, the segment's carry-in). A guard bit passes
// the carry on (1, 0), or, when brk[k], replaces it with cin[k] (cin, cin); its sum bit is then the
// carry out of the block below, which is that block's lane carry when block k starts a lane.
module fu_add_sub_mm_seg #(
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
  output logic [NBLK-1:0]   bco      // carry out of the top block, and of each block below a guard
);
  function automatic int guards_upto(int k);   // guard bits at or below block k
    int n = 0;
    for (int i = 0; i <= k; i++) n += int'(BRK[i]);
    return n;
  endfunction
  localparam int W = 8*NBLK + guards_upto(NBLK-1);
  logic [W-1:0] xa, xb;
  // verilator lint_off UNUSEDSIGNAL
  logic [W-1:0] xs;   // the lowest guard's sum is dropped
  // verilator lint_on UNUSEDSIGNAL
  logic         co;
  for (genvar k = 0; k < NBLK; k++) begin : blk
    localparam int OFF = 8*k + guards_upto(k);
    if (BRK[k]) begin : guard
      assign xa[OFF-1] = brk[k] ? cin[k] : 1'b1;
      assign xb[OFF-1] = brk[k] ? cin[k] : 1'b0;
    end
    assign xa[OFF +: 8] = a[8*k +: 8];
    assign xb[OFF +: 8] = be[8*k +: 8];
    assign s[8*k +: 8] = xs[OFF +: 8];
    if (k == NBLK-1)     begin : top    assign bco[k] = co;               end
    else if (BRK[k+1])   begin : below  assign bco[k] = xs[OFF + 8];      end   // the guard above
    else                 begin : mid    assign bco[k] = 1'b0;             end   // never ends a lane
  end
  assign {co, xs} = {1'b0, xa} + {1'b0, xb};
endmodule : fu_add_sub_mm_seg

// Output stage: PIPE = 0 passes the result through (latency 0); PIPE = 1 registers it (latency 1),
// loading only when a result is accepted, with the usual stall: the register holds while the
// consumer is not ready.
module fu_out_stage #(
  parameter int W    = 64,
  parameter bit PIPE = 0
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic         clk,
  input  logic         rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [W-1:0] d,
  input  logic         d_valid,
  output logic         d_ready,
  output logic [W-1:0] q,
  output logic         q_valid,
  input  logic         q_ready
);
  if (PIPE) begin : registered
    logic         advance, v_q;
    logic [W-1:0] d_q;
    assign advance = ~v_q | q_ready;
    always_ff @(posedge clk or negedge rst_n)
      if (!rst_n)       v_q <= 1'b0;
      else if (advance) v_q <= d_valid;
    always_ff @(posedge clk)
      if (advance & d_valid) d_q <= d;
    assign q       = d_q;
    assign q_valid = v_q;
    assign d_ready = advance & d_valid;
  end else begin : combinational
    assign q       = d;
    assign q_valid = d_valid;
    assign d_ready = q_ready & d_valid;
  end
endmodule : fu_out_stage

// The decomposable Min/Max (fu_min_max_gen.sv) behind the same output stage, for the pipelined
// comparison: tiers m2 (EN16 = 0) and m4.
module fu_min_max_piped #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
  input  logic        is_signed,
  input  logic [3:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  logic [63:0] y;
  // verilator lint_off UNUSEDSIGNAL
  logic        core_valid, core_ready0, core_ready1;   // the stage handles the handshake
  // verilator lint_on UNUSEDSIGNAL
  fu_min_max_dec #(.EN32(EN32), .EN16(EN16)) core (
    .clk(clk), .rst_n(rst_n), .mode(mode), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(1'b1), .in_ready_0(core_ready0),
    .in_data_1(in_data_1), .in_valid_1(1'b1), .in_ready_1(core_ready1),
    .out_data(y), .out_valid(core_valid), .out_ready(1'b1));
  fu_out_stage #(.W(64), .PIPE(1)) stage (
    .clk(clk), .rst_n(rst_n), .d(y), .d_valid(in_valid_0 & in_valid_1), .d_ready(in_ready_0),
    .q(out_data), .q_valid(out_valid), .q_ready(out_ready));
  assign in_ready_1 = in_ready_0;
endmodule : fu_min_max_piped
