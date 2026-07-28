// tb_fu_fp_add_sub_dx.sv -- Self-checking TB for fu_fp_add_sub_dx (64/32-only FP add/sub).
// Combinational DUT; drive (mode, op_sel, a, b), settle, compare per lane to a hardware-FP golden
// via DPI-C (double / float). NaN-lenient (any qNaN accepted); else bit-exact (incl signed zero,
// subnormals). Directed IEEE corners + uniform random + cancellation-stress random. Both modes.
`timescale 1ns/1ps

module tb_fu_fp_add_sub_dx #(
  parameter int unsigned NRAND = 20000
);
  import "DPI-C" function longint unsigned g_fp64_add(input longint unsigned a,
                                                      input longint unsigned b, input int sub);
  import "DPI-C" function int unsigned      g_fp32_add(input int unsigned a,
                                                      input int unsigned b, input int sub);

  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [1:0]  op_sel;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_fp_add_sub_dx dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .op_sel(op_sel),
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

  function automatic logic [63:0] golden(input logic [1:0]  m,
                                         input logic [1:0]  op,
                                         input logic [63:0] a,
                                         input logic [63:0] b);
    logic [63:0] r;
    begin : gbody
      if (m == 2'b01) begin : g2x32
        r[31:0]  = g_fp32_add(a[31:0],  b[31:0],  {31'b0, op[0]});
        r[63:32] = g_fp32_add(a[63:32], b[63:32], {31'b0, op[1]});
      end : g2x32
      else begin : g1x64
        r = g_fp64_add(a, b, {31'b0, op[0]});   // 1x64 and reserved
      end : g1x64
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
      if (m == 2'b01) ok = lane_ok(e[31:0], a[31:0], 8, 23) & lane_ok(e[63:32], a[63:32], 8, 23);
      else            ok = lane_ok(e, a, 11, 52);
      result_ok = ok;
    end : rb
  endfunction

  task automatic check_vec(input logic [1:0]  m, input logic [1:0]  op,
                           input logic [63:0] a, input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, op, a, b);
      if (!result_ok(m, exp, out_data)) begin : mism
        $display("FAIL data: mode=%02b op=%02b a=%h b=%h got=%h exp=%h",
                 m, op, a, b, out_data, exp);
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

  task automatic check_backpressure(input logic [1:0]  m, input logic [1:0]  op,
                                    input logic [63:0] a, input logic [63:0] b);
    begin : bp
      mode = m; op_sel = op; in_data_0 = a; in_data_1 = b;
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
      mode = 2'b00; op_sel = 2'b00; in_data_0 = '0; in_data_1 = '0;
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
  localparam logic [63:0] D_1   = 64'h3FF0000000000000, D_2   = 64'h4000000000000000;
  localparam logic [63:0] D_N1  = 64'hBFF0000000000000, D_PZ  = 64'h0000000000000000;
  localparam logic [63:0] D_NZ  = 64'h8000000000000000, D_INF = 64'h7FF0000000000000;
  localparam logic [63:0] D_NIN = 64'hFFF0000000000000, D_NAN = 64'h7FF8000000000000;
  localparam logic [63:0] D_MAX = 64'h7FEFFFFFFFFFFFFF, D_MSB = 64'h0000000000000001;
  localparam logic [63:0] D_MXS = 64'h000FFFFFFFFFFFFF, D_MNN = 64'h0010000000000000;
  localparam logic [31:0] S_1   = 32'h3F800000, S_2 = 32'h40000000, S_INF = 32'h7F800000;
  localparam logic [31:0] S_MAX = 32'h7F7FFFFF, S_MSB = 32'h00000001;

  initial begin : main
    integer      i;
    logic [63:0] a, b;
    logic [1:0]  m;
    logic [1:0]  op;

    error_count = 0;
    mode = 2'b00; op_sel = 2'b00; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed fp64 (mode 00) ----
    check_vec(2'b00, 2'b00, D_1,  D_1);            // 1+1=2
    check_vec(2'b00, 2'b00, D_1,  D_2);            // 1+2=3
    check_vec(2'b00, 2'b01, D_2,  D_1);            // 2-1=1
    check_vec(2'b00, 2'b01, D_1,  D_1);            // 1-1=+0
    check_vec(2'b00, 2'b00, D_PZ, D_NZ);           // +0 + -0 = +0
    check_vec(2'b00, 2'b00, D_NZ, D_NZ);           // -0 + -0 = -0
    check_vec(2'b00, 2'b00, D_1,  D_N1);           // 1 + -1 = +0
    check_vec(2'b00, 2'b00, D_INF, D_INF);         // inf+inf=inf
    check_vec(2'b00, 2'b00, D_INF, D_NIN);         // inf + -inf = NaN
    check_vec(2'b00, 2'b01, D_INF, D_INF);         // inf - inf = NaN
    check_vec(2'b00, 2'b00, D_INF, D_1);           // inf + 1 = inf
    check_vec(2'b00, 2'b00, D_NAN, D_1);           // NaN + 1 = NaN
    check_vec(2'b00, 2'b00, D_MAX, D_MAX);         // overflow -> inf
    check_vec(2'b00, 2'b00, D_MSB, D_MSB);         // subnormal + subnormal
    check_vec(2'b00, 2'b01, D_MNN, D_MSB);         // minnorm - minsub -> subnormal
    check_vec(2'b00, 2'b00, D_MXS, D_MSB);         // maxsub + minsub -> minnorm
    check_vec(2'b00, 2'b01, D_MAX, 64'h7FEFFFFFFFFFFFFE); // near-equal cancellation

    // ---- Directed fp32 (mode 01): independent lanes, mixed ops ----
    check_vec(2'b01, 2'b00, {S_2,   S_1},   {S_1,   S_2});   // both add
    check_vec(2'b01, 2'b10, {S_2,   S_1},   {S_1,   S_1});   // lane1(op[1]) sub, lane0 add
    check_vec(2'b01, 2'b00, {S_MAX, S_1},   {S_MAX, S_1});   // lane1 overflow->inf, lane0 normal
    check_vec(2'b01, 2'b00, {S_INF, S_MSB}, {S_1,   S_MSB}); // lane1 inf+1, lane0 subnormal sum
    check_vec(2'b01, 2'b11, {S_2,   S_2},   {S_1,   S_1});   // both lanes subtract

    // reserved mode 11 behaves as fp64
    check_vec(2'b11, 2'b00, D_1, D_2);

    // ---- Handshake corners ----
    check_backpressure(2'b01, 2'b01, {S_1, S_2}, {S_2, S_1});
    check_input_invalid(1'b0, 1'b1);
    check_input_invalid(1'b1, 1'b0);
    check_input_invalid(1'b0, 1'b0);

    // ---- Uniform random (both modes incl reserved) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random}; b = {$random, $random}; m = $random; op = $random;
      check_vec(m, op, a, b);
    end : rl

    // ---- Cancellation stress: a and b nearly equal ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl2
      a = {$random, $random};
      b = a ^ {32'b0, ($random & 32'h0000_FFFF)};
      m = $random; op = $random;
      check_vec(m, op, a, b);
    end : rl2

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_fp_add_sub_dx all modes, %0d+%0d random vectors, 0 mismatches", NRAND, NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_fp_add_sub_dx %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_fp_add_sub_dx
