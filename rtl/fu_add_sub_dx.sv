// fu_add_sub_dx.sv -- Decomposable (duplex) FU for integer add/sub, built on DesignWare.
// share group integer_add_sub (arith.addi / arith.subi). Decomposable at ONE boundary (bit 32):
//
//   mode = 2'b00 -> 1x64 : one 64-bit add/sub
//   mode = 2'b01 -> 2x32 : two independent 32-bit add/sub
//   mode = 2'b10/11 -> reserved, behaves as 1x64
//
//   op_sel[i] per 32-bit lane: 0 -> add, 1 -> subtract. In 1x64 only op_sel[0] applies.
//
// The datapath IS the Synopsys DesignWare duplex adder DW_addsub_dx (width=64, p1_width=32):
// dplx=0 gives one 64-bit chain, dplx=1 two independent 32-bit chains (the vendor block is the
// segmented datapath -- no manual carry-kill). It runs in add mode (addsub=0); per-lane subtract
// is a - b = a + ~b + 1, done by inverting the subtracting lane's b and injecting that segment's
// carry-in (ci1/ci2). Combinational, latency 0. Simulated via the DW sim_ver model, synthesized
// from dw_foundation.sldb.
module fu_add_sub_dx (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic [1:0]  op_sel,

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

  // Duplex select + per-lane subtract control.
  logic        dplx, sub_lo, sub_hi;
  assign dplx   = (mode == M_2X32);
  assign sub_lo = op_sel[0];
  assign sub_hi = dplx ? op_sel[1] : op_sel[0];   // 1x64: whole word driven by op_sel[0]

  // Invert the subtracting lane's b; carry-in completes the two's-complement negate.
  logic [63:0] b_eff;
  assign b_eff[31:0]  = in_data_1[31:0]  ^ {32{sub_lo}};
  assign b_eff[63:32] = in_data_1[63:32] ^ {32{sub_hi}};

  // DesignWare duplex adder-subtractor: the shared, mode-split datapath.
  logic co1_unused, co2_unused;
  DW_addsub_dx #(.width(64), .p1_width(32)) u_addsub (
    .a      (in_data_0),
    .b      (b_eff),
    .ci1    (sub_lo),      // low segment (and full-width) carry-in
    .ci2    (sub_hi),      // high segment carry-in (used when dplx=1)
    .addsub (1'b0),        // add mode; subtract handled by b-invert + carry-in
    .tc     (1'b0),        // wrap (two's-complement sum bits are format-agnostic)
    .sat    (1'b0),
    .avg    (1'b0),
    .dplx   (dplx),
    .sum    (out_data),
    .co1    (co1_unused),
    .co2    (co2_unused)
  );

endmodule : fu_add_sub_dx
