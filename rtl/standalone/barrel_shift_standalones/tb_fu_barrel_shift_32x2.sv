// Self-checking Verilator TB for standalone 2x32 barrel shift.
module tb_fu_barrel_shift_32x2 #(
  parameter int unsigned NRAND = 20000
);
  logic [1:0] shift_op; logic [63:0] a, amt, y;
  logic in_valid_0, in_valid_1, in_ready_0, in_ready_1, out_valid, out_ready;
  integer errors;
  fu_barrel_shift_32x2 dut (.clk(1'b0),.rst_n(1'b1),.shift_op(shift_op),.in_data_0(a),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(amt),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(y),.out_valid(out_valid),.out_ready(out_ready));

  function automatic logic [31:0] sh(input logic [1:0] op,input logic [31:0] x,input logic [4:0] n);
    case(op)2'b01:sh=x>>n;2'b10:sh=$signed(x)>>>n;default:sh=x<<n;endcase
  endfunction
  task automatic check(input logic [1:0] op,input logic [63:0] x,input logic [63:0] n);begin
    shift_op=op;a=x;amt=n;in_valid_0=1;in_valid_1=1;out_ready=1;#1;
    if(y[31:0]!==sh(op,x[31:0],n[4:0])||y[63:32]!==sh(op,x[63:32],n[36:32]))begin $display("FAIL data op=%b a=%h n=%h got=%h",op,x,n,y);errors++;end
    if(out_valid!==1||in_ready_0!==1||in_ready_1!==1)begin $display("FAIL handshake");errors++;end
  end endtask
  initial begin
    errors=0;a='0;amt='0;shift_op=0;in_valid_0=0;in_valid_1=0;out_ready=0;
    check(2'b00,64'h0000_0000_0000_00FF,64'h0000_0000_0000_0008);
    check(2'b01,64'hFF00_0000_8000_0000,64'h0000_001F_0000_0001);
    check(2'b10,64'hFF00_0000_8000_0000,64'h0000_0005_0000_000B);
    check(2'b11,64'h1234_5678_9ABC_DEF0,64'h0000_0001_0000_001F);
    in_valid_0=1;in_valid_1=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0||in_ready_1!==0)begin $display("FAIL backpressure");errors++;end
    in_valid_1=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL incomplete join");errors++;end
    for(int i=0;i<NRAND;i++)check($random,{$random,$random},{$random,$random});
    if(errors==0)$display("PASS: fu_barrel_shift_32x2, %0d random vectors",NRAND);else begin $display("FAIL: fu_barrel_shift_32x2 %0d mismatches",errors);$fatal(1);end
    $finish;
  end
endmodule : tb_fu_barrel_shift_32x2
