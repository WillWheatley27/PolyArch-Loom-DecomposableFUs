// tb_fu_cmp_decomp.sv -- Self-checking TB for fu_cmp_decomp (packed integer compare).
// Drive (mode, pred, a, b), settle, compare per lane to a native-SV golden that evaluates the
// predicate at the lane width and produces an all-ones/all-zeros mask. Directed corners
// (each predicate, signed-vs-unsigned, per-lane isolation) + randomized. Testbench only.
`timescale 1ns/1ps

module tb_fu_cmp_decomp #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [3:0]  pred;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_cmp_decomp dut (
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

  // Per-lane predicate evaluation -> mask.
  function automatic logic cmp_bit_16(input logic [3:0] p, input logic [15:0] a, input logic [15:0] b);
    case (p)
      4'd0:    cmp_bit_16 = (a == b);
      4'd1:    cmp_bit_16 = (a != b);
      4'd2:    cmp_bit_16 = ($signed(a) <  $signed(b));
      4'd3:    cmp_bit_16 = ($signed(a) <= $signed(b));
      4'd4:    cmp_bit_16 = ($signed(a) >  $signed(b));
      4'd5:    cmp_bit_16 = ($signed(a) >= $signed(b));
      4'd6:    cmp_bit_16 = (a <  b);
      4'd7:    cmp_bit_16 = (a <= b);
      4'd8:    cmp_bit_16 = (a >  b);
      4'd9:    cmp_bit_16 = (a >= b);
      default: cmp_bit_16 = 1'b0;
    endcase
  endfunction
  function automatic logic cmp_bit_32(input logic [3:0] p, input logic [31:0] a, input logic [31:0] b);
    case (p)
      4'd0:    cmp_bit_32 = (a == b);
      4'd1:    cmp_bit_32 = (a != b);
      4'd2:    cmp_bit_32 = ($signed(a) <  $signed(b));
      4'd3:    cmp_bit_32 = ($signed(a) <= $signed(b));
      4'd4:    cmp_bit_32 = ($signed(a) >  $signed(b));
      4'd5:    cmp_bit_32 = ($signed(a) >= $signed(b));
      4'd6:    cmp_bit_32 = (a <  b);
      4'd7:    cmp_bit_32 = (a <= b);
      4'd8:    cmp_bit_32 = (a >  b);
      4'd9:    cmp_bit_32 = (a >= b);
      default: cmp_bit_32 = 1'b0;
    endcase
  endfunction
  function automatic logic cmp_bit_64(input logic [3:0] p, input logic [63:0] a, input logic [63:0] b);
    case (p)
      4'd0:    cmp_bit_64 = (a == b);
      4'd1:    cmp_bit_64 = (a != b);
      4'd2:    cmp_bit_64 = ($signed(a) <  $signed(b));
      4'd3:    cmp_bit_64 = ($signed(a) <= $signed(b));
      4'd4:    cmp_bit_64 = ($signed(a) >  $signed(b));
      4'd5:    cmp_bit_64 = ($signed(a) >= $signed(b));
      4'd6:    cmp_bit_64 = (a <  b);
      4'd7:    cmp_bit_64 = (a <= b);
      4'd8:    cmp_bit_64 = (a >  b);
      4'd9:    cmp_bit_64 = (a >= b);
      default: cmp_bit_64 = 1'b0;
    endcase
  endfunction

  function automatic logic [63:0] golden(input logic [1:0] m, input logic [3:0] p,
                                         input logic [63:0] a, input logic [63:0] b);
    logic [63:0] r;
    begin : gbody
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = {32{cmp_bit_32(p, a[31:0],  b[31:0])}};
          r[63:32] = {32{cmp_bit_32(p, a[63:32], b[63:32])}};
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = {16{cmp_bit_16(p, a[15:0],  b[15:0])}};
          r[31:16] = {16{cmp_bit_16(p, a[31:16], b[31:16])}};
          r[47:32] = {16{cmp_bit_16(p, a[47:32], b[47:32])}};
          r[63:48] = {16{cmp_bit_16(p, a[63:48], b[63:48])}};
        end : g4x16
        default: r = {64{cmp_bit_64(p, a, b)}};   // 1x64 and reserved 11
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
      mode = 2'b00; pred = 4'd0; in_data_0 = '0; in_data_1 = '0;
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

  initial begin : main
    integer      i;
    logic [63:0] a, b;
    logic [1:0]  m;
    logic [3:0]  p;

    error_count = 0;
    mode = 2'b00; pred = 4'd0; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed: 1x64 all predicates on a fixed pair ----
    for (p = 4'd0; p <= 4'd9; p = p + 4'd1) begin : sweep64
      check_vec(2'b00, p, 64'h0000000000000005, 64'h0000000000000003); // 5 vs 3
      check_vec(2'b00, p, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // -1 vs 1 (signed vs unsigned)
      check_vec(2'b00, p, 64'h0123456789ABCDEF, 64'h0123456789ABCDEF); // equal
    end : sweep64
    check_vec(2'b00, 4'd15, 64'd7, 64'd7);   // reserved -> all zeros

    // ---- Directed: 4x16 signed-vs-unsigned boundary + per-lane isolation ----
    check_vec(2'b10, 4'd2, 64'h8000_7FFF_FFFF_0001, 64'h0001_0001_0001_0001); // slt per lane
    check_vec(2'b10, 4'd6, 64'h8000_7FFF_FFFF_0001, 64'h0001_0001_0001_0001); // ult (differs on high-MSB lanes)
    check_vec(2'b10, 4'd0, 64'h0001_0002_0003_0004, 64'h0001_9999_0003_0000); // eq: lanes 0,2 equal
    check_vec(2'b10, 4'd4, 64'h0005_0005_8000_8000, 64'h0003_0007_0001_7FFF); // sgt mixed

    // ---- Directed: 2x32 break vs 1x64 (same operands) ----
    check_vec(2'b01, 4'd8, 64'h00000001_00000000, 64'h00000000_00000001); // ugt per 32-bit lane
    check_vec(2'b00, 4'd8, 64'h00000001_00000000, 64'h00000000_00000001); // ugt whole 64
    check_vec(2'b01, 4'd5, 64'h80000000_00000005, 64'h00000001_00000003); // sge signed lanes

    // ---- Handshake corners ----
    check_backpressure(2'b10, 4'd4, 64'h1111_2222_3333_4444, 64'h4444_3333_2222_1111);
    check_input_invalid(1'b0, 1'b1);
    check_input_invalid(1'b1, 1'b0);
    check_input_invalid(1'b0, 1'b0);

    // ---- Randomized (all modes, all predicates incl reserved) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a = {$random, $random};
      b = {$random, $random};
      m = $random;
      p = $random;
      check_vec(m, p, a, b);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_cmp_decomp all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_cmp_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_cmp_decomp
