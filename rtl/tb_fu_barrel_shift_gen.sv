// Self-checking TB for the genuine barrel-shift tiers (g1/g2/g3).
// Golden: independent per-lane SLL/SRL/SRA using native shift operators, count masked to
// the lane width. Each tier is checked only over the modes it supports.
module tb;
  logic [1:0]  mode;
  logic [1:0]  shift_op;
  logic [63:0] a, amt, y1, y2, y3;

  fu_bshift_bs1 u1 (.clk(1'b0), .rst_n(1'b1), .shift_op(shift_op),
    .in_data_0(a),   .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(amt), .in_valid_1(1'b1), .in_ready_1(), .out_data(y1), .out_valid(), .out_ready(1'b1));
  fu_bshift_bs2 u2 (.clk(1'b0), .rst_n(1'b1), .mode(mode[0]), .shift_op(shift_op),
    .in_data_0(a),   .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(amt), .in_valid_1(1'b1), .in_ready_1(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_bshift_bs3 u3 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .shift_op(shift_op),
    .in_data_0(a),   .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(amt), .in_valid_1(1'b1), .in_ready_1(), .out_data(y3), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  // One lane of width W (16/32/64): op 00 SLL,01 SRL,10 SRA,11->SLL. Count masked to log2(W).
  function automatic logic [63:0] lane_sh(input int W, input logic [1:0] op,
                                          input logic [63:0] xv, input logic [63:0] cv);
    logic [63:0] mask, x, fill; int sh; logic s;
    mask = (W == 64) ? {64{1'b1}} : ((64'd1 << W) - 64'd1);
    x   = xv & mask;
    sh  = cv & (W - 1);                                  // low log2(W) count bits
    s   = x[W-1];                                        // lane sign
    fill = mask & ~(((64'd1 << (W - sh)) - 64'd1));      // top sh bits of the lane
    case (op)
      2'b01:   lane_sh = (x >> sh) & mask;               // SRL: zero fill
      2'b10:   lane_sh = ((x >> sh) & mask) | (s ? fill : 64'd0); // SRA: sign fill
      default: lane_sh = (x << sh) & mask;               // SLL: zero fill
    endcase
  endfunction

  function automatic logic [63:0] gold(input logic [1:0] m, input logic [1:0] op,
                                       input logic [63:0] xv, input logic [63:0] cv);
    logic [63:0] r;
    case (m)
      2'b01: for (int L=0;L<2;L++) r[L*32 +: 32] = lane_sh(32, op, xv>>(L*32), cv>>(L*32));
      2'b10: for (int L=0;L<4;L++) r[L*16 +: 16] = lane_sh(16, op, xv>>(L*16), cv>>(L*16));
      default:                     r             = lane_sh(64, op, xv,         cv);
    endcase
    gold = r;
  endfunction

  task automatic chk(input logic [1:0] m, input logic [1:0] op,
                     input logic [63:0] xv, input logic [63:0] cv);
    logic [63:0] g;
    a=xv; amt=cv; mode=m; shift_op=op; #1;
    g = gold(m, op, xv, cv);
    if (y3 !== g) begin $display("FAIL g3 m=%b op=%b a=%h amt=%h got %h exp %h",m,op,xv,cv,y3,g); errors++; end
    if ((m==2'b00 || m==2'b01) && y2 !== g) begin
      $display("FAIL g2 m=%b op=%b a=%h amt=%h got %h exp %h",m,op,xv,cv,y2,g); errors++; end
    if (m==2'b00 && y1 !== g) begin
      $display("FAIL g1 op=%b a=%h amt=%h got %h exp %h",op,xv,cv,y1,g); errors++; end
  endtask

  logic [63:0] xa, xc; int i;
  initial begin
    // directed: each op, boundary counts (0, W-1, >=W wraps), sign patterns, per mode
    for (int op=0;op<4;op++) begin
      chk(2'b00, op[1:0], 64'hF0F0_F0F0_0F0F_0F0F, 64'd0);   // count 0 -> identity
      chk(2'b00, op[1:0], 64'h8000_0000_0000_0001, 64'd63);  // max 64-bit count
      chk(2'b00, op[1:0], 64'hFEDC_BA98_7654_3210, 64'd1);
      chk(2'b01, op[1:0], 64'h8000_0001_8000_0001, 64'h0000_001F_0000_001F); // 2x32 count 31
      chk(2'b01, op[1:0], 64'hDEAD_BEEF_CAFE_BABE, 64'h0000_0005_0000_000B);
      chk(2'b10, op[1:0], 64'h8001_8001_8001_8001, 64'h000F_000F_000F_000F);  // 4x16 count 15
      chk(2'b10, op[1:0], 64'h1234_5678_9ABC_DEF0, 64'h0003_0007_000A_000F);
    end

    // randomized across all modes / ops (LFSR data + counts)
    xa = 64'h1234_5678_9ABC_DEF0; xc = 64'h0FED_CBA9_8765_4321;
    for (i=0;i<80000;i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xc = {xc[62:0], xc[63]^xc[59]^xc[4]^xc[1]};
      chk(xc[1:0]==2'b11 ? 2'b10 : xc[1:0], xa[1:0], xa, xc); // reserved mode 11 -> 4x16
    end

    if (errors==0) $display("PASS all (genuine == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
