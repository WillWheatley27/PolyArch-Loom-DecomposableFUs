// tb_fu_min_max_decomp.sv -- Self-checking TB for fu_min_max_decomp.
// Combinational DUT; drive (mode, is_signed, op_sel, a, b), settle, compare to a golden
// that splits operands into subword lanes per mode and computes signed/unsigned min/max
// at the lane width. Directed corners (cross-lane isolation, signedness at lane tops,
// 2x32-vs-1x64) + randomized. All modes in one run. Testbench only.
`timescale 1ns/1ps

module tb_fu_min_max_decomp #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic        is_signed;
  logic [3:0]  op_sel;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_min_max_decomp dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .is_signed(is_signed), .op_sel(op_sel),
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

  // Per-lane min/max helpers. mx: 0=min, 1=max. sgn: signed compare.
  function automatic logic [15:0] mm16(input logic sgn, input logic mx,
                                       input logic [15:0] x, input logic [15:0] y);
    logic xgty;
    begin
      xgty = sgn ? ($signed(x) > $signed(y)) : (x > y);
      mm16 = mx ? (xgty ? x : y) : (xgty ? y : x);
    end
  endfunction
  function automatic logic [31:0] mm32(input logic sgn, input logic mx,
                                       input logic [31:0] x, input logic [31:0] y);
    logic xgty;
    begin
      xgty = sgn ? ($signed(x) > $signed(y)) : (x > y);
      mm32 = mx ? (xgty ? x : y) : (xgty ? y : x);
    end
  endfunction
  function automatic logic [63:0] mm64(input logic sgn, input logic mx,
                                       input logic [63:0] x, input logic [63:0] y);
    logic xgty;
    begin
      xgty = sgn ? ($signed(x) > $signed(y)) : (x > y);
      mm64 = mx ? (xgty ? x : y) : (xgty ? y : x);
    end
  endfunction

  function automatic logic [63:0] golden(input logic [1:0]  m,
                                         input logic        sgn,
                                         input logic [3:0]  op,
                                         input logic [63:0] a,
                                         input logic [63:0] b);
    logic [63:0] r;
    begin : gbody
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = mm32(sgn, op[0], a[31:0],  b[31:0]);
          r[63:32] = mm32(sgn, op[2], a[63:32], b[63:32]);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = mm16(sgn, op[0], a[15:0],  b[15:0]);
          r[31:16] = mm16(sgn, op[1], a[31:16], b[31:16]);
          r[47:32] = mm16(sgn, op[2], a[47:32], b[47:32]);
          r[63:48] = mm16(sgn, op[3], a[63:48], b[63:48]);
        end : g4x16
        default: r = mm64(sgn, op[0], a, b);   // 1x64 and reserved 11
      endcase
      golden = r;
    end : gbody
  endfunction

  task automatic check_vec(input logic [1:0]  m,
                           input logic        sgn,
                           input logic [3:0]  op,
                           input logic [63:0] a,
                           input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; is_signed = sgn; op_sel = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, sgn, op, a, b);
      if (out_data !== exp) begin : mism
        $display("FAIL data: mode=%02b sgn=%b op=%04b a=%h b=%h got=%h exp=%h",
                 m, sgn, op, a, b, out_data, exp);
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

  task automatic check_backpressure(input logic [1:0] m, input logic sgn, input logic [3:0] op,
                                    input logic [63:0] a, input logic [63:0] b);
    begin : bp
      mode = m; is_signed = sgn; op_sel = op; in_data_0 = a; in_data_1 = b;
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
      mode = 2'b00; is_signed = 1'b0; op_sel = 4'b0000; in_data_0 = '0; in_data_1 = '0;
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
    logic        sgn;
    logic [3:0]  op;

    error_count = 0;
    mode = 2'b00; is_signed = 1'b0; op_sel = 4'b0000; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed: 1x64 signed vs unsigned distinction ----
    check_vec(2'b00, 1'b1, 4'b0000, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // signed min -> -1 (a)
    check_vec(2'b00, 1'b0, 4'b0000, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // unsigned min -> 1 (b)
    check_vec(2'b00, 1'b1, 4'b0001, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // signed max -> 1 (b)
    check_vec(2'b00, 1'b0, 4'b0001, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // unsigned max -> a
    check_vec(2'b00, 1'b1, 4'b0000, 64'h0123456789ABCDEF, 64'h0123456789ABCDEF); // equal
    check_vec(2'b00, 1'b1, 4'b0000, 64'h8000000000000000, 64'h7FFFFFFFFFFFFFFF); // most-neg vs most-pos (signed)

    // ---- Directed: 4x16 signedness at lane tops + isolation, signed min ----
    check_vec(2'b10, 1'b1, 4'b0000, 64'h8000_7FFF_0001_FFFF, 64'h0001_0001_0001_0001);
    // lane0: -1 vs 1 -> -1 ; lane1: 1 vs 1 -> 1 ; lane2: 32767 vs 1 -> 1 ; lane3: -32768 vs 1 -> -32768
    // ---- same bits, unsigned min (different at lanes with high MSB) ----
    check_vec(2'b10, 1'b0, 4'b0000, 64'h8000_7FFF_0001_FFFF, 64'h0001_0001_0001_0001);
    // ---- 4x16 mixed per-lane min/max ----
    check_vec(2'b10, 1'b1, 4'b1010, 64'h0005_FFF0_0007_8000, 64'h0003_0010_0002_0001);

    // ---- Directed: 2x32 break vs 1x64 (same operands) ----
    check_vec(2'b01, 1'b0, 4'b0000, 64'h00000001_FFFFFFFF, 64'h00000000_FFFFFFFF); // per-lane
    check_vec(2'b00, 1'b0, 4'b0000, 64'h00000001_FFFFFFFF, 64'h00000000_FFFFFFFF); // whole 64
    // ---- 2x32 mixed ops, signed ----
    check_vec(2'b01, 1'b1, 4'b0100, 64'h80000000_00000005, 64'h00000001_FFFFFFFF);

    // ---- Corners ----
    check_vec(2'b10, 1'b1, 4'b1111, 64'hFFFF_FFFF_FFFF_FFFF, 64'h0000_0000_0000_0000);
    check_vec(2'b01, 1'b0, 4'b0000, 64'hFFFFFFFF_FFFFFFFF, 64'hFFFFFFFF_FFFFFFFF); // equal max
    check_vec(2'b11, 1'b1, 4'b0001, 64'h0123456789ABCDEF, 64'hFEDCBA9876543210); // reserved -> 1x64

    // ---- Handshake corners ----
    check_backpressure(2'b10, 1'b1, 4'b0101, 64'h1111_2222_3333_4444, 64'h4444_3333_2222_1111);
    check_input_invalid(1'b0, 1'b1);
    check_input_invalid(1'b1, 1'b0);
    check_input_invalid(1'b0, 1'b0);

    // ---- Randomized (all modes, both signedness) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a   = {$random, $random};
      b   = {$random, $random};
      m   = $random;
      sgn = $random;
      op  = $random;
      check_vec(m, sgn, op, a, b);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_min_max_decomp all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_min_max_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_min_max_decomp
