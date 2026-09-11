module tb_fu_cmp_64 #(parameter int unsigned NRAND = 20000);
  logic [3:0] pred; logic [63:0] a,b,y; logic v0,v1,r0,r1,ov,or_; integer errors;
  fu_cmp_64 dut (.clk(0),.rst_n(1),.pred(pred),.in_data_0(a),.in_valid_0(v0),.in_ready_0(r0),
    .in_data_1(b),.in_valid_1(v1),.in_ready_1(r1),.out_data(y),.out_valid(ov),.out_ready(or_));
  function automatic logic g(input logic [3:0] p,input logic [63:0] x,input logic [63:0] z);
    logic u,s,e; begin u=x>z;s=$signed(x)>$signed(z);e=x==z;case(p)
      0:g=e;1:g=~e;2:g=~(s|e);3:g=~s;4:g=s;5:g=s|e;6:g=~(u|e);7:g=~u;8:g=u;9:g=u|e;default:g=0;endcase end
  endfunction
  task automatic check(input logic [63:0] x,input logic [63:0] z,input logic [3:0] p);
    begin a=x;b=z;pred=p;v0=1;v1=1;or_=1;#1;if(y !== {64{g(p,x,z)}})errors++;end
  endtask
  initial begin errors=0;v0=0;v1=0;or_=0;for(int p=0;p<10;p++)begin check(0,1,p);check(64'h8000_0000_0000_0000,0,p);end
    for(int i=0;i<NRAND;i++)check({$random,$random},{$random,$random},$urandom_range(0,9));
    if(errors==0)$display("PASS: fu_cmp_64, %0d random vectors",NRAND); else $fatal(1);$finish;end
endmodule
