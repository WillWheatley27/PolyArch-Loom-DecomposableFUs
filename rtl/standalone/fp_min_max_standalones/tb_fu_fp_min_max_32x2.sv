// Self-checking Verilator TB for standalone 2xFP32 min/max.
module tb_fu_fp_min_max_32x2 #(
  parameter int unsigned NRAND = 20000
);
  logic [1:0] op_sel; logic [63:0] a,b,y; logic in_valid_0,in_valid_1,in_ready_0,in_ready_1,out_valid,out_ready; integer errors;
  fu_fp_min_max_32x2 dut (.clk(1'b0),.rst_n(1'b1),.op_sel(op_sel),.in_data_0(a),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(b),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(y),.out_valid(out_valid),.out_ready(out_ready));
  function automatic logic [31:0] lane_gold(input logic mx,input logic [31:0] x,input logic [31:0] z);
    logic xn,zn,xlt; logic [30:0] xm,zm; begin
      xn=(&x[30:23])&&(|x[22:0]);zn=(&z[30:23])&&(|z[22:0]);
      if(xn||zn)lane_gold=32'h7FC0_0000;else begin xm=x[30:0];zm=z[30:0];if(x[31]!=z[31])xlt=x[31];else if(x[31])xlt=xm>zm;else xlt=xm<zm;lane_gold=mx?(xlt?z:x):(xlt?x:z);end
    end
  endfunction
  task automatic check(input logic [1:0] op,input logic [63:0] x,input logic [63:0] z);begin
    op_sel=op;a=x;b=z;in_valid_0=1;in_valid_1=1;out_ready=1;#1;
    if(y[31:0]!==lane_gold(op[0],x[31:0],z[31:0])||y[63:32]!==lane_gold(op[1],x[63:32],z[63:32]))begin $display("FAIL data op=%b a=%h b=%h got=%h",op,x,z,y);errors++;end
    if(out_valid!==1||in_ready_0!==1||in_ready_1!==1)begin $display("FAIL handshake");errors++;end
  end endtask
  initial begin
    errors=0;a='0;b='0;op_sel=0;in_valid_0=0;in_valid_1=0;out_ready=0;
    check(2'b00,64'h3F80_0000_C000_0000,64'h4000_0000_BF80_0000);
    check(2'b11,64'h8000_0000_7FC0_0001,64'h0000_0000_3F80_0000);
    check(2'b01,64'h8000_0000_8000_0000,64'h0000_0000_0000_0000);
    in_valid_0=1;in_valid_1=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0)begin $display("FAIL backpressure");errors++;end
    in_valid_1=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL incomplete join");errors++;end
    for(int i=0;i<NRAND;i++)check($random,{$random,$random},{$random,$random});
    if(errors==0)$display("PASS: fu_fp_min_max_32x2, %0d random vectors",NRAND);else begin $display("FAIL: fu_fp_min_max_32x2 %0d mismatches",errors);$fatal(1);end
    $finish;
  end
endmodule : tb_fu_fp_min_max_32x2
