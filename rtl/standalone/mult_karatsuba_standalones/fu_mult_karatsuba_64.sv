// Fixed-format Karatsuba 1x64 multiply-low baseline.
//
// This is the mode-free counterpart of fu_mult_decomp's 64-bit path.  The
// 64-bit product is split at 32 bits; each 32-bit diagonal product is itself
// split at 16 bits.  Only the low 64 result bits are observable.
module fu_mult_karatsuba_64 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  logic [63:0] z0, z2;
  logic [32:0] sum_a, sum_b;
  logic [65:0] sum_product;
  // Only cross_term[31:0] survives the 32-bit shift in a low-64 product.
  // verilator lint_off UNUSEDSIGNAL
  logic [65:0] cross_term;
  // verilator lint_on UNUSEDSIGNAL

  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  fu_mult_karatsuba_fixed32_full_64 u_z0 (
    .a(in_data_0[31:0]), .b(in_data_1[31:0]), .product(z0)
  );
  fu_mult_karatsuba_fixed32_full_64 u_z2 (
    .a(in_data_0[63:32]), .b(in_data_1[63:32]), .product(z2)
  );

  assign sum_a = {1'b0, in_data_0[31:0]} + {1'b0, in_data_0[63:32]};
  assign sum_b = {1'b0, in_data_1[31:0]} + {1'b0, in_data_1[63:32]};
  DW02_mult #(.A_width(33), .B_width(33)) u_sum_product (
    .A(sum_a), .B(sum_b), .TC(1'b0), .PRODUCT(sum_product)
  );
  assign cross_term = sum_product - {2'b0, z0} - {2'b0, z2};
  assign out_data = z0 + {cross_term[31:0], 32'b0};
endmodule : fu_mult_karatsuba_64

module fu_mult_karatsuba_fixed32_full_64 (
  input logic [31:0] a,
  input logic [31:0] b,
  output logic [63:0] product
);
  logic [31:0] z0, z2;
  logic [16:0] sum_a, sum_b;
  logic [33:0] sum_product, cross_term;

  DW02_mult #(.A_width(16), .B_width(16)) u_z0 (
    .A(a[15:0]), .B(b[15:0]), .TC(1'b0), .PRODUCT(z0)
  );
  DW02_mult #(.A_width(16), .B_width(16)) u_z2 (
    .A(a[31:16]), .B(b[31:16]), .TC(1'b0), .PRODUCT(z2)
  );
  assign sum_a = {1'b0, a[15:0]} + {1'b0, a[31:16]};
  assign sum_b = {1'b0, b[15:0]} + {1'b0, b[31:16]};
  DW02_mult #(.A_width(17), .B_width(17)) u_sum_product (
    .A(sum_a), .B(sum_b), .TC(1'b0), .PRODUCT(sum_product)
  );
  assign cross_term = sum_product - {2'b0, z0} - {2'b0, z2};
  assign product = {32'b0, z0}
                 + ({30'b0, cross_term} << 16)
                 + ({32'b0, z2} << 32);
endmodule : fu_mult_karatsuba_fixed32_full_64
