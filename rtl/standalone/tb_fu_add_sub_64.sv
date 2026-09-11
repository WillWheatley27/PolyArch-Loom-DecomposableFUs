module tb_fu_add_sub_64 #(parameter int unsigned NRAND = 20000);
  logic [7:0] op; logic [63:0] a,b,y; logic v0,v1,r0,r1,ov,or_; integer errors;
  fu_add_sub_64 dut (.clk(0),.rst_n(1),.op_sel(op),.in_data_0(a),.in_valid_0(v0),.in_ready_0(r0),
    .in_data_1(b),.in_valid_1(v1),.in_ready_1(r1),.out_data(y),.out_valid(ov),.out_ready(or_));
  task automatic check(input logic [63:0] x,input logic [63:0] z,input logic sub);
    begin a=x;b=z;op='0;op[0]=sub;v0=1;v1=1;or_=1;#1;
      if (y !== (sub ? x-z : x+z)) errors++;
    end
  endtask
  initial begin errors=0;v0=0;v1=0;or_=0;check(64'h1,64'h2,0);check(64'h0,64'h1,1);
    for(int i=0;i<NRAND;i++) check({$random,$random},{$random,$random},$random);
    if(errors==0)$display("PASS: fu_add_sub_64, %0d random vectors",NRAND); else $fatal(1);
    $finish; end
endmodule
