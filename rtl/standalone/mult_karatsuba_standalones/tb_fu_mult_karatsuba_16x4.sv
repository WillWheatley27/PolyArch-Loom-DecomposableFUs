`timescale 1ns/1ps
module tb_fu_mult_karatsuba_16x4 #(parameter int unsigned NRAND = 20000);
  logic [63:0] a, b, y;
  logic in_valid_0, in_valid_1, in_ready_0, in_ready_1, out_valid, out_ready;
  integer errors;

  fu_mult_karatsuba_16x4 dut (
    .clk(1'b0), .rst_n(1'b1),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(b), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic logic [63:0] golden(input logic [63:0] x, input logic [63:0] z);
    logic [63:0] r;
    begin
      for (int lane=0; lane<4; lane++)
        r[lane*16 +: 16] = x[lane*16 +: 16] * z[lane*16 +: 16];
      return r;
    end
  endfunction

  task automatic check_vec(input logic [63:0] x, input logic [63:0] z);
    logic [63:0] exp;
    begin
      a=x; b=z; in_valid_0=1; in_valid_1=1; out_ready=1; #1; exp=golden(x,z);
      if (y !== exp) begin
        $display("FAIL data: a=%h b=%h got=%h exp=%h", x, z, y, exp); errors++;
      end
      if (!out_valid || !in_ready_0 || !in_ready_1) begin $display("FAIL handshake"); errors++; end
    end
  endtask

  initial begin
    errors=0; a='0; b='0; in_valid_0=0; in_valid_1=0; out_ready=0;
    check_vec(64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff);
    check_vec(64'h0003_0002_0001_ffff, 64'h0005_0004_0003_ffff);
    check_vec(64'hffff_8000_7fff_8000, 64'h0002_0002_0002_0002);
    a='1; b=64'h2; in_valid_0=1; in_valid_1=1; out_ready=0; #1;
    if (!out_valid || in_ready_0 || in_ready_1) begin $display("FAIL backpressure"); errors++; end
    in_valid_1=0; out_ready=1; #1;
    if (out_valid || in_ready_0) begin $display("FAIL incomplete join"); errors++; end
    for (int i=0; i<NRAND; i++) check_vec({$random,$random}, {$random,$random});
    if (!errors) $display("PASS: fu_mult_karatsuba_16x4, %0d random vectors", NRAND);
    else begin $display("FAIL: fu_mult_karatsuba_16x4 %0d errors", errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_mult_karatsuba_16x4
