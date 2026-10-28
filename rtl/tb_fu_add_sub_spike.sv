// Self-checking TB for the AddSub spike variants (rtl/fu_add_sub_spike.sv): every ARCH x FLAT
// combination as tiers d2, d4 and d8 (ARCH 2: d2 and d4), each checked in every mode its tier
// supports; the REP_OP variants (op_sel replicated per block) for every ARCH; and the 32x2 probe
// on each adder primitive, against the 2x32 golden.
module tb;
  logic [1:0]  mode;
  logic [7:0]  op_sel;
  logic [63:0] a, b;
  logic [63:0] y [4][2][3];   // [ARCH][FLAT][tier]
  logic [63:0] yr [4][3];     // REP_OP: [ARCH][tier]
  logic [7:0]  op_rep;        // each block gets its lane's op (the lane-start bit of op_sel)

  for (genvar arch = 0; arch < 4; arch++) begin : g_arch
    for (genvar flat = 0; flat < 2; flat++) begin : g_flat
      for (genvar t = 0; t < (arch == 2 ? 2 : 3); t++) begin : g_tier   // 0: d2, 1: d4, 2: d8
        fu_add_sub_spike #(.ARCH(arch), .FLAT(flat), .EN32(1), .EN16(t >= 1), .EN8(t >= 2)) dut (
          .clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_sel),
          .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
          .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
          .out_data(y[arch][flat][t]), .out_valid(), .out_ready(1'b1));
      end
    end
  end

  for (genvar arch = 0; arch < 4; arch++) begin : g_rep
    for (genvar t = 0; t < (arch == 2 ? 2 : 3); t++) begin : g_tier
      fu_add_sub_spike #(.ARCH(arch), .REP_OP(1), .EN32(1), .EN16(t >= 1), .EN8(t >= 2)) dut (
        .clk(1'b0), .rst_n(1'b1), .mode(mode), .op_sel(op_rep),
        .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
        .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
        .out_data(yr[arch][t]), .out_valid(), .out_ready(1'b1));
    end
  end

  logic [63:0] yp [5];       // probe32x2: [PRIM]
  for (genvar p = 0; p < 5; p++) begin : g_probe
    fu_add_sub_spike_probe32x2 #(.PRIM(p)) dut (
      .clk(1'b0), .rst_n(1'b1), .op_sel({op_sel[4], op_sel[0]}),
      .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
      .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
      .out_data(yp[p]), .out_valid(), .out_ready(1'b1));
  end

  int errors = 0;
  `include "add_sub_lane_gold.svh"

  task automatic chk(input logic [1:0] m, input logic [7:0] op, input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] g;
    a = av; b = bv; mode = m; op_sel = op;
    for (int i = 0; i < 8; i++) op_rep[i] = op[m == 2'b01 ? i & 4 : m == 2'b10 ? i & 6 : m == 2'b11 ? i : 0];
    #1;
    g = gold(m, op, av, bv);
    for (int p = 0; p < 5; p++)
      if (yp[p] !== gold(2'b01, op, av, bv)) begin
        $display("FAIL probe32x2 prim=%0d op=%h a=%h b=%h got %h exp %h", p, op, av, bv, yp[p],
                 gold(2'b01, op, av, bv));
        errors++;
      end
    for (int arch = 0; arch < 4; arch++)
      for (int flat = 0; flat < 2; flat++)
        for (int t = 0; t < (arch == 2 ? 2 : 3); t++) begin
          if (!(m == 2'b00 || m == 2'b01 || (m == 2'b10 && t >= 1) || t >= 2)) continue;
          if (y[arch][flat][t] !== g) begin
            $display("FAIL arch=%0d flat=%0d d%0d m=%b op=%h a=%h b=%h got %h exp %h",
                     arch, flat, 2 << t, m, op, av, bv, y[arch][flat][t], g);
            errors++;
          end
          if (flat == 0 && yr[arch][t] !== g) begin
            $display("FAIL arch=%0d rep_op d%0d m=%b op=%h a=%h b=%h got %h exp %h",
                     arch, 2 << t, m, op, av, bv, yr[arch][t], g);
            errors++;
          end
        end
  endtask

  logic [63:0] xa, xb; int i;
  initial begin
    // directed: full-width carry/borrow chains and their isolation at every lane boundary
    chk(2'b00, 8'h00, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001); // carry through all 64 bits
    chk(2'b00, 8'h01, 64'h0000000000000000, 64'h0000000000000001); // borrow through all 64 bits
    chk(2'b00, 8'h00, 64'h00000000FFFFFFFF, 64'h0000000000000001); // carry across bit 32 only
    chk(2'b00, 8'h01, 64'h0000000100000000, 64'h0000000000000001); // borrow across bit 32 only
    chk(2'b00, 8'hFE, 64'h00000000FFFFFFFF, 64'h0000000000000001); // 64-bit op ignores op_sel[7:1]
    chk(2'b01, 8'h00, 64'hFFFFFFFF_FFFFFFFF, 64'h00000001_00000001); // carry stops at bit 32
    chk(2'b01, 8'h11, 64'h00000000_00000000, 64'h00000001_00000001); // 2x32 sub both lanes
    chk(2'b01, 8'h10, 64'hFFFFFFFF_00000000, 64'h00000001_00000001); // mixed op per 32 lane
    chk(2'b10, 8'h00, 64'hFFFF_FFFF_FFFF_FFFF, 64'h0001_0001_0001_0001); // carry stops at each 16
    chk(2'b10, 8'h55, 64'h0000_0000_0000_0000, 64'h0001_0001_0001_0001); // 4x16 sub all
    chk(2'b11, 8'h00, 64'hFF_FF_FF_FF_FF_FF_FF_FF, 64'h01_01_01_01_01_01_01_01); // carry stops at each 8
    chk(2'b11, 8'hFF, 64'h00_00_00_00_00_00_00_00, 64'h01_01_01_01_01_01_01_01); // 8x8 sub all
    chk(2'b11, 8'hAA, 64'hFF_00_FF_00_FF_00_FF_00, 64'h01_01_01_01_01_01_01_01); // 8x8 mixed op

    // randomized across all modes and ops
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321;
    for (i = 0; i < 40000; i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      chk(xa[1:0], xb[7:0], xa, xb);
    end

    if (errors == 0) $display("PASS all (spike ARCH x FLAT, REP_OP and probe32x2 == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
