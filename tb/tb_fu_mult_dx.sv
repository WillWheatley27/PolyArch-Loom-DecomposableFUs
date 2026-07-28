// tb_fu_mult_dx.sv -- Self-checking TB for fu_mult_dx (64/32-only duplex multiply-low).
// Drive (mode, a, b), settle, compare to a native-SV golden: each lane returns the low W bits
// of its W×W product (sign-agnostic). Directed mode-isolation (full-width low product in 1x64 vs
// isolated low-32 lane in 2x32) + handshake corners + randomized. Testbench only.
`timescale 1ns/1ps

module tb_fu_mult_dx #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_ready_0;
  logic        in_valid_1, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_mult_dx dut (
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

  function automatic logic [63:0] golden(input logic [1:0] m,
                                         input logic [63:0] a, input logic [63:0] b);
    logic [63:0] pl, ph;
    begin : gbody
      if (m == 2'b01) begin : g2x32
        pl = a[31:0]  * b[31:0];     // full 32x32 low lane
        ph = a[63:32] * b[63:32];    // full 32x32 high lane
        golden = {ph[31:0], pl[31:0]};   // multiply-low: low 32 of each
      end : g2x32
      else begin : g1x64
        golden = a * b;              // low 64 (self-determined 64-bit product)
      end : g1x64
    end : gbody
  endfunction

  task automatic check_vec(input logic [1:0] m, input logic [63:0] a, input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, a, b);
      if (out_data !== exp) begin : mism
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

  task automatic check_input_invalid;
    begin : ii
      mode = 2'b00; in_data_0 = '0; in_data_1 = '0;
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
    logic [1:0]  m;

    error_count = 0;
    mode = 2'b00; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Mode isolation: 0xFFFFFFFF * 0xFFFFFFFF ----
    // 1x64: full 32x32 = 0xFFFFFFFE_00000001, low64 keeps the upper bits.
    check_vec(2'b00, 64'h00000000_FFFFFFFF, 64'h00000000_FFFFFFFF);
    // 2x32: low lane low32 = 0x00000001, high lane 0*0 = 0 -> 0x00000000_00000001.
    check_vec(2'b01, 64'h00000000_FFFFFFFF, 64'h00000000_FFFFFFFF);

    // ---- multiply-low truncation (1x64): 2^33 * ... keeps low 64 ----
    check_vec(2'b00, 64'h00000001_00000000, 64'h00000000_00000002); // 2^32 * 2 = 2^33
    check_vec(2'b00, 64'hFFFFFFFF_FFFFFFFF, 64'h00000000_00000002); // -1*2 low64 = FFFF..FE

    // ---- 2x32 independent lanes ----
    check_vec(2'b01, 64'h00000003_00000005, 64'h00000007_00000009); // hi 3*7=0x15, lo 5*9=0x2D
    check_vec(2'b01, 64'hFFFFFFFF_00010000, 64'h00000002_00010000); // hi FFFFFFFF*2 low32, lo 0x10000*0x10000 low32=0

    // ---- reserved modes -> 1x64 ----
    check_vec(2'b10, 64'h00000000_FFFFFFFF, 64'h00000000_FFFFFFFF);
    check_vec(2'b11, 64'h00000001_00000000, 64'h00000000_00000002);

    // ---- handshake ----
    check_backpressure(2'b01, 64'hDEADBEEF_CAFEF00D, 64'h01234567_89ABCDEF);
    check_input_invalid;

    // ---- randomized ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random}; b = {$random, $random}; m = $random;
      check_vec(m, a, b);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_mult_dx all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_mult_dx %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_mult_dx
