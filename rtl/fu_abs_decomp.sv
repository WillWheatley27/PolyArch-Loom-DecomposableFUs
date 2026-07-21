// fu_abs_decomp.sv -- Decomposable (subword-SIMD) FU for absolute value.
// ops: math.absf (FP) + math.absi (integer), decomposed across lanes; is_float selects.
//
//   mode = 2'b00 -> 1x64 : one 64-bit lane
//   mode = 2'b01 -> 2x32 : two independent 32-bit lanes
//   mode = 2'b10 -> 4x16 : four independent 16-bit lanes
//   mode = 2'b11 -> reserved, behaves as 1x64
//   is_float : 1 = absf (clear each lane's sign bit; IEEE abs), 0 = absi (per-lane
//              conditional two's-complement negate; INT_MIN wraps to itself).
//
// Unary op. absf is a per-lane sign-bit clear; absi negates negative lanes with carries kept
// within each lane (no cross-lane spill). Combinational, latency 0.
module fu_abs_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic        is_float,

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

  // ---- Per-lane conditional two's-complement negate (absi), for each lane width ----
  logic [15:0] a0, a1, a2, a3, n0, n1, n2, n3;
  assign {a3, a2, a1, a0} = in_data_0;
  assign n0 = a0[15] ? (~a0 + 16'd1) : a0;
  assign n1 = a1[15] ? (~a1 + 16'd1) : a1;
  assign n2 = a2[15] ? (~a2 + 16'd1) : a2;
  assign n3 = a3[15] ? (~a3 + 16'd1) : a3;

  logic [31:0] w0, w1, p0, p1;
  assign w0 = in_data_0[31:0];
  assign w1 = in_data_0[63:32];
  assign p0 = w0[31] ? (~w0 + 32'd1) : w0;
  assign p1 = w1[31] ? (~w1 + 32'd1) : w1;

  logic [63:0] q;
  assign q = in_data_0[63] ? (~in_data_0 + 64'd1) : in_data_0;

  // ---- Sign-bit mask (absf) + absi result, selected by mode ----
  logic [63:0] sign_mask, absi_res;
  always_comb begin : sel
    case (mode)
      M_2X32: begin : d2x32
        sign_mask = 64'h8000_0000_8000_0000;
        absi_res  = {p1, p0};
      end : d2x32
      M_4X16: begin : d4x16
        sign_mask = 64'h8000_8000_8000_8000;
        absi_res  = {n3, n2, n1, n0};
      end : d4x16
      default: begin : d1x64
        sign_mask = 64'h8000_0000_0000_0000;
        absi_res  = q;
      end : d1x64
    endcase
  end : sel

  assign out_data = is_float ? (in_data_0 & ~sign_mask) : absi_res;

endmodule : fu_abs_decomp
