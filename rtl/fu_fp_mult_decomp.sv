// fu_fp_mult_decomp.sv -- Decomposable (subword-SIMD) FU for IEEE-754 multiply.
// op: arith.mulf, decomposed across packed-FP lanes.
//
//   mode = 2'b00 -> 1x fp64  (1/11/52, bias 1023)
//   mode = 2'b01 -> 2x fp32  (1/8/23,  bias 127)
//   mode = 2'b10 -> 4x fp16  (1/5/10,  bias 15)
//   mode = 2'b11 -> reserved, behaves as 1x fp64
//
// Full IEEE-754: round-to-nearest-even, gradual underflow (subnormals),
// NaN / +-Inf / signed zero, Inf*0 = NaN. No op_sel (multiply has no add/sub variant;
// the result sign is always sign_a ^ sign_b). One shared format-parameterized core
// (fp_mul_lane) is written once and reused for every format/lane; only MAN_W and EXP_W
// (round position / bias / exponent limits) differ. Combinational, intrinsic latency 0.
//
// The mantissa multiplier is the dominant, lane-separable resource (a 53x53 PP array
// segments into 2x24x24 / 4x11x11). This RTL proves functional decomposition; physical
// single-multiplier sharing (a segmented PP array) is the synthesis/area follow-up.
module fu_fp_mult_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,

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

  // Shared IEEE-754 multiply core for one lane of the given format.
  // Operands in the low (1+EXP_W+MAN_W) bits of a/b; result in the low bits. The exact
  // product is placed left-justified in a 128-bit field; a single-shot normalize/round
  // handles overflow, gradual underflow, and RNE.
  function automatic logic [63:0] fp_mul_lane(input logic [63:0] a,
                                              input logic [63:0] b,
                                              input int          EXP_W,
                                              input int          MAN_W);
    localparam int IMP = 120;                 // fixed implicit-bit position for a normalized result
    logic [63:0]  EXP_MASK, MAN_MASK, A, B, kept;
    logic [11:0]  EXP_ONES, exp_field;
    logic [51:0]  ma, mb, man_field;
    logic signed [15:0] BIAS, eA_unb, eB_unb, baseExp, eNorm, msb16, totalShift, dsh, resExp;
    logic         sa, sb, sgn;
    logic [11:0]  ea, eb;
    logic         a_nan, a_inf, a_zero, b_nan, b_inf, b_zero;
    logic [127:0] P, mag;
    logic [7:0]   msb;
    int           k;
    logic         stk_shift, lsb, guard, sticky, rnd_up, implicit;

    begin : body
      EXP_MASK = (64'd1 << EXP_W) - 64'd1;
      MAN_MASK = (64'd1 << MAN_W) - 64'd1;
      EXP_ONES = EXP_MASK[11:0];
      BIAS     = 16'((1 << (EXP_W - 1)) - 1);

      // ---- unpack ----
      sa  = a[EXP_W + MAN_W];
      sb  = b[EXP_W + MAN_W];
      sgn = sa ^ sb;
      ea  = 12'((a >> MAN_W) & EXP_MASK);
      eb  = 12'((b >> MAN_W) & EXP_MASK);
      ma  = 52'(a & MAN_MASK);
      mb  = 52'(b & MAN_MASK);
      a_inf  = (ea == EXP_ONES) && (ma == 52'd0);
      a_nan  = (ea == EXP_ONES) && (ma != 52'd0);
      a_zero = (ea == 12'd0)    && (ma == 52'd0);
      b_inf  = (eb == EXP_ONES) && (mb == 52'd0);
      b_nan  = (eb == EXP_ONES) && (mb != 52'd0);
      b_zero = (eb == 12'd0)    && (mb == 52'd0);

      // ---- specials ----
      if (a_nan || b_nan)
        return (EXP_MASK << MAN_W) | (64'd1 << (MAN_W - 1));                    // qNaN
      if ((a_inf && b_zero) || (a_zero && b_inf))
        return (EXP_MASK << MAN_W) | (64'd1 << (MAN_W - 1));                    // Inf * 0 = NaN
      if (a_inf || b_inf)
        return (64'(sgn) << (EXP_W+MAN_W)) | (EXP_MASK << MAN_W);               // Inf
      if (a_zero || b_zero)
        return 64'(sgn) << (EXP_W+MAN_W);                                       // signed zero

      // ---- significands (implicit bit) and unbiased exponents ----
      A = (64'(ea != 12'd0) << MAN_W) | {12'd0, ma};
      B = (64'(eb != 12'd0) << MAN_W) | {12'd0, mb};
      eA_unb = (ea == 12'd0) ? (16'sd1 - BIAS) : ($signed({4'b0, ea}) - BIAS);
      eB_unb = (eb == 12'd0) ? (16'sd1 - BIAS) : ($signed({4'b0, eb}) - BIAS);
      baseExp = eA_unb + eB_unb + BIAS;

      // ---- exact product, placed left-justified (bit 2*MAN_W -> IMP) ----
      P   = 128'(A) * 128'(B);
      mag = P << (IMP - 2*MAN_W);

      // ---- normalized biased exponent ----
      msb = 8'd0;
      for (k = 0; k < 128; k = k + 1) if (mag[k]) msb = 8'(k);
      msb16 = 16'(msb);
      eNorm = baseExp + msb16 - 16'(IMP);
      if (eNorm >= $signed({4'b0, EXP_ONES}))
        return (64'(sgn) << (EXP_W+MAN_W)) | (EXP_MASK << MAN_W);               // overflow -> Inf

      // ---- shift into the rounding frame: normal (MSB->IMP) or subnormal (exp = emin) ----
      if (eNorm >= 16'sd1) begin : norm
        totalShift = 16'(IMP) - msb16;
        resExp     = eNorm;
      end : norm
      else begin : subn
        totalShift = (16'(IMP) - 16'sd1) + eNorm - msb16;
        resExp     = 16'sd1;
      end : subn

      if (totalShift >= 16'sd0) begin : lsh
        mag = mag << totalShift;
        stk_shift = 1'b0;
      end : lsh
      else begin : rsh
        dsh = -totalShift;
        if (dsh >= 16'sd128) begin
          stk_shift = |mag;
          mag = 128'd0;
        end
        else begin
          stk_shift = |(mag << (16'sd128 - dsh));
          mag = mag >> dsh;
        end
      end : rsh

      // ---- round to nearest even at the mantissa LSB (bit IMP-MAN_W) ----
      lsb    = mag[IMP - MAN_W];
      guard  = mag[IMP - MAN_W - 1];
      sticky = stk_shift | (|(mag & ((128'd1 << (IMP - MAN_W - 1)) - 128'd1)));
      rnd_up = guard & (lsb | sticky);
      kept   = 64'(mag >> (IMP - MAN_W)) & ((64'd1 << (MAN_W + 1)) - 64'd1);
      if (rnd_up) begin : do_round
        kept = kept + 64'd1;
        if (kept == (64'd1 << (MAN_W + 1))) begin : carry
          kept   = 64'd1 << MAN_W;            // 1.111..1 + 1 -> 10.000, renormalize
          resExp = resExp + 16'sd1;
        end : carry
      end : do_round

      // ---- pack (round-carry overflow -> Inf; subnormal -> exp field 0) ----
      if (resExp >= $signed({4'b0, EXP_ONES}))
        return (64'(sgn) << (EXP_W+MAN_W)) | (EXP_MASK << MAN_W);
      implicit  = kept[MAN_W];
      man_field = 52'(kept & MAN_MASK);
      exp_field = implicit ? resExp[11:0] : 12'd0;
      return (64'(sgn) << (EXP_W+MAN_W)) | ({52'd0, exp_field} << MAN_W) | {12'd0, man_field};
    end : body
  endfunction

  // ---- per-mode lane evaluations (shared core at three widths) ----
  logic [63:0] p1, p2, p4;
  logic [31:0] s0, s1;
  logic [15:0] h0, h1, h2, h3;

  assign p1 = fp_mul_lane(in_data_0, in_data_1, 11, 52);

  assign s0 = 32'(fp_mul_lane({32'd0, in_data_0[31:0]},  {32'd0, in_data_1[31:0]},  8, 23));
  assign s1 = 32'(fp_mul_lane({32'd0, in_data_0[63:32]}, {32'd0, in_data_1[63:32]}, 8, 23));
  assign p2 = {s1, s0};

  assign h0 = 16'(fp_mul_lane({48'd0, in_data_0[15:0]},  {48'd0, in_data_1[15:0]},  5, 10));
  assign h1 = 16'(fp_mul_lane({48'd0, in_data_0[31:16]}, {48'd0, in_data_1[31:16]}, 5, 10));
  assign h2 = 16'(fp_mul_lane({48'd0, in_data_0[47:32]}, {48'd0, in_data_1[47:32]}, 5, 10));
  assign h3 = 16'(fp_mul_lane({48'd0, in_data_0[63:48]}, {48'd0, in_data_1[63:48]}, 5, 10));
  assign p4 = {h3, h2, h1, h0};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // 1x fp64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_fp_mult_decomp
