// fu_fp_min_max_decomp.sv -- Decomposable (subword-SIMD) FU for FP min/max.
// share group 12 (arith.minimumf / arith.maximumf), decomposed across packed-FP lanes.
//
//   mode = 2'b00 -> 1x fp64  (1/11/52)   mode = 2'b01 -> 2x fp32 (1/8/23)
//   mode = 2'b10 -> 4x fp16  (1/5/10)    mode = 2'b11 -> reserved -> 1x fp64
//   op_sel[i] per lane: 0 -> min, 1 -> max.
//
// IEEE-754-2019 minimum/maximum: NaN-propagating (NaN if either operand is NaN) and
// -0.0 < +0.0. The order is a sign+magnitude compare (a monotonic-key compare); the result
// is always exactly one input (no rounding). One shared format-parameterized comparator core
// (fp_mm_lane) reused at all lane widths. Combinational, latency 0. Proves functional
// decomposition; a physically-shared segmented FP comparator is the synthesis/area objective.
module fu_fp_min_max_decomp (
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

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // Shared FP min/max for one lane of the given format. Operands in the low
  // (1+EXP_W+MAN_W) bits of a/b; result (one of the inputs, or qNaN) in the low bits.
  function automatic logic [63:0] fp_mm_lane(input logic [63:0] a,
                                             input logic [63:0] b,
                                             input logic        is_max,
                                             input int          EXP_W,
                                             input int          MAN_W);
    logic [63:0] EXP_MASK, MAN_MASK, MAG_MASK, mag_a, mag_b;
    logic [11:0] EXP_ONES, ea, eb;
    logic [51:0] ma, mb;
    logic        sa, sb, a_nan, b_nan, a_lt;
    begin : body
      EXP_MASK = (64'd1 << EXP_W) - 64'd1;
      MAN_MASK = (64'd1 << MAN_W) - 64'd1;
      MAG_MASK = (64'd1 << (EXP_W + MAN_W)) - 64'd1;   // low bits: {exp, mantissa}, sign cleared
      EXP_ONES = EXP_MASK[11:0];

      sa = a[EXP_W + MAN_W];
      sb = b[EXP_W + MAN_W];
      ea = 12'((a >> MAN_W) & EXP_MASK);
      eb = 12'((b >> MAN_W) & EXP_MASK);
      ma = 52'(a & MAN_MASK);
      mb = 52'(b & MAN_MASK);
      a_nan = (ea == EXP_ONES) && (ma != 52'd0);
      b_nan = (eb == EXP_ONES) && (mb != 52'd0);

      if (a_nan || b_nan)
        return (EXP_MASK << MAN_W) | (64'd1 << (MAN_W - 1));   // canonical qNaN

      mag_a = a & MAG_MASK;
      mag_b = b & MAG_MASK;

      // a < b (as floats): differing signs -> negative one smaller (handles -0<+0);
      // both negative -> larger magnitude smaller; both positive -> smaller magnitude smaller.
      if (sa != sb)      a_lt = sa;
      else if (sa)       a_lt = mag_a > mag_b;
      else               a_lt = mag_a < mag_b;

      return is_max ? (a_lt ? b : a) : (a_lt ? a : b);
    end : body
  endfunction

  // ---- Per-mode lane evaluations (shared comparator at three widths) ----
  logic [63:0] p1, p2, p4;
  logic [31:0] s0, s1;
  logic [15:0] h0, h1, h2, h3;

  assign p1 = fp_mm_lane(in_data_0, in_data_1, op_sel[0], 11, 52);

  assign s0 = 32'(fp_mm_lane({32'd0, in_data_0[31:0]},  {32'd0, in_data_1[31:0]},  op_sel[0], 8, 23));
  assign s1 = 32'(fp_mm_lane({32'd0, in_data_0[63:32]}, {32'd0, in_data_1[63:32]}, op_sel[2], 8, 23));
  assign p2 = {s1, s0};

  assign h0 = 16'(fp_mm_lane({48'd0, in_data_0[15:0]},  {48'd0, in_data_1[15:0]},  op_sel[0], 5, 10));
  assign h1 = 16'(fp_mm_lane({48'd0, in_data_0[31:16]}, {48'd0, in_data_1[31:16]}, op_sel[1], 5, 10));
  assign h2 = 16'(fp_mm_lane({48'd0, in_data_0[47:32]}, {48'd0, in_data_1[47:32]}, op_sel[2], 5, 10));
  assign h3 = 16'(fp_mm_lane({48'd0, in_data_0[63:48]}, {48'd0, in_data_1[63:48]}, op_sel[3], 5, 10));
  assign p4 = {h3, h2, h1, h0};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // 1x fp64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_fp_min_max_decomp
