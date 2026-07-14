// fu_mult_decomp.sv -- Decomposable (subword-SIMD) FU for integer multiply.
// op: arith.muli, low-half (truncated) product, decomposed across subword lanes.
//
//   mode = 2'b00 -> 1x64 : one 64-bit lane
//   mode = 2'b01 -> 2x32 : two independent 32-bit lanes
//   mode = 2'b10 -> 4x16 : four independent 16-bit lanes
//   mode = 2'b11 -> reserved, behaves as 1x64
//
// Each lane returns the LOW w bits of its w x w product (multiply-low, like PMULLW).
// This is sign-agnostic: the low w bits of a two's-complement product are identical
// for signed and unsigned operands, so no signed/unsigned op_sel is needed.
//
// One shared block-product array (16-bit x 16-bit -> 32-bit) is reused across modes;
// only the summation/alignment network and the final 64-bit output mux change per mode.
// Combinational, intrinsic latency 0.
module fu_mult_decomp (
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

  // ---- Split operands into four 16-bit blocks (little-endian by lane) ----
  logic [15:0] a0, a1, a2, a3;
  logic [15:0] b0, b1, b2, b3;
  assign {a3, a2, a1, a0} = in_data_0;
  assign {b3, b2, b1, b0} = in_data_1;

  // ---- Shared block-product array: pp_ij = a_i * b_j (16x16 -> 32-bit unsigned).
  //      This is the 64x64 partial-product array at 16-bit granularity. A low-half
  //      decomposable multiply needs 14 of the 16 products; the corner products
  //      pp13, pp31 (weight 2^64) influence no lane's low bits and are not built.
  //      pp33 is only ever needed at 16-bit precision (lane 3 of 4x16), so it is a
  //      16-bit product; all others feed the wider 1x64 / 2x32 sums at 32-bit.
  logic [31:0] pp00, pp01, pp02, pp03;
  logic [31:0] pp10, pp11, pp12;
  logic [31:0] pp20, pp21, pp22, pp23;
  logic [31:0] pp30, pp32;
  logic [15:0] pp33;

  assign pp00 = {16'b0, a0} * {16'b0, b0};
  assign pp01 = {16'b0, a0} * {16'b0, b1};
  assign pp02 = {16'b0, a0} * {16'b0, b2};
  assign pp03 = {16'b0, a0} * {16'b0, b3};
  assign pp10 = {16'b0, a1} * {16'b0, b0};
  assign pp11 = {16'b0, a1} * {16'b0, b1};
  assign pp12 = {16'b0, a1} * {16'b0, b2};
  assign pp20 = {16'b0, a2} * {16'b0, b0};
  assign pp21 = {16'b0, a2} * {16'b0, b1};
  assign pp22 = {16'b0, a2} * {16'b0, b2};
  assign pp23 = {16'b0, a2} * {16'b0, b3};
  assign pp30 = {16'b0, a3} * {16'b0, b0};
  assign pp32 = {16'b0, a3} * {16'b0, b2};
  assign pp33 = a3 * b3;   // 16-bit context -> low 16 of a3*b3 (lane 3 only)

  // ---- 1x64: low 64 of the full product (sum mod 2^64) ----
  logic [63:0] p1;
  assign p1 = {32'b0, pp00}
            + (({32'b0, pp01} + {32'b0, pp10}) << 16)
            + (({32'b0, pp02} + {32'b0, pp11} + {32'b0, pp20}) << 32)
            + (({32'b0, pp03} + {32'b0, pp12} + {32'b0, pp21} + {32'b0, pp30}) << 48);

  // ---- 2x32: per-lane low 32 (sum mod 2^32; higher blocks drop out) ----
  logic [31:0] lane0_32, lane1_32;
  assign lane0_32 = pp00 + ((pp01 + pp10) << 16);   // a[31:0]  * b[31:0]
  assign lane1_32 = pp22 + ((pp23 + pp32) << 16);   // a[63:32] * b[63:32]
  logic [63:0] p2;
  assign p2 = {lane1_32, lane0_32};

  // ---- 4x16: per-lane low 16 (diagonal block products) ----
  logic [63:0] p4;
  assign p4 = {pp33, pp22[15:0], pp11[15:0], pp00[15:0]};

  // ---- Mode-select output ----
  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // 1x64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_mult_decomp
