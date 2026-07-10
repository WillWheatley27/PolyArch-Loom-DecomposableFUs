// fu_add_sub_decomp.sv -- Decomposable (subword-SIMD) FU for share group add_sub.
// STUB (Task 1): 1x64 add/sub only; ignores mode and per-lane op_sel[3:1].
// Correct interface so the testbench compiles; intentionally wrong for 2x32/4x16.
module fu_add_sub_decomp (
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
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // STUB datapath: whole-word add/sub only.
  assign out_data = op_sel[0] ? (in_data_0 - in_data_1) : (in_data_0 + in_data_1);
endmodule : fu_add_sub_decomp
