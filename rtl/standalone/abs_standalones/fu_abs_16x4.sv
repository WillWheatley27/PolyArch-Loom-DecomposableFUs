// fu_abs_16x4.sv -- Standalone fixed-width 4x16 absolute-value baseline.
//
// Four independent 16-bit lanes are packed in a 64-bit word. is_float selects
// IEEE FP16 abs (clear each lane sign bit) or integer two's-complement abs
// (negative lanes are inverted and incremented; INT_MIN wraps to itself).
// There is no runtime precision mode and no cross-lane carry. DW01_add is used
// for each lane-local invert-plus-one operation.
// Combinational, latency 0, unary valid/ready handshake.
module fu_abs_16x4 (
  // verilator lint_off UNUSEDSIGNAL
  input logic        clk,
  input logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic        is_float,
  input logic [63:0] in_data_0,
  input logic        in_valid_0,
  output logic       in_ready_0,
  output logic [63:0] out_data,
  output logic        out_valid,
  input logic        out_ready
);
  assign out_valid  = in_valid_0;
  assign in_ready_0 = out_ready & out_valid;

  logic [15:0] int_result [0:3];
  logic        carry_unused [0:3];
  for (genvar i = 0; i < 4; i++) begin : lane
    logic [15:0] value;
    logic [15:0] operand;
    assign value   = in_data_0[i*16 +: 16];
    assign operand = value ^ {16{value[15]}};
    DW01_add #(.width(16)) u_abs_add (
      .A(operand), .B(16'd0), .CI(value[15]),
      .SUM(int_result[i]), .CO(carry_unused[i])
    );
    assign out_data[i*16 +: 16] = is_float
      ? {1'b0, value[14:0]} : int_result[i];
  end
endmodule : fu_abs_16x4
