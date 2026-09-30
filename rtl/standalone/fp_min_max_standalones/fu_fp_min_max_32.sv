module fu_fp_min_max_32 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk,input logic rst_n,                         // combinational FU
  input logic [63:0] in_data_0,input logic [63:0] in_data_1, // upper 32 bits unused
  // verilator lint_on UNUSEDSIGNAL
  input logic op_sel,
  input logic in_valid_0,output logic in_ready_0,
  input logic in_valid_1,output logic in_ready_1,
  output logic [63:0] out_data,output logic out_valid,input logic out_ready
);
  assign out_valid=in_valid_0&in_valid_1; assign in_ready_0=out_ready&out_valid; assign in_ready_1=out_ready&out_valid;
  // verilator lint_off UNUSEDSIGNAL
  logic aeqb,altb,agtb,unordered; logic [31:0] z0,z1; logic [7:0] status0,status1; logic [31:0] a,b;
  // verilator lint_on UNUSEDSIGNAL
  assign a=in_data_0[31:0]; assign b=in_data_1[31:0];
  DW_fp_cmp #(.sig_width(23),.exp_width(8),.ieee_compliance(1)) u_cmp(.a(a),.b(b),.zctr(op_sel),.aeqb(aeqb),.altb(altb),.agtb(agtb),.unordered(unordered),.z0(z0),.z1(z1),.status0(status0),.status1(status1));
  logic both_zero,a_nan,b_nan; assign both_zero=(a[30:0]==31'd0)&&(b[30:0]==31'd0); assign a_nan=(&a[30:23])&&(|a[22:0]); assign b_nan=(&b[30:23])&&(|b[22:0]);
  assign out_data = {32'd0,(a_nan||b_nan)?32'h7FC0_0000:both_zero?(op_sel?(a[31]?(b):(a)):(a[31]?(a):(b))):z0};
endmodule
