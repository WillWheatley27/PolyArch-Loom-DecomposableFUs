// Self-checking TB for the parallel-prefix AddSub: tiers (pd2/pd4/pd8) over the modes each
// supports, and the fixed units (p64/p32x2/p16x4/p8x8) in their one lane width.
module tb;
  logic [1:0]  mode;
  logic [7:0]  op_sel;
  logic [63:0] a, b, y2, y4, y8, f64, f32, f16, f8;

  fu_add_sub_pd2 u2 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_add_sub_pd4 u4 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y4), .out_valid(), .out_ready(1'b1));
  fu_add_sub_pd8 u8 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y8), .out_valid(), .out_ready(1'b1));
  // Fixed units: lane i's op is op_sel[i] (the lane-start block's bit in the tiers' encoding).
  fu_add_sub_p64 p64 (.clk(1'b0), .rst_n(1'b1), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(f64), .out_valid(), .out_ready(1'b1));
  fu_add_sub_p32x2 p32 (.clk(1'b0), .rst_n(1'b1), .op_sel({op_sel[4], op_sel[0]}),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(f32), .out_valid(), .out_ready(1'b1));
  fu_add_sub_p16x4 p16 (.clk(1'b0), .rst_n(1'b1), .op_sel({op_sel[6], op_sel[4], op_sel[2], op_sel[0]}),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(f16), .out_valid(), .out_ready(1'b1));
  fu_add_sub_p8x8 p8 (.clk(1'b0), .rst_n(1'b1), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(f8), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  `include "add_sub_lane_gold.svh"

  task automatic expect_eq(input string who, input logic [1:0] m, input logic [63:0] got,
                           input logic [63:0] g);
    if (got !== g) begin
      $display("FAIL %s m=%b op=%h a=%h b=%h got %h exp %h", who, m, op_sel, a, b, got, g);
      errors++;
    end
  endtask

  task automatic chk(input logic [1:0] m, input logic [7:0] op,
                     input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] g;
    a=av; b=bv; mode=m; op_sel=op; #1;
    g = gold(m, op, av, bv);
    expect_eq("pd8", m, y8, g);
    if (m != 2'b11) expect_eq("pd4", m, y4, g);
    if (m == 2'b00 || m == 2'b01) expect_eq("pd2", m, y2, g);
    case (m)
      2'b00: expect_eq("p64", m, f64, g);
      2'b01: expect_eq("p32x2", m, f32, g);
      2'b10: expect_eq("p16x4", m, f16, g);
      default: expect_eq("p8x8", m, f8, g);
    endcase
  endtask

  logic [63:0] xa, xb; int i;
  initial begin
    // directed: full-width carry/borrow chains and their isolation at every lane boundary
    chk(2'b00, 8'h00, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // carry through all 64 bits
    chk(2'b00, 8'h01, 64'h0000000000000000, 64'h0000000000000001); // borrow through all 64 bits
    chk(2'b01, 8'h00, 64'hFFFFFFFF_FFFFFFFF, 64'h00000001_00000001); // carry stops at bit 32
    chk(2'b01, 8'h11, 64'h00000000_00000000, 64'h00000001_00000001); // 2x32 sub both lanes
    chk(2'b01, 8'h10, 64'hFFFFFFFF_00000000, 64'h00000001_00000001); // mixed op per 32 lane
    chk(2'b10, 8'h00, 64'hFFFF_FFFF_FFFF_FFFF, 64'h0001_0001_0001_0001); // carry stops at each 16
    chk(2'b10, 8'h55, 64'h0000_0000_0000_0000, 64'h0001_0001_0001_0001); // 4x16 sub all
    chk(2'b11, 8'h00, 64'hFF_FF_FF_FF_FF_FF_FF_FF, 64'h01_01_01_01_01_01_01_01); // carry stops at each 8
    chk(2'b11, 8'hFF, 64'h00_00_00_00_00_00_00_00, 64'h01_01_01_01_01_01_01_01); // 8x8 sub all
    chk(2'b11, 8'hAA, 64'hFF_00_FF_00_FF_00_FF_00, 64'h01_01_01_01_01_01_01_01); // 8x8 mixed op

    // randomized across all modes/ops
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321;
    for (i=0;i<40000;i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      chk(xa[1:0], xb[7:0], xa, xb);
    end

    if (errors==0) $display("PASS all (prefix tiers and fixed units == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
