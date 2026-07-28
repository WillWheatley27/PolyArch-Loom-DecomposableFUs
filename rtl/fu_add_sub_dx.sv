// fu_add_sub_dx.sv -- STUB (RED). 2-input join handshake only; out_data = a & b (not add/sub),
// fails the golden. Replaced in GREEN by a DW_addsub_dx duplex instantiation.
module fu_add_sub_dx (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
  input  logic [1:0]  op_sel,
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

  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  assign out_data = in_data_0 & in_data_1;   // STUB: not add/sub

endmodule : fu_add_sub_dx
