// Self-checking Verilator TB for standalone 4xFP16 min/max.
module tb_fu_fp_min_max_16x4 #(
  parameter int unsigned NRAND = 20000
);
  logic [3:0] op_sel; logic [63:0] a,b,y; logic in_valid_0,in_valid_1,in_ready_0,in_ready_1,out_valid,out_ready; integer errors;
  fu_fp_min_max_16x4 dut (.clk(1'b0),.rst_n(1'b1),.op_sel(op_sel),.in_data_0(a),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(b),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(y),.out_valid(out_valid),.out_ready(out_ready));
  function automatic logic [15:0] lane_gold(input logic mx,input logic [15:0] x,input logic [15:0] z);
    logic xn,zn,xlt; logic [14:0] xm,zm; begin
      xn=(&x[14:10])&&(|x[9:0]);zn=(&z[14:10])&&(|z[9:0]);
      if(xn||zn)lane_gold=16'h7E00;else begin xm=x[14:0];zm=z[14:0];if(x[15]!=z[15])xlt=x[15];else if(x[15])xlt=xm>zm;else xlt=xm<zm;lane_gold=mx?(xlt?z:x):(xlt?x:z);end
    end
  endfunction
  task automatic check(input logic [3:0] op,input logic [63:0] x,input logic [63:0] z);begin
    op_sel=op;a=x;b=z;in_valid_0=1;in_valid_1=1;out_ready=1;#1;
    for(int l=0;l<4;l++)if(y[l*16 +: 16]!==lane_gold(op[l],x[l*16 +: 16],z[l*16 +: 16]))begin $display("FAIL data op=%b a=%h b=%h lane=%0d got=%h",op,x,z,l,y[l*16 +: 16]);errors++;end
    if(out_valid!==1||in_ready_0!==1||in_ready_1!==1)begin $display("FAIL handshake");errors++;end
  end endtask
  initial begin
    errors=0;a='0;b='0;op_sel=0;in_valid_0=0;in_valid_1=0;out_ready=0;
    check(4'b0101,64'h3C00_C000_7E00_0000,64'h4000_BC00_3C00_8000);
    check(4'b1111,64'h8000_7C00_FC00_0000,64'h0000_7C00_7E00_8000);
    check(4'b0010,64'h0001_0002_0003_0004,64'h0002_0001_0004_0003);
    in_valid_0=1;in_valid_1=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0)begin $display("FAIL backpressure");errors++;end
    in_valid_1=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL incomplete join");errors++;end
    for(int i=0;i<NRAND;i++)check($random,{$random,$random},{$random,$random});
    if(errors==0)$display("PASS: fu_fp_min_max_16x4, %0d random vectors",NRAND);else begin $display("FAIL: fu_fp_min_max_16x4 %0d mismatches",errors);$fatal(1);end
    $finish;
  end
endmodule : tb_fu_fp_min_max_16x4
