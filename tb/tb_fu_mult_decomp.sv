// tb_fu_mult_decomp.sv -- Self-checking TB for fu_mult_decomp.
// Combinational DUT; drive (mode, a, b), settle, compare to a golden model that
// splits operands into subword lanes per mode and multiplies each lane at its own
// width, keeping the low (truncated) product. Directed corners (cross-lane PP
// isolation, mode equivalence, 2x32-vs-1x64 distinction, sign-agnostic) + randomized.
// All modes exercised in one run (mode is a runtime input). Testbench only.
`timescale 1ns/1ps

module tb_fu_mult_decomp #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_mult_decomp dut (
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

  // Golden: per-lane low (truncated) product. Multiply is context-determined by the
  // lane-width lvalue, so each assignment keeps only the low bits of that lane's product.
  function automatic logic [63:0] golden(input logic [1:0]  m,
                                         input logic [63:0] a,
                                         input logic [63:0] b);
    logic [63:0] r;
    begin : golden_body
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = a[31:0]  * b[31:0];
          r[63:32] = a[63:32] * b[63:32];
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = a[15:0]  * b[15:0];
          r[31:16] = a[31:16] * b[31:16];
          r[47:32] = a[47:32] * b[47:32];
          r[63:48] = a[63:48] * b[63:48];
        end : g4x16
        default: begin : g1x64   // 2'b00 and reserved 2'b11
          r = a * b;
        end : g1x64
      endcase
      golden = r;
    end : golden_body
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
      if (out_data !== exp) begin : mism
        $display("FAIL data: mode=%02b a=%h b=%h got=%h exp=%h",
                 m, a, b, out_data, exp);
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

  task automatic check_backpressure(input logic [1:0]  m,
                                    input logic [63:0] a, input logic [63:0] b);
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
        $display("FAIL: in_ready_0 high when join incomplete (in_valid_0=%b in_valid_1=%b)", v0, v1);
        error_count = error_count + 1;
      end : iir0
      if (v1 && (in_ready_1 !== 1'b0)) begin : iir1
        $display("FAIL: in_ready_1 high when join incomplete (in_valid_0=%b in_valid_1=%b)", v0, v1);
        error_count = error_count + 1;
      end : iir1
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

    // ---- Directed: 1x64 equivalence (truncated 64-bit product) ----
    check_vec(2'b00, 64'h0000_0000_0000_0000, 64'h0123_4567_89AB_CDEF);
    check_vec(2'b00, 64'h0123_4567_89AB_CDEF, 64'h0000_0000_0000_0001); // x1
    check_vec(2'b00, 64'h0000_0000_0000_0002, 64'h8000_0000_0000_0001); // low64 wrap
    check_vec(2'b00, 64'hFFFF_FFFF_FFFF_FFFF, 64'hFFFF_FFFF_FFFF_FFFF); // -> 0x...0001

    // ---- Directed: 4x16 overflow isolation: lane0 FFFF*FFFF keeps low16, no leak ----
    check_vec(2'b10, 64'h0003_0002_0001_FFFF, 64'h0005_0004_0003_FFFF); // -> 000F_0008_0003_0001

    // ---- Directed: 2x32 vs 1x64 distinction (identical operands, different mode) ----
    check_vec(2'b01, 64'h0000_0001_0000_0001, 64'h0000_0001_0000_0001); // -> 0000_0001_0000_0001
    check_vec(2'b00, 64'h0000_0001_0000_0001, 64'h0000_0001_0000_0001); // -> 0000_0002_0000_0001

    // ---- Directed: 2x32 lane0 product overflows 32 bits, must not leak into lane1 ----
    check_vec(2'b01, 64'h0000_0001_FFFF_FFFF, 64'h0000_0001_0000_0002); // -> 0000_0001_FFFF_FFFE

    // ---- Directed: 4x16 mixed per-lane products ----
    check_vec(2'b10, 64'h0010_000A_00FF_0002, 64'h0010_0003_0002_0007);

    // ---- Directed: sign-agnostic (lane MSB set; low bits match unsigned golden) ----
    check_vec(2'b10, 64'hFFFF_8000_7FFF_8000, 64'h0002_0002_0002_0002); // -> FFFE_0000_FFFE_0000

    // ---- All-lanes corner cluster ----
    check_vec(2'b10, 64'h0000_0000_0000_0000, 64'h0000_0000_0000_0000); // 4x16 zeros
    check_vec(2'b10, 64'hFFFF_FFFF_FFFF_FFFF, 64'hFFFF_FFFF_FFFF_FFFF); // 4x16 max -> 0001x4
    check_vec(2'b01, 64'hFFFF_FFFF_FFFF_FFFF, 64'hFFFF_FFFF_FFFF_FFFF); // 2x32 max -> 0000_0001 x2
    check_vec(2'b00, 64'hFFFF_FFFF_FFFF_FFFF, 64'h0000_0000_0000_0001); // 1x64 x1
    check_vec(2'b01, 64'h5555_5555_5555_5555, 64'hAAAA_AAAA_AAAA_AAAA); // 2x32 alternating
    check_vec(2'b11, 64'h0123_4567_89AB_CDEF, 64'hFEDC_BA98_7654_3210); // reserved 11 -> 1x64

    // ---- Handshake corners ----
    check_backpressure(2'b10, 64'h1111_2222_3333_4444, 64'h0001_0001_0001_0001);
    check_input_invalid(1'b0, 1'b1);
    check_input_invalid(1'b1, 1'b0);
    check_input_invalid(1'b0, 1'b0);

    // ---- Randomized (all modes incl reserved 11) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random};
      b = {$random, $random};
      m = $random;   // low 2 bits; includes reserved 11 (== 1x64)
      check_vec(m, a, b);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_mult_decomp all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_mult_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_mult_decomp
