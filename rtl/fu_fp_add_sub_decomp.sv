// fu_fp_add_sub_decomp.sv -- STUB (RED). Handshake only; out_data is a non-FP
// integer combine (XOR), so it fails the FP golden on essentially all vectors.
// Replaced by the shared IEEE-754 add/sub core in GREEN.
module fu_fp_add_sub_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
  input  logic [3:0]  op_sel,
  // verilator lint_on UNUSEDSIGNAL

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

  // STUB datapath: not floating point.
  assign out_data = in_data_0 ^ in_data_1;

endmodule : fu_fp_add_sub_decomp
