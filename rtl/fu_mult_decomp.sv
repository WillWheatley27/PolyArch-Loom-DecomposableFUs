// fu_mult_decomp.sv -- STUB (RED). Always computes the 1x64 truncated product and
// ignores mode; passes 1x64 + handshake corners but fails the decomposed 2x32 / 4x16
// modes (cross-lane partial products leak). Replaced by the segmented datapath in GREEN.
module fu_mult_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
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

  // STUB datapath: low 64 bits of the full product, regardless of mode.
  assign out_data = in_data_0 * in_data_1;

endmodule : fu_mult_decomp
