// Self-checking TB for the GENUINE shared-comparator cmp ladder (c1/c2/c4/c8).
// Golden: width-parameterized per-lane predicate -> all-ones/all-zeros mask.
// Each rung is checked only over the modes it supports (c1<=1x64, c2<=2x32,
// c4<=4x16, c8<=8x8).
module tb;
  logic [1:0]  mode;
  logic [3:0]  pred;
  logic [63:0] a, b, y1, y2, y4, y8;

  fu_cmp_c1 d1 (.clk(1'b0), .rst_n(1'b1), .pred(pred),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
    .out_data(y1), .out_valid(), .out_ready(1'b1));
  fu_cmp_c2 d2 (.clk(1'b0), .rst_n(1'b1), .mode(mode[0]), .pred(pred),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
    .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_cmp_c4 d4 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .pred(pred),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
    .out_data(y4), .out_valid(), .out_ready(1'b1));
  fu_cmp_c8 d8 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .pred(pred),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
    .out_data(y8), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  // One-bit predicate result at width W (W in {8,16,32,64}); operands masked to W bits.
  function automatic logic cmp_bit(input int W, input logic [3:0] p,
                                   input logic [63:0] a, input logic [63:0] b);
    logic [63:0] mask, am, bm;
    logic signed [63:0] sa, sb;
    mask = (W == 64) ? {64{1'b1}} : ((64'd1 << W) - 64'd1);
    am = a & mask; bm = b & mask;
    sa = $signed(am << (64 - W)) >>> (64 - W);   // sign-extend the W-bit value
    sb = $signed(bm << (64 - W)) >>> (64 - W);
    case (p)
      4'd0: cmp_bit = (am == bm);   4'd1: cmp_bit = (am != bm);
      4'd2: cmp_bit = (sa <  sb);   4'd3: cmp_bit = (sa <= sb);
      4'd4: cmp_bit = (sa >  sb);   4'd5: cmp_bit = (sa >= sb);
      4'd6: cmp_bit = (am <  bm);   4'd7: cmp_bit = (am <= bm);
      4'd8: cmp_bit = (am >  bm);   4'd9: cmp_bit = (am >= bm);
      default: cmp_bit = 1'b0;
    endcase
  endfunction

  function automatic logic [63:0] gold(input logic [1:0] mm, input logic [3:0] p,
                                       input logic [63:0] a, input logic [63:0] b);
    logic [63:0] r;
    case (mm)
      2'b01: for (int L=0;L<2;L++) r[L*32 +: 32] = {32{cmp_bit(32,p,a>>(L*32),b>>(L*32))}};
      2'b10: for (int L=0;L<4;L++) r[L*16 +: 16] = {16{cmp_bit(16,p,a>>(L*16),b>>(L*16))}};
      2'b11: for (int L=0;L<8;L++) r[L*8  +: 8 ] = {8 {cmp_bit(8, p,a>>(L*8 ),b>>(L*8 ))}};
      default: r = {64{cmp_bit(64,p,a,b)}};
    endcase
    gold = r;
  endfunction

  task automatic chk(input logic [1:0] mm, input logic [3:0] p,
                     input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] g;
    a=av; b=bv; mode=mm; pred=p; #1;
    g = gold(mm,p,av,bv);
    if (y8 !== g) begin
      $display("FAIL c8 m=%b p=%0d a=%h b=%h got %h exp %h",mm,p,av,bv,y8,g); errors++; end
    if (mm!=2'b11 && y4 !== g) begin
      $display("FAIL c4 m=%b p=%0d a=%h b=%h got %h exp %h",mm,p,av,bv,y4,g); errors++; end
    if (mm[1]==1'b0 && y2 !== g) begin
      $display("FAIL c2 m=%b p=%0d a=%h b=%h got %h exp %h",mm,p,av,bv,y2,g); errors++; end
    if (mm==2'b00 && y1 !== g) begin
      $display("FAIL c1 p=%0d a=%h b=%h got %h exp %h",p,av,bv,y1,g); errors++; end
  endtask

  logic [63:0] xa, xb; int i; logic [3:0] pp; logic [1:0] mm;
  initial begin
    // directed: all predicates on fixed pairs across all four modes
    for (int p=0;p<10;p++) begin
      chk(2'b00, p[3:0], 64'h0000000000000005, 64'h0000000000000003);
      chk(2'b00, p[3:0], 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // -1 vs 1
      chk(2'b00, p[3:0], 64'h0123456789ABCDEF, 64'h0123456789ABCDEF); // equal
      chk(2'b01, p[3:0], 64'h80000000_00000005, 64'h00000001_00000003);
      chk(2'b10, p[3:0], 64'h8000_7FFF_FFFF_0001, 64'h0001_0001_0001_0001);
      chk(2'b11, p[3:0], 64'h80_7F_01_FF_00_02_C0_40, 64'h00_7F_02_01_00_01_C0_41);
    end
    chk(2'b00, 4'd15, 64'd7, 64'd7);   // reserved pred -> all zeros
    chk(2'b11, 4'd8, 64'hFF_00_80_7F_01_02_03_04, 64'h01_00_7F_80_04_03_02_01); // 8x8 ugt

    // randomized across all modes / predicates
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321;
    for (i=0;i<40000;i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      pp = xa[3:0]; if (pp>9) pp=pp-4'd6;
      mm = xb[1:0];
      chk(mm, pp, xa, xb);
    end

    if (errors==0) $display("PASS all (genuine == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
