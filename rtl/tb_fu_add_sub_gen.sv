// Self-checking TB for the unified genuine AddSub tiers (d1/d2/d4/d8).
// One 8-block golden; each tier is checked only over the modes it supports.
module tb;
  logic [1:0]  mode;
  logic [7:0]  op_sel;
  logic [63:0] a, b, y1, y2, y4, y8;

  fu_add_sub_d1 u1 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y1), .out_valid(), .out_ready(1'b1));
  fu_add_sub_d2 u2 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_add_sub_d4 u4 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y4), .out_valid(), .out_ready(1'b1));
  fu_add_sub_d8 u8 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
    .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y8), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  // Lane op (add/sub) at byte-lane [lo..lo+nbytes-1], op taken from op_sel[lo].
  function automatic logic [63:0] gold(input logic [1:0] m, input logic [7:0] op,
                                       input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] r;
    int nb;   // bytes per lane
    r = 64'd0;
    case (m)
      2'b01: nb = 4;   // 2x32
      2'b10: nb = 2;   // 4x16
      2'b11: nb = 1;   // 8x8
      default: nb = 8; // 1x64
    endcase
    for (int lo = 0; lo < 8; lo += nb) begin
      logic [63:0] al, bl, res, lmask;
      int w;
      w = nb * 8;
      lmask = (w == 64) ? {64{1'b1}} : ((64'd1 << w) - 64'd1);
      al = (av >> (lo*8)) & lmask;
      bl = (bv >> (lo*8)) & lmask;
      res = (op[lo] ? (al - bl) : (al + bl)) & lmask;
      r |= (res << (lo*8));
    end
    gold = r;
  endfunction

  task automatic chk(input logic [1:0] m, input logic [7:0] op,
                     input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] g;
    a=av; b=bv; mode=m; op_sel=op; #1;
    g = gold(m, op, av, bv);
    // d8 supports all modes; d4 up to 4x16; d2 up to 2x32; d1 only 1x64.
    if (y8 !== g) begin $display("FAIL d8 m=%b op=%h a=%h b=%h got %h exp %h",m,op,av,bv,y8,g); errors++; end
    if (m != 2'b11 && y4 !== g) begin $display("FAIL d4 m=%b op=%h a=%h b=%h got %h exp %h",m,op,av,bv,y4,g); errors++; end
    if ((m == 2'b00 || m == 2'b01) && y2 !== g) begin $display("FAIL d2 m=%b op=%h a=%h b=%h got %h exp %h",m,op,av,bv,y2,g); errors++; end
    if (m == 2'b00 && y1 !== g) begin $display("FAIL d1 m=%b op=%h a=%h b=%h got %h exp %h",m,op,av,bv,y1,g); errors++; end
  endtask

  logic [63:0] xa, xb; int i;
  initial begin
    // directed: add/sub, borrow/carry across lane boundaries, each mode
    chk(2'b00, 8'h00, 64'h0000000000000001, 64'h0000000000000001); // 64 add
    chk(2'b00, 8'h01, 64'h0000000000000000, 64'h0000000000000001); // 64 sub -> -1 (no lane spill)
    chk(2'b01, 8'h11, 64'h00000000_00000000, 64'h00000001_00000001); // 2x32 sub both lanes
    chk(2'b01, 8'h10, 64'hFFFFFFFF_00000000, 64'h00000001_00000001); // mixed op per 32 lane
    chk(2'b10, 8'h55, 64'h0000_0000_0000_0000, 64'h0001_0001_0001_0001); // 4x16 sub all (no cross-lane borrow)
    chk(2'b11, 8'hFF, 64'h00_00_00_00_00_00_00_00, 64'h01_01_01_01_01_01_01_01); // 8x8 sub all
    chk(2'b11, 8'hAA, 64'hFF_00_FF_00_FF_00_FF_00, 64'h01_01_01_01_01_01_01_01); // 8x8 mixed op

    // randomized across all modes/ops
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321;
    for (i=0;i<40000;i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      chk(xa[1:0], xb[7:0], xa, xb);
    end

    if (errors==0) $display("PASS all (unified tiers == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
