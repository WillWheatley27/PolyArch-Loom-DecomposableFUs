// fu_mult_karatsuba_64_32.sv -- Karatsuba integer multiply-low, 64/32 modes.
// mode 00: low 64 bits of one 64x64 product.
// mode 01: low 32 bits of each of two independent 32x32 products.
// mode 10/11: reserved, behave as mode 00.
//
// The 64-bit path uses three 32x32 products: z0=alo*blo, z2=ahi*bhi, and
// z1=(alo+ahi)*(blo+bhi).  The cross term is z1-z0-z2, and only its low
// 32 bits contribute after the <<32 shift.  The 32-bit mode reuses z0/z2.
// Low-product semantics are sign-agnostic, so operands are unsigned.
// Combinational, latency 0.
module fu_mult_karatsuba_64_32 (
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

  logic [31:0] alo, ahi, blo, bhi;
  assign alo = in_data_0[31:0]; assign ahi = in_data_0[63:32];
  assign blo = in_data_1[31:0]; assign bhi = in_data_1[63:32];

  logic [63:0] z0;
  // The high halves of z1/z2 are not needed for multiply-low outputs.
  // verilator lint_off UNUSEDSIGNAL
  logic [63:0] z2, z1;
  // verilator lint_on UNUSEDSIGNAL
  logic [31:0] sum_a, sum_b, cross_lo;
  logic [63:0] p64, p32;
  assign sum_a = alo + ahi;
  assign sum_b = blo + bhi;

  DW02_mult #(.A_width(32), .B_width(32)) u_z0 (
    .A(alo), .B(blo), .TC(1'b0), .PRODUCT(z0)
  );
  DW02_mult #(.A_width(32), .B_width(32)) u_z2 (
    .A(ahi), .B(bhi), .TC(1'b0), .PRODUCT(z2)
  );
  DW02_mult #(.A_width(32), .B_width(32)) u_z1 (
    .A(sum_a), .B(sum_b), .TC(1'b0), .PRODUCT(z1)
  );

  assign cross_lo = z1[31:0] - z0[31:0] - z2[31:0];
  assign p64 = z0 + {cross_lo, 32'b0};
  assign p32 = {z2[31:0], z0[31:0]};
  assign out_data = (mode == 2'b01) ? p32 : p64;
endmodule : fu_mult_karatsuba_64_32
