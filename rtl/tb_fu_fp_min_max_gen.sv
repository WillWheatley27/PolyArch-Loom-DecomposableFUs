// Self-checking TB for genuine packed-FP min/max tiers (m1/m2/m3).
// Golden: independent per-lane IEEE-2019 min/max (NaN-propagate, -0 < +0).
module tb;
  logic [1:0]  mode;
  logic [3:0]  op_sel;
  logic [63:0] a, b, y1, y2, y3;

  fu_fp_min_max_m1 d1 (.clk(1'b0), .rst_n(1'b1), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y1), .out_valid(), .out_ready(1'b1));
  fu_fp_min_max_m2 d2 (.clk(1'b0), .rst_n(1'b1), .mode(mode[0]), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_fp_min_max_m3 d3 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y3), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  // Reference lane result for width (EXP_W,MAN_W); operands in low bits, result in low bits.
  function automatic logic [63:0] mm_lane(input int EXP_W, input int MAN_W, input logic is_max,
                                          input logic [63:0] a, input logic [63:0] b);
    logic [63:0] EXP_MASK, MAN_MASK, MAG_MASK, mag_a, mag_b, qnan;
    logic sa, sb, a_nan, b_nan, a_lt;
    logic [63:0] ea, eb, ma, mb;
    EXP_MASK = (64'd1 << EXP_W) - 64'd1;  MAN_MASK = (64'd1 << MAN_W) - 64'd1;
    MAG_MASK = (64'd1 << (EXP_W+MAN_W)) - 64'd1;
    qnan = (EXP_MASK << MAN_W) | (64'd1 << (MAN_W-1));
    sa = a[EXP_W+MAN_W]; sb = b[EXP_W+MAN_W];
    ea = (a >> MAN_W) & EXP_MASK; eb = (b >> MAN_W) & EXP_MASK;
    ma = a & MAN_MASK; mb = b & MAN_MASK;
    a_nan=(ea==EXP_MASK)&&(ma!=0); b_nan=(eb==EXP_MASK)&&(mb!=0);
    if (a_nan || b_nan) mm_lane = qnan;
    else begin
      mag_a=a&MAG_MASK; mag_b=b&MAG_MASK;
      if (sa!=sb)  a_lt = sa;             // differing signs: negative one is smaller (-0<+0)
      else if (sa) a_lt = mag_a > mag_b;  // both negative: larger magnitude is smaller
      else         a_lt = mag_a < mag_b;  // both positive: smaller magnitude is smaller
      mm_lane = (is_max ? (a_lt ? b : a) : (a_lt ? a : b)) & ((EXP_W+MAN_W==63) ? {64{1'b1}} : ((64'd1<<(EXP_W+MAN_W+1))-64'd1));
    end
  endfunction

  function automatic logic [63:0] gold(input logic [1:0] mm, input logic [3:0] op,
                                       input logic [63:0] a, input logic [63:0] b);
    logic [63:0] r;
    case (mm)
      2'b01: begin
        r[31:0]  = mm_lane(8,23, op[0], a & 64'hFFFF_FFFF, b & 64'hFFFF_FFFF);
        r[63:32] = mm_lane(8,23, op[2], a >> 32,           b >> 32);
      end
      2'b10: begin
        r[15:0]  = mm_lane(5,10, op[0],  a & 64'hFFFF,          b & 64'hFFFF);
        r[31:16] = mm_lane(5,10, op[1], (a >> 16) & 64'hFFFF,  (b >> 16) & 64'hFFFF);
        r[47:32] = mm_lane(5,10, op[2], (a >> 32) & 64'hFFFF,  (b >> 32) & 64'hFFFF);
        r[63:48] = mm_lane(5,10, op[3], (a >> 48) & 64'hFFFF,  (b >> 48) & 64'hFFFF);
      end
      default: r = mm_lane(11,52, op[0], a, b);
    endcase
    gold = r;
  endfunction

  task automatic chk(input logic [1:0] mm, input logic [3:0] op,
                     input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] g;
    a=av; b=bv; mode=mm; op_sel=op; #1;
    g = gold(mm,op,av,bv);
    if (y3 !== g) begin $display("FAIL m3 m=%b op=%h a=%h b=%h got %h exp %h",mm,op,av,bv,y3,g); errors++; end
    if (mm[1]==1'b0 && y2 !== g) begin $display("FAIL m2 m=%b op=%h a=%h b=%h got %h exp %h",mm,op,av,bv,y2,g); errors++; end
    if (mm==2'b00 && y1 !== g) begin $display("FAIL m1 op=%h a=%h b=%h got %h exp %h",op,av,bv,y1,g); errors++; end
  endtask

  logic [63:0] xa, xb; int i;
  initial begin
    // directed: NaN propagate, +-0 ordering, +-Inf, mixed op per lane
    chk(2'b00, 4'h1, 64'h3FF0000000000000, 64'h4000000000000000); // max(1,2)=2
    chk(2'b00, 4'h0, 64'h7FF8000000000000, 64'h3FF0000000000000); // min(NaN,1)=qNaN
    chk(2'b00, 4'h1, 64'h8000000000000000, 64'h0000000000000000); // max(-0,+0)=+0
    chk(2'b00, 4'h0, 64'h8000000000000000, 64'h0000000000000000); // min(-0,+0)=-0
    chk(2'b00, 4'h0, 64'hFFF0000000000000, 64'h7FF0000000000000); // min(-Inf,+Inf)=-Inf
    chk(2'b01, 4'h4, 64'h3F800000_C0000000, 64'h40000000_BF800000); // fp32 lanes, mixed op
    chk(2'b01, 4'h1, 64'h7FC00000_00000000, 64'h3F800000_80000000); // fp32 NaN + -0/+0
    chk(2'b10, 4'h6, 64'h3C00_C000_7E00_0000, 64'h4000_BC00_3C00_8000); // fp16 four lanes
    chk(2'b10, 4'h0, 64'h7C00_FC00_0000_8000, 64'h7C00_FC00_8000_0000); // fp16 +-Inf,+-0

    // randomized across modes / per-lane op (LFSR hits NaN/Inf/denormal patterns)
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321;
    for (i=0;i<60000;i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      chk(xa[1:0]==2'b11 ? 2'b10 : xa[1:0], xb[3:0], xa, xb);
    end

    if (errors==0) $display("PASS all (genuine == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
