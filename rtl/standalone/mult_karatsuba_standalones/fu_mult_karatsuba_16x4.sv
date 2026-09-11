// Fixed-format packed 4x16 multiply-low Karatsuba leaf bank.
//
// Sixteen bits is the terminal multiplication leaf in both this fixed bank
// and fu_mult_decomp.  No Karatsuba recombination is required in 4x16 mode;
// the four independent low-16 leaf results are exposed directly.
module fu_mult_karatsuba_16x4 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  logic [31:0] product [0:3];

  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  for (genvar lane = 0; lane < 4; lane++) begin : g_lane
    DW02_mult #(.A_width(16), .B_width(16)) u_leaf (
      .A(in_data_0[lane*16 +: 16]),
      .B(in_data_1[lane*16 +: 16]),
      .TC(1'b0),
      .PRODUCT(product[lane])
    );
    assign out_data[lane*16 +: 16] = product[lane][15:0];
  end
endmodule : fu_mult_karatsuba_16x4
