// fu_fp_add_sub_decomp.sv -- Decomposable (subword-SIMD) FU for IEEE-754 add/sub.
// op: arith.addf / arith.subf, decomposed across packed-FP lanes.
//
//   mode = 2'b00 -> 1x fp64  (1/11/52, bias 1023)
//   mode = 2'b01 -> 2x fp32  (1/8/23,  bias 127)
//   mode = 2'b10 -> 4x fp16  (1/5/10,  bias 15)
//   mode = 2'b11 -> reserved, behaves as 1x fp64
//
//   op_sel[i] per lane: 0 -> add, 1 -> subtract (flip b's sign bit).
//
// Full IEEE-754: round-to-nearest-even, gradual underflow (subnormals),
// NaN / +-Inf / signed zero. One shared format-parameterized core (fp_lane) is
// written once and reused for every format/lane; only MAN_W (round position) and
// EXP_W (bias / exponent limits) differ. Combinational, intrinsic latency 0.
//
// This RTL proves functional decomposition (correct independent per-lane results);
// physical single-datapath sharing (a segmented aligner/adder/normalizer) is the
// synthesis/area objective, tracked as a follow-up alongside the area inequality.
module fu_fp_add_sub_decomp (
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

  // Shared IEEE-754 add/sub core for one lane of the given format.
  // Operands in the low (1+EXP_W+MAN_W) bits of a/b; result in the low bits.
  // Internal significands are left-justified with the implicit bit at bit 120 in a
  // 128-bit field, so alignment/add/subtract are exact and the sticky is a clean OR.
  function automatic logic [63:0] fp_lane(input logic [63:0] a,
                                          input logic [63:0] b,
                                          input logic        sub,
                                          input int          EXP_W,
                                          input int          MAN_W);
    localparam int IMP = 120;                 // fixed implicit-bit position
    logic [63:0] EXP_MASK, MAN_MASK;
    logic [11:0] EXP_ONES;
    logic        sa, sb;
    logic [11:0] ea, eb;
    logic [51:0] ma, mb;
    logic        a_nan, a_inf, b_nan, b_inf;
    logic signed [15:0] expA, expB, baseExp;
    logic [127:0] sigA, sigB, alA, alB, mag;
    logic signed [15:0] shA, shB;
    logic         stkA, stkB, stk_align, eff_sub, sgn;
    logic [127:0] rsh_lost_mask;
    int           msb, k;
    logic signed [15:0] lz, sh_norm, rsh;
    logic         sticky_norm;
    logic         guard, lsb, sticky, rnd_up, implicit;
    logic [63:0]  kept;
    logic [11:0]  exp_field;
    logic [51:0]  man_field;

    begin : body
      EXP_MASK = (64'd1 << EXP_W) - 64'd1;
      MAN_MASK = (64'd1 << MAN_W) - 64'd1;
      EXP_ONES = EXP_MASK[11:0];

      // ---- unpack ----
      sa = a[EXP_W + MAN_W];
      sb = b[EXP_W + MAN_W] ^ sub;
      ea = 12'((a >> MAN_W) & EXP_MASK);
      eb = 12'((b >> MAN_W) & EXP_MASK);
      ma = 52'(a & MAN_MASK);
      mb = 52'(b & MAN_MASK);
      a_inf = (ea == EXP_ONES) && (ma == 52'd0);
      a_nan = (ea == EXP_ONES) && (ma != 52'd0);
      b_inf = (eb == EXP_ONES) && (mb == 52'd0);
      b_nan = (eb == EXP_ONES) && (mb != 52'd0);

      // ---- specials ----
      if (a_nan || b_nan)
        return (EXP_MASK << MAN_W) | (64'd1 << (MAN_W - 1));           // canonical qNaN, sign 0
      if (a_inf && b_inf) begin : ii
        if (sa == sb) return (64'(sa) << (EXP_W+MAN_W)) | (EXP_MASK << MAN_W);
        else          return (EXP_MASK << MAN_W) | (64'd1 << (MAN_W - 1));  // Inf - Inf = NaN
      end : ii
      if (a_inf) return (64'(sa) << (EXP_W+MAN_W)) | (EXP_MASK << MAN_W);
      if (b_inf) return (64'(sb) << (EXP_W+MAN_W)) | (EXP_MASK << MAN_W);

      // ---- build significands (implicit bit at IMP), effective biased exponent ----
      expA = (ea == 12'd0) ? 16'sd1 : $signed({4'b0, ea});
      expB = (eb == 12'd0) ? 16'sd1 : $signed({4'b0, eb});
      sigA = (({127'd0, (ea != 12'd0)} << MAN_W) | {76'd0, ma}) << (IMP - MAN_W);
      sigB = (({127'd0, (eb != 12'd0)} << MAN_W) | {76'd0, mb}) << (IMP - MAN_W);

      // ---- align to the larger exponent ----
      baseExp = (expA >= expB) ? expA : expB;
      shA = baseExp - expA;
      shB = baseExp - expB;
      if (shA == 16'sd0)            begin alA = sigA;        stkA = 1'b0; end
      else if (shA >= 16'sd128)     begin alA = 128'd0;      stkA = |sigA; end
      else                          begin alA = sigA >> shA; stkA = |(sigA << (128 - shA)); end
      if (shB == 16'sd0)            begin alB = sigB;        stkB = 1'b0; end
      else if (shB >= 16'sd128)     begin alB = 128'd0;      stkB = |sigB; end
      else                          begin alB = sigB >> shB; stkB = |(sigB << (128 - shB)); end
      stk_align = stkA | stkB;

      // ---- add / subtract significands ----
      eff_sub = sa ^ sb;
      if (!eff_sub) begin : do_add
        mag = alA + alB;
        sgn = sa;
      end : do_add
      else if (alA >= alB) begin : do_sub_a
        mag = alA - alB - (stk_align ? 128'd1 : 128'd0);
        sgn = sa;
      end : do_sub_a
      else begin : do_sub_b
        mag = alB - alA - (stk_align ? 128'd1 : 128'd0);
        sgn = sb;
      end : do_sub_b

      // ---- zero result: effective subtraction (cancellation) -> +0 (RNE);
      //      effective addition of two zeros keeps their common sign (-0 + -0 = -0) ----
      if (mag == 128'd0) return eff_sub ? 64'd0 : (64'(sgn) << (EXP_W + MAN_W));

      // ---- normalize: bring MSB to IMP, exponent-clamped for gradual underflow ----
      msb = 0;
      for (k = 0; k < 128; k = k + 1) if (mag[k]) msb = k;
      sticky_norm = 1'b0;
      if (msb > IMP) begin : norm_r
        rsh = 16'(msb - IMP);
        rsh_lost_mask = (128'd1 << rsh) - 128'd1;
        sticky_norm = |(mag & rsh_lost_mask);
        mag = mag >> rsh;
        baseExp = baseExp + rsh;
      end : norm_r
      else begin : norm_l
        lz = 16'(IMP - msb);
        sh_norm = (lz <= (baseExp - 16'sd1)) ? lz : (baseExp - 16'sd1);
        mag = mag << sh_norm;
        baseExp = baseExp - sh_norm;
      end : norm_l

      // ---- round to nearest even at the mantissa LSB (bit IMP-MAN_W) ----
      lsb    = mag[IMP - MAN_W];
      guard  = mag[IMP - MAN_W - 1];
      sticky = stk_align | sticky_norm | (|(mag & ((128'd1 << (IMP - MAN_W - 1)) - 128'd1)));
      rnd_up = guard & (lsb | sticky);
      kept   = 64'(mag >> (IMP - MAN_W)) & ((64'd1 << (MAN_W + 1)) - 64'd1);
      if (rnd_up) begin : do_round
        kept = kept + 64'd1;
        if (kept == (64'd1 << (MAN_W + 1))) begin : carry
          kept    = 64'd1 << MAN_W;           // 1.111..1 + 1 -> 10.000, renormalize
          baseExp = baseExp + 16'sd1;
        end : carry
      end : do_round

      // ---- pack (overflow -> Inf; subnormal -> exp field 0) ----
      if (baseExp >= $signed({4'b0, EXP_ONES}))
        return (64'(sgn) << (EXP_W+MAN_W)) | (EXP_MASK << MAN_W);   // overflow -> Inf
      implicit  = kept[MAN_W];
      man_field = 52'(kept & MAN_MASK);
      exp_field = implicit ? baseExp[11:0] : 12'd0;
      return (64'(sgn) << (EXP_W+MAN_W)) | ({52'd0, exp_field} << MAN_W) | {12'd0, man_field};
    end : body
  endfunction

  // ---- per-mode lane evaluations (shared core at three widths) ----
  logic [63:0] p1, p2, p4;
  logic [31:0] s0, s1;
  logic [15:0] h0, h1, h2, h3;

  assign p1 = fp_lane(in_data_0, in_data_1, op_sel[0], 11, 52);

  assign s0 = 32'(fp_lane({32'd0, in_data_0[31:0]},  {32'd0, in_data_1[31:0]},  op_sel[0], 8, 23));
  assign s1 = 32'(fp_lane({32'd0, in_data_0[63:32]}, {32'd0, in_data_1[63:32]}, op_sel[2], 8, 23));
  assign p2 = {s1, s0};

  assign h0 = 16'(fp_lane({48'd0, in_data_0[15:0]},  {48'd0, in_data_1[15:0]},  op_sel[0], 5, 10));
  assign h1 = 16'(fp_lane({48'd0, in_data_0[31:16]}, {48'd0, in_data_1[31:16]}, op_sel[1], 5, 10));
  assign h2 = 16'(fp_lane({48'd0, in_data_0[47:32]}, {48'd0, in_data_1[47:32]}, op_sel[2], 5, 10));
  assign h3 = 16'(fp_lane({48'd0, in_data_0[63:48]}, {48'd0, in_data_1[63:48]}, op_sel[3], 5, 10));
  assign p4 = {h3, h2, h1, h0};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // 1x fp64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_fp_add_sub_decomp
