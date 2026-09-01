// Self-checking Verilator TB for fu_add_sub_8x8.
module tb_fu_add_sub_8x8 #(
  parameter int unsigned NRAND = 20000
);
  logic [7:0]  op_sel;
  logic [63:0] a, b, y;
  logic        in_valid_0, in_valid_1, in_ready_0, in_ready_1;
  logic        out_valid, out_ready;
  integer     errors;

  fu_add_sub_8x8 dut (
    .clk(1'b0), .rst_n(1'b1), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(b), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic logic [63:0] golden(input logic [7:0] ops,
                                         input logic [63:0] x,
                                         input logic [63:0] z);
    logic [63:0] r;
    begin
      r = '0;
      for (int l = 0; l < 8; l++) begin
        r[l*8 +: 8] = ops[l]
          ? (x[l*8 +: 8] - z[l*8 +: 8])
          : (x[l*8 +: 8] + z[l*8 +: 8]);
      end
      golden = r;
    end
  endfunction

  task automatic check_vec(input logic [7:0] ops,
                           input logic [63:0] x, input logic [63:0] z);
    logic [63:0] exp;
    begin
      op_sel = ops; a = x; b = z;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(ops, x, z);
      if (y !== exp) begin
        $display("FAIL data: op=%b a=%h b=%h got=%h exp=%h", ops, x, z, y, exp);
        errors = errors + 1;
      end
      if (out_valid !== 1'b1 || in_ready_0 !== 1'b1 || in_ready_1 !== 1'b1) begin
        $display("FAIL handshake: op=%b out_valid=%b ready=%b/%b", ops, out_valid,
                 in_ready_0, in_ready_1);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    errors = 0;
    a = '0; b = '0; op_sel = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0;

    // Carry/borrow must stop at every 8-bit boundary.
    check_vec(8'b0000_0000, 64'h0000_0000_0000_00FF, 64'h1);
    check_vec(8'b1111_1111, 64'h0000_0000_0000_0000, 64'h0101_0101_0101_0101);
    check_vec(8'b1010_0101, 64'h1122_3344_5566_7788, 64'h0102_0304_0506_0708);

    op_sel = 8'b1010_0101; a = 64'hDEAD_BEEF_CAFE_F00D; b = 64'h0123_4567_89AB_CDEF;
    in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0; #1;
    if (out_valid !== 1'b1 || in_ready_0 !== 1'b0 || in_ready_1 !== 1'b0) begin
      $display("FAIL backpressure"); errors = errors + 1;
    end
    in_valid_1 = 1'b0; out_ready = 1'b1; #1;
    if (out_valid !== 1'b0 || in_ready_0 !== 1'b0) begin
      $display("FAIL incomplete join"); errors = errors + 1;
    end

    for (int i = 0; i < NRAND; i++) begin
      check_vec($random, {$random, $random}, {$random, $random});
    end

    if (errors == 0) $display("PASS: fu_add_sub_8x8, %0d random vectors", NRAND);
    else begin $display("FAIL: fu_add_sub_8x8 %0d mismatches", errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_add_sub_8x8
