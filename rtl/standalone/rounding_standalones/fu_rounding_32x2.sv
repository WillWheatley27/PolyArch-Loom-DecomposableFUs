// fu_rounding_32x2.sv -- Standalone fixed-width 2xFP32 round-to-integral baseline.
//
// Two independent IEEE binary32 lanes packed in 64 bits. round_mode is global:
//   000 floor, 001 ceil, 010 trunc, 011 nearest/ties-away,
//   100 nearest/ties-even, reserved values -> trunc.
// NaN, infinity, signed zero, and already-integral values pass through unchanged.
// There is no runtime format mode and no cross-lane carry.
//
// DesignWare has no block for these five FP round-to-integral operations.
// DW01_satrnd and DW_norm_rnd have different semantics, so fixed-format
// guard/sticky/mask/increment logic is used here.
// Combinational, latency 0, unary valid/ready handshake.
module fu_rounding_32x2 (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [2:0]  round_mode,
  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,
  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready
);
  assign out_valid  = in_valid_0;
  assign in_ready_0 = out_ready & out_valid;

  function automatic logic round_inc(input logic [2:0] rm, input logic sign,
                                     input logic guard, input logic sticky,
                                     input logic int_lsb);
    case (rm)
      3'b000:  round_inc = sign  & (guard | sticky);
      3'b001:  round_inc = ~sign & (guard | sticky);
      3'b011:  round_inc = guard;
      3'b100:  round_inc = guard & (sticky | int_lsb);
      default: round_inc = 1'b0;
    endcase
  endfunction

  function automatic logic [31:0] round_fp32(input logic [31:0] x,
                                              input logic [2:0] rm);
    logic sign, guard, sticky, int_lsb, inc;
    logic [7:0] exp;
    logic [22:0] mant;
    logic [23:0] sig;
    logic [31:0] frac_mask, rounded;
    logic signed [10:0] unbiased_exp;
    logic [5:0] frac_bits;
    begin
      sign = x[31]; exp = x[30:23]; mant = x[22:0];
      if ((exp == 8'hFF) || ((exp == 8'd0) && (mant == 23'd0))) begin
        round_fp32 = x;
      end else begin
        unbiased_exp = (exp == 8'd0) ? -11'sd126
                                      : $signed({3'b000, exp}) - 11'sd127;
        if (unbiased_exp >= 11'sd23) begin
          round_fp32 = x;
        end else if (unbiased_exp >= 11'sd0) begin
          sig = {1'b1, mant};
          frac_bits = 6'(11'sd23 - unbiased_exp);
          frac_mask = (32'd1 << frac_bits) - 32'd1;
          guard = |(sig & (24'd1 << (frac_bits - 6'd1)));
          sticky = |(sig & ((24'd1 << (frac_bits - 6'd1)) - 24'd1));
          int_lsb = |(sig & (24'd1 << frac_bits));
          inc = round_inc(rm, sign, guard, sticky, int_lsb);
          rounded = x & ~frac_mask;
          round_fp32 = rounded + (inc ? (32'd1 << frac_bits) : 32'd0);
        end else begin
          guard = (unbiased_exp == -11'sd1);
          sticky = (unbiased_exp == -11'sd1) ? |mant : 1'b1;
          inc = round_inc(rm, sign, guard, sticky, 1'b0);
          round_fp32 = {sign, inc ? 8'd127 : 8'd0, 23'd0};
        end
      end
    end
  endfunction

  assign out_data[31:0]  = round_fp32(in_data_0[31:0], round_mode);
  assign out_data[63:32] = round_fp32(in_data_0[63:32], round_mode);
endmodule : fu_rounding_32x2
