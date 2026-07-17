// tb_fu_fp_to_int_decomp.sv -- Self-checking TB for fu_fp_to_int_decomp (unary).
// Drive (mode, is_signed, a=FP), settle, compare per lane to a DPI-C golden (saturating,
// round-toward-zero float->int, NaN->0). Bit-exact (integer output). Directed corners
// (trunc, saturate, +-Inf, NaN, +-0, subnormal) + randomized. Testbench only.
`timescale 1ns/1ps

module tb_fu_fp_to_int_decomp #(
  parameter int unsigned NRAND = 20000
);
  import "DPI-C" function longint unsigned g_fp64_f2i(input longint unsigned a, input int is_signed);
  import "DPI-C" function int unsigned      g_fp32_f2i(input int unsigned a, input int is_signed);
  import "DPI-C" function int unsigned      g_fp16_f2i(input int unsigned a, input int is_signed);

  logic        clk, rst_n;
  logic [1:0]  mode;
  logic        is_signed;
  logic [63:0] in_data_0;
  logic        in_valid_0, in_ready_0;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_fp_to_int_decomp dut (
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
          r[31:0]  = g_fp32_f2i(a[31:0],  si);
          r[63:32] = g_fp32_f2i(a[63:32], si);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = g_fp16_f2i({16'b0, a[15:0]},  si);
          r[31:16] = g_fp16_f2i({16'b0, a[31:16]}, si);
          r[47:32] = g_fp16_f2i({16'b0, a[47:32]}, si);
          r[63:48] = g_fp16_f2i({16'b0, a[63:48]}, si);
        end : g4x16
        default: r = g_fp64_f2i(a, si);   // 1x64 and reserved 11
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

  // fp64 test values
  localparam logic [63:0] D_1p5 = 64'h3FF8000000000000, D_N1p5 = 64'hBFF8000000000000;
  localparam logic [63:0] D_2p7 = 64'h4005999999999999, D_N2p7 = 64'hC005999999999999;
  localparam logic [63:0] D_0p5 = 64'h3FE0000000000000, D_2P63 = 64'h43E0000000000000; // 2^63
  localparam logic [63:0] D_INF = 64'h7FF0000000000000, D_NIN  = 64'hFFF0000000000000;
  localparam logic [63:0] D_NAN = 64'h7FF8000000000000, D_NZ   = 64'h8000000000000000;
  localparam logic [63:0] D_100 = 64'h4059000000000000, D_SUB  = 64'h0000000000000001;
  // fp32 test values
  localparam logic [31:0] S_1p5 = 32'h3FC00000, S_N2p7 = 32'hC02CCCCD, S_2P31 = 32'h4F000000; // 2^31
  localparam logic [31:0] S_INF = 32'h7F800000, S_NAN = 32'h7FC00000, S_100 = 32'h42C80000;
  // fp16 test values
  localparam logic [15:0] H_1p5 = 16'h3E00, H_N2p7 = 16'hC164, H_BIG = 16'h7800; // 32768
  localparam logic [15:0] H_INF = 16'h7C00, H_NAN = 16'h7E00, H_NZ = 16'h8000, H_100 = 16'h5640;

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
    check_vec(2'b00, 1'b1, D_1p5);    check_vec(2'b00, 1'b1, D_N1p5);   // 1, -1
    check_vec(2'b00, 1'b1, D_2p7);    check_vec(2'b00, 1'b1, D_N2p7);   // 2, -2
    check_vec(2'b00, 1'b0, D_N2p7);                                     // unsigned neg -> 0
    check_vec(2'b00, 1'b1, D_0p5);    check_vec(2'b00, 1'b0, D_NZ);     // 0.5->0 ; -0->0
    check_vec(2'b00, 1'b1, D_2P63);   check_vec(2'b00, 1'b0, D_2P63);   // 2^63: signed sat max, unsigned ok
    check_vec(2'b00, 1'b1, D_INF);    check_vec(2'b00, 1'b1, D_NIN);    // +-Inf signed saturate
    check_vec(2'b00, 1'b0, D_INF);    check_vec(2'b00, 1'b0, D_NIN);    // Inf unsigned max ; -Inf -> 0
    check_vec(2'b00, 1'b1, D_NAN);    check_vec(2'b00, 1'b1, D_100);    // NaN->0 ; 100
    check_vec(2'b00, 1'b1, D_SUB);                                      // subnormal -> 0

    // ---- Directed fp32 (mode 01) ----
    check_vec(2'b01, 1'b1, {S_N2p7, S_1p5});     // -2, 1
    check_vec(2'b01, 1'b1, {S_2P31, S_INF});     // 2^31 sat max, +Inf sat max
    check_vec(2'b01, 1'b0, {S_NAN,  S_100});     // NaN->0, 100

    // ---- Directed fp16 (mode 10): four independent lanes ----
    check_vec(2'b10, 1'b1, {H_INF, H_BIG, H_N2p7, H_1p5}); // +Inf sat, 32768 sat max, -2, 1
    check_vec(2'b10, 1'b0, {H_NZ,  H_BIG, H_NAN,  H_100}); // -0->0, 32768, NaN->0, 100 (unsigned)
    check_vec(2'b10, 1'b1, {H_NAN, H_100, H_N2p7, H_1p5});

    // reserved mode -> fp64->int64
    check_vec(2'b11, 1'b1, D_2p7);

    // ---- Handshake corners ----
    check_backpressure(2'b10, 1'b1, {H_1p5, H_100, H_N2p7, H_INF});
    check_input_invalid;

    // ---- Uniform random ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random}; m = $random; sgn = $random;
      check_vec(m, sgn, a);
    end : rl
    // ---- Large-magnitude random (stress saturation) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl2
      a = {$random, $random} | 64'h4380_5380_5380_5380;   // bias exponents large
      m = $random; sgn = $random;
      check_vec(m, sgn, a);
    end : rl2

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_fp_to_int_decomp all modes, %0d+%0d random vectors, 0 mismatches",
               NRAND, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_fp_to_int_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_fp_to_int_decomp
