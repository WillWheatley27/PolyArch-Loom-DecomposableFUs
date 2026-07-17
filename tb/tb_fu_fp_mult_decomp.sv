// tb_fu_fp_mult_decomp.sv -- Self-checking TB for fu_fp_mult_decomp.
// Combinational DUT; drive (mode, a, b), settle, compare per lane to a hardware-FP
// golden via DPI-C (double / float / F16C). NaN-lenient (any qNaN accepted); everything
// else (incl signed zero, subnormals) bit-exact. Directed IEEE corners + uniform random
// + small-exponent (underflow/subnormal) stress. All modes in one run.
`timescale 1ns/1ps

module tb_fu_fp_mult_decomp #(
  parameter int unsigned NRAND = 20000
);
  // DPI-C hardware-FP golden (tb/fu_fp_mult_decomp_golden.c).
  import "DPI-C" function longint unsigned g_fp64_mul(input longint unsigned a,
                                                      input longint unsigned b);
  import "DPI-C" function int unsigned      g_fp32_mul(input int unsigned a,
                                                      input int unsigned b);
  import "DPI-C" function int unsigned      g_fp16_mul(input int unsigned a,
                                                      input int unsigned b);

  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_fp_mult_decomp dut (
    .clk(clk), .rst_n(rst_n), .mode(mode),
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

  // ---- Golden: per-lane hardware-FP product, repacked per mode ----
  function automatic logic [63:0] golden(input logic [1:0]  m,
                                         input logic [63:0] a,
                                         input logic [63:0] b);
    logic [63:0] r;
    begin : gbody
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = g_fp32_mul(a[31:0],  b[31:0]);
          r[63:32] = g_fp32_mul(a[63:32], b[63:32]);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = g_fp16_mul({16'b0, a[15:0]},  {16'b0, b[15:0]});
          r[31:16] = g_fp16_mul({16'b0, a[31:16]}, {16'b0, b[31:16]});
          r[47:32] = g_fp16_mul({16'b0, a[47:32]}, {16'b0, b[47:32]});
          r[63:48] = g_fp16_mul({16'b0, a[63:48]}, {16'b0, b[63:48]});
        end : g4x16
        default: r = g_fp64_mul(a, b);   // 1x64 and reserved 11
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
                           input logic [63:0] a,
                           input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, a, b);
      if (!result_ok(m, exp, out_data)) begin : mism
        $display("FAIL data: mode=%02b a=%h b=%h got=%h exp=%h", m, a, b, out_data, exp);
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

  task automatic check_backpressure(input logic [1:0] m, input logic [63:0] a, input logic [63:0] b);
    begin : bp
      mode = m; in_data_0 = a; in_data_1 = b;
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
      mode = 2'b00; in_data_0 = '0; in_data_1 = '0;
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

  // fp constants
  localparam logic [63:0] D_1  = 64'h3FF0000000000000, D_2  = 64'h4000000000000000;
  localparam logic [63:0] D_H  = 64'h3FE0000000000000, D_3  = 64'h4008000000000000;
  localparam logic [63:0] D_N1 = 64'hBFF0000000000000, D_PZ = 64'h0000000000000000;
  localparam logic [63:0] D_NZ = 64'h8000000000000000, D_INF= 64'h7FF0000000000000;
  localparam logic [63:0] D_NAN= 64'h7FF8000000000000, D_MAX= 64'h7FEFFFFFFFFFFFFF;
  localparam logic [63:0] D_MSB= 64'h0000000000000001, D_MXS= 64'h000FFFFFFFFFFFFF;
  localparam logic [63:0] D_MNN= 64'h0010000000000000;
  localparam logic [31:0] S_1  = 32'h3F800000, S_2 = 32'h40000000, S_H = 32'h3F000000;
  localparam logic [31:0] S_INF= 32'h7F800000, S_MAX= 32'h7F7FFFFF, S_MSB= 32'h00000001;
  localparam logic [31:0] S_NAN= 32'h7FC00000, S_MNN= 32'h00800000;
  localparam logic [15:0] H_1  = 16'h3C00, H_2 = 16'h4000, H_H = 16'h3800;
  localparam logic [15:0] H_INF= 16'h7C00, H_MAX= 16'h7BFF, H_MSB= 16'h0001;
  localparam logic [15:0] H_NAN= 16'h7E00, H_MNN= 16'h0400, H_PZ = 16'h0000;

  initial begin : main
    integer      i;
    logic [63:0] a, b;
    logic [1:0]  m;

    error_count = 0;
    mode = 2'b00; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed fp64 (mode 00) ----
    check_vec(2'b00, D_1,  D_1);      // 1*1=1
    check_vec(2'b00, D_1,  D_2);      // 1*2=2
    check_vec(2'b00, D_2,  D_3);      // 2*3=6
    check_vec(2'b00, D_3,  D_H);      // 3*0.5=1.5
    check_vec(2'b00, D_1,  D_PZ);     // 1*0=+0
    check_vec(2'b00, D_N1, D_1);      // -1*1=-1
    check_vec(2'b00, D_NZ, D_3);      // -0*3=-0
    check_vec(2'b00, D_MAX, D_MAX);   // overflow -> inf
    check_vec(2'b00, D_MSB, D_MSB);   // minsub*minsub -> +0 (underflow)
    check_vec(2'b00, D_MNN, D_H);     // minnorm*0.5 -> subnormal
    check_vec(2'b00, D_MXS, D_2);     // maxsub*2 -> normal
    check_vec(2'b00, D_INF, D_2);     // inf*2 -> inf
    check_vec(2'b00, D_INF, D_PZ);    // inf*0 -> NaN
    check_vec(2'b00, D_NAN, D_1);     // nan*1 -> nan
    check_vec(2'b00, D_INF, D_INF);   // inf*inf -> inf

    // ---- Directed fp32 (mode 01): independent lanes ----
    check_vec(2'b01, {S_2,   S_1},   {S_H,   S_2});    // l0 1*2, l1 2*0.5
    check_vec(2'b01, {S_MAX, S_1},   {S_MAX, S_2});    // l0 overflow->inf, l1 1*2
    check_vec(2'b01, {S_INF, S_MSB}, {S_H,   S_MSB});  // l0 inf*.5->inf, l1 subnml*subnml
    check_vec(2'b01, {S_MNN, S_INF}, {S_H,   S_MNN});  // l0 minnorm*.5->subnml, l1 inf*minnorm->inf

    // ---- Directed fp16 (mode 10): four independent lanes, all cases at once ----
    check_vec(2'b10, {H_MAX, H_INF, H_MNN, H_1},  {H_MAX, H_PZ,  H_H,   H_2});
    //                 l3 ovf  l2 inf*0->NaN l1 sub  l0 1*2
    check_vec(2'b10, {H_NAN, H_MSB, H_2,   H_H},  {H_1,   H_MSB, H_H,   H_H});
    //                 l3 NaN  l2 sub*sub  l1 2*.5  l0 .5*.5

    // reserved mode 11 behaves as fp64
    check_vec(2'b11, D_2, D_3);

    // ---- Handshake corners ----
    check_backpressure(2'b10, {H_1, H_2, H_1, H_2}, {H_2, H_1, H_2, H_1});
    check_input_invalid(1'b0, 1'b1);
    check_input_invalid(1'b1, 1'b0);
    check_input_invalid(1'b0, 1'b0);

    // ---- Uniform random (all modes incl reserved 11) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random};
      b = {$random, $random};
      m = $random;
      check_vec(m, a, b);
    end : rl

    // ---- Small-exponent stress: bias operands tiny (per 16-bit group: clear high exp
    //      bits) to hit underflow / subnormal products, especially in fp16 ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl2
      a = {$random, $random} & 64'h8FFF_8FFF_8FFF_8FFF;
      b = {$random, $random} & 64'h8FFF_8FFF_8FFF_8FFF;
      m = $random;
      check_vec(m, a, b);
    end : rl2

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_fp_mult_decomp all modes, %0d+%0d random vectors, 0 mismatches",
               NRAND, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_fp_mult_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_fp_mult_decomp
