// fu_mult_dx.sv -- Decomposable (dual, 64/32) FU for integer multiply-low, hand-written.
// arith.muli (singleton). Decomposable at ONE boundary (bit 32):
//
//   mode = 2'b00 -> 1x64 : low 64 bits of a*b
//   mode = 2'b01 -> 2x32 : low 32 bits of each 32x32
//   mode = 2'b10/11 -> reserved, behaves as 1x64
//
// Multiply-low (like PMULLW/PMULLD) is sign-agnostic -> no op_sel. Split operands into 32-bit
// halves a={a1,a0}, b={b1,b0}; with Pij = ai*bj and mod 2^64 (the a1*b1*2^64 term vanishes):
//   low64(a*b) = P00 + (P10_lo + P01_lo)*2^32
// so 1x64 uses P00(full)+P01_lo+P10_lo, 2x32 uses P00_lo(lane0)+P11_lo(lane1). Only the LOW half
// of the partial-product array is built (why this beats a full-product block for multiply-low).
// The vendor DesignWare duplex multiplier was evaluated and dropped: it emits the full 128-bit
// product (~2x area, slower) with no low-only mode. Combinational, latency 0.
module fu_mult_dx (
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
  logic dplx;
  assign dplx = (mode == M_2X32);

  // 32-bit halves (little-endian: lane 0 = low).
  logic [31:0] a0, a1, b0, b1;
  assign {a1, a0} = in_data_0;
  assign {b1, b0} = in_data_1;

  // Block products: P00 full 64b; cross/high terms low 32b only.
  logic [63:0] p00;
  logic [31:0] p01, p10, p11;
  assign p00 = a0 * b0;          // 64-bit context -> full product
  assign p01 = 32'(a0 * b1);     // low 32
  assign p10 = 32'(a1 * b0);     // low 32
  assign p11 = 32'(a1 * b1);     // low 32

  // Low word is P00[31:0] in both modes; high word is mode-selected.
  logic [31:0] hi_1x64, hi_out;
  assign hi_1x64 = p00[63:32] + p10 + p01;   // 1x64 multiply-low high word (carries >2^64 dropped)
  assign hi_out  = dplx ? p11 : hi_1x64;
  assign out_data = {hi_out, p00[31:0]};

endmodule : fu_mult_dx
