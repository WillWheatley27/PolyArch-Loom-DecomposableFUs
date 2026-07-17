// fu_int_to_fp_decomp.sv -- Decomposable (subword-SIMD) FU for integer->float conversion.
// share group 8 (arith.sitofp / arith.uitofp), decomposed across lanes.
//
//   mode = 2'b00 -> int64 -> fp64      mode = 2'b01 -> 2x (int32 -> fp32)
//   mode = 2'b10 -> 4x (int16 -> fp16) mode = 2'b11 -> reserved -> int64->fp64
//   is_signed : 1 = sitofp (two's-complement), 0 = uitofp. Global.
//
// Unary op. Per lane: sign/magnitude -> leading-one position -> left-justify -> RNE round ->
// pack; round-overflow -> +Inf. One shared LZC + shifter + rounder reused at all widths (only
// exponent bias / mantissa width / packing differ). Combinational, latency 0. Proves functional
// decomposition; a physically-shared segmented converter is the synthesis/area objective.
module fu_int_to_fp_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic        is_signed,

  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,

  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready
);

  // Handshake: 1-input (unary), combinational, lossless backpressure.
  assign out_valid  = in_valid_0;
  assign in_ready_0 = out_ready & out_valid;

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // Shared int->float conversion for one lane (W = 1+EXP_W+MAN_W bits).
  function automatic logic [63:0] i2f_lane(input logic [63:0] x, input logic is_signed_i,
                                           input int EXP_W, input int MAN_W);
    localparam int IMP = 120;
    int W;
    logic [63:0]  W_MASK, xw, mag, kept;
    logic [11:0]  EXP_ONES, exp_field;
    logic [51:0]  mant_field;
    logic [127:0] sig;
    logic [7:0]   p;
    int           k;
    logic signed [15:0] BIAS, bexp;
    logic         sign, lsb, guard, sticky, rnd_up;
    begin : body
      W        = 1 + EXP_W + MAN_W;
      BIAS     = 16'((1 << (EXP_W - 1)) - 1);
      EXP_ONES = 12'((1 << EXP_W) - 1);
      W_MASK   = (W == 64) ? {64{1'b1}} : ((64'd1 << W) - 64'd1);

      xw   = x & W_MASK;
      sign = is_signed_i & xw[W - 1];
      mag  = sign ? ((~xw + 64'd1) & W_MASK) : xw;
      if (mag == 64'd0) return 64'd0;                  // integer 0 -> +0.0

      // leading-one position
      p = 8'd0;
      for (k = 0; k < 64; k = k + 1) if (mag[k]) p = 8'(k);

      // left-justify so the MSB sits at bit IMP (exact; no bits lost)
      sig  = 128'(mag) << (IMP - int'(p));
      bexp = $signed({8'd0, p}) + BIAS;

      // round to nearest even at the mantissa LSB (bit IMP-MAN_W)
      lsb    = sig[IMP - MAN_W];
      guard  = sig[IMP - MAN_W - 1];
      sticky = |(sig & ((128'd1 << (IMP - MAN_W - 1)) - 128'd1));
      kept   = 64'(sig >> (IMP - MAN_W)) & ((64'd1 << (MAN_W + 1)) - 64'd1);
      rnd_up = guard & (lsb | sticky);
      if (rnd_up) begin
        kept = kept + 64'd1;
        if (kept == (64'd1 << (MAN_W + 1))) begin
          kept = 64'd1 << MAN_W;
          bexp = bexp + 16'sd1;
        end
      end

      if (bexp >= $signed({4'b0, EXP_ONES}))
        return (64'(sign) << (EXP_W+MAN_W)) | ({52'd0, EXP_ONES} << MAN_W);   // round-overflow -> Inf
      exp_field  = bexp[11:0];
      mant_field = 52'(kept & ((64'd1 << MAN_W) - 64'd1));
      return (64'(sign) << (EXP_W+MAN_W)) | ({52'd0, exp_field} << MAN_W) | {12'd0, mant_field};
    end : body
  endfunction

  // ---- Per-mode lane evaluations (shared converter at three widths) ----
  logic [63:0] p1, p2, p4;
  logic [31:0] s0, s1;
  logic [15:0] h0, h1, h2, h3;

  assign p1 = i2f_lane(in_data_0, is_signed, 11, 52);

  assign s0 = 32'(i2f_lane({32'd0, in_data_0[31:0]},  is_signed, 8, 23));
  assign s1 = 32'(i2f_lane({32'd0, in_data_0[63:32]}, is_signed, 8, 23));
  assign p2 = {s1, s0};

  assign h0 = 16'(i2f_lane({48'd0, in_data_0[15:0]},  is_signed, 5, 10));
  assign h1 = 16'(i2f_lane({48'd0, in_data_0[31:16]}, is_signed, 5, 10));
  assign h2 = 16'(i2f_lane({48'd0, in_data_0[47:32]}, is_signed, 5, 10));
  assign h3 = 16'(i2f_lane({48'd0, in_data_0[63:48]}, is_signed, 5, 10));
  assign p4 = {h3, h2, h1, h0};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // int64->fp64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_int_to_fp_decomp
