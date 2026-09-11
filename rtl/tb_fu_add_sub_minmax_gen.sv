// Self-checking testbench for AddSub with the shared integer Min/Max side path.
module tb;
  logic [1:0] mode;
  logic is_min_max, is_signed;
  logic [7:0] op_sel;
  logic [63:0] a, b, y1, y2, y4, y8;

  fu_add_sub_minmax_d1 u1 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .is_min_max(is_min_max), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(), .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y1), .out_valid(), .out_ready(1'b1));
  fu_add_sub_minmax_d2 u2 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .is_min_max(is_min_max), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(), .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_add_sub_minmax_d4 u4 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .is_min_max(is_min_max), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(), .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y4), .out_valid(), .out_ready(1'b1));
  fu_add_sub_minmax_d8 u8 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .is_min_max(is_min_max), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(), .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(), .out_data(y8), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  function automatic logic signed [63:0] sign_extend(input logic [63:0] value, input int width);
    sign_extend = $signed(value << (64-width)) >>> (64-width);
  endfunction

  function automatic logic [63:0] gold(input logic mm, input logic sg,
                                       input logic [1:0] m, input logic [7:0] op,
                                       input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] r;
    logic [63:0] al, bl, lmask;
    logic signed [63:0] sal, sbl;
    logic gt;
    int nb, width;
    begin
      case (m)
        2'b01: nb = 4;
        2'b10: nb = 2;
        2'b11: nb = 1;
        default: nb = 8;
      endcase
      width = nb * 8;
      lmask = (width == 64) ? '1 : ((64'd1 << width) - 1);
      r = '0;
      for (int lo = 0; lo < 8; lo += nb) begin
        al = (av >> (lo*8)) & lmask;
        bl = (bv >> (lo*8)) & lmask;
        if (!mm) begin
          r |= ((op[lo] ? al - bl : al + bl) & lmask) << (lo*8);
        end else begin
          sal = sign_extend(al, width);
          sbl = sign_extend(bl, width);
          gt = sg ? (sal > sbl) : (al > bl);
          // min selects A on equality; max selects B on equality.
          r |= ((op[lo] ? (gt ? al : bl) : (gt ? bl : al)) & lmask) << (lo*8);
        end
      end
      gold = r;
    end
  endfunction

  task automatic chk(input logic mm, input logic sg, input logic [1:0] m,
                     input logic [7:0] op, input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] expected;
    begin
      a=av; b=bv; mode=m; is_min_max=mm; is_signed=sg; op_sel=op; #1;
      expected = gold(mm, sg, m, op, av, bv);
      if (y8 !== expected) begin $display("FAIL d8 mm=%b sg=%b m=%b op=%h a=%h b=%h got=%h exp=%h",mm,sg,m,op,av,bv,y8,expected); errors++; end
      if (m != 2'b11 && y4 !== expected) begin $display("FAIL d4"); errors++; end
      if ((m == 2'b00 || m == 2'b01) && y2 !== expected) begin $display("FAIL d2"); errors++; end
      if (m == 2'b00 && y1 !== expected) begin $display("FAIL d1"); errors++; end
    end
  endtask

  logic [63:0] xa, xb;
  logic [7:0] xop;
  int i;
  initial begin
    // Add/sub compatibility plus signed/unsigned Min/Max boundaries and ties.
    chk(0, 0, 2'b00, 8'h01, 64'h0, 64'h1);
    chk(0, 0, 2'b10, 8'h55, 64'h0, 64'h0001_0001_0001_0001);
    chk(1, 1, 2'b00, 8'h00, 64'h8000_0000_0000_0000, 64'h1); // signed min
    chk(1, 1, 2'b00, 8'h01, 64'h8000_0000_0000_0000, 64'h1); // signed max
    chk(1, 0, 2'b00, 8'h00, 64'h8000_0000_0000_0000, 64'h1); // unsigned min
    chk(1, 0, 2'b00, 8'h01, 64'h8000_0000_0000_0000, 64'h1); // unsigned max
    chk(1, 1, 2'b01, 8'h11, 64'h8000_0000_0000_0001, 64'h0000_0001_FFFF_FFFF);
    chk(1, 0, 2'b10, 8'h44, 64'h8000_7FFF_0001_FFFF, 64'h0001_8000_FFFF_0001);
    chk(1, 0, 2'b11, 8'hAA, 64'h00_01_02_03_04_05_06_07, 64'h00_00_03_02_05_04_07_06);
    chk(1, 1, 2'b10, 8'h55, 64'hFFFF_FFFF_FFFF_FFFF, 64'hFFFF_FFFF_FFFF_FFFF); // ties

    xa = 64'h1234_5678_9abc_def0;
    xb = 64'h0fed_cba9_8765_4321;
    xop = 8'h5a;
    for (i = 0; i < 40000; i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      xop = {xop[6:0], xop[7]^xop[5]^xop[1]^xop[0]};
      chk(xa[2], xb[3], xa[1:0], xop, xa, xb);
    end
    if (errors == 0) $display("PASS all (AddSub + shared Min/Max side function == golden)");
    else begin $display("TOTAL FAILURES: %0d", errors); $fatal(1); end
    $finish;
  end
endmodule
