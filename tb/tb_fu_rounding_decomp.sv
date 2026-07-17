// tb_fu_rounding_decomp.sv -- Self-checking TB for fu_rounding_decomp (unary).
// Drive (mode, round_mode, a), settle, compare per lane to a DPI-C golden (C floor/ceil/
// trunc/round/rint on double/float/F16C). NaN-lenient (any qNaN); else bit-exact (incl signed
// zero). Directed corners (each mode, ties, ±0, Inf, NaN, subnormal) + randomized. Testbench only.
`timescale 1ns/1ps

module tb_fu_rounding_decomp #(
  parameter int unsigned NRAND = 20000
);
  import "DPI-C" function longint unsigned g_fp64_round(input longint unsigned a, input int rm);
  import "DPI-C" function int unsigned      g_fp32_round(input int unsigned a, input int rm);
  import "DPI-C" function int unsigned      g_fp16_round(input int unsigned a, input int rm);

  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [2:0]  round_mode;
  logic [63:0] in_data_0;
  logic        in_valid_0, in_ready_0;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_rounding_decomp dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .round_mode(round_mode),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  function automatic logic [63:0] golden(input logic [1:0]  m,
                                         input logic [2:0]  rm,
                                         input logic [63:0] a);
    logic [63:0] r;
    logic [31:0] rmi;
    begin : gbody
      rmi = {29'b0, rm};
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = g_fp32_round(a[31:0],  rmi);
          r[63:32] = g_fp32_round(a[63:32], rmi);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = g_fp16_round({16'b0, a[15:0]},  rmi);
          r[31:16] = g_fp16_round({16'b0, a[31:16]}, rmi);
          r[47:32] = g_fp16_round({16'b0, a[47:32]}, rmi);
          r[63:48] = g_fp16_round({16'b0, a[63:48]}, rmi);
        end : g4x16
        default: r = g_fp64_round(a, rmi);   // 1x64 and reserved 11
      endcase
      golden = r;
    end : gbody
  endfunction

  function automatic bit is_nan(input logic [63:0] v, input int EXP_W, input int MAN_W);
    logic [10:0] e;
    logic [51:0] man;
    begin : nb
      e   = (v >> MAN_W) & ((11'd1 << EXP_W) - 11'd1);
      man = v & ((64'd1 << MAN_W) - 64'd1);
      is_nan = (e == ((11'd1 << EXP_W) - 11'd1)) && (man != 52'd0);
    end : nb
  endfunction

  function automatic bit lane_ok(input logic [63:0] e, input logic [63:0] a,
                                 input int EXP_W, input int MAN_W);
    begin : lb
      if (is_nan(e, EXP_W, MAN_W)) lane_ok = is_nan(a, EXP_W, MAN_W);
      else                         lane_ok = (e === a);
    end : lb
  endfunction

  function automatic bit result_ok(input logic [1:0] m, input logic [63:0] e, input logic [63:0] a);
    bit ok;
    begin : rb
      case (m)
        2'b01: ok = lane_ok(e[31:0],  a[31:0],  8, 23) & lane_ok(e[63:32], a[63:32], 8, 23);
        2'b10: ok = lane_ok(e[15:0],  a[15:0],  5, 10) & lane_ok(e[31:16], a[31:16], 5, 10)
                  & lane_ok(e[47:32], a[47:32], 5, 10) & lane_ok(e[63:48], a[63:48], 5, 10);
        default: ok = lane_ok(e, a, 11, 52);
      endcase
      result_ok = ok;
    end : rb
  endfunction

  task automatic check_vec(input logic [1:0]  m,
                           input logic [2:0]  rm,
                           input logic [63:0] a);
    logic [63:0] exp;
    begin : cv
      mode = m; round_mode = rm; in_data_0 = a;
      in_valid_0 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, rm, a);
      if (!result_ok(m, exp, out_data)) begin : mism
        $display("FAIL data: mode=%02b rm=%03b a=%h got=%h exp=%h", m, rm, a, out_data, exp);
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

  task automatic check_backpressure(input logic [1:0] m, input logic [2:0] rm, input logic [63:0] a);
    begin : bp
      mode = m; round_mode = rm; in_data_0 = a;
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
      mode = 2'b00; round_mode = 3'b010; in_data_0 = '0;
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
  localparam logic [63:0] D_2p5 = 64'h4004000000000000, D_N2p5 = 64'hC004000000000000;
  localparam logic [63:0] D_3p5 = 64'h400C000000000000, D_0p5  = 64'h3FE0000000000000;
  localparam logic [63:0] D_N0p5= 64'hBFE0000000000000, D_0p3  = 64'h3FD3333333333333;
  localparam logic [63:0] D_N0p3= 64'hBFD3333333333333, D_2p0  = 64'h4000000000000000;
  localparam logic [63:0] D_BIG = 64'h4330000000000000, D_INF  = 64'h7FF0000000000000;
  localparam logic [63:0] D_NIN = 64'hFFF0000000000000, D_NAN  = 64'h7FF8000000000000;
  localparam logic [63:0] D_NZ  = 64'h8000000000000000, D_SUB  = 64'h0000000000000001;
  // fp16 test values
  localparam logic [15:0] H_2p5 = 16'h4100, H_3p5 = 16'h4300, H_0p5 = 16'h3800;
  localparam logic [15:0] H_N2p5= 16'hC100, H_N0p3= 16'hB4CD, H_INF = 16'h7C00;
  localparam logic [15:0] H_NAN = 16'h7E00, H_NZ  = 16'h8000, H_SUB = 16'h0001, H_2p0 = 16'h4000;
  // fp32 test values
  localparam logic [31:0] S_2p5 = 32'h40200000, S_N2p5= 32'hC0200000, S_0p5 = 32'h3F000000;
  localparam logic [31:0] S_INF = 32'h7F800000, S_NAN = 32'h7FC00000, S_0p3 = 32'h3E99999A;

  initial begin : main
    integer      i;
    logic [63:0] a;
    logic [1:0]  m;
    logic [2:0]  rm;

    error_count = 0;
    mode = 2'b00; round_mode = 3'b010; in_data_0 = '0;
    in_valid_0 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed fp64: sweep all modes on ties / fractions / specials ----
    for (rm = 3'b000; rm <= 3'b100; rm = rm + 3'b001) begin : sweep
      check_vec(2'b00, rm, D_2p5);   check_vec(2'b00, rm, D_N2p5);
      check_vec(2'b00, rm, D_3p5);   check_vec(2'b00, rm, D_0p5);
      check_vec(2'b00, rm, D_N0p5);  check_vec(2'b00, rm, D_0p3);
      check_vec(2'b00, rm, D_N0p3);  check_vec(2'b00, rm, D_2p0);
      check_vec(2'b00, rm, D_BIG);   check_vec(2'b00, rm, D_INF);
      check_vec(2'b00, rm, D_NIN);   check_vec(2'b00, rm, D_NAN);
      check_vec(2'b00, rm, D_NZ);    check_vec(2'b00, rm, D_SUB);
    end : sweep

    // reserved round_mode -> trunc
    check_vec(2'b00, 3'b111, D_2p5);
    check_vec(2'b00, 3'b101, D_N2p5);

    // ---- Directed fp16 (mode 10): four independent lanes, per mode ----
    check_vec(2'b10, 3'b000, {H_2p5, H_N2p5, H_0p5, H_N0p3});   // floor
    check_vec(2'b10, 3'b001, {H_2p5, H_N2p5, H_0p5, H_N0p3});   // ceil
    check_vec(2'b10, 3'b100, {H_2p5, H_3p5,  H_0p5, H_2p0});    // roundeven ties
    check_vec(2'b10, 3'b011, {H_INF, H_NAN,  H_NZ,  H_SUB});    // round: specials
    // ---- Directed fp32 (mode 01) ----
    check_vec(2'b01, 3'b011, {S_2p5, S_N2p5});                  // round ties away
    check_vec(2'b01, 3'b000, {S_INF, S_0p3});                   // floor: inf, 0.3
    check_vec(2'b01, 3'b100, {S_NAN, S_0p5});                   // roundeven: NaN, 0.5

    // ---- Handshake corners ----
    check_backpressure(2'b10, 3'b011, {H_2p5, H_3p5, H_0p5, H_2p0});
    check_input_invalid;

    // ---- Uniform random ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random}; m = $random; rm = $random;
      check_vec(m, rm, a);
    end : rl
    // ---- Small-exponent random (more sub-1 magnitudes, subnormals, fractions) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl2
      a = {$random, $random} & 64'h9FFF_9FFF_9FFF_9FFF;
      m = $random; rm = $random;
      check_vec(m, rm, a);
    end : rl2

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_rounding_decomp all modes, %0d+%0d random vectors, 0 mismatches",
               NRAND, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_rounding_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_rounding_decomp
