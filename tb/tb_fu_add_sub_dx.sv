// tb_fu_add_sub_dx.sv -- Self-checking TB for fu_add_sub_dx (64/32-only duplex add/sub).
// Drive (mode, op_sel, a, b), settle, compare to a native-SV golden: per 32-bit lane,
// op_sel bit picks add/sub (two's-complement wrap). Directed mode-isolation (carry crosses
// bit 32 in 1x64, blocked in 2x32) + handshake corners + randomized. Testbench only.
`timescale 1ns/1ps

module tb_fu_add_sub_dx #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [1:0]  op_sel;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_ready_0;
  logic        in_valid_1, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_add_sub_dx dut (
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

  function automatic logic [63:0] golden(input logic [1:0] m, input logic [1:0] os,
                                         input logic [63:0] a, input logic [63:0] b);
    logic [31:0] lo, hi;
    logic        sub_lo, sub_hi;
    begin : gbody
      if (m == 2'b01) begin : g2x32
        sub_lo = os[0];
        sub_hi = os[1];
        lo = sub_lo ? (a[31:0]  - b[31:0])  : (a[31:0]  + b[31:0]);
        hi = sub_hi ? (a[63:32] - b[63:32]) : (a[63:32] + b[63:32]);
        golden = {hi, lo};
      end : g2x32
      else begin : g1x64
        golden = os[0] ? (a - b) : (a + b);   // 1x64 and reserved
      end : g1x64
    end : gbody
  endfunction

  task automatic check_vec(input logic [1:0] m, input logic [1:0] os,
                           input logic [63:0] a, input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; op_sel = os; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, os, a, b);
      if (out_data !== exp) begin : mism
        $display("FAIL data: mode=%02b op=%02b a=%h b=%h got=%h exp=%h",
                 m, os, a, b, out_data, exp);
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

  task automatic check_backpressure(input logic [1:0] m, input logic [1:0] os,
                                    input logic [63:0] a, input logic [63:0] b);
    begin : bp
      mode = m; op_sel = os; in_data_0 = a; in_data_1 = b;
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

  task automatic check_input_invalid;
    begin : ii
      mode = 2'b00; op_sel = 2'b00; in_data_0 = '0; in_data_1 = '0;
      in_valid_0 = 1'b1; in_valid_1 = 1'b0; out_ready = 1'b1;
      #1;
      if (out_valid !== 1'b0) begin : iiv
        $display("FAIL: out_valid high when in_valid_1=0");
        error_count = error_count + 1;
      end : iiv
      if (in_ready_0 !== 1'b0) begin : iir
        $display("FAIL: in_ready_0 high when join not satisfied");
        error_count = error_count + 1;
      end : iir
    end : ii
  endtask

  initial begin : main
    integer      i;
    logic [63:0] a, b;
    logic [1:0]  m, os;

    error_count = 0;
    mode = 2'b00; op_sel = 2'b00; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Mode isolation: carry across bit 32 ----
    // 1x64 add: 0x00000000_FFFFFFFF + 1 = 0x00000001_00000000 (carry crosses bit 32)
    check_vec(2'b00, 2'b00, 64'h00000000_FFFFFFFF, 64'h00000000_00000001);
    // 2x32 add, same inputs: low wraps to 0, high stays 0 -> 0x00000000_00000000 (carry blocked)
    check_vec(2'b01, 2'b00, 64'h00000000_FFFFFFFF, 64'h00000000_00000001);

    // ---- 1x64 subtract / edges ----
    check_vec(2'b00, 2'b01, 64'h00000001_00000000, 64'h00000000_00000001); // borrow across bit32
    check_vec(2'b00, 2'b01, 64'h00000000_00000000, 64'h00000000_00000001); // 0-1 = -1 (all ones)
    check_vec(2'b00, 2'b01, 64'h80000000_00000000, 64'h00000000_00000001); // INT64_MIN-1 wrap

    // ---- 2x32 independent + mixed op ----
    check_vec(2'b01, 2'b10, 64'h00000001_00000000, 64'h00000001_00000001); // low add, high sub
    check_vec(2'b01, 2'b01, 64'h00000000_00000000, 64'h00000001_00000001); // both sub, low borrow blocked
    check_vec(2'b01, 2'b11, 64'hFFFFFFFF_FFFFFFFF, 64'h00000001_00000001); // both sub

    // ---- reserved modes -> 1x64 ----
    check_vec(2'b10, 2'b00, 64'h00000000_FFFFFFFF, 64'h00000000_00000001); // add, crosses bit32
    check_vec(2'b11, 2'b01, 64'h00000001_00000000, 64'h00000000_00000001); // sub, borrows across

    // ---- handshake ----
    check_backpressure(2'b01, 2'b10, 64'hDEADBEEF_CAFEF00D, 64'h01234567_89ABCDEF);
    check_input_invalid;

    // ---- randomized ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random}; b = {$random, $random};
      m = $random; os = $random;
      check_vec(m, os, a, b);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_add_sub_dx all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_add_sub_dx %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_add_sub_dx
