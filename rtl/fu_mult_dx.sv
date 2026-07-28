// fu_mult_dx.sv -- Decomposable (duplex) FU for integer multiply-low, built on DesignWare.
// arith.muli (singleton). Decomposable at ONE boundary (bit 32):
//
//   mode = 2'b00 -> 1x64 : low 64 bits of a*b
//   mode = 2'b01 -> 2x32 : low 32 bits of each 32x32
//   mode = 2'b10/11 -> reserved, behaves as 1x64
//
// Multiply-low (like PMULLW/PMULLD) is sign-agnostic -> no op_sel, tc=0. The datapath IS the
// Synopsys DesignWare duplex multiplier DW_mult_dx (width=64, p1_width=32): dplx=0 gives one
// 64x64->128b product, dplx=1 two independent 32x32 products (low lane in product[63:0], high
// lane in product[127:64]). We slice the low W bits per lane. Combinational, latency 0.
// Simulated via the DW sim_ver model, synthesized from dw_foundation.sldb.
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

  // DesignWare duplex multiplier: the shared, mode-split datapath. Full 128-bit product.
  // verilator lint_off UNUSEDSIGNAL
  logic [127:0] prod;
  // verilator lint_on UNUSEDSIGNAL
  DW_mult_dx #(.width(64), .p1_width(32)) u_mult (
    .a       (in_data_0),
    .b       (in_data_1),
    .tc      (1'b0),        // unsigned; low product bits are sign-agnostic
    .dplx    (dplx),
    .product (prod)
  );

  // Multiply-low slice: 2x32 -> low 32 of each lane; 1x64 -> low 64.
  assign out_data = dplx ? {prod[95:64], prod[31:0]} : prod[63:0];

endmodule : fu_mult_dx
