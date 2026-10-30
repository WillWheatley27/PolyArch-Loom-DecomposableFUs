// Self-checking TB for rtl/fu_add_sub_mm.sv: every ARCH x MINMAX x tier (d2, d4, d8) x PIPE (0, 1, and
// 2 with MINMAX) instance, and the pipelined Min/Max baseline (m2, m4), against the shared lane golds. Every
// operation draws a new mode, function, signedness, lane ops and operands; the per-block controls
// are prepared as the issuing logic would (sub_sel: the lane's subtract, all ones for Min/Max;
// max_sel: the lane's max). Combinational instances are checked before the clock edge, pipelined
// ones after it (latency 1); a stall checks that a pipelined result holds while out_ready is low.
// fu_add_sub_mm_reg (the same instances behind the original interface, controls registered in the
// FU) gets each operation's controls one cycle ahead of its operands; a stall and a bubble check
// that its control register loads exactly when an upstream operand register would.
module tb;
  localparam int NARCH = 2;   // ARCH 0 (segmented), 1 (carry-select at bit 32)
  logic        clk = 1'b0, rst_n = 1'b0, out_ready = 1'b1;
  logic [1:0]  mode;
  logic        is_min_max, is_signed;
  logic [7:0]  sub_sel, max_sel;
  logic [3:0]  mm_op;         // Min/Max baseline: op of the lane starting at 16-bit block j
  logic [63:0] a, b;
  logic [63:0] y [NARCH][2][3][3];   // [ARCH][MINMAX][tier][PIPE]
  logic        v [NARCH][2][3][3];
  logic        rdy [NARCH][2][3][3];
  logic [63:0] ym [2];               // pipelined Min/Max baseline: [0] m2, [1] m4
  logic        vm [2];
  // fu_add_sub_mm_reg: controls of the next operation (r_*), operands of the current one (ra, rb)
  logic [1:0]  r_mode;
  logic        r_fn, r_sg, r_valid;
  logic [7:0]  r_op;
  logic [63:0] ra, rb;
  logic [63:0] yr [NARCH][2][3][3];
  logic        vr [NARCH][2][3][3];
  logic        rdyr [NARCH][2][3][3];

  for (genvar arch = 0; arch < NARCH; arch++) begin : g_arch
    for (genvar mm = 0; mm < 2; mm++) begin : g_mm
      for (genvar t = 0; t < 3; t++) begin : g_tier   // 0: d2, 1: d4, 2: d8
        for (genvar p = 0; p < (mm ? 3 : 2); p++) begin : g_pipe
          fu_add_sub_mm #(.ARCH(arch), .MINMAX(mm), .PIPE(p), .EN32(1), .EN16(t >= 1), .EN8(t >= 2)) dut (
            .clk(clk), .rst_n(rst_n), .mode(mode), .is_min_max(is_min_max), .is_signed(is_signed),
            .sub_sel(sub_sel), .max_sel(max_sel),
            .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(rdy[arch][mm][t][p]),
            .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
            .out_data(y[arch][mm][t][p]), .out_valid(v[arch][mm][t][p]), .out_ready(out_ready));
        end
      end
    end
  end

  for (genvar arch = 0; arch < NARCH; arch++) begin : g_rarch
    for (genvar mm = 0; mm < 2; mm++) begin : g_rmm
      for (genvar t = 0; t < 3; t++) begin : g_rtier
        for (genvar p = 0; p < (mm ? 3 : 2); p++) begin : g_rpipe
          fu_add_sub_mm_reg #(.ARCH(arch), .MINMAX(mm), .PIPE(p), .EN32(1), .EN16(t >= 1), .EN8(t >= 2)) dut (
            .clk(clk), .rst_n(rst_n), .mode(r_mode), .is_min_max(r_fn), .is_signed(r_sg), .op_sel(r_op),
            .in_data_0(ra), .in_valid_0(r_valid), .in_ready_0(rdyr[arch][mm][t][p]),
            .in_data_1(rb), .in_valid_1(r_valid), .in_ready_1(),
            .out_data(yr[arch][mm][t][p]), .out_valid(vr[arch][mm][t][p]), .out_ready(out_ready));
        end
      end
    end
  end

  for (genvar k = 0; k < 2; k++) begin : g_minmax
    fu_min_max_piped #(.EN32(1), .EN16(k)) dut (
      .clk(clk), .rst_n(rst_n), .mode(mode), .is_signed(is_signed), .op_sel(mm_op),
      .in_data_0(a), .in_valid_0(1'b1), .in_ready_0(),
      .in_data_1(b), .in_valid_1(1'b1), .in_ready_1(),
      .out_data(ym[k]), .out_valid(vm[k]), .out_ready(out_ready));
  end

  int errors = 0, checks = 0;
  `include "add_sub_lane_gold.svh"
  `include "min_max_lane_gold.svh"

  function automatic bit supports(input int t, input logic [1:0] m);
    return m == 2'b00 || m == 2'b01 || (m == 2'b10 && t >= 1) || (m == 2'b11 && t >= 2);
  endfunction

  task automatic expect_eq(input string what, input logic [63:0] got, input logic [63:0] exp);
    checks++;
    if (got !== exp) begin
      if (errors < 10)
        $display("FAIL %s mode=%b mm=%b sg=%b sub=%h max=%h a=%h b=%h got %h exp %h",
                 what, mode, is_min_max, is_signed, sub_sel, max_sel, a, b, got, exp);
      errors++;
    end
  endtask

  task automatic check(input int p, input logic [63:0] exp, input logic [63:0] exp_mm);
    for (int arch = 0; arch < NARCH; arch++)
      for (int mm = 0; mm < 2; mm++)
        for (int t = 0; t < 3; t++) begin
          if (!supports(t, mode) || (is_min_max && mm == 0) || (p == 2 && mm == 0)) continue;
          expect_eq($sformatf("arch=%0d minmax=%0d d%0d pipe=%0d", arch, mm, 2 << t, p),
                    y[arch][mm][t][p], exp);
          if (p > 0 && v[arch][mm][t][p] !== 1'b1) begin
            $display("FAIL out_valid arch=%0d minmax=%0d d%0d pipe=%0d", arch, mm, 2 << t, p); errors++;
          end
        end
    if (p == 1)
      for (int k = 0; k < 2; k++)
        if (mode == 2'b00 || mode == 2'b01 || (mode == 2'b10 && k == 1))
          expect_eq($sformatf("minmax piped m%0d", 2 << k), ym[k], exp_mm);
  endtask

  // The registered instances' operation in flight: its controls are in their registers, its
  // operands at their inputs during the current cycle.
  logic [1:0]  cur_m;
  logic        cur_fn, cur_ok;   // cur_ok: an operation to check (not a bubble or a don't-care)
  logic [63:0] cur_exp;

  task automatic check_reg(input int p);
    if (!cur_ok) return;
    for (int arch = 0; arch < NARCH; arch++)
      for (int mm = 0; mm < 2; mm++)
        for (int t = 0; t < 3; t++) begin
          if (!supports(t, cur_m) || (cur_fn && mm == 0) || (p == 2 && mm == 0)) continue;
          expect_eq($sformatf("reg arch=%0d minmax=%0d d%0d pipe=%0d", arch, mm, 2 << t, p),
                    yr[arch][mm][t][p], cur_exp);
          if (p > 0 && vr[arch][mm][t][p] !== 1'b1) begin
            $display("FAIL reg out_valid arch=%0d minmax=%0d d%0d pipe=%0d", arch, mm, 2 << t, p); errors++;
          end
        end
  endtask

  task automatic tick;
    #1 clk = 1'b1; #1 clk = 1'b0;
  endtask

  // One operation: drive, check the combinational instances, clock, check the pipelined ones.
  task automatic op(input logic fn, input logic sg, input logic [1:0] m, input logic [7:0] lane_op,
                    input logic [63:0] av, input logic [63:0] bv);
    logic [63:0] exp, exp_mm;
    mode = m; is_min_max = fn; is_signed = sg; a = av; b = bv;
    r_mode = m; r_fn = fn; r_sg = sg; r_op = lane_op;   // the registered instances: this operation's
    r_valid = 1'b1;                                     // controls, the previous one's operands
    for (int k = 0; k < 8; k++) begin
      int ls;
      ls = m == 2'b01 ? k & 4 : m == 2'b10 ? k & 6 : m == 2'b11 ? k : 0;
      max_sel[k] = lane_op[ls];
      sub_sel[k] = fn ? 1'b1 : lane_op[ls];
    end
    for (int j = 0; j < 4; j++) mm_op[j] = lane_op[2*j];
    exp_mm = mm_gold(sg, m, lane_op, av, bv);
    exp = fn ? exp_mm : gold(m, lane_op, av, bv);
    #1 check(0, exp, exp_mm);
    check_reg(0);
    tick();
    check(1, exp, exp_mm);
    check(2, exp, exp_mm);
    check_reg(1);
    check_reg(2);
    cur_m = m; cur_fn = fn; cur_exp = exp; cur_ok = 1'b1; ra = av; rb = bv;
  endtask

  logic [63:0] xa, xb, held [NARCH][2][3][3], rheld [NARCH][2][3][3];
  logic [7:0]  xo;
  initial begin
    mode = 2'b00; is_min_max = 1'b0; is_signed = 1'b0; sub_sel = '0; max_sel = '0; mm_op = '0;
    a = '0; b = '0;
    r_mode = 2'b00; r_fn = 1'b0; r_sg = 1'b0; r_op = '0; r_valid = 1'b0; ra = '0; rb = '0; cur_ok = 1'b0;
    tick(); rst_n = 1'b1;

    // directed: full carry and borrow chains, isolation at every lane boundary
    for (int m = 0; m < 4; m++) begin
      op(0, 0, 2'(m), 8'h00, 64'hFFFF_FFFF_FFFF_FFFF, 64'h0101_0101_0101_0101);
      op(0, 0, 2'(m), 8'hFF, 64'h0000_0000_0000_0000, 64'h0101_0101_0101_0101);
      op(0, 0, 2'(m), 8'h00, 64'h00FF_FFFF_FFFF_FFFF, 64'h0000_0000_0000_0001);
    end
    // directed Min/Max: ties, sign boundaries, operands differing only in the lowest bit
    for (int m = 0; m < 4; m++)
      for (int sg = 0; sg < 2; sg++)
        for (int o = 0; o < 2; o++) begin
          op(1, sg[0], 2'(m), {8{o[0]}}, 64'h1234_5678_9ABC_DEF0, 64'h1234_5678_9ABC_DEF0);
          op(1, sg[0], 2'(m), {8{o[0]}}, 64'h8000_8000_8000_8000, 64'h7FFF_7FFF_7FFF_7FFF);
          op(1, sg[0], 2'(m), {8{o[0]}}, 64'h80FF_FFFF_0000_0001, 64'h7F00_0000_FFFF_FFFF);
          op(1, sg[0], 2'(m), {8{o[0]}}, 64'h0000_0000_0000_0001, 64'h0000_0000_0000_0000);
          op(1, sg[0], 2'(m), {8{o[0]}}, 64'h0000_0000_0000_0000, 64'h0000_0000_0000_0001);
          op(1, sg[0], 2'(m), 8'hA5,     64'hFFFF_FFFF_FFFF_FFFE, 64'hFFFF_FFFF_FFFF_FFFF);
        end

    // random: a new mode, function, signedness and lane ops every operation
    xa = 64'h1234_5678_9ABC_DEF0; xb = 64'h0FED_CBA9_8765_4321; xo = 8'h5A;
    for (int i = 0; i < 40000; i++) begin
      xa = {xa[62:0], xa[63]^xa[60]^xa[7]^xa[0]};
      xb = {xb[62:0], xb[63]^xb[59]^xb[4]^xb[1]};
      xo = {xo[6:0], xo[7]^xo[5]^xo[1]^xo[0]};
      // every 5th operation compares nearly equal operands (long compare carries)
      op(xa[2], xb[3], xa[1:0], xo, xa, i % 5 == 0 ? xa ^ (64'd1 << xb[5:0]) : xb);
    end

    // stall: with out_ready low a pipelined result holds and no new operation is accepted (a Min/Max
    // result, then an AddSub one, so the late-select registers are checked in both functions)
    for (int fn = 1; fn >= 0; fn--) begin
      op(fn[0], 0, 2'b01, 8'h10, 64'h0000_0005_0000_0009, 64'h0000_0007_0000_0003);
      for (int arch = 0; arch < NARCH; arch++)
        for (int mm = 0; mm < 2; mm++)
          for (int t = 0; t < 3; t++)
            for (int p = 1; p < (mm ? 3 : 2); p++) held[arch][mm][t][p] = y[arch][mm][t][p];
      out_ready = 1'b0;
      is_min_max = 1'b1; a = 64'd100; b = 64'd200;   // a Min/Max offer: nothing may load
      #1;
      for (int arch = 0; arch < NARCH; arch++)
        for (int mm = 0; mm < 2; mm++)
          for (int t = 0; t < 3; t++)
            for (int p = 1; p < (mm ? 3 : 2); p++)
              if (rdy[arch][mm][t][p] !== 1'b0) begin $display("FAIL in_ready during stall"); errors++; end
      tick();
      for (int arch = 0; arch < NARCH; arch++)
        for (int mm = 0; mm < 2; mm++)
          for (int t = 0; t < 3; t++)
            for (int p = 1; p < (mm ? 3 : 2); p++)
              expect_eq($sformatf("stall hold pipe=%0d", p), y[arch][mm][t][p], held[arch][mm][t][p]);
      out_ready = 1'b1;
    end
    op(0, 0, 2'b00, 8'h00, 64'd100, 64'd200);

    // registered instances, stall: while out_ready is low the operation in flight holds its
    // controls although the next operation's controls (here very different ones) are offered
    for (int fn = 1; fn >= 0; fn--) begin
      op(fn[0], 1, 2'b01, 8'h11, 64'h8000_0005_7FFF_0009, 64'h7FFF_0007_8000_0003);
      op(fn[0], 1, 2'b01, 8'h01, 64'hFFFF_FFF0_0000_0001, 64'h0000_0010_FFFF_FFFF);   // in flight
      for (int arch = 0; arch < NARCH; arch++)
        for (int mm = 0; mm < 2; mm++)
          for (int t = 0; t < 3; t++)
            for (int p = 1; p < (mm ? 3 : 2); p++) rheld[arch][mm][t][p] = yr[arch][mm][t][p];
      out_ready = 1'b0;
      r_mode = 2'b00; r_fn = ~fn[0]; r_sg = 1'b0; r_op = 8'hFE;   // the next operation's controls
      #1 check_reg(0);
      for (int arch = 0; arch < NARCH; arch++)
        for (int mm = 0; mm < 2; mm++)
          for (int t = 0; t < 3; t++)
            for (int p = 0; p < (mm ? 3 : 2); p++)
              if (rdyr[arch][mm][t][p] !== 1'b0) begin $display("FAIL reg in_ready during stall"); errors++; end
      tick();
      check_reg(0);   // its controls were not replaced by the offered ones
      for (int arch = 0; arch < NARCH; arch++)
        for (int mm = 0; mm < 2; mm++)
          for (int t = 0; t < 3; t++)
            for (int p = 1; p < (mm ? 3 : 2); p++)
              expect_eq($sformatf("reg stall hold pipe=%0d", p), yr[arch][mm][t][p], rheld[arch][mm][t][p]);
      out_ready = 1'b1;
      #1 check_reg(0);
      tick();         // accepted: the pipelined results, and the offered controls load
      check_reg(1);
      check_reg(2);
      cur_m = 2'b00; cur_fn = ~fn[0]; cur_ok = 1'b1;
      ra = 64'h0123_4567_89AB_CDEF; rb = 64'h0123_4567_89AB_CDEE;
      cur_exp = fn[0] ? gold(2'b00, 8'hFE, ra, rb) : mm_gold(1'b0, 2'b00, 8'hFE, ra, rb);
      #1 check_reg(0);
      tick();
      check_reg(1);
      check_reg(2);
    end

    // registered instances, bubble: with no operation at the inputs the next operation's controls
    // load (the in-flight slot is empty), and the next operation then computes with them
    r_mode = 2'b11; r_fn = 1'b1; r_sg = 1'b1; r_op = 8'h00;   // offered during the last operation:
    #1 tick();                                                // the bubble's controls, don't care
    cur_ok = 1'b0;
    r_valid = 1'b0; ra = '1; rb = '0;                         // the bubble
    r_mode = 2'b10; r_fn = 1'b0; r_sg = 1'b0; r_op = 8'h44;   // the next operation's controls
    #1 tick();
    for (int arch = 0; arch < NARCH; arch++)
      for (int mm = 0; mm < 2; mm++)
        for (int t = 0; t < 3; t++)
          for (int p = 1; p < (mm ? 3 : 2); p++)
            if (vr[arch][mm][t][p] !== 1'b0) begin $display("FAIL reg out_valid after bubble"); errors++; end
    r_valid = 1'b1; ra = 64'h0000_FFFF_0000_FFFF; rb = 64'h0000_0001_0000_0001;
    cur_m = 2'b10; cur_fn = 1'b0; cur_ok = 1'b1; cur_exp = gold(2'b10, 8'h44, ra, rb);
    r_mode = 2'b00; r_fn = 1'b0; r_sg = 1'b0; r_op = 8'h00;
    #1 check_reg(0);
    tick();
    check_reg(1);
    check_reg(2);

    if (errors == 0) $display("PASS all (AddSub + Min/Max side function, %0d checks == golden)", checks);
    else begin $display("TOTAL FAILURES: %0d of %0d checks", errors, checks); $fatal(1); end
    $finish;
  end
endmodule
