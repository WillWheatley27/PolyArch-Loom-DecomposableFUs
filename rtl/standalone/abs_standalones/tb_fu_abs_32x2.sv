// Self-checking Verilator TB for standalone 2x32 absolute value.
module tb_fu_abs_32x2 #(parameter int unsigned NRAND = 20000);
  logic is_float;
  logic [63:0] a, y;
  logic in_valid_0, in_ready_0, out_valid, out_ready;
  integer errors;

  fu_abs_32x2 dut (
    .clk(1'b0), .rst_n(1'b1), .is_float(is_float),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic logic [63:0] lane_abs(input int W, input logic isf,
                                            input logic [63:0] x);
    logic [63:0] mask, v;
    begin
      mask = (W == 64) ? {64{1'b1}} : ((64'd1 << W) - 64'd1);
      v = x & mask;
      if (isf) lane_abs = v & ~(64'd1 << (W-1));
      else     lane_abs = v[W-1] ? ((~v + 64'd1) & mask) : v;
    end
  endfunction

  function automatic logic [63:0] golden(input logic isf, input logic [63:0] x);
    logic [63:0] r;
    begin
      r[31:0]  = lane_abs(32, isf, x[31:0]);
      r[63:32] = lane_abs(32, isf, x[63:32]);
      golden = r;
    end
  endfunction

  task automatic check_vec(input logic isf, input logic [63:0] x);
    logic [63:0] exp;
    begin
      is_float=isf; a=x; in_valid_0=1'b1; out_ready=1'b1; #1;
      exp=golden(isf,x);
      if (y !== exp) begin $display("FAIL data f=%b a=%h got=%h exp=%h",isf,x,y,exp); errors++; end
      if (out_valid!==1'b1 || in_ready_0!==1'b1) begin $display("FAIL handshake"); errors++; end
    end
  endtask

  initial begin
    errors=0; a='0; is_float=0; in_valid_0=0; out_ready=0;
    check_vec(1'b0,64'h8000_0000_FFFF_FFFF); // INT_MIN and -1
    check_vec(1'b0,64'h7FFF_FFFF_8000_0000); // +max and INT_MIN
    check_vec(1'b1,64'hBF80_0000_4000_0000); // -1.0 and +2.0
    check_vec(1'b1,64'h8000_0000_7FC0_0001); // -0 and negative NaN
    check_vec(1'b1,64'hFF80_0000_0000_0000); // -Inf and +0

    a=64'hDEAD_BEEF_1234_5678; in_valid_0=1; out_ready=0; #1;
    if (out_valid!==1'b1 || in_ready_0!==1'b0) begin $display("FAIL backpressure"); errors++; end
    in_valid_0=0; out_ready=1; #1;
    if (out_valid!==1'b0 || in_ready_0!==1'b0) begin $display("FAIL invalid"); errors++; end

    for (int i=0; i<NRAND; i++)
      check_vec(($urandom % 2), {$urandom,$urandom});
    if (errors==0) $display("PASS: fu_abs_32x2, %0d random vectors", NRAND);
    else begin $display("FAIL: fu_abs_32x2 %0d errors", errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_abs_32x2
