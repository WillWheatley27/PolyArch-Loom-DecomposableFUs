// fu_add_sub_64.sv -- Standalone fixed-width 1x64 add/sub baseline.
// There is no runtime mode and no lane-boundary control. op_sel[0]=0 selects
// addition and op_sel[0]=1 selects subtraction; the remaining bits are ignored
// to keep the packed FU control convention compatible with the shared core.
module fu_add_sub_64 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  // verilator lint_off UNUSEDSIGNAL
  input logic [7:0] op_sel,
  // verilator lint_on UNUSEDSIGNAL
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;
  // verilator lint_off UNUSEDSIGNAL
  logic carry_out;
  // verilator lint_on UNUSEDSIGNAL
  DW01_addsub #(.width(64)) u_addsub (
    .A(in_data_0), .B(in_data_1), .CI(1'b0), .ADD_SUB(op_sel[0]),
    .SUM(out_data), .CO(carry_out)
  );
endmodule
