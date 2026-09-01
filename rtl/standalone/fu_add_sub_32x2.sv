// fu_add_sub_32x2.sv -- Standalone fixed-width 2x32 add/sub baseline.
//
// This module is one bank component for the decomposable-area comparison.  It
// always performs two independent 32-bit lane operations packed in 64 bits;
// there is no runtime mode and no 64-bit carry path.  A lane op_sel bit of 0
// selects addition and 1 selects subtraction.  The DesignWare duplex adder is
// the natural implementation because its dplx input hard-breaks the 64-bit
// chain into two 32-bit chains.
//
// Combinational, latency 0, 2-input join handshake.
module fu_add_sub_32x2 (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

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
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // Subtraction is A + (~B) + 1.  DW_addsub_dx then supplies independent
  // carry seeds to the two 32-bit segments when dplx=1.
  logic [63:0] b_eff;
  assign b_eff[31:0]  = in_data_1[31:0]  ^ {32{op_sel[0]}};
  assign b_eff[63:32] = in_data_1[63:32] ^ {32{op_sel[1]}};

  logic co1_unused, co2_unused;
  DW_addsub_dx #(.width(64), .p1_width(32)) u_addsub (
    .a      (in_data_0),
    .b      (b_eff),
    .ci1    (op_sel[0]),
    .ci2    (op_sel[1]),
    .addsub (1'b0),
    .tc     (1'b0),
    .sat    (1'b0),
    .avg    (1'b0),
    .dplx   (1'b1),
    .sum    (out_data),
    .co1    (co1_unused),
    .co2    (co2_unused)
  );
endmodule : fu_add_sub_32x2
