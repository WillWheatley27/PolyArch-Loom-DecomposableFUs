// Self-checking TB for genuine packed-FP compare tiers (g1/g2/g3).
// Golden: independent per-lane IEEE compare -> predicate -> all-ones/all-zeros mask.
module tb;
  logic [1:0]  mode;
  logic [3:0]  pred;
  logic [63:0] a, b, y1, y2, y3;

  fu_fp_cmp_g1 d1 (.clk(1'b0), .rst_n(1'b1), .pred(pred),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y1), .out_valid(), .out_ready(1'b1));
  fu_fp_cmp_g2 d2 (.clk(1'b0), .rst_n(1'b1), .mode(mode[0]), .pred(pred),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_fp_cmp_g3 d3 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .pred(pred),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y3), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  // Reference predicate bit for one lane of width (EXP_W,MAN_W), operands in low bits.
  function automatic logic cmp_bit(input int EXP_W, input int MAN_W, input logic [3:0] p,
                                   input logic [63:0] a, input logic [63:0] b);
    logic [63:0] EXP_MASK, MAN_MASK, MAG_MASK, mag_a, mag_b;
    logic ea_ones, eb_ones, sa, sb, a_nan, b_nan, a_zero, b_zero, uno, lt, gt, eq_;
    logic [63:0] ea, eb, ma, mb;
    EXP_MASK = (64'd1 << EXP_W) - 64'd1;  MAN_MASK = (64'd1 << MAN_W) - 64'd1;
    MAG_MASK = (64'd1 << (EXP_W+MAN_W)) - 64'd1;
    sa = a[EXP_W+MAN_W]; sb = b[EXP_W+MAN_W];
    ea = (a >> MAN_W) & EXP_MASK; eb = (b >> MAN_W) & EXP_MASK;
    ma = a & MAN_MASK; mb = b & MAN_MASK;
    a_nan=(ea==EXP_MASK)&&(ma!=0); b_nan=(eb==EXP_MASK)&&(mb!=0);
    a_zero=(ea==0)&&(ma==0); b_zero=(eb==0)&&(mb==0);
    uno=a_nan|b_nan; mag_a=a&MAG_MASK; mag_b=b&MAG_MASK;
    if (a_zero && b_zero) begin lt=0; gt=0; eq_=1; end
    else begin
      if (sa!=sb)   begin lt=sa;            gt=sb;            end
      else if (sa)  begin lt=mag_a>mag_b;   gt=mag_a<mag_b;   end
      else          begin lt=mag_a<mag_b;   gt=mag_a>mag_b;   end
      eq_ = ~lt & ~gt;
    end
    case (p)
      4'd0: cmp_bit=0;            4'd1: cmp_bit=~uno&eq_;
      4'd2: cmp_bit=~uno&gt;      4'd3: cmp_bit=~uno&(gt|eq_);
      4'd4: cmp_bit=~uno&lt;      4'd5: cmp_bit=~uno&(lt|eq_);
      4'd6: cmp_bit=~uno&(lt|gt); 4'd7: cmp_bit=~uno;
      4'd8: cmp_bit=uno|eq_;      4'd9: cmp_bit=uno|gt;
      4'd10:cmp_bit=uno|(gt|eq_); 4'd11:cmp_bit=uno|lt;
      4'd12:cmp_bit=uno|(lt|eq_); 4'd13:cmp_bit=uno|(lt|gt);
      4'd14:cmp_bit=uno;          default: cmp_bit=1;
    endcase
  endfunction

  function automatic logic [63:0] gold(input logic [1:0] mm, input logic [3:0] p,
                                       input logic [63:0] a, input logic [63:0] b);
    logic [63:0] r;
    case (mm)
      2'b01: for (int L=0;L<2;L++) r[L*32 +: 32] = {32{cmp_bit(8, 23,p,a>>(L*32),b>>(L*32))}};
      2'b10: for (int L=0;L<4;L++) r[L*16 +: 16] = {16{cmp_bit(5, 10,p,a>>(L*16),b>>(L*16))}};
      default: r = {64{cmp_bit(11,52,p,a,b)}};
    endcase
    gold = r;
  endfunction

  task automatic chk(input logic [1:0] mm, input logic [3:0] p,
                     input logic [63:0] av, input logic [63:0] bv);
    a=av; b=bv; mode=mm; pred=p; #1;
    if (y3 !== gold(mm,p,av,bv)) begin
      $display("FAIL g3 m=%b p=%0d a=%h b=%h got %h exp %h",mm,p,av,bv,y3,gold(mm,p,av,bv)); errors++; end
    if (mm[1]==1'b0 && y2 !== gold(mm,p,av,bv)) begin
      $display("FAIL g2 m=%b p=%0d a=%h b=%h got %h exp %h",mm,p,av,bv,y2,gold(mm,p,av,bv)); errors++; end
    if (mm==2'b00 && y1 !== gold(mm,p,av,bv)) begin
      $display("FAIL g1 p=%0d a=%h b=%h got %h exp %h",p,av,bv,y1,gold(mm,p,av,bv)); errors++; end
  endtask

  logic [63:0] xa, xb; int i; logic [3:0] pp; logic [1:0] mm;
  initial begin
    // directed corners: fp64 NaN/Inf/+-0, fp32 lanes, fp16 lanes, all predicates
    for (int p=0;p<16;p++) begin
      chk(2'b00, p[3:0], 64'h3FF0000000000000, 64'h4000000000000000); // 1.0 vs 2.0
      chk(2'b00, p[3:0], 64'h7FF8000000000000, 64'h3FF0000000000000); // qNaN vs 1.0
      chk(2'b00, p[3:0], 64'h8000000000000000, 64'h0000000000000000); // -0 vs +0
      chk(2'b00, p[3:0], 64'hFFF0000000000000, 64'h7FF0000000000000); // -Inf vs +Inf
      chk(2'b01, p[3:0], 64'h3F800000_C0000000, 64'h40000000_BF800000); // fp32: (1,-2) vs (2,-1)
      chk(2'b01, p[3:0], 64'h7FC00000_00000000, 64'h3F800000_80000000); // fp32: (NaN,+0) vs (1,-0)
      chk(2'b10, p[3:0], 64'h3C00_C000_7E00_0000, 64'h4000_BC00_3C00_8000); // fp16 four lanes
      chk(2'b10, p[3:0], 64'h7C00_FC00_0000_8000, 64'h7C00_FC00_8000_0000); // +-Inf, +-0
    end

    // randomized across all modes / predicates (LFSR operands hit NaN/Inf/denormal patterns)
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321;
    for (i=0;i<60000;i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      pp = xa[3:0]; mm = xb[1:0];
      chk(mm, pp, xa, xb);
    end

    if (errors==0) $display("PASS all (genuine == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
