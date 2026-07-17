// fu_rounding_decomp.sv -- STUB (RED). Unary handshake only; out_data = ~in_data_0
// (not a rounding), fails the golden. Replaced by the shared rounding core in GREEN.
module fu_rounding_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
  input  logic [2:0]  round_mode,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,

  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready
);

  // Handshake: 1-input (unary), combinational, lossless backpressure.
  assign out_valid  = in_valid_0;
  assign in_ready_0 = out_ready & out_valid;

  // STUB datapath: not a rounding.
  assign out_data = ~in_data_0;

endmodule : fu_rounding_decomp
