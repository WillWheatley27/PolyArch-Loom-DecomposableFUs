// tb_fu_fp_cmp_decomp.sv -- Self-checking TB for fu_fp_cmp_decomp (packed float compare).
// Drive (mode, pred, a, b), settle, compare per lane to a DPI-C golden (IEEE ordered/unordered
// compare) replicated to an all-ones/all-zeros mask. Bit-exact. Directed corners (every
// predicate, NaN/Inf/+-0, subnormal, per-lane isolation) + randomized. Testbench only.
`timescale 1ns/1ps

module tb_fu_fp_cmp_decomp #(
  parameter int unsigned NRAND = 20000
);
  import "DPI-C" function int g_fp64_cmpf(input longint unsigned a, input longint unsigned b, input int pred);
  import "DPI-C" function int g_fp32_cmpf(input int unsigned a, input int unsigned b, input int pred);
  import "DPI-C" function int g_fp16_cmpf(input int unsigned a, input int unsigned b, input int pred);

  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [3:0]  pred;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_fp_cmp_decomp dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready)
  );

  initial begin : clk_init
    clk = 1'b0;
  end
  always begin : clk_toggle
    #5 clk = ~clk;
  end

  function automatic logic [63:0] golden(input logic [1:0] m, input logic [3:0] p,
                                         input logic [63:0] a, input logic [63:0] b);
    logic [63:0] r;
    logic [31:0] pi;
    begin : gbody
      pi = {28'b0, p};
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = {32{(g_fp32_cmpf(a[31:0],  b[31:0],  pi) != 0)}};
          r[63:32] = {32{(g_fp32_cmpf(a[63:32], b[63:32], pi) != 0)}};
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = {16{(g_fp16_cmpf({16'b0, a[15:0]},  {16'b0, b[15:0]},  pi) != 0)}};
          r[31:16] = {16{(g_fp16_cmpf({16'b0, a[31:16]}, {16'b0, b[31:16]}, pi) != 0)}};
          r[47:32] = {16{(g_fp16_cmpf({16'b0, a[47:32]}, {16'b0, b[47:32]}, pi) != 0)}};
          r[63:48] = {16{(g_fp16_cmpf({16'b0, a[63:48]}, {16'b0, b[63:48]}, pi) != 0)}};
        end : g4x16
        default: r = {64{(g_fp64_cmpf(a, b, pi) != 0)}};   // 1x64 and reserved 11
      endcase
      golden = r;
    end : gbody
  endfunction

  task automatic check_vec(input logic [1:0] m, input logic [3:0] p,
                           input logic [63:0] a, input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; pred = p; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, p, a, b);
      if (out_data !== exp) begin : mism
        $display("FAIL data: mode=%02b pred=%0d a=%h b=%h got=%h exp=%h", m, p, a, b, out_data, exp);
        error_count = error_count + 1;
      end : mism
      if (out_valid !== 1'b1) begin : vlo
        $display("FAIL out_valid low (mode=%02b a=%h b=%h)", m, a, b);
        error_count = error_count + 1;
      end : vlo
      if ((in_ready_0 !== 1'b1) || (in_ready_1 !== 1'b1)) begin : rlo
        $display("FAIL in_ready low with out_ready & out_valid (a=%h b=%h)", a, b);
        error_count = error_count + 1;
      end : rlo
    end : cv
  endtask

  task automatic check_backpressure(input logic [1:0] m, input logic [3:0] p,
                                    input logic [63:0] a, input logic [63:0] b);
    begin : bp
      mode = m; pred = p; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b0;
      #1;
      if (out_valid !== 1'b1) begin : bpv
        $display("FAIL backpressure: out_valid must stay high");
        error_count = error_count + 1;
      end : bpv
      if ((in_ready_0 !== 1'b0) || (in_ready_1 !== 1'b0)) begin : bpr
        $display("FAIL backpressure: in_ready must be low when out_ready=0");
        error_count = error_count + 1;
      end : bpr
    end : bp
  endtask

  task automatic check_input_invalid(input logic v0, input logic v1);
    begin : ii
      mode = 2'b00; pred = 4'd1; in_data_0 = '0; in_data_1 = '0;
      in_valid_0 = v0; in_valid_1 = v1; out_ready = 1'b1;
      #1;
      if (out_valid !== 1'b0) begin : iiv
        $display("FAIL: out_valid high when in_valid_0=%b in_valid_1=%b", v0, v1);
        error_count = error_count + 1;
      end : iiv
      if (v0 && (in_ready_0 !== 1'b0)) begin : iir0
        $display("FAIL: in_ready_0 high when join incomplete");
        error_count = error_count + 1;
      end : iir0
      if (v1 && (in_ready_1 !== 1'b0)) begin : iir1
        $display("FAIL: in_ready_1 high when join incomplete");
        error_count = error_count + 1;
      end : iir1
    end : ii
  endtask

  // fp64 constants
  localparam logic [63:0] D_1  = 64'h3FF0000000000000, D_2  = 64'h4000000000000000;
  localparam logic [63:0] D_N1 = 64'hBFF0000000000000, D_PZ = 64'h0000000000000000;
  localparam logic [63:0] D_NZ = 64'h8000000000000000, D_INF= 64'h7FF0000000000000;
  localparam logic [63:0] D_NAN= 64'h7FF8000000000000, D_SUB= 64'h0000000000000001;
  // fp16 constants
  localparam logic [15:0] H_1  = 16'h3C00, H_2 = 16'h4000, H_N1 = 16'hBC00;
  localparam logic [15:0] H_INF= 16'h7C00, H_NAN= 16'h7E00, H_PZ = 16'h0000, H_NZ = 16'h8000;
  // fp32 constants
  localparam logic [31:0] S_1  = 32'h3F800000, S_2 = 32'h40000000, S_NAN = 32'h7FC00000;

  initial begin : main
    integer      i;
    logic [63:0] a, b;
    logic [1:0]  m;
    logic [3:0]  p;

    error_count = 0;
    mode = 2'b00; pred = 4'd1; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed fp64: every predicate on key pairs ----
    for (i = 0; i < 16; i = i + 1) begin : sweep
      p = i[3:0];
      check_vec(2'b00, p, D_1,  D_2);    // 1 vs 2 (ordered, 1<2)
      check_vec(2'b00, p, D_1,  D_1);    // equal
      check_vec(2'b00, p, D_NAN, D_1);   // NaN vs 1 (unordered)
      check_vec(2'b00, p, D_PZ, D_NZ);   // +0 vs -0 (equal per IEEE compare)
      check_vec(2'b00, p, D_N1, D_1);    // -1 vs 1
      check_vec(2'b00, p, D_INF, D_2);   // inf vs 2
    end : sweep

    // ---- Directed fp16 (mode 10): per-lane independence, NaN/+-0/Inf mix ----
    check_vec(2'b10, 4'd4, {H_NAN, H_INF, H_NZ, H_N1}, {H_1, H_1, H_PZ, H_1}); // OLT
    check_vec(2'b10, 4'd11, {H_NAN, H_INF, H_NZ, H_N1}, {H_1, H_1, H_PZ, H_1}); // ULT (NaN lane -> true)
    check_vec(2'b10, 4'd1, {H_2, H_2, H_PZ, H_1}, {H_2, H_1, H_NZ, H_1});       // OEQ (+0==-0)
    check_vec(2'b10, 4'd14, {H_NAN, H_1, H_2, H_INF}, {H_1, H_1, H_1, H_INF});  // UNO

    // ---- Directed fp32 (mode 01) ----
    check_vec(2'b01, 4'd2, {S_2, S_1}, {S_1, S_2});    // OGT
    check_vec(2'b01, 4'd6, {S_NAN, S_1}, {S_1, S_1});  // ONE (NaN lane ordered -> false)

    // reserved mode 11 -> fp64
    check_vec(2'b11, 4'd5, D_1, D_2);

    // ---- Handshake corners ----
    check_backpressure(2'b10, 4'd2, {H_1, H_2, H_1, H_2}, {H_2, H_1, H_2, H_1});
    check_input_invalid(1'b0, 1'b1);
    check_input_invalid(1'b1, 1'b0);
    check_input_invalid(1'b0, 1'b0);

    // ---- Uniform random ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random}; b = {$random, $random}; m = $random; p = $random;
      check_vec(m, p, a, b);
    end : rl
    // ---- Small-exponent random (more zeros / subnormals / near-equal) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl2
      a = {$random, $random} & 64'h8FFF_8FFF_8FFF_8FFF;
      b = {$random, $random} & 64'h8FFF_8FFF_8FFF_8FFF;
      m = $random; p = $random;
      check_vec(m, p, a, b);
    end : rl2

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_fp_cmp_decomp all modes, %0d+%0d random vectors, 0 mismatches", NRAND, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_fp_cmp_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_fp_cmp_decomp
