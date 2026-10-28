// Self-checking TB for the AddSub window-fix variants (rtl/fu_add_sub_window_fix.sv): the
// partitioned (part) and lane-block carry-increment (blkinc) units are combinational and are
// checked in every mode their tier supports; the pipelined unit (pipe) is checked one cycle
// later in 64-bit mode (back to back, so a wrong stage register shows) and combinationally
// otherwise, plus a backpressure stall.
module tb;
  logic        clk = 1'b0, rst_n = 1'b0, out_ready = 1'b1;
  logic [1:0]  mode;
  logic [7:0]  op_sel;
  logic [63:0] a, b;
  logic [63:0] part [3], blk [3], pipe [3];
  logic        pipe_valid [3], pipe_ready [3];

  // tier t: 0 -> d2 (64, 2x32), 1 -> d4 (+4x16), 2 -> d8 (+8x8)
  for (genvar t = 0; t < 3; t++) begin : tier
    localparam bit E16 = t >= 1;
    localparam bit E8  = t >= 2;
    fu_add_sub_part #(.EN32(1), .EN16(E16), .EN8(E8)) u_part (
      .clk(clk), .rst_n(rst_n), .mode(mode), .op_sel(op_sel),
      .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
      .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
      .out_data(part[t]), .out_valid(), .out_ready(1'b1));
    fu_add_sub_blkinc #(.EN32(1), .EN16(E16), .EN8(E8)) u_blk (
      .clk(clk), .rst_n(rst_n), .mode(mode), .op_sel(op_sel),
      .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
      .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
      .out_data(blk[t]), .out_valid(), .out_ready(1'b1));
    fu_add_sub_pipe #(.EN32(1), .EN16(E16), .EN8(E8)) u_pipe (
      .clk(clk), .rst_n(rst_n), .mode(mode), .op_sel(op_sel),
      .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(pipe_ready[t]),
      .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
      .out_data(pipe[t]), .out_valid(pipe_valid[t]), .out_ready(out_ready));
  end

  int errors = 0;
  `include "add_sub_lane_gold.svh"

  function automatic bit supports(int t, logic [1:0] m);
    return m == 2'b00 || m == 2'b01 || (m == 2'b10 && t >= 1) || t >= 2;
  endfunction

  task automatic expect_eq(input string who, input int t, input logic [63:0] got, input logic [63:0] g);
    if (got !== g) begin
      $display("FAIL %s d%0d m=%b op=%h a=%h b=%h got %h exp %h", who, 2 << t, mode, op_sel, a, b, got, g);
      errors++;
    end
  endtask

  task automatic tick;
    clk = 1'b1; #1; clk = 1'b0; #1;
  endtask

  // Apply one operation, check the outputs, then clock it in. prev/prev_m: the operation
  // clocked in on the previous cycle (what the pipe shows in 64-bit mode).
  logic [63:0] prev;
  logic [1:0]  prev_m;
  task automatic step(input logic [1:0] m, input logic [7:0] op, input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] g;
    a = av; b = bv; mode = m; op_sel = op; #1;
    g = gold(m, op, av, bv);
    for (int t = 0; t < 3; t++) begin
      if (!supports(t, m)) continue;
      expect_eq("part", t, part[t], g);
      expect_eq("blkinc", t, blk[t], g);
      if (m != 2'b00) expect_eq("pipe", t, pipe[t], g);
      else if (prev_m == 2'b00) begin
        expect_eq("pipe(64, previous op)", t, pipe[t], prev);
        if (pipe_valid[t] !== 1'b1) begin $display("FAIL pipe d%0d out_valid low", 2 << t); errors++; end
      end
    end
    tick;
    prev = g; prev_m = m;
  endtask

  logic [63:0] xa, xb, held; int i;
  initial begin
    prev_m = 2'b11;
    mode = 2'b00; op_sel = '0; a = '0; b = '0;
    #1 rst_n = 1'b1;
    // directed: full-width carry/borrow chains and their isolation at every lane boundary
    step(2'b00, 8'h00, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // carry through all 64 bits
    step(2'b00, 8'h01, 64'h0000000000000000, 64'h0000000000000001); // borrow through all 64 bits
    step(2'b00, 8'h00, 64'h00000000FFFFFFFF, 64'h0000000000000001); // carry across bit 32 only
    step(2'b00, 8'h01, 64'h0000000100000000, 64'h0000000000000001); // borrow across bit 32 only
    step(2'b01, 8'h00, 64'hFFFFFFFF_FFFFFFFF, 64'h00000001_00000001); // carry stops at bit 32
    step(2'b01, 8'h11, 64'h00000000_00000000, 64'h00000001_00000001); // 2x32 sub both lanes
    step(2'b01, 8'h10, 64'hFFFFFFFF_00000000, 64'h00000001_00000001); // mixed op per 32 lane
    step(2'b10, 8'h00, 64'hFFFF_FFFF_FFFF_FFFF, 64'h0001_0001_0001_0001); // carry stops at each 16
    step(2'b10, 8'h55, 64'h0000_0000_0000_0000, 64'h0001_0001_0001_0001); // 4x16 sub all
    step(2'b11, 8'h00, 64'hFF_FF_FF_FF_FF_FF_FF_FF, 64'h01_01_01_01_01_01_01_01); // carry stops at each 8
    step(2'b11, 8'hFF, 64'h00_00_00_00_00_00_00_00, 64'h01_01_01_01_01_01_01_01); // 8x8 sub all
    step(2'b11, 8'hAA, 64'hFF_00_FF_00_FF_00_FF_00, 64'h01_01_01_01_01_01_01_01); // 8x8 mixed op

    // randomized: runs of one mode (as a scheduler would issue them), random ops and operands
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321;
    for (i = 0; i < 40000; i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      step(2'((i / 37) % 4), xb[7:0], xa, xb);
    end

    // backpressure in 64-bit mode: a stalled stage holds its result and refuses new input
    step(2'b00, 8'h00, 64'h0000000000000005, 64'h0000000000000003);   // stage holds 8
    held = prev;
    out_ready = 1'b0;
    a = 64'h7; b = 64'h7; #1;
    for (int t = 0; t < 3; t++)
      if (pipe_ready[t] !== 1'b0) begin $display("FAIL pipe d%0d in_ready high while stalled", 2 << t); errors++; end
    tick;
    for (int t = 0; t < 3; t++) expect_eq("pipe(stalled)", t, pipe[t], held);
    out_ready = 1'b1; #1;
    for (int t = 0; t < 3; t++)
      if (pipe_ready[t] !== 1'b1) begin $display("FAIL pipe d%0d in_ready low after stall", 2 << t); errors++; end
    tick;
    for (int t = 0; t < 3; t++) expect_eq("pipe(after stall)", t, pipe[t], 64'he);

    if (errors == 0) $display("PASS all (part, blkinc, pipe tiers == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
