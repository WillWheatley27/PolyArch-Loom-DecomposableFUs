// Self-checking TB for genuine decomposable abs tiers (a1/a2/a3).
// Golden: independent per-lane two's-complement negate (absi) / sign-clear (absf).
module tb;
  logic [1:0]  mode;
  logic        is_float;
  logic [63:0] a, y1, y2, y3;

  fu_abs_a1 d1 (.clk(1'b0), .rst_n(1'b1), .is_float(is_float),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(), .out_data(y1), .out_valid(), .out_ready(1'b1));
  fu_abs_a2 d2 (.clk(1'b0), .rst_n(1'b1), .mode(mode[0]), .is_float(is_float),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_abs_a3 d3 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .is_float(is_float),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(), .out_data(y3), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  // Per-lane golden at width W (16/32/64): absf clears sign bit; absi negates if lane MSB set.
  function automatic logic [63:0] lane_abs(input int W, input logic isf,
                                           input logic [63:0] lane);
    logic [63:0] mask, v;
    mask = (W == 64) ? {64{1'b1}} : ((64'd1 << W) - 64'd1);
    v = lane & mask;
    if (isf) lane_abs = v & ~(64'd1 << (W-1));                 // clear sign bit
    else     lane_abs = v[W-1] ? ((~v + 64'd1) & mask) : v;    // two's-complement negate
  endfunction

  function automatic logic [63:0] gold(input logic [1:0] m, input logic isf,
                                       input logic [63:0] av);
    logic [63:0] r;
    r = 64'd0;
    case (m)
      2'b01: for (int L=0;L<2;L++) r[L*32 +: 32] = lane_abs(32, isf, av>>(L*32));
      2'b10: for (int L=0;L<4;L++) r[L*16 +: 16] = lane_abs(16, isf, av>>(L*16));
      default:                     r             = lane_abs(64, isf, av);
    endcase
    gold = r;
  endfunction

  task automatic chk(input logic [1:0] m, input logic isf, input logic [63:0] av);
    logic [63:0] g;
    a=av; mode=m; is_float=isf; #1;
    g = gold(m, isf, av);
    if (y3 !== g) begin $display("FAIL a3 m=%b f=%b a=%h got %h exp %h",m,isf,av,y3,g); errors++; end
    if (m[1]==1'b0 && y2 !== g) begin $display("FAIL a2 m=%b f=%b a=%h got %h exp %h",m,isf,av,y2,g); errors++; end
    if (m==2'b00 && y1 !== g) begin $display("FAIL a1 f=%b a=%h got %h exp %h",isf,av,y1,g); errors++; end
  endtask

  logic [63:0] xa; int i;
  initial begin
    // directed: INT_MIN wrap, -1, +max, sign boundaries per width; FP sign-clear
    chk(2'b00, 1'b0, 64'h8000000000000000); // int64 INT_MIN -> itself
    chk(2'b00, 1'b0, 64'hFFFFFFFFFFFFFFFF); // -1 -> 1
    chk(2'b00, 1'b0, 64'h7FFFFFFFFFFFFFFF); // +max -> itself
    chk(2'b01, 1'b0, 64'h80000000_FFFFFFFF); // 2x32: INT_MIN, -1
    chk(2'b10, 1'b0, 64'h8000_FFFF_7FFF_0001); // 4x16: INT_MIN,-1,+max,+1
    chk(2'b00, 1'b1, 64'hC000000000000000); // fp64 -2.0 -> +2.0
    chk(2'b01, 1'b1, 64'hBF800000_40000000); // fp32 -1.0, +2.0
    chk(2'b10, 1'b1, 64'hC000_BC00_3C00_8000); // fp16 lanes incl -0

    // randomized across modes / is_float
    xa = 64'hDEAD_BEEF_1234_5678;
    for (i=0;i<40000;i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      chk(xa[1:0]==2'b11 ? 2'b10 : xa[1:0], xa[5], xa);
    end

    if (errors==0) $display("PASS all (genuine == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
