// Self-checking Verilator TB for the standalone fp64 min/max baseline.
module tb_fu_fp_min_max_64 #(
  parameter int unsigned NRAND = 20000
);
  logic op_sel; logic [63:0] a,b,y; logic in_valid_0,in_valid_1,in_ready_0,in_ready_1,out_valid,out_ready;
  integer errors;
  fu_fp_min_max_64 dut (.clk(1'b0),.rst_n(1'b1),.op_sel(op_sel),.in_data_0(a),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(b),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(y),.out_valid(out_valid),.out_ready(out_ready));

  function automatic logic [63:0] gold(input logic mx,input logic [63:0] x,input logic [63:0] z);
    logic xn,zn,xlt; logic [63:0] xm,zm; begin
      xn=(&x[62:52])&&(|x[51:0]); zn=(&z[62:52])&&(|z[51:0]);
      if (xn||zn) gold=64'h7FF8_0000_0000_0000;
      else begin
        xm=x&64'h7FFF_FFFF_FFFF_FFFF; zm=z&64'h7FFF_FFFF_FFFF_FFFF;
        if (x[63]!=z[63]) xlt=x[63]; else if (x[63]) xlt=xm>zm; else xlt=xm<zm;
        gold=mx ? (xlt?z:x) : (xlt?x:z);
      end
    end
  endfunction
  task automatic check(input logic mx,input logic [63:0] x,input logic [63:0] z);
    begin op_sel=mx;a=x;b=z;in_valid_0=1;in_valid_1=1;out_ready=1;#1;
      if(y!==gold(mx,x,z))begin $display("FAIL data mx=%b a=%h b=%h got=%h exp=%h",mx,x,z,y,gold(mx,x,z));errors++;end
      if(out_valid!==1||in_ready_0!==1||in_ready_1!==1)begin $display("FAIL handshake");errors++;end
    end
  endtask
  initial begin
    errors=0;a='0;b='0;op_sel=0;in_valid_0=0;in_valid_1=0;out_ready=0;
    check(0,64'h3FF0_0000_0000_0000,64'h4000_0000_0000_0000);
    check(1,64'hBFF0_0000_0000_0000,64'h0000_0000_0000_0000);
    check(0,64'h8000_0000_0000_0000,64'h0000_0000_0000_0000);
    check(1,64'h8000_0000_0000_0000,64'h0000_0000_0000_0000);
    check(0,64'h7FF8_0000_0000_0001,64'h3FF0_0000_0000_0000);
    in_valid_0=1;in_valid_1=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0)begin $display("FAIL backpressure");errors++;end
    in_valid_1=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL incomplete join");errors++;end
    for(int i=0;i<NRAND;i++)check($random,{$random,$random},{$random,$random});
    if(errors==0)$display("PASS: fu_fp_min_max_64, %0d random vectors",NRAND);else begin $display("FAIL: fu_fp_min_max_64 %0d mismatches",errors);$fatal(1);end
    $finish;
  end
endmodule : tb_fu_fp_min_max_64
