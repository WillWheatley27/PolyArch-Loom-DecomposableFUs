// Self-checking Verilator TB for standalone 2xFP32 compare.
module tb_fu_fp_cmp_32x2 #(parameter int unsigned NRAND = 20000);
  logic [3:0] pred; logic [63:0] a,b,y;
  logic in_valid_0,in_valid_1,in_ready_0,in_ready_1,out_valid,out_ready; integer errors;
  fu_fp_cmp_32x2 dut (.clk(1'b0),.rst_n(1'b1),.pred(pred),.in_data_0(a),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(b),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(y),.out_valid(out_valid),.out_ready(out_ready));

  function automatic logic gold_bit(input int EW,input int MW,input logic [3:0] p,input logic [63:0] x,input logic [63:0] z);
    logic [63:0] mask,xa,za,expa,mana,expz,manz; logic sx,sz,uno,lt,gt,eq;
    begin
      mask=(64'd1<<(EW+MW))-1; xa=x&mask; za=z&mask; expa=(x>>MW)&((64'd1<<EW)-1); mana=x&((64'd1<<MW)-1); expz=(z>>MW)&((64'd1<<EW)-1); manz=z&((64'd1<<MW)-1); sx=x[EW+MW]; sz=z[EW+MW];
      uno=((expa==((64'd1<<EW)-1))&&(mana!=0))||((expz==((64'd1<<EW)-1))&&(manz!=0));
      if((xa==0)&&(za==0))begin lt=0;gt=0;eq=1;end else if(sx!=sz)begin lt=sx;gt=sz;eq=0;end else if(sx)begin lt=xa>za;gt=xa<za;eq=xa==za;end else begin lt=xa<za;gt=xa>za;eq=xa==za;end
      case(p)
        4'd0:gold_bit=0;4'd1:gold_bit=~uno&eq;4'd2:gold_bit=~uno&gt;4'd3:gold_bit=~uno&(gt|eq);4'd4:gold_bit=~uno&lt;4'd5:gold_bit=~uno&(lt|eq);4'd6:gold_bit=~uno&(lt|gt);4'd7:gold_bit=~uno;4'd8:gold_bit=uno|eq;4'd9:gold_bit=uno|gt;4'd10:gold_bit=uno|(gt|eq);4'd11:gold_bit=uno|lt;4'd12:gold_bit=uno|(lt|eq);4'd13:gold_bit=uno|(lt|gt);4'd14:gold_bit=uno;default:gold_bit=1;
      endcase
    end
  endfunction
  function automatic logic [63:0] golden(input logic [3:0] p,input logic [63:0] x,input logic [63:0] z); logic [63:0] r; begin r='0; for(int i=0;i<2;i++)r[i*32+:32]={32{gold_bit(8,23,p,x>>(i*32),z>>(i*32))}}; golden=r; end endfunction
  task automatic check(input logic [3:0] p,input logic [63:0] x,input logic [63:0] z); logic [63:0] e; begin pred=p;a=x;b=z;in_valid_0=1;in_valid_1=1;out_ready=1;#1;e=golden(p,x,z);if(y!==e)begin $display("FAIL data p=%0d a=%h b=%h got=%h exp=%h",p,x,z,y,e);errors++;end;if(out_valid!==1||in_ready_0!==1||in_ready_1!==1)begin $display("FAIL handshake");errors++;end end endtask
  initial begin
    errors=0;a='0;b='0;pred=0;in_valid_0=0;in_valid_1=0;out_ready=0;
    for(int p=0;p<16;p++)begin check(p,64'h3f800000_c0000000,64'h40000000_bf800000);check(p,64'h7fc00000_00000000,64'h3f800000_80000000);check(p,64'h80000000_00000000,64'h00000000_00000000);check(p,64'h7f800000_ff800000,64'h7f800000_7f800000);check(p,64'h00000001_80000001,64'h80000001_00000001);end
    a=64'hdead_beef_cafe_f00d;b=64'h0123_4567_89ab_cdef;in_valid_0=1;in_valid_1=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0)begin $display("FAIL backpressure");errors++;end;in_valid_1=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL incomplete join");errors++;end
    for(int i=0;i<NRAND;i++)check($urandom[3:0],$urandom,$urandom);if(errors==0)$display("PASS: fu_fp_cmp_32x2, %0d random vectors",NRAND);else begin $display("FAIL: fu_fp_cmp_32x2 %0d errors",errors);$fatal(1);end;$finish;
  end
endmodule : tb_fu_fp_cmp_32x2
