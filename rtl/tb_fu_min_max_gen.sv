// Self-checking TB for the unified genuine min/max tiers (m1/m2/m4).
// One width-parameterized golden; each tier is checked only over the modes it supports.
module tb;
  logic [1:0]  mode;
  logic        is_signed;
  logic [3:0]  op_sel;
  logic [63:0] a, b, y1, y2, y4;

  fu_min_max_m1 u1 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y1), .out_valid(), .out_ready(1'b1));
  fu_min_max_m2 u2 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_min_max_m4 u4 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y4), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  // Per-lane min/max at width W (W in {16,32,64}); operands are the W-bit lane values.
  function automatic logic [63:0] lane_res(input int W, input logic op, input logic sgn,
                                           input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] mask, am, bm;
    logic signed [63:0] sa, sb;
    logic agt;
    mask = (W == 64) ? {64{1'b1}} : ((64'd1 << W) - 64'd1);
    am = av & mask; bm = bv & mask;
    sa = $signed(am << (64 - W)) >>> (64 - W);   // sign-extend the W-bit value
    sb = $signed(bm << (64 - W)) >>> (64 - W);
    agt = sgn ? (sa > sb) : (am > bm);
    // op=1 max -> larger; op=0 min -> smaller
    lane_res = (op ? agt : ~agt) ? am : bm;
  endfunction

  function automatic logic [63:0] gold(input logic [1:0] m, input logic sgn, input logic [3:0] op,
                                       input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] r;
    r = 64'd0;
    case (m)
      2'b01: for (int L=0;L<2;L++) r[L*32 +: 32] = lane_res(32, op[L*2],  sgn, av>>(L*32), bv>>(L*32));
      2'b10: for (int L=0;L<4;L++) r[L*16 +: 16] = lane_res(16, op[L],    sgn, av>>(L*16), bv>>(L*16));
      default:                     r             = lane_res(64, op[0],    sgn, av,         bv);
    endcase
    gold = r;
  endfunction

  task automatic chk(input logic [1:0] m, input logic sgn, input logic [3:0] op,
                     input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] g;
    a=av; b=bv; mode=m; is_signed=sgn; op_sel=op; #1;
    g = gold(m, sgn, op, av, bv);
    // m4 supports all modes; m2 up to 2x32; m1 only 1x64.
    if (y4 !== g) begin $display("FAIL m4 m=%b s=%b op=%h a=%h b=%h got %h exp %h",m,sgn,op,av,bv,y4,g); errors++; end
    if ((m == 2'b00 || m == 2'b01) && y2 !== g) begin $display("FAIL m2 m=%b s=%b op=%h a=%h b=%h got %h exp %h",m,sgn,op,av,bv,y2,g); errors++; end
    if (m == 2'b00 && y1 !== g) begin $display("FAIL m1 m=%b s=%b op=%h a=%h b=%h got %h exp %h",m,sgn,op,av,bv,y1,g); errors++; end
  endtask

  logic [63:0] xa, xb; int i;
  initial begin
    // directed: signed/unsigned, min/max, sign-boundary values, each mode
    chk(2'b00, 1'b1, 4'h0, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // signed min: -1 vs 1 -> -1
    chk(2'b00, 1'b1, 4'h1, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // signed max: -1 vs 1 -> 1
    chk(2'b00, 1'b0, 4'h0, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // unsigned min -> 1
    chk(2'b00, 1'b0, 4'h1, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // unsigned max -> FFFF..
    chk(2'b01, 1'b1, 4'h4, 64'h80000000_7FFFFFFF, 64'h00000001_00000001); // 2x32 signed, mixed op per lane
    chk(2'b10, 1'b1, 4'h6, 64'h8000_7FFF_0001_FFFF, 64'h0001_0001_0001_0001); // 4x16 signed, mixed op
    chk(2'b10, 1'b0, 4'h9, 64'h8000_7FFF_0001_FFFF, 64'h0001_0001_0001_0001); // 4x16 unsigned, mixed op
    chk(2'b01, 1'b0, 4'h0, 64'h00000000_FFFFFFFF, 64'hFFFFFFFF_00000000); // 2x32 unsigned min

    // randomized across supported modes / signedness / per-lane ops
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321;
    for (i=0;i<40000;i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      chk(xa[1:0]==2'b11 ? 2'b10 : xa[1:0], xb[7], xa[3:0], xa, xb); // map reserved mode 11 -> 4x16
    end

    if (errors==0) $display("PASS all (unified tiers == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
