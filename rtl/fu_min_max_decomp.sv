// fu_min_max_decomp.sv -- Decomposable (subword-SIMD) FU for min/max.
// share groups 6 (arith.minsi/maxsi) + 7 (arith.minui/maxui), decomposed across lanes.
//
//   mode = 2'b00 -> 1x64 : one 64-bit lane
//   mode = 2'b01 -> 2x32 : two independent 32-bit lanes
//   mode = 2'b10 -> 4x16 : four independent 16-bit lanes
//   mode = 2'b11 -> reserved, behaves as 1x64
//
//   is_signed   : 1 = signed compare, 0 = unsigned (held config, all lanes).
//   op_sel[i]   : per-lane op: 0 -> min, 1 -> max.
//
// One shared 64-bit comparator viewed as four 16-bit block comparators; the
// lexicographic combine chain is broken at the 16/32/48-bit boundaries by mode
// (the compare analogue of the segmented carry in fu_add_sub_decomp). Signedness
// only reinterprets the most-significant block of each lane. Combinational, latency 0.
module fu_min_max_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic        is_signed,
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

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // ---- Split operands into four 16-bit blocks (little-endian by lane) ----
  logic [15:0] a0, a1, a2, a3;
  logic [15:0] b0, b1, b2, b3;
  assign {a3, a2, a1, a0} = in_data_0;
  assign {b3, b2, b1, b0} = in_data_1;

  // ---- Shared per-block comparators (unsigned magnitude + equality) ----
  logic gtu0, gtu1, gtu2, gtu3;
  logic       eq1, eq2, eq3;             // eq0 unneeded (block0 never has a lower neighbor)
  assign gtu0 = a0 > b0;
  assign gtu1 = a1 > b1;  assign eq1 = a1 == b1;
  assign gtu2 = a2 > b2;  assign eq2 = a2 == b2;
  assign gtu3 = a3 > b3;  assign eq3 = a3 == b3;

  // ---- Which blocks are the MSB (top) block of their lane (mode-dependent) ----
  logic top0, top1, top2;                // top3 is always a lane top
  assign top0 = (mode == M_4X16);
  assign top1 = (mode == M_2X32) || (mode == M_4X16);
  assign top2 = (mode == M_4X16);

  // ---- Signed adjust: at a lane's top block, differing signs flip the order
  //      (a>b iff a non-negative and b negative, i.e. b_msb) ----
  logic gt0, gt1, gt2, gt3;
  assign gt0 = (is_signed & top0 & (a0[15] ^ b0[15])) ? b0[15] : gtu0;
  assign gt1 = (is_signed & top1 & (a1[15] ^ b1[15])) ? b1[15] : gtu1;
  assign gt2 = (is_signed & top2 & (a2[15] ^ b2[15])) ? b2[15] : gtu2;
  assign gt3 = (is_signed &        (a3[15] ^ b3[15])) ? b3[15] : gtu3;

  // ---- Lexicographic combine (MSB block dominates), broken at lane starts ----
  logic brk1, brk2, brk3;                // block k starts a new lane -> ignore r_{k-1}
  assign brk1 = (mode == M_4X16);
  assign brk2 = (mode == M_2X32) || (mode == M_4X16);
  assign brk3 = (mode == M_4X16);

  logic r0, r1, r2, r3;                   // r_k = "a > b" for the lane whose top block is k
  assign r0 = gt0;
  assign r1 = brk1 ? gt1 : (gt1 | (eq1 & r0));
  assign r2 = brk2 ? gt2 : (gt2 | (eq2 & r1));
  assign r3 = brk3 ? gt3 : (gt3 | (eq3 & r2));

  // ---- Route each block's lane "a>b" and op (min/max) per mode ----
  logic agt0, agt1, agt2, agt3;
  logic o0, o1, o2, o3;
  always_comb begin : route
    agt0 = r3; agt1 = r3; agt2 = r3; agt3 = r3;            // 1x64 (and reserved): one lane = r3
    o0   = op_sel[0]; o1 = op_sel[0]; o2 = op_sel[0]; o3 = op_sel[0];
    case (mode)
      M_2X32: begin : d2x32
        agt0 = r1; agt1 = r1; agt2 = r3; agt3 = r3;
        o0 = op_sel[0]; o1 = op_sel[0]; o2 = op_sel[2]; o3 = op_sel[2];
      end : d2x32
      M_4X16: begin : d4x16
        agt0 = r0; agt1 = r1; agt2 = r2; agt3 = r3;
        o0 = op_sel[0]; o1 = op_sel[1]; o2 = op_sel[2]; o3 = op_sel[3];
      end : d4x16
      default: ;                                           // 1x64 defaults above
    endcase
  end : route

  // ---- Per-block output select: pick b when (min & a>b) or (max & a<=b) ----
  assign out_data = {
    ((o3 ? ~agt3 : agt3) ? b3 : a3),
    ((o2 ? ~agt2 : agt2) ? b2 : a2),
    ((o1 ? ~agt1 : agt1) ? b1 : a1),
    ((o0 ? ~agt0 : agt0) ? b0 : a0)
  };

endmodule : fu_min_max_decomp
