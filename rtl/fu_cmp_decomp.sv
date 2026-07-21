// fu_cmp_decomp.sv -- Decomposable (subword-SIMD) FU for packed integer compare.
// op: arith.cmpi, decomposed across lanes; per-lane mask output (SSE PCMPGT-style).
//
//   mode = 2'b00 -> 1x64 : one 64-bit lane
//   mode = 2'b01 -> 2x32 : two independent 32-bit lanes
//   mode = 2'b10 -> 4x16 : four independent 16-bit lanes
//   mode = 2'b11 -> reserved, behaves as 1x64
//
//   pred[3:0] (global): 0 eq, 1 ne, 2 slt, 3 sle, 4 sgt, 5 sge, 6 ult, 7 ule, 8 ugt, 9 uge;
//                       reserved (10..15) -> all-zeros. Signedness is part of the predicate.
//   out_data lane = predicate-true ? all-ones : all-zeros (over the lane width).
//
// One shared 64-bit comparator (four 16-bit block comparators) with the lexicographic combine
// broken at 16/32/48-bit boundaries by mode (same pattern as fu_min_max_decomp); three combines
// derive per-lane eq, unsigned a>b, and signed a>b, and a predicate mux forms the mask.
// Combinational, latency 0.
module fu_cmp_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic [3:0]  pred,

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

  // Predicate evaluation from per-lane (unsigned a>b, signed a>b, a==b).
  function automatic logic pred_eval(input logic [3:0] p, input logic ugt,
                                     input logic sgt, input logic eq);
    case (p)
      4'd0:    pred_eval = eq;               // eq
      4'd1:    pred_eval = ~eq;              // ne
      4'd2:    pred_eval = ~(sgt | eq);      // slt
      4'd3:    pred_eval = ~sgt;             // sle
      4'd4:    pred_eval = sgt;              // sgt
      4'd5:    pred_eval = sgt | eq;         // sge
      4'd6:    pred_eval = ~(ugt | eq);      // ult
      4'd7:    pred_eval = ~ugt;             // ule
      4'd8:    pred_eval = ugt;              // ugt
      4'd9:    pred_eval = ugt | eq;         // uge
      default: pred_eval = 1'b0;             // reserved
    endcase
  endfunction

  // ---- Split into four 16-bit blocks ----
  logic [15:0] a0, a1, a2, a3, b0, b1, b2, b3;
  assign {a3, a2, a1, a0} = in_data_0;
  assign {b3, b2, b1, b0} = in_data_1;

  // ---- Per-block comparators ----
  logic gtu0, gtu1, gtu2, gtu3, eq0, eq1, eq2, eq3;
  assign gtu0 = a0 > b0;  assign eq0 = a0 == b0;
  assign gtu1 = a1 > b1;  assign eq1 = a1 == b1;
  assign gtu2 = a2 > b2;  assign eq2 = a2 == b2;
  assign gtu3 = a3 > b3;  assign eq3 = a3 == b3;

  // ---- Top-block flags + signed-adjusted gt (top block of each lane only) ----
  logic top0, top1, top2;
  assign top0 = (mode == M_4X16);
  assign top1 = (mode == M_2X32) || (mode == M_4X16);
  assign top2 = (mode == M_4X16);
  logic gts0, gts1, gts2, gts3;
  assign gts0 = (top0 & (a0[15] ^ b0[15])) ? b0[15] : gtu0;
  assign gts1 = (top1 & (a1[15] ^ b1[15])) ? b1[15] : gtu1;
  assign gts2 = (top2 & (a2[15] ^ b2[15])) ? b2[15] : gtu2;
  assign gts3 = (       (a3[15] ^ b3[15])) ? b3[15] : gtu3;

  // ---- Lane breaks ----
  logic brk1, brk2, brk3;
  assign brk1 = (mode == M_4X16);
  assign brk2 = (mode == M_2X32) || (mode == M_4X16);
  assign brk3 = (mode == M_4X16);

  // ---- Three mode-gated combines: unsigned a>b, signed a>b, a==b (per lane-top k) ----
  logic ru0, ru1, ru2, ru3, rs0, rs1, rs2, rs3, e0, e1, e2, e3;
  assign ru0 = gtu0;
  assign ru1 = brk1 ? gtu1 : (gtu1 | (eq1 & ru0));
  assign ru2 = brk2 ? gtu2 : (gtu2 | (eq2 & ru1));
  assign ru3 = brk3 ? gtu3 : (gtu3 | (eq3 & ru2));
  assign rs0 = gts0;
  assign rs1 = brk1 ? gts1 : (gts1 | (eq1 & rs0));
  assign rs2 = brk2 ? gts2 : (gts2 | (eq2 & rs1));
  assign rs3 = brk3 ? gts3 : (gts3 | (eq3 & rs2));
  assign e0  = eq0;
  assign e1  = brk1 ? eq1 : (eq1 & e0);
  assign e2  = brk2 ? eq2 : (eq2 & e1);
  assign e3  = brk3 ? eq3 : (eq3 & e2);

  // ---- Per-lane-top predicate result ----
  logic res0, res1, res2, res3;
  assign res0 = pred_eval(pred, ru0, rs0, e0);
  assign res1 = pred_eval(pred, ru1, rs1, e1);
  assign res2 = pred_eval(pred, ru2, rs2, e2);
  assign res3 = pred_eval(pred, ru3, rs3, e3);

  // ---- Route each block to its lane's result, broadcast to a 16-bit mask ----
  logic m0, m1, m2, m3;
  always_comb begin : route
    m0 = res3; m1 = res3; m2 = res3; m3 = res3;   // 1x64 (and reserved)
    case (mode)
      M_2X32: begin : d2x32
        m0 = res1; m1 = res1; m2 = res3; m3 = res3;
      end : d2x32
      M_4X16: begin : d4x16
        m0 = res0; m1 = res1; m2 = res2; m3 = res3;
      end : d4x16
      default: ;
    endcase
  end : route

  assign out_data = {{16{m3}}, {16{m2}}, {16{m1}}, {16{m0}}};

endmodule : fu_cmp_decomp
