// Self-checking Verilator TB for standalone packed 2xFP16 min/max (low 32 bits active).
module tb_fu_fp_min_max_16x2 #(
  parameter int unsigned NRAND = 20000
);
  logic [1:0] op_sel; logic [63:0] a,b,y; logic in_valid_0,in_valid_1,in_ready_0,in_ready_1,out_valid,out_ready; integer errors;
  fu_fp_min_max_16x2 dut (.clk(1'b0),.rst_n(1'b1),.op_sel(op_sel),.in_data_0(a),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(b),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(y),.out_valid(out_valid),.out_ready(out_ready));
  function automatic logic [15:0] lane_gold(input logic mx,input logic [15:0] x,input logic [15:0] z);
    logic xn,zn,xlt; logic [14:0] xm,zm; begin
      xn=(&x[14:10])&&(|x[9:0]);zn=(&z[14:10])&&(|z[9:0]);
      if(xn||zn)lane_gold=16'h7E00;else begin xm=x[14:0];zm=z[14:0];if(x[15]!=z[15])xlt=x[15];else if(x[15])xlt=xm>zm;else xlt=xm<zm;lane_gold=mx?(xlt?z:x):(xlt?x:z);end
    end
  endfunction
  task automatic check(input logic [1:0] op,input logic [63:0] x,input logic [63:0] z);begin
    op_sel=op;a=x;b=z;in_valid_0=1;in_valid_1=1;out_ready=1;#1;
    if(y!=={32'd0,lane_gold(op[1],x[31:16],z[31:16]),lane_gold(op[0],x[15:0],z[15:0])})begin $display("FAIL data op=%b a=%h b=%h got=%h",op,x,z,y);errors++;end
    if(out_valid!==1||in_ready_0!==1||in_ready_1!==1)begin $display("FAIL handshake");errors++;end
  end endtask
  initial begin
    errors=0;a='0;b='0;op_sel=0;in_valid_0=0;in_valid_1=0;out_ready=0;
    for(int op=0;op<4;op++)begin
      check(op[1:0],64'h0000_0000_3C00_4000,64'h0000_0000_4000_3C00); // (1,2) vs (2,1)
      check(op[1:0],64'h0000_0000_7C01_7C00,64'h0000_0000_3C00_3C00); // lane1 NaN via bit 0, lane0 +Inf
      check(op[1:0],64'h0000_0000_8000_0000,64'h0000_0000_0000_8000); // -0/+0 in both orders
      check(op[1:0],64'h0000_0000_FC00_0001,64'h0000_0000_7C00_8001); // -Inf/+Inf, +/- min subnormal
      check(op[1:0],64'h0000_0000_C000_BC00,64'h0000_0000_C000_BC00); // equal negatives
      check(op[1:0],64'hDEAD_BEEF_BC00_3C00,64'h1234_5678_C000_4000); // upper bits ignored
    end
    in_valid_0=1;in_valid_1=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0)begin $display("FAIL backpressure");errors++;end
    in_valid_1=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL incomplete join");errors++;end
    for(int i=0;i<NRAND;i++)check($random,{$random,$random},{$random,$random});
    if(errors==0)$display("PASS: fu_fp_min_max_16x2, %0d random vectors",NRAND);else begin $display("FAIL: fu_fp_min_max_16x2 %0d mismatches",errors);$fatal(1);end
    $finish;
  end
endmodule : tb_fu_fp_min_max_16x2
