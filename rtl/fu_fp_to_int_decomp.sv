// fu_fp_to_int_decomp.sv -- Decomposable (subword-SIMD) FU for float->integer conversion.
// share group 9 (arith.fptosi / arith.fptoui), decomposed across lanes.
//
//   mode = 2'b00 -> fp64 -> int64      mode = 2'b01 -> 2x (fp32 -> int32)
//   mode = 2'b10 -> 4x (fp16 -> int16) mode = 2'b11 -> reserved -> fp64->int64
//   is_signed : 1 = fptosi, 0 = fptoui. Global.
//
// Unary op. Saturating, round-toward-zero (defined HW behavior; arith.fptosi/fptoui are UB on
// overflow): NaN -> 0; +-Inf -> saturate; |x|<1 -> 0; out-of-range -> clamp to int min/max.
// One shared shifter + saturation logic reused at all widths (bias / significand width / integer
// range differ). Combinational, latency 0. Proves functional decomposition; a physically-shared
// segmented converter is the synthesis/area objective.
module fu_fp_to_int_decomp (
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

  // Shared float->int conversion for one lane (W = 1+EXP_W+MAN_W bits).
  function automatic logic [63:0] f2i_lane(input logic [63:0] x, input logic is_signed_i,
                                           input int EXP_W, input int MAN_W);
    int W;
    logic [63:0]  EXP_MASK, MAN_MASK, W_MASK, sig, M64, res, IMIN, IMAX;
    logic [11:0]  EXP_ONES, exp;
    logic [51:0]  mant;
    logic         s, isnan_, isinf_, big;
    logic signed [15:0] BIAS, E, MW;
    begin : body
      W        = 1 + EXP_W + MAN_W;
      EXP_MASK = (64'd1 << EXP_W) - 64'd1;
      MAN_MASK = (64'd1 << MAN_W) - 64'd1;
      EXP_ONES = 12'((1 << EXP_W) - 1);
      BIAS     = 16'((1 << (EXP_W - 1)) - 1);
      MW       = 16'(MAN_W);
      W_MASK   = (W == 64) ? {64{1'b1}} : ((64'd1 << W) - 64'd1);
      IMIN     = 64'd1 << (W - 1);        // signed min pattern = 2^(W-1)
      IMAX     = IMIN - 64'd1;            // signed max = 2^(W-1)-1

      s      = x[EXP_W + MAN_W];
      exp    = 12'((x >> MAN_W) & EXP_MASK);
      mant   = 52'(x & MAN_MASK);
      isnan_ = (exp == EXP_ONES) && (mant != 52'd0);
      isinf_ = (exp == EXP_ONES) && (mant == 52'd0);

      if (isnan_) return 64'd0;
      if (isinf_) begin
        if (is_signed_i) return s ? IMIN : IMAX;
        else             return s ? 64'd0 : W_MASK;
      end

      sig = ((exp != 12'd0) ? (64'd1 << MAN_W) : 64'd0) | {12'd0, mant};
      E   = (exp == 12'd0) ? (16'sd1 - BIAS) : ($signed({4'b0, exp}) - BIAS);

      if (E < 16'sd0) return 64'd0;       // |x| < 1

      big = (E >= 16'sd64);
      M64 = big ? 64'd0 : ((E <= MW) ? (sig >> (MW - E)) : (sig << (E - MW)));

      if (is_signed_i) begin
        if (s) res = (big || (M64 >  IMIN)) ? IMIN : ((~M64 + 64'd1) & W_MASK);  // negative
        else   res = (big || (M64 >= IMIN)) ? IMAX : (M64 & W_MASK);              // positive
      end
      else begin
        if (s) res = 64'd0;                                                        // negative -> 0
        else   res = (big || ((W < 64) && (M64 >= (64'd1 << W)))) ? W_MASK : (M64 & W_MASK);
      end
      return res;
    end : body
  endfunction

  // ---- Per-mode lane evaluations (shared converter at three widths) ----
  logic [63:0] p1, p2, p4;
  logic [31:0] s0, s1;
  logic [15:0] h0, h1, h2, h3;

  assign p1 = f2i_lane(in_data_0, is_signed, 11, 52);

  assign s0 = 32'(f2i_lane({32'd0, in_data_0[31:0]},  is_signed, 8, 23));
  assign s1 = 32'(f2i_lane({32'd0, in_data_0[63:32]}, is_signed, 8, 23));
  assign p2 = {s1, s0};

  assign h0 = 16'(f2i_lane({48'd0, in_data_0[15:0]},  is_signed, 5, 10));
  assign h1 = 16'(f2i_lane({48'd0, in_data_0[31:16]}, is_signed, 5, 10));
  assign h2 = 16'(f2i_lane({48'd0, in_data_0[47:32]}, is_signed, 5, 10));
  assign h3 = 16'(f2i_lane({48'd0, in_data_0[63:48]}, is_signed, 5, 10));
  assign p4 = {h3, h2, h1, h0};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // fp64->int64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_fp_to_int_decomp
