// tb_fu_int_to_fp_decomp.sv -- Self-checking TB for fu_int_to_fp_decomp (unary).
// Drive (mode, is_signed, a=integer), settle, compare per lane to a DPI-C golden (trusted C
// int->float casts). Bit-exact (integer conversions never produce NaN). Directed corners
// (0, +-small, powers of two, rounding, max/min, unsigned-max->Inf) + randomized. Testbench only.
`timescale 1ns/1ps

module tb_fu_int_to_fp_decomp #(
  parameter int unsigned NRAND = 20000
);
  import "DPI-C" function longint unsigned g_fp64_i2f(input longint unsigned a, input int is_signed);
  import "DPI-C" function int unsigned      g_fp32_i2f(input int unsigned a, input int is_signed);
  import "DPI-C" function int unsigned      g_fp16_i2f(input int unsigned a, input int is_signed);

  logic        clk, rst_n;
  logic [1:0]  mode;
  logic        is_signed;
  logic [63:0] in_data_0;
  logic        in_valid_0, in_ready_0;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_int_to_fp_decomp dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .is_signed(is_signed),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  function automatic logic [63:0] golden(input logic [1:0] m, input logic sgn, input logic [63:0] a);
    logic [63:0] r;
    logic [31:0] si;
    begin : gbody
      si = {31'b0, sgn};
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = g_fp32_i2f(a[31:0],  si);
          r[63:32] = g_fp32_i2f(a[63:32], si);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = g_fp16_i2f({16'b0, a[15:0]},  si);
          r[31:16] = g_fp16_i2f({16'b0, a[31:16]}, si);
          r[47:32] = g_fp16_i2f({16'b0, a[47:32]}, si);
          r[63:48] = g_fp16_i2f({16'b0, a[63:48]}, si);
        end : g4x16
        default: r = g_fp64_i2f(a, si);   // 1x64 and reserved 11
      endcase
      golden = r;
    end : gbody
  endfunction

  task automatic check_vec(input logic [1:0] m, input logic sgn, input logic [63:0] a);
    logic [63:0] exp;
    begin : cv
      mode = m; is_signed = sgn; in_data_0 = a;
      in_valid_0 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, sgn, a);
      if (out_data !== exp) begin : mism
        $display("FAIL data: mode=%02b sgn=%b a=%h got=%h exp=%h", m, sgn, a, out_data, exp);
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

  task automatic check_backpressure(input logic [1:0] m, input logic sgn, input logic [63:0] a);
    begin : bp
      mode = m; is_signed = sgn; in_data_0 = a;
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
      mode = 2'b00; is_signed = 1'b0; in_data_0 = '0;
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
    logic        sgn;

    error_count = 0;
    mode = 2'b00; is_signed = 1'b0; in_data_0 = '0;
    in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed fp64 (mode 00), signed and unsigned ----
    check_vec(2'b00, 1'b1, 64'd0);
    check_vec(2'b00, 1'b1, 64'd5);                        // 5.0
    check_vec(2'b00, 1'b1, 64'hFFFFFFFFFFFFFFFF);         // signed -1 -> -1.0
    check_vec(2'b00, 1'b0, 64'hFFFFFFFFFFFFFFFF);         // uint64 max -> 2^64
    check_vec(2'b00, 1'b1, 64'h0010000000000000);         // 2^52 (exact boundary)
    check_vec(2'b00, 1'b1, 64'h0020000000000001);         // 2^53+1 (rounding)
    check_vec(2'b00, 1'b1, 64'h7FFFFFFFFFFFFFFF);         // max int64
    check_vec(2'b00, 1'b1, 64'h8000000000000000);         // min int64 -> -2^63
    check_vec(2'b00, 1'b0, 64'h8000000000000000);         // 2^63 unsigned

    // ---- Directed fp32 (mode 01) ----
    check_vec(2'b01, 1'b1, {32'hFFFFFFFF, 32'd7});         // l0 7, l1 -1 (signed)
    check_vec(2'b01, 1'b0, {32'd16777217, 32'd16777217}); // 2^24+1 (rounding), unsigned
    check_vec(2'b01, 1'b1, {32'h80000000, 32'h7FFFFFFF});  // min/max int32

    // ---- Directed fp16 (mode 10): four independent lanes ----
    check_vec(2'b10, 1'b1, {16'hFFFF, 16'd2048, 16'd5, 16'd0});   // -1, 2048, 5, 0 (signed)
    check_vec(2'b10, 1'b0, {16'hFFFF, 16'd32768, 16'd32767, 16'd1024}); // uint: 65535->inf, 32768, 32767, 1024
    check_vec(2'b10, 1'b1, {16'h8000, 16'd100, 16'hFF9C, 16'd12345}); // -32768, 100, -100, 12345

    // reserved mode -> int64->fp64
    check_vec(2'b11, 1'b1, 64'd42);

    // ---- Handshake corners ----
    check_backpressure(2'b10, 1'b1, {16'd1, 16'd2, 16'd3, 16'd4});
    check_input_invalid;

    // ---- Uniform random ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random}; m = $random; sgn = $random;
      check_vec(m, sgn, a);
    end : rl
    // ---- Large-magnitude random (stress rounding / overflow) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl2
      a = {$random, $random} | 64'hF000_F000_F000_F000;
      m = $random; sgn = $random;
      check_vec(m, sgn, a);
    end : rl2

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_int_to_fp_decomp all modes, %0d+%0d random vectors, 0 mismatches",
               NRAND, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_int_to_fp_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_int_to_fp_decomp
