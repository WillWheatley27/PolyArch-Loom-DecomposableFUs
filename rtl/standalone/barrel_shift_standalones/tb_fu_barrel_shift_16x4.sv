// Self-checking Verilator TB for standalone 4x16 barrel shift.
module tb_fu_barrel_shift_16x4 #(
  parameter int unsigned NRAND = 20000
);
  logic [1:0] shift_op; logic [63:0] a, amt, y;
  logic in_valid_0, in_valid_1, in_ready_0, in_ready_1, out_valid, out_ready;
  integer errors;
  fu_barrel_shift_16x4 dut (.clk(1'b0),.rst_n(1'b1),.shift_op(shift_op),.in_data_0(a),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(amt),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(y),.out_valid(out_valid),.out_ready(out_ready));

  function automatic logic [15:0] sh(input logic [1:0] op,input logic [15:0] x,input logic [3:0] n);
    case(op)2'b01:sh=x>>n;2'b10:sh=$signed(x)>>>n;default:sh=x<<n;endcase
  endfunction
  task automatic check(input logic [1:0] op,input logic [63:0] x,input logic [63:0] n);begin
    shift_op=op;a=x;amt=n;in_valid_0=1;in_valid_1=1;out_ready=1;#1;
    for(int l=0;l<4;l++)if(y[l*16 +: 16]!==sh(op,x[l*16 +: 16],n[l*16 +: 4]))begin $display("FAIL data op=%b lane=%0d a=%h n=%h got=%h",op,l,x,n,y[l*16 +: 16]);errors++;end
    if(out_valid!==1||in_ready_0!==1||in_ready_1!==1)begin $display("FAIL handshake");errors++;end
  end endtask
  initial begin
    errors=0;a='0;amt='0;shift_op=0;in_valid_0=0;in_valid_1=0;out_ready=0;
    check(2'b00,64'h0001_0001_0001_0001,64'h000F_0008_0001_0004);
    check(2'b01,64'hF000_0F00_00F0_000F,64'h0004_0004_0004_0004);
    check(2'b10,64'h8000_8000_8000_8000,64'h0004_0004_0004_0004);
    check(2'b11,64'h1234_5678_9ABC_DEF0,64'h0003_0007_000A_000F);
    in_valid_0=1;in_valid_1=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0||in_ready_1!==0)begin $display("FAIL backpressure");errors++;end
    in_valid_1=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL incomplete join");errors++;end
    for(int i=0;i<NRAND;i++)check($random,{$random,$random},{$random,$random});
    if(errors==0)$display("PASS: fu_barrel_shift_16x4, %0d random vectors",NRAND);else begin $display("FAIL: fu_barrel_shift_16x4 %0d mismatches",errors);$fatal(1);end
    $finish;
  end
endmodule : tb_fu_barrel_shift_16x4
