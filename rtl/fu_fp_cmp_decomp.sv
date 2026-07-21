// fu_fp_cmp_decomp.sv -- Decomposable (subword-SIMD) FU for packed float compare.
// op: arith.cmpf, decomposed across packed-FP lanes; per-lane mask output (SSE CMPPS-style).
//
//   mode = 2'b00 -> 1x fp64      mode = 2'b01 -> 2x fp32
//   mode = 2'b10 -> 4x fp16      mode = 2'b11 -> reserved -> 1x fp64
//   pred[3:0] (global): 0 false,1 OEQ,2 OGT,3 OGE,4 OLT,5 OLE,6 ONE,7 ORD,
//                       8 UEQ,9 UGT,10 UGE,11 ULT,12 ULE,13 UNE,14 UNO,15 true.
//   out_data lane = predicate-true ? all-ones : all-zeros (over the lane width).
//
// IEEE ordered/unordered semantics: unordered = either operand NaN; -0 == +0 (unlike min/max).
// Per lane: uno + sign/magnitude trichotomy (lt/eq/gt), then a 16-way predicate mux -> mask.
// Combinational, latency 0.
module fu_fp_cmp_decomp (
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

  // Packed float compare for one lane: returns the predicate boolean.
  function automatic logic fp_cmp_lane(input logic [3:0] pr, input logic [63:0] a,
                                       input logic [63:0] b, input int EXP_W, input int MAN_W);
    logic [63:0] EXP_MASK, MAN_MASK, MAG_MASK, mag_a, mag_b;
    logic [11:0] EXP_ONES, ea, eb;
    logic [51:0] ma, mb;
    logic sa, sb, a_nan, b_nan, a_zero, b_zero, uno, lt, gt, eq_;
    begin : body
      EXP_MASK = (64'd1 << EXP_W) - 64'd1;
      MAN_MASK = (64'd1 << MAN_W) - 64'd1;
      MAG_MASK = (64'd1 << (EXP_W + MAN_W)) - 64'd1;
      EXP_ONES = 12'((1 << EXP_W) - 1);

      sa = a[EXP_W + MAN_W];
      sb = b[EXP_W + MAN_W];
      ea = 12'((a >> MAN_W) & EXP_MASK);
      eb = 12'((b >> MAN_W) & EXP_MASK);
      ma = 52'(a & MAN_MASK);
      mb = 52'(b & MAN_MASK);
      a_nan  = (ea == EXP_ONES) && (ma != 52'd0);
      b_nan  = (eb == EXP_ONES) && (mb != 52'd0);
      a_zero = (ea == 12'd0)    && (ma == 52'd0);
      b_zero = (eb == 12'd0)    && (mb == 52'd0);
      uno    = a_nan | b_nan;
      mag_a  = a & MAG_MASK;
      mag_b  = b & MAG_MASK;

      // ordered trichotomy (valid when !uno); -0 == +0
      if (a_zero && b_zero) begin
        lt = 1'b0; gt = 1'b0; eq_ = 1'b1;
      end
      else begin
        if (sa != sb)   begin lt = sa;            gt = sb;            end  // negative < positive
        else if (sa)    begin lt = mag_a > mag_b; gt = mag_a < mag_b; end  // both negative
        else            begin lt = mag_a < mag_b; gt = mag_a > mag_b; end  // both positive
        eq_ = ~lt & ~gt;
      end

      case (pr)
        4'd0:    fp_cmp_lane = 1'b0;                // false
        4'd1:    fp_cmp_lane = ~uno & eq_;          // OEQ
        4'd2:    fp_cmp_lane = ~uno & gt;           // OGT
        4'd3:    fp_cmp_lane = ~uno & (gt | eq_);   // OGE
        4'd4:    fp_cmp_lane = ~uno & lt;           // OLT
        4'd5:    fp_cmp_lane = ~uno & (lt | eq_);   // OLE
        4'd6:    fp_cmp_lane = ~uno & (lt | gt);    // ONE
        4'd7:    fp_cmp_lane = ~uno;                // ORD
        4'd8:    fp_cmp_lane = uno | eq_;           // UEQ
        4'd9:    fp_cmp_lane = uno | gt;            // UGT
        4'd10:   fp_cmp_lane = uno | (gt | eq_);    // UGE
        4'd11:   fp_cmp_lane = uno | lt;            // ULT
        4'd12:   fp_cmp_lane = uno | (lt | eq_);    // ULE
        4'd13:   fp_cmp_lane = uno | (lt | gt);     // UNE
        4'd14:   fp_cmp_lane = uno;                 // UNO
        default: fp_cmp_lane = 1'b1;                // true (15)
      endcase
    end : body
  endfunction

  // ---- Per-mode lane evaluations (shared comparator at three widths) ----
  logic r64, rs0, rs1, rh0, rh1, rh2, rh3;
  assign r64 = fp_cmp_lane(pred, in_data_0, in_data_1, 11, 52);
  assign rs0 = fp_cmp_lane(pred, {32'd0, in_data_0[31:0]},  {32'd0, in_data_1[31:0]},  8, 23);
  assign rs1 = fp_cmp_lane(pred, {32'd0, in_data_0[63:32]}, {32'd0, in_data_1[63:32]}, 8, 23);
  assign rh0 = fp_cmp_lane(pred, {48'd0, in_data_0[15:0]},  {48'd0, in_data_1[15:0]},  5, 10);
  assign rh1 = fp_cmp_lane(pred, {48'd0, in_data_0[31:16]}, {48'd0, in_data_1[31:16]}, 5, 10);
  assign rh2 = fp_cmp_lane(pred, {48'd0, in_data_0[47:32]}, {48'd0, in_data_1[47:32]}, 5, 10);
  assign rh3 = fp_cmp_lane(pred, {48'd0, in_data_0[63:48]}, {48'd0, in_data_1[63:48]}, 5, 10);

  logic [63:0] p1, p2, p4;
  assign p1 = {64{r64}};
  assign p2 = {{32{rs1}}, {32{rs0}}};
  assign p4 = {{16{rh3}}, {16{rh2}}, {16{rh1}}, {16{rh0}}};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // 1x fp64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_fp_cmp_decomp
