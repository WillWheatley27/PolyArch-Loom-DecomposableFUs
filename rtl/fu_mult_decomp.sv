// fu_mult_decomp.sv -- Decomposable integer multiply-low using Karatsuba.
//
//   mode = 2'b00 -> 1x64 : low 64 bits of one product
//   mode = 2'b01 -> 2x32 : low 32 bits of two independent products
//   mode = 2'b10 -> 4x16 : low 16 bits of four independent products
//   mode = 2'b11 -> reserved, behaves as 1x64
//
// The low product is sign-agnostic, so operands are treated as unsigned.
// Two shared 32x32 Karatsuba blocks form the low and high halves of the 64-bit
// operation. Their diagonal 16x16 terms are also reused by 4x16 mode. The
// 64-bit mode uses one additional Karatsuba cross product on the summed halves:
//   A*B = z0 + ((z1-z0-z2) << 32) + (z2 << 64)
// where z0=Alo*Blo and z2=Ahi*Bhi. The z2 term is dropped for multiply-low.
// Combinational, intrinsic latency 0.
module fu_mult_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input logic        clk,
  input logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input logic [1:0]  mode,
  input logic [63:0] in_data_0,
  input logic        in_valid_0,
  output logic       in_ready_0,
  input logic [63:0] in_data_1,
  input logic        in_valid_1,
  output logic       in_ready_1,
  output logic [63:0] out_data,
  output logic        out_valid,
  input logic        out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  logic [31:0] a_lo, a_hi, b_lo, b_hi;
  assign a_lo = in_data_0[31:0];
  assign a_hi = in_data_0[63:32];
  assign b_lo = in_data_1[31:0];
  assign b_hi = in_data_1[63:32];

  // Shared Karatsuba halves. In addition to the full 32x32 products, expose
  // their diagonal 16x16 terms for the 4x16 low products.
  logic [63:0] z0, z2;
  logic [15:0] z0_lo16, z0_hi16, z2_lo16, z2_hi16;
  fu_mult_karatsuba_32_full u_kar_lo (
    .a(a_lo), .b(b_lo), .product(z0),
    .low_diag(z0_lo16), .high_diag(z0_hi16)
  );
  fu_mult_karatsuba_32_full u_kar_hi (
    .a(a_hi), .b(b_hi), .product(z2),
    .low_diag(z2_lo16), .high_diag(z2_hi16)
  );

  // 64-bit Karatsuba cross term. The 33-bit sums need a 33x33 product;
  // only its low 32 bits affect the low 64-bit result after << 32.
  logic [32:0] sum_a, sum_b;
  logic [65:0] cross_product;
  // Only the low 32 cross bits survive the <<32 low-product truncation.
  // verilator lint_off UNUSEDSIGNAL
  logic [65:0] cross_term;
  // verilator lint_on UNUSEDSIGNAL
  assign sum_a = {1'b0, a_lo} + {1'b0, a_hi};
  assign sum_b = {1'b0, b_lo} + {1'b0, b_hi};
  DW02_mult #(.A_width(33), .B_width(33)) u_kar_cross (
    .A(sum_a), .B(sum_b), .TC(1'b0), .PRODUCT(cross_product)
  );
  assign cross_term = cross_product - {2'b0, z0} - {2'b0, z2};

  // Low 64-bit product: z2 << 64 vanishes modulo 2^64.
  logic [63:0] p1;
  assign p1 = z0 + {cross_term[31:0], 32'b0};

  // Two independent low 32-bit products reuse the Karatsuba halves.
  logic [63:0] p2;
  assign p2 = {z2[31:0], z0[31:0]};

  // Four independent low 16-bit products reuse the diagonal leaf products.
  logic [63:0] p4;
  assign p4 = {z2_hi16, z2_lo16, z0_hi16, z0_lo16};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;
    endcase
  end : outmux
endmodule : fu_mult_decomp

// One 32x32 full product using Karatsuba at a 16-bit split. The three leaf
// multipliers are z0=x0*y0, z2=x1*y1, and (x0+x1)*(y0+y1); the cross term is
// reconstructed with two subtractors. low_diag/high_diag are exposed so the
// parent can reuse the same leaf products for 4x16 multiply-low mode.
module fu_mult_karatsuba_32_full (
  input logic [31:0] a,
  input logic [31:0] b,
  output logic [63:0] product,
  output logic [15:0] low_diag,
  output logic [15:0] high_diag
);
  logic [15:0] a0, a1, b0, b1;
  logic [31:0] z0, z2;
  logic [16:0] sum_a, sum_b;
  logic [33:0] z1_sum, z1_cross;

  assign a0 = a[15:0];
  assign a1 = a[31:16];
  assign b0 = b[15:0];
  assign b1 = b[31:16];
  assign sum_a = {1'b0, a0} + {1'b0, a1};
  assign sum_b = {1'b0, b0} + {1'b0, b1};

  DW02_mult #(.A_width(16), .B_width(16)) u_z0 (
    .A(a0), .B(b0), .TC(1'b0), .PRODUCT(z0)
  );
  DW02_mult #(.A_width(16), .B_width(16)) u_z2 (
    .A(a1), .B(b1), .TC(1'b0), .PRODUCT(z2)
  );
  DW02_mult #(.A_width(17), .B_width(17)) u_z1 (
    .A(sum_a), .B(sum_b), .TC(1'b0), .PRODUCT(z1_sum)
  );

  assign z1_cross = z1_sum - {2'b0, z0} - {2'b0, z2};
  assign product = {32'b0, z0}
                 + ({30'b0, z1_cross} << 16)
                 + ({32'b0, z2} << 32);
  assign low_diag  = z0[15:0];
  assign high_diag = z2[15:0];
endmodule : fu_mult_karatsuba_32_full
