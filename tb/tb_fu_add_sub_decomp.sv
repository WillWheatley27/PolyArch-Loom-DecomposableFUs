// tb_fu_add_sub_decomp.sv -- Self-checking TB for fu_add_sub_decomp.
// Combinational DUT; drive (mode, op_sel, a, b), settle, compare to a golden
// model that splits operands into subword lanes per mode. Directed corners
// (carry/borrow isolation, mode equivalence, mixed ops) + randomized. All modes
// exercised in one run (mode is a runtime input). Testbench only.
`timescale 1ns/1ps

module tb_fu_add_sub_decomp #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [3:0]  op_sel;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_add_sub_decomp dut (
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
                                         input logic [3:0]  op,
                                         input logic [63:0] a,
                                         input logic [63:0] b);
    logic [63:0] r;
    begin : golden_body
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = op[0] ? (a[31:0]  - b[31:0])  : (a[31:0]  + b[31:0]);
          r[63:32] = op[2] ? (a[63:32] - b[63:32]) : (a[63:32] + b[63:32]);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = op[0] ? (a[15:0]  - b[15:0])  : (a[15:0]  + b[15:0]);
          r[31:16] = op[1] ? (a[31:16] - b[31:16]) : (a[31:16] + b[31:16]);
          r[47:32] = op[2] ? (a[47:32] - b[47:32]) : (a[47:32] + b[47:32]);
          r[63:48] = op[3] ? (a[63:48] - b[63:48]) : (a[63:48] + b[63:48]);
        end : g4x16
        default: begin : g1x64   // 2'b00 and reserved 2'b11
          r = op[0] ? (a - b) : (a + b);
        end : g1x64
      endcase
      golden = r;
    end : golden_body
  endfunction

  task automatic check_vec(input logic [1:0]  m,
                           input logic [3:0]  op,
                           input logic [63:0] a,
                           input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, op, a, b);
      if (out_data !== exp) begin : mism
        $display("FAIL data: mode=%02b op=%04b a=%h b=%h got=%h exp=%h",
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

  task automatic check_backpressure(input logic [1:0]  m, input logic [3:0]  op,
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

  task automatic check_input_invalid;
    begin : ii
      mode = 2'b00; op_sel = 4'b0000; in_data_0 = '0; in_data_1 = '0;
      in_valid_0 = 1'b0; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      if (out_valid !== 1'b0) begin : iiv
        $display("FAIL: out_valid high when in_valid_0 low");
        error_count = error_count + 1;
      end : iiv
      if (in_ready_1 !== 1'b0) begin : iir
        $display("FAIL: in_ready_1 high when join incomplete");
        error_count = error_count + 1;
      end : iir
    end : ii
  endtask

  initial begin : main
    integer      i;
    logic [63:0] a, b;
    logic [1:0]  m;
    logic [3:0]  op;

    error_count = 0;
    mode = 2'b00; op_sel = 4'b0000; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed: 1x64 equivalence ----
    check_vec(2'b00, 4'b0000, 64'h0000_0000_0000_0000, 64'h0000_0000_0000_0000);
    check_vec(2'b00, 4'b0000, 64'h0123_4567_89AB_CDEF, 64'h0000_0000_0000_0001);
    check_vec(2'b00, 4'b0001, 64'h0000_0000_0000_0000, 64'h0000_0000_0000_0001); // 0-1 -> all ones
    check_vec(2'b00, 4'b0001, 64'hFFFF_FFFF_FFFF_FFFF, 64'hFFFF_FFFF_FFFF_FFFF); // a-a -> 0

    // ---- Directed: 4x16 carry isolation (add): lane0 FFFF+0001 wraps, no leak into lane1 ----
    check_vec(2'b10, 4'b0000, 64'h0001_0001_0001_FFFF, 64'h0000_0000_0000_0001);
    // ---- Directed: 4x16 borrow isolation (sub lane0 only): 0000-0001=FFFF, no borrow into lane1 ----
    check_vec(2'b10, 4'b0001, 64'h0005_0005_0005_0000, 64'h0002_0002_0002_0001);
    // ---- Directed: 4x16 mixed per-lane ops (op=1010) ----
    check_vec(2'b10, 4'b1010, 64'h0010_0010_0010_0010, 64'h0003_0003_0003_0003);

    // ---- Directed: 2x32 break vs 1x64 propagate (identical operands, different mode) ----
    check_vec(2'b01, 4'b0000, 64'h0000_0001_FFFF_FFFF, 64'h0000_0000_0000_0001); // -> 0000_0001_0000_0000
    check_vec(2'b00, 4'b0000, 64'h0000_0001_FFFF_FFFF, 64'h0000_0000_0000_0001); // -> 0000_0002_0000_0000
    // ---- Directed: 2x32 mixed ops (lane0 add, lane1 sub via op[2]) ----
    check_vec(2'b01, 4'b0100, 64'h0000_000A_0000_000A, 64'h0000_0003_0000_0003);

    // ---- Handshake corners ----
    check_backpressure(2'b10, 4'b0101, 64'h1111_2222_3333_4444, 64'h0001_0001_0001_0001);
    check_input_invalid();

    // ---- Randomized (all modes incl reserved 11) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a  = {$random, $random};
      b  = {$random, $random};
      m  = $random;   // low 2 bits; includes reserved 11 (== 1x64)
      op = $random;   // low 4 bits
      check_vec(m, op, a, b);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_add_sub_decomp all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_add_sub_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_add_sub_decomp
