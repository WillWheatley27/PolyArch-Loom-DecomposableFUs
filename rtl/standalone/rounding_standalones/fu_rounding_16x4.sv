// fu_rounding_16x4.sv -- Standalone fixed-width 4xFP16 round-to-integral baseline.
//
// Four independent IEEE binary16 lanes packed in 64 bits. round_mode is global:
//   000 floor, 001 ceil, 010 trunc, 011 nearest/ties-away,
//   100 nearest/ties-even, reserved values -> trunc.
// NaN, infinity, signed zero, and already-integral values pass through unchanged.
// There is no runtime format mode and no cross-lane carry.
//
// DesignWare has no block for these five FP round-to-integral operations.
// DW01_satrnd and DW_norm_rnd have different semantics, so fixed-format
// guard/sticky/mask/increment logic is used here.
// Combinational, latency 0, unary valid/ready handshake.
module fu_rounding_16x4 (
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

  function automatic logic [15:0] round_fp16(input logic [15:0] x,
                                              input logic [2:0] rm);
    logic sign, guard, sticky, int_lsb, inc;
    logic [4:0] exp;
    logic [9:0] mant;
    logic [10:0] sig;
    logic [15:0] frac_mask, rounded;
    logic signed [6:0] unbiased_exp;
    logic [4:0] frac_bits;
    begin
      sign = x[15]; exp = x[14:10]; mant = x[9:0];
      if ((exp == 5'h1F) || ((exp == 5'd0) && (mant == 10'd0))) begin
        round_fp16 = x;
      end else begin
        unbiased_exp = (exp == 5'd0) ? -7'sd14
                                      : $signed({2'b00, exp}) - 7'sd15;
        if (unbiased_exp >= 7'sd10) begin
          round_fp16 = x;
        end else if (unbiased_exp >= 7'sd0) begin
          sig = {1'b1, mant};
          frac_bits = 5'(7'sd10 - unbiased_exp);
          frac_mask = (16'd1 << frac_bits) - 16'd1;
          guard = |(sig & (11'd1 << (frac_bits - 5'd1)));
          sticky = |(sig & ((11'd1 << (frac_bits - 5'd1)) - 11'd1));
          int_lsb = |(sig & (11'd1 << frac_bits));
          inc = round_inc(rm, sign, guard, sticky, int_lsb);
          rounded = x & ~frac_mask;
          round_fp16 = rounded + (inc ? (16'd1 << frac_bits) : 16'd0);
        end else begin
          guard = (unbiased_exp == -7'sd1);
          sticky = (unbiased_exp == -7'sd1) ? |mant : 1'b1;
          inc = round_inc(rm, sign, guard, sticky, 1'b0);
          round_fp16 = {sign, inc ? 5'd15 : 5'd0, 10'd0};
        end
      end
    end
  endfunction

  for (genvar i = 0; i < 4; i++) begin : lane
    assign out_data[i*16 +: 16] = round_fp16(in_data_0[i*16 +: 16], round_mode);
  end
endmodule : fu_rounding_16x4
