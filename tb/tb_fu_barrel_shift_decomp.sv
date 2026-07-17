// tb_fu_barrel_shift_decomp.sv -- Self-checking TB for fu_barrel_shift_decomp.
// Combinational DUT; drive (mode, shift_op, a=data, b=amounts), settle, compare to a golden
// that shifts each subword lane (SLL/SRL/SRA) at the lane width by the low log2(w) bits of the
// corresponding b lane. Directed corners (each type x width, sign-fill, cross-lane isolation)
// + randomized. All modes in one run. Testbench only.
`timescale 1ns/1ps

module tb_fu_barrel_shift_decomp #(
  parameter int unsigned NRAND = 20000
);
  logic        clk, rst_n;
  logic [1:0]  mode;
  logic [1:0]  shift_op;
  logic [63:0] in_data_0, in_data_1;
  logic        in_valid_0, in_valid_1;
  logic        in_ready_0, in_ready_1;
  logic [63:0] out_data;
  logic        out_valid, out_ready;
  integer      error_count;

  fu_barrel_shift_decomp dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .shift_op(shift_op),
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

  // Per-lane shift helpers. op: 00=SLL, 01=SRL, 10=SRA, else SLL. amt already low log2(w) bits.
  function automatic logic [15:0] sh16(input logic [1:0] op, input logic [15:0] x, input logic [3:0] amt);
    case (op)
      2'b01:   sh16 = x >> amt;
      2'b10:   sh16 = $signed(x) >>> amt;
      default: sh16 = x << amt;
    endcase
  endfunction
  function automatic logic [31:0] sh32(input logic [1:0] op, input logic [31:0] x, input logic [4:0] amt);
    case (op)
      2'b01:   sh32 = x >> amt;
      2'b10:   sh32 = $signed(x) >>> amt;
      default: sh32 = x << amt;
    endcase
  endfunction
  function automatic logic [63:0] sh64(input logic [1:0] op, input logic [63:0] x, input logic [5:0] amt);
    case (op)
      2'b01:   sh64 = x >> amt;
      2'b10:   sh64 = $signed(x) >>> amt;
      default: sh64 = x << amt;
    endcase
  endfunction

  function automatic logic [63:0] golden(input logic [1:0]  m,
                                         input logic [1:0]  op,
                                         input logic [63:0] a,
                                         input logic [63:0] b);
    logic [63:0] r;
    begin : gbody
      case (m)
        2'b01: begin : g2x32
          r[31:0]  = sh32(op, a[31:0],  b[4:0]);
          r[63:32] = sh32(op, a[63:32], b[36:32]);
        end : g2x32
        2'b10: begin : g4x16
          r[15:0]  = sh16(op, a[15:0],  b[3:0]);
          r[31:16] = sh16(op, a[31:16], b[19:16]);
          r[47:32] = sh16(op, a[47:32], b[35:32]);
          r[63:48] = sh16(op, a[63:48], b[51:48]);
        end : g4x16
        default: r = sh64(op, a, b[5:0]);   // 1x64 and reserved 11
      endcase
      golden = r;
    end : gbody
  endfunction

  task automatic check_vec(input logic [1:0]  m,
                           input logic [1:0]  op,
                           input logic [63:0] a,
                           input logic [63:0] b);
    logic [63:0] exp;
    begin : cv
      mode = m; shift_op = op; in_data_0 = a; in_data_1 = b;
      in_valid_0 = 1'b1; in_valid_1 = 1'b1; out_ready = 1'b1;
      #1;
      exp = golden(m, op, a, b);
      if (out_data !== exp) begin : mism
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

  task automatic check_backpressure(input logic [1:0] m, input logic [1:0] op,
                                    input logic [63:0] a, input logic [63:0] b);
    begin : bp
      mode = m; shift_op = op; in_data_0 = a; in_data_1 = b;
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
      mode = 2'b00; shift_op = 2'b00; in_data_0 = '0; in_data_1 = '0;
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
    logic [1:0]  m, op;

    error_count = 0;
    mode = 2'b00; shift_op = 2'b00; in_data_0 = '0; in_data_1 = '0;
    in_valid_0 = 1'b0; in_valid_1 = 1'b0; out_ready = 1'b0; rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // ---- Directed: 1x64 each shift type ----
    check_vec(2'b00, 2'b00, 64'h0000_0000_0000_00FF, 64'd8);                    // SLL by 8
    check_vec(2'b00, 2'b01, 64'hFF00_0000_0000_0000, 64'd8);                    // SRL by 8
    check_vec(2'b00, 2'b10, 64'hFF00_0000_0000_0000, 64'd8);                    // SRA by 8 (sign fill)
    check_vec(2'b00, 2'b10, 64'h0F00_0000_0000_0000, 64'd8);                    // SRA positive
    check_vec(2'b00, 2'b00, 64'h0123_4567_89AB_CDEF, 64'd0);                    // shift 0 (identity)
    check_vec(2'b00, 2'b01, 64'hFFFF_FFFF_FFFF_FFFF, 64'd63);                   // SRL by 63
    check_vec(2'b00, 2'b00, 64'h0000_0000_0000_0001, 64'd70);                   // amt 70 -> masked to 6

    // ---- Directed: 4x16 per-lane independent amounts + SRA sign-fill + isolation ----
    // lane amts: lane0=4, lane1=1, lane2=8, lane3=15 (packed in b lanes)
    check_vec(2'b10, 2'b00, 64'h0001_0001_0001_0001, 64'h000F_0008_0001_0004);  // SLL per-lane
    check_vec(2'b10, 2'b10, 64'h8000_8000_8000_8000, 64'h0004_0004_0004_0004);  // SRA: each lane sign-fills, no spill
    check_vec(2'b10, 2'b01, 64'hF000_0F00_00F0_000F, 64'h0004_0004_0004_0004);  // SRL per-lane

    // ---- Directed: 2x32 independent amounts, break vs 1x64 (same operands) ----
    check_vec(2'b01, 2'b00, 64'h0000_0001_0000_0001, 64'h0000_0010_0000_0004);  // lane0<<4, lane1<<16
    check_vec(2'b01, 2'b10, 64'h8000_0000_8000_0000, 64'h0000_0008_0000_0008);  // SRA both lanes
    check_vec(2'b00, 2'b00, 64'h0000_0000_0000_0001, 64'd32);                   // 1x64 <<32 (crosses bit 32)

    // ---- Corners ----
    check_vec(2'b10, 2'b00, 64'hFFFF_FFFF_FFFF_FFFF, 64'h000F_000F_000F_000F);  // 4x16 all <<15
    check_vec(2'b11, 2'b01, 64'hFFFF_FFFF_FFFF_FFFF, 64'd4);                    // reserved -> 1x64 SRL

    // ---- Handshake corners ----
    check_backpressure(2'b10, 2'b10, 64'h1234_5678_9ABC_DEF0, 64'h0002_0002_0002_0002);
    check_input_invalid(1'b0, 1'b1);
    check_input_invalid(1'b1, 1'b0);
    check_input_invalid(1'b0, 1'b0);

    // ---- Randomized (all modes, all shift types) ----
    for (i = 0; i < NRAND; i = i + 1) begin : rl
      a  = {$random, $random};
      b  = {$random, $random};
      m  = $random;
      op = $random;
      check_vec(m, op, a, b);
    end : rl

    if (error_count == 0) begin : pass_blk
      $display("PASS: fu_barrel_shift_decomp all modes, %0d random vectors, 0 mismatches", NRAND);
    end : pass_blk
    else begin : fail_blk
      $display("FAIL: fu_barrel_shift_decomp %0d mismatches", error_count);
      $fatal(1);
    end : fail_blk
    $finish;
  end : main
endmodule : tb_fu_barrel_shift_decomp
