// fu_rounding_decomp.sv -- Decomposable (subword-SIMD) FU for FP round-to-integral.
// share group 17 (math.floor/ceil/trunc/round/roundeven), decomposed across packed-FP lanes.
//
//   mode = 2'b00 -> 1x fp64  (1/11/52)   mode = 2'b01 -> 2x fp32 (1/8/23)
//   mode = 2'b10 -> 4x fp16  (1/5/10)    mode = 2'b11 -> reserved -> 1x fp64
//   round_mode (global): 000 floor(->-inf), 001 ceil(->+inf), 010 trunc(->0),
//                        011 round(nearest, ties away), 100 roundeven(nearest, ties even),
//                        other -> trunc.
//
// Unary op (single operand). Per lane: clear the fractional bits and conditionally increment
// the integer part per mode/sign/guard/sticky, then renormalize. NaN/Inf/+-0/already-integral
// returned unchanged; sign preserved. Combinational, latency 0. Proves functional decomposition;
// a physically-shared segmented rounding network is the synthesis/area objective.
module fu_rounding_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic [2:0]  round_mode,

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

  // Increment decision: should the integer-part magnitude round up by 1?
  function automatic logic round_inc(input logic [2:0] rm, input logic s,
                                     input logic guard, input logic sticky, input logic int_lsb);
    case (rm)
      3'b000:  round_inc = s  & (guard | sticky);       // floor  (-inf): neg + frac -> away
      3'b001:  round_inc = ~s & (guard | sticky);       // ceil   (+inf): pos + frac -> away
      3'b011:  round_inc = guard;                        // round: nearest, ties away
      3'b100:  round_inc = guard & (sticky | int_lsb);   // roundeven: nearest, ties to even
      default: round_inc = 1'b0;                          // trunc (010) and reserved
    endcase
  endfunction

  // Shared round-to-integral for one lane of the given format.
  function automatic logic [63:0] round_lane(input logic [63:0] x, input logic [2:0] rm,
                                             input int EXP_W, input int MAN_W);
    logic [63:0] EXP_MASK, MAN_MASK, sig, int_sig, frac_mask, new_sig;
    logic [11:0] EXP_ONES, exp, exp_res;
    logic [51:0] mant, mant_res;
    logic signed [15:0] BIAS, E, F;
    logic s, guard, sticky, int_lsb, inc;
    begin : body
      EXP_MASK = (64'd1 << EXP_W) - 64'd1;
      MAN_MASK = (64'd1 << MAN_W) - 64'd1;
      EXP_ONES = EXP_MASK[11:0];
      BIAS     = 16'((1 << (EXP_W - 1)) - 1);

      s    = x[EXP_W + MAN_W];
      exp  = 12'((x >> MAN_W) & EXP_MASK);
      mant = 52'(x & MAN_MASK);

      if (exp == EXP_ONES)                 return x;   // NaN / Inf -> unchanged
      if (exp == 12'd0 && mant == 52'd0)   return x;   // +-0 -> unchanged

      sig = ((exp != 12'd0) ? (64'd1 << MAN_W) : 64'd0) | {12'd0, mant};
      E   = (exp == 12'd0) ? (16'sd1 - BIAS) : ($signed({4'b0, exp}) - BIAS);

      if (E >= 16'(MAN_W))                 return x;   // already integral

      F = 16'(MAN_W) - E;                              // fractional bits, >= 1
      if (E >= 16'sd0) begin                           // 0 <= E < MAN_W
        frac_mask = (64'd1 << F) - 64'd1;
        guard   = |(sig & (64'd1 << (F - 16'sd1)));
        sticky  = |(sig & ((64'd1 << (F - 16'sd1)) - 64'd1));
        int_lsb = |(sig & (64'd1 << F));
        int_sig = sig & ~frac_mask;
        inc     = round_inc(rm, s, guard, sticky, int_lsb);
        new_sig = int_sig + (inc ? (64'd1 << F) : 64'd0);
        if (|(new_sig & (64'd1 << (MAN_W + 1)))) begin
          exp_res  = exp + 12'd1;                       // 1.11..1 + 1 -> 10.00..0
          mant_res = 52'd0;
        end
        else begin
          exp_res  = exp;
          mant_res = 52'(new_sig & MAN_MASK);
        end
        return (64'(s) << (EXP_W+MAN_W)) | ({52'd0, exp_res} << MAN_W) | {12'd0, mant_res};
      end
      else begin                                       // E < 0 : |x| < 1
        if (E == -16'sd1) begin
          guard = 1'b1;                                 // 0.5 bit = implicit
          sticky = |mant;
        end
        else begin
          guard = 1'b0;                                 // |x| < 0.5
          sticky = 1'b1;                                // nonzero
        end
        inc = round_inc(rm, s, guard, sticky, 1'b0);    // integer part 0 (even)
        if (inc) return (64'(s) << (EXP_W+MAN_W)) | ({52'd0, BIAS[11:0]} << MAN_W);  // +-1.0
        else     return (64'(s) << (EXP_W+MAN_W));                                   // +-0
      end
    end : body
  endfunction

  // ---- Per-mode lane evaluations (shared rounding core at three widths) ----
  logic [63:0] p1, p2, p4;
  logic [31:0] s0, s1;
  logic [15:0] h0, h1, h2, h3;

  assign p1 = round_lane(in_data_0, round_mode, 11, 52);

  assign s0 = 32'(round_lane({32'd0, in_data_0[31:0]},  round_mode, 8, 23));
  assign s1 = 32'(round_lane({32'd0, in_data_0[63:32]}, round_mode, 8, 23));
  assign p2 = {s1, s0};

  assign h0 = 16'(round_lane({48'd0, in_data_0[15:0]},  round_mode, 5, 10));
  assign h1 = 16'(round_lane({48'd0, in_data_0[31:16]}, round_mode, 5, 10));
  assign h2 = 16'(round_lane({48'd0, in_data_0[47:32]}, round_mode, 5, 10));
  assign h3 = 16'(round_lane({48'd0, in_data_0[63:48]}, round_mode, 5, 10));
  assign p4 = {h3, h2, h1, h0};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // 1x fp64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_rounding_decomp
