// Self-checking Verilator TB for standalone 4xFP16 round-to-integral.
module tb_fu_rounding_16x4 #(
  parameter int unsigned NRAND = 20000
);
  import "DPI-C" function int unsigned g_fp16_round(input int unsigned a, input int rm);

  logic [2:0] round_mode;
  logic [63:0] in_data_0, out_data;
  logic in_valid_0, in_ready_0, out_valid, out_ready;
  integer errors;

  fu_rounding_16x4 dut (
    .clk(1'b0), .rst_n(1'b1), .round_mode(round_mode),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic bit is_nan16(input logic [15:0] x);
    return (&x[14:10]) && (|x[9:0]);
  endfunction

  task automatic check_vec(input logic [2:0] rm, input logic [63:0] x);
    logic [15:0] exp;
    begin
      round_mode=rm;in_data_0=x;in_valid_0=1'b1;out_ready=1'b1;#1;
      for(int l=0;l<4;l++)begin
        exp=16'(g_fp16_round({16'd0,x[l*16 +: 16]},{29'd0,rm}));
        if(!((out_data[l*16 +: 16]===exp)||(is_nan16(out_data[l*16 +: 16])&&is_nan16(exp))))begin
          $display("FAIL data: rm=%b lane=%0d x=%h got=%h exp=%h",rm,l,x[l*16 +: 16],out_data[l*16 +: 16],exp);errors++;
        end
      end
      if(out_valid!==1||in_ready_0!==1)begin $display("FAIL handshake");errors++;end
    end
  endtask

  initial begin
    errors=0;round_mode=3'b010;in_data_0='0;in_valid_0=0;out_ready=0;
    for(int r=0;r<8;r++)begin
      check_vec(r[2:0],64'h4100_C100_3800_B800); // +2.5,-2.5,+0.5,-0.5
      check_vec(r[2:0],64'h7E00_7C00_8000_0001); // NaN,+Inf,-0,subnormal
      check_vec(r[2:0],64'h4300_C300_4000_C000); // +3.5,-3.5,+2,-2
    end
    in_valid_0=1;out_ready=0;#1;if(out_valid!==1||in_ready_0!==0)begin $display("FAIL backpressure");errors++;end
    in_valid_0=0;out_ready=1;#1;if(out_valid!==0||in_ready_0!==0)begin $display("FAIL invalid");errors++;end
    for(int i=0;i<NRAND;i++)check_vec($random,{$random,$random});
    if(errors==0)$display("PASS: fu_rounding_16x4, %0d random vectors",NRAND);
    else begin $display("FAIL: fu_rounding_16x4 %0d mismatches",errors);$fatal(1);end
    $finish;
  end
endmodule : tb_fu_rounding_16x4
