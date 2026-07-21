// tb_fu_abs_decomp.sv -- Self-checking TB for fu_abs_decomp (packed absolute value).
// Drive (mode, is_float, a), settle, compare per lane to a native-SV golden: absf clears the
// lane sign bit; absi = msb ? -lane : lane. Bit-exact. Directed corners (absf +-0/+-Inf/NaN;
// absi +-int/INT_MIN) + randomized. Testbench only.
`timescale 1ns/1ps

module tb_fu_abs_decomp #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic        is_float;
  logic [63:0] in_data_0;
  logic        in_valid_0, in_ready_0;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_abs_decomp dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .is_float(is_float),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  function automatic logic [15:0] abs16(input logic isf, input logic [15:0] x);
    abs16 = isf ? (x & 16'h7FFF) : (x[15] ? (-x) : x);
  endfunction
  function automatic logic [31:0] abs32(input logic isf, input logic [31:0] x);
    abs32 = isf ? (x & 32'h7FFFFFFF) : (x[31] ? (-x) : x);
  endfunction
  function automatic logic [63:0] abs64(input logic isf, input logic [63:0] x);
    abs64 = isf ? (x & 64'h7FFFFFFFFFFFFFFF) : (x[63] ? (-x) : x);
  endfunction

  function automatic logic [63:0] golden(input logic [1:0] m, input logic isf, input logic [63:0] a);
    logic [63:0] r;
    begin : gbody
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = abs32(isf, a[31:0]);
          r[63:32] = abs32(isf, a[63:32]);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = abs16(isf, a[15:0]);
          r[31:16] = abs16(isf, a[31:16]);
          r[47:32] = abs16(isf, a[47:32]);
          r[63:48] = abs16(isf, a[63:48]);
        end : g4x16
        default: r = abs64(isf, a);   // 1x64 and reserved 11
      endcase
      golden = r;
    end : gbody
  endfunction

  task automatic check_vec(input logic [1:0] m, input logic isf, input logic [63:0] a);
    logic [63:0] exp;
    begin : cv
      mode = m; is_float = isf; in_data_0 = a;
      in_valid_0 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, isf, a);
      if (out_data !== exp) begin : mism
        $display("FAIL data: mode=%02b isf=%b a=%h got=%h exp=%h", m, isf, a, out_data, exp);
        error_count = error_count + 1;
      end : mism
      if (out_valid !== 1'b1) begin : vlo
        $display("FAIL out_valid low (mode=%02b a=%h)", m, a);
        error_count = error_count + 1;
      end : vlo
      if (in_ready_0 !== 1'b1) begin : rlo
        $display("FAIL in_ready_0 low with out_ready & out_valid (a=%h)", a);
        error_count = error_count + 1;
      end : rlo
    end : cv
  endtask

  task automatic check_backpressure(input logic [1:0] m, input logic isf, input logic [63:0] a);
    begin : bp
      mode = m; is_float = isf; in_data_0 = a;
      in_valid_0 = 1'b1; out_ready = 1'b0;
      #1;
      if (out_valid !== 1'b1) begin : bpv
        $display("FAIL backpressure: out_valid must stay high");
        error_count = error_count + 1;
      end : bpv
      if (in_ready_0 !== 1'b0) begin : bpr
        $display("FAIL backpressure: in_ready_0 must be low when out_ready=0");
        error_count = error_count + 1;
      end : bpr
    end : bp
  endtask

  task automatic check_input_invalid;
    begin : ii
      mode = 2'b00; is_float = 1'b0; in_data_0 = '0;
      in_valid_0 = 1'b0; out_ready = 1'b1;
      #1;
      if (out_valid !== 1'b0) begin : iiv
        $display("FAIL: out_valid high when in_valid_0=0");
        error_count = error_count + 1;
      end : iiv
      if (in_ready_0 !== 1'b0) begin : iir
        $display("FAIL: in_ready_0 high when in_valid_0=0");
        error_count = error_count + 1;
      end : iir
    end : ii
  endtask

  initial begin : main
    integer      i;
    logic [63:0] a;
    logic [1:0]  m;
    logic        isf;

    error_count = 0;
    mode = 2'b00; is_float = 1'b0; in_data_0 = '0;
    in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed absf (is_float=1) ----
    check_vec(2'b00, 1'b1, 64'hBFF0000000000000); // -1.0 -> +1.0
    check_vec(2'b00, 1'b1, 64'h8000000000000000); // -0.0 -> +0.0
    check_vec(2'b00, 1'b1, 64'hFFF0000000000000); // -Inf -> +Inf
    check_vec(2'b00, 1'b1, 64'hFFF8000000000000); // -NaN -> +NaN (sign cleared)
    check_vec(2'b00, 1'b1, 64'h8000000000000001); // -min subnormal
    check_vec(2'b10, 1'b1, 64'h8000_BC00_7C00_FE00); // fp16 lanes: -0, -1.0, +Inf, -NaN
    check_vec(2'b01, 1'b1, 64'hBF800000_C0000000);   // fp32: -1.0, -2.0

    // ---- Directed absi (is_float=0) ----
    check_vec(2'b00, 1'b0, 64'hFFFFFFFFFFFFFFFF); // -1 -> 1
    check_vec(2'b00, 1'b0, 64'h8000000000000000); // INT64_MIN -> itself (wrap)
    check_vec(2'b00, 1'b0, 64'h0000000000000005); // 5 -> 5
    check_vec(2'b10, 1'b0, 64'h8000_FFFF_7FFF_0001); // int16: -32768(wrap), -1, 32767, 1
    check_vec(2'b01, 1'b0, 64'h80000000_FFFFFFF6);   // int32: INT_MIN(wrap), -10

    // reserved mode 11 -> 1x64
    check_vec(2'b11, 1'b0, 64'hFFFFFFFFFFFFFFF0); // -16 -> 16
    check_vec(2'b11, 1'b1, 64'hC000000000000000); // -2.0 -> 2.0

    // ---- Handshake corners ----
    check_backpressure(2'b10, 1'b0, 64'h8001_7FFF_FFFF_0002);
    check_input_invalid;

    // ---- Randomized ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random}; m = $random; isf = $random;
      check_vec(m, isf, a);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_abs_decomp all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_abs_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_abs_decomp
