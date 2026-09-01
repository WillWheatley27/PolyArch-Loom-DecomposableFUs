// Self-checking Verilator TB for fu_mult_32x2.
module tb_fu_mult_32x2 #(
  parameter int unsigned NRAND = 20000
);
  logic [63:0] a, b, y;
  logic        in_valid_0, in_valid_1, in_ready_0, in_ready_1;
  logic        out_valid, out_ready;
  integer     errors;

  fu_mult_32x2 dut (
    .clk(1'b0), .rst_n(1'b1),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(b), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic logic [63:0] golden(input logic [63:0] x,
                                         input logic [63:0] z);
    logic [63:0] r;
    begin
      r = '0;
      for (int l = 0; l < 2; l++) r[l*32 +: 32] = x[l*32 +: 32] * z[l*32 +: 32];
      golden = r;
    end
  endfunction

  task automatic check_vec(input logic [63:0] x, input logic [63:0] z);
    logic [63:0] exp;
    begin
      a = x; b = z; in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1; #1;
      exp = golden(x, z);
      if (y !== exp) begin
        $display("FAIL data: a=%h b=%h got=%h exp=%h", x, z, y, exp); errors++;
      end
      if (out_valid !== 1'b1 || in_ready_0 !== 1'b1 || in_ready_1 !== 1'b1) begin
        $display("FAIL handshake: out_valid=%b ready=%b/%b", out_valid, in_ready_0, in_ready_1);
        errors++;
      end
    end
  endtask

  initial begin
    errors = 0; a = '0; b = '0; in_valid_0 = 0; in_valid_1 = 0; out_ready = 0;

    // Low-word products must not carry into the other lane.
    check_vec(64'h0000_0000_FFFF_FFFF, 64'h0000_0000_0000_0002);
    check_vec(64'hFFFF_FFFF_FFFF_FFFF, 64'h0000_0001_0000_0001);
    check_vec(64'h0000_0001_0000_0001, 64'h0000_0001_0000_0001);

    a = 64'hDEAD_BEEF_CAFE_F00D; b = 64'h0123_4567_89AB_CDEF;
    in_valid_0 = 1; in_valid_1 = 1; out_ready = 0; #1;
    if (out_valid !== 1'b1 || in_ready_0 !== 1'b0 || in_ready_1 !== 1'b0) begin
      $display("FAIL backpressure"); errors++;
    end
    in_valid_1 = 0; out_ready = 1; #1;
    if (out_valid !== 1'b0 || in_ready_0 !== 1'b0) begin
      $display("FAIL incomplete join"); errors++;
    end

    for (int i = 0; i < NRAND; i++) check_vec({$random, $random}, {$random, $random});
    if (errors == 0) $display("PASS: fu_mult_32x2, %0d random vectors", NRAND);
    else begin $display("FAIL: fu_mult_32x2 %0d mismatches", errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_mult_32x2
