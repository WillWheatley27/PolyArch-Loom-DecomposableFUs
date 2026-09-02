// Self-checking Verilator TB for standalone 4x16 absolute value.
module tb_fu_abs_16x4 #(parameter int unsigned NRAND = 20000);
  logic is_float;
  logic [63:0] a, y;
  logic in_valid_0, in_ready_0, out_valid, out_ready;
  integer errors;

  fu_abs_16x4 dut (
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
      for (int i=0; i<4; i++) r[i*16 +: 16] = lane_abs(16, isf, x >> (i*16));
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
    check_vec(1'b0,64'h8000_FFFF_7FFF_0001); // INT_MIN,-1,+max,+1
    check_vec(1'b0,64'h7FFF_8000_8000_FFFF);
    check_vec(1'b1,64'hC000_BC00_3C00_8000); // -2,-1,+1,-0
    check_vec(1'b1,64'h7E00_7C00_FC00_0000); // NaN,+Inf,-Inf,+0
    check_vec(1'b1,64'h8001_0001_FBFF_7BFF); // signed subnormals and finite values

    a=64'hDEAD_BEEF_CAFE_F00D; in_valid_0=1; out_ready=0; #1;
    if (out_valid!==1'b1 || in_ready_0!==1'b0) begin $display("FAIL backpressure"); errors++; end
    in_valid_0=0; out_ready=1; #1;
    if (out_valid!==1'b0 || in_ready_0!==1'b0) begin $display("FAIL invalid"); errors++; end

    for (int i=0; i<NRAND; i++)
      check_vec(($urandom % 2), {$urandom,$urandom});
    if (errors==0) $display("PASS: fu_abs_16x4, %0d random vectors", NRAND);
    else begin $display("FAIL: fu_abs_16x4 %0d errors", errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_abs_16x4
