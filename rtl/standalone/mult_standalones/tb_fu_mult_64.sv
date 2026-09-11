// Self-checking Verilator TB for fu_mult_64.
module tb_fu_mult_64 #(parameter int unsigned NRAND = 20000);
  logic [63:0] a, b, y;
  logic in_valid_0, in_valid_1, in_ready_0, in_ready_1, out_valid, out_ready;
  integer errors;
  fu_mult_64 dut (.clk(1'b0), .rst_n(1'b1),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(b), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready));
  task automatic check_vec(input logic [63:0] x, input logic [63:0] z);
    logic [127:0] p;
    begin
      a=x; b=z; in_valid_0=1; in_valid_1=1; out_ready=1; #1;
      p = x * z;
      if (y !== p[63:0]) begin $display("FAIL a=%h b=%h got=%h exp=%h",x,z,y,p[63:0]); errors++; end
      if (!out_valid || !in_ready_0 || !in_ready_1) errors++;
    end
  endtask
  initial begin
    errors=0; a='0; b='0; in_valid_0=0; in_valid_1=0; out_ready=0;
    check_vec(64'hffff_ffff_ffff_ffff, 64'h2);
    check_vec(64'h0000_0001_0000_0001, 64'h0000_0001_0000_0001);
    for (int i=0;i<NRAND;i++) check_vec({$random,$random}, {$random,$random});
    if (errors==0) $display("PASS: fu_mult_64, %0d random vectors", NRAND);
    else begin $display("FAIL: fu_mult_64 %0d errors", errors); $fatal(1); end
    $finish;
  end
endmodule
