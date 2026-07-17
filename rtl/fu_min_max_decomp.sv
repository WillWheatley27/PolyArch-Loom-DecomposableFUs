// fu_min_max_decomp.sv -- STUB (RED). Handshake only; out_data = in_data_0 & in_data_1
// (not a min/max; uses both operands so lint is clean). Fails min/max selection and all
// decomposed modes. Replaced by the shared segmented comparator in GREEN.
module fu_min_max_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
  input  logic        is_signed,
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

  // STUB datapath: not a min/max.
  assign out_data = in_data_0 & in_data_1;

endmodule : fu_min_max_decomp
