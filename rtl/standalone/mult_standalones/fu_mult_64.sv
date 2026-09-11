// fu_mult_64.sv -- Standalone fixed-width 1x64 multiply-low baseline.
// The 128-bit product is truncated to the low 64 bits, matching the integer
// multiply-low semantics of the decomposable multiplier. There is no mode or
// cross-lane interaction. DW02_mult is the synthesis/simulation primitive.
module fu_mult_64 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;
  // verilator lint_off UNUSEDSIGNAL
  logic [127:0] product;
  // verilator lint_on UNUSEDSIGNAL
  DW02_mult #(.A_width(64), .B_width(64)) u_mult (
    .A(in_data_0), .B(in_data_1), .TC(1'b0), .PRODUCT(product)
  );
  assign out_data = product[63:0];
endmodule
