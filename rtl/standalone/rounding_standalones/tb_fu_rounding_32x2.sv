// Self-checking Verilator TB for standalone 2xFP32 round-to-integral.
module tb_fu_rounding_32x2 #(
  parameter int unsigned NRAND = 20000
);
  import "DPI-C" function int unsigned g_fp32_round(input int unsigned a, input int rm);

  logic [2:0] round_mode;
  logic [63:0] in_data_0, out_data;
  logic in_valid_0, in_ready_0, out_valid, out_ready;
  integer errors;

  fu_rounding_32x2 dut (
    .clk(1'b0), .rst_n(1'b1), .round_mode(round_mode),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic bit is_nan32(input logic [31:0] x);
    return (&x[30:23]) && (|x[22:0]);
  endfunction

  task automatic check_vec(input logic [2:0] rm, input logic [63:0] x);
    logic [31:0] exp0, exp1;
    begin
      round_mode=rm; in_data_0=x; in_valid_0=1'b1; out_ready=1'b1; #1;
      exp0=g_fp32_round(x[31:0], {29'd0,rm}); exp1=g_fp32_round(x[63:32], {29'd0,rm});
      if (!((out_data[31:0]===exp0)||(is_nan32(out_data[31:0])&&is_nan32(exp0))) ||
          !((out_data[63:32]===exp1)||(is_nan32(out_data[63:32])&&is_nan32(exp1)))) begin
        $display("FAIL data: rm=%b x=%h got=%h exp=%h_%h",rm,x,out_data,exp1,exp0); errors++;
      end
      if(out_valid!==1||in_ready_0!==1)begin $display("FAIL handshake");errors++;end
    end
  endtask

  initial begin
    errors=0;round_mode=3'b010;in_data_0='0;in_valid_0=0;out_ready=0;
    for(int r=0;r<8;r++)begin
      check_vec(r[2:0],64'h4020_0000_C020_0000); // +2.5, -2.5
      check_vec(r[2:0],64'h3F00_0000_BF00_0000); // +0.5, -0.5
      check_vec(r[2:0],64'h7FC0_0000_7F80_0000); // NaN, +Inf
      check_vec(r[2:0],64'h8000_0000_0000_0001); // -0, subnormal
    end
    in_valid_0=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0)begin $display("FAIL backpressure");errors++;end
    in_valid_0=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL invalid");errors++;end
    for(int i=0;i<NRAND;i++)check_vec($random,{$random,$random});
    if(errors==0)$display("PASS: fu_rounding_32x2, %0d random vectors",NRAND);
    else begin $display("FAIL: fu_rounding_32x2 %0d mismatches",errors);$fatal(1);end
    $finish;
  end
endmodule : tb_fu_rounding_32x2
