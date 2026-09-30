module fu_fp_min_max_16x2 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk,input logic rst_n,                         // combinational FU
  input logic [63:0] in_data_0,input logic [63:0] in_data_1, // upper 32 bits unused
  // verilator lint_on UNUSEDSIGNAL
  input logic [1:0] op_sel,
  input logic in_valid_0,output logic in_ready_0,
  input logic in_valid_1,output logic in_ready_1,
  output logic [63:0] out_data,output logic out_valid,input logic out_ready
);
  assign out_valid=in_valid_0&in_valid_1; assign in_ready_0=out_ready&out_valid; assign in_ready_1=out_ready&out_valid;
  for(genvar i=0;i<2;i++) begin: lane
    // verilator lint_off UNUSEDSIGNAL
    logic aeqb,altb,agtb,unordered; logic [15:0] z0,z1; logic [7:0] status0,status1; logic [15:0] a,b;
    // verilator lint_on UNUSEDSIGNAL
    assign a=in_data_0[i*16 +:16]; assign b=in_data_1[i*16 +:16];
    DW_fp_cmp #(.sig_width(10),.exp_width(5),.ieee_compliance(1)) u_cmp(.a(a),.b(b),.zctr(op_sel[i]),.aeqb(aeqb),.altb(altb),.agtb(agtb),.unordered(unordered),.z0(z0),.z1(z1),.status0(status0),.status1(status1));
    logic both_zero,a_nan,b_nan; assign both_zero=(a[14:0]==15'd0)&&(b[14:0]==15'd0); assign a_nan=(&a[14:10])&&(|a[9:0]); assign b_nan=(&b[14:10])&&(|b[9:0]);
    assign out_data[i*16 +:16]=(a_nan||b_nan)?16'h7E00:both_zero?(op_sel[i]?(a[15]?b:a):(a[15]?a:b)):z0;
  end
  assign out_data[63:32]=32'd0;
endmodule
