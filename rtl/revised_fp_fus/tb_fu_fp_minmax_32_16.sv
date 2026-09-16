module tb_fu_fp_minmax_32_16;
  logic mode;
  logic [1:0] op_sel;
  logic [63:0] a,b,y;
  logic valid0,valid1,ready0,ready1,out_valid,out_ready;
  int errors=0;

  fu_fp_minmax_revised_32_16 dut(
    .clk(1'b0),.rst_n(1'b1),.mode(mode),.op_sel(op_sel),
    .in_data_0(a),.in_valid_0(valid0),.in_ready_0(ready0),
    .in_data_1(b),.in_valid_1(valid1),.in_ready_1(ready1),
    .out_data(y),.out_valid(out_valid),.out_ready(out_ready)
  );

  function automatic logic [31:0] gold32(input logic mx,input logic [31:0] x,input logic [31:0] z);
    logic sx,sz,nx,nz,lt; logic [7:0] ex,ez; logic [22:0] fx,fz;
    sx=x[31]; sz=z[31]; ex=x[30:23]; ez=z[30:23]; fx=x[22:0]; fz=z[22:0];
    nx=(&ex)&&(fx!='0); nz=(&ez)&&(fz!='0);
    if(nx||nz) gold32=32'h7FC0_0000;
    else begin
      if(sx!=sz) lt=sx;
      else if(sx) lt=(ex>ez)||((ex==ez)&&(fx>fz));
      else lt=(ex<ez)||((ex==ez)&&(fx<fz));
      gold32=mx?(lt?z:x):(lt?x:z);
    end
  endfunction
  function automatic logic [15:0] gold16(input logic mx,input logic [15:0] x,input logic [15:0] z);
    logic sx,sz,nx,nz,lt; logic [4:0] ex,ez; logic [9:0] fx,fz;
    sx=x[15]; sz=z[15]; ex=x[14:10]; ez=z[14:10]; fx=x[9:0]; fz=z[9:0];
    nx=(&ex)&&(fx!='0); nz=(&ez)&&(fz!='0);
    if(nx||nz) gold16=16'h7E00;
    else begin
      if(sx!=sz) lt=sx;
      else if(sx) lt=(ex>ez)||((ex==ez)&&(fx>fz));
      else lt=(ex<ez)||((ex==ez)&&(fx<fz));
      gold16=mx?(lt?z:x):(lt?x:z);
    end
  endfunction
  function automatic logic [63:0] gold(input logic m,input logic [1:0] op,input logic [63:0] x,input logic [63:0] z);
    if(m) gold={32'd0,gold16(op[1],x[31:16],z[31:16]),gold16(op[0],x[15:0],z[15:0])};
    else gold={32'd0,gold32(op[0],x[31:0],z[31:0])};
  endfunction
  task automatic check(input logic m,input logic [1:0] op,input logic [63:0] x,input logic [63:0] z);
    logic [63:0] g;
    mode=m; op_sel=op; a=x; b=z; valid0=1; valid1=1; out_ready=1; #1; g=gold(m,op,x,z);
    if(y!==g) begin $display("FAIL mode=%b op=%b a=%h b=%h got=%h exp=%h",m,op,x,z,y,g); errors++; end
    if(out_valid!==1 || ready0!==1 || ready1!==1) begin $display("FAIL handshake active"); errors++; end
  endtask

  logic [63:0] x,z;
  initial begin
    valid0=0; valid1=0; out_ready=1; mode=0; op_sel=0; a=0; b=0; #1;
    if(out_valid!==0 || ready0!==0 || ready1!==0) begin $display("FAIL handshake invalid"); errors++; end
    check(0,2'b01,64'h0000_0000_3F80_0000,64'h0000_0000_4000_0000); // max(1,2)
    check(0,2'b00,64'h0000_0000_7FC0_0000,64'h0000_0000_3F80_0000); // NaN
    check(0,2'b00,64'h0000_0000_8000_0000,64'h0000_0000_0000_0000); // min(-0,+0)
    check(1,2'b10,64'h0000_0000_3C00_C000,64'h0000_0000_4000_BC00); // max/min mixed
    check(1,2'b01,64'h0000_0000_7E00_8000,64'h0000_0000_3C00_0000); // NaN, signed zero
    x=64'h0000_0000_1234_5678; z=64'h0000_0000_89AB_CDEF;
    for(int i=0;i<20000;i++) begin
      x={32'd0,x[62:0],x[63]^x[60]^x[7]^x[0]};
      z={32'd0,z[62:0],z[63]^z[59]^z[4]^z[1]};
      check(z[0],x[1:0],x,z);
    end
    if(errors==0) $display("PASS fp_minmax_32_16 20000 randomized vectors");
    else $display("FAILURES %0d",errors);
    $finish;
  end
endmodule
