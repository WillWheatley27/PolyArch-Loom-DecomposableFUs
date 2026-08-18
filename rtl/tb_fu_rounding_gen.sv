// Self-checking TB for the GENUINE shared-datapath rounding FUs (g1/g2/g3).
// Golden = the proven per-lane round_lane reference (hardware-independent).
module tb;
  logic [1:0]  mode;
  logic [2:0]  rm;
  logic [63:0] x;
  logic [63:0] y1, y2, y3;
  logic uv, ir;

  fu_rounding_g1 d1 (.clk(1'b0), .rst_n(1'b1), .round_mode(rm),
    .in_data_0(x), .in_valid_0(1'b1), .in_ready_0(ir), .out_data(y1), .out_valid(uv), .out_ready(1'b1));
  fu_rounding_g2 d2 (.clk(1'b0), .rst_n(1'b1), .mode(mode[0]), .round_mode(rm),
    .in_data_0(x), .in_valid_0(1'b1), .in_ready_0(), .out_data(y2), .out_valid(), .out_ready(1'b1));
  fu_rounding_g3 d3 (.clk(1'b0), .rst_n(1'b1), .mode(mode), .round_mode(rm),
    .in_data_0(x), .in_valid_0(1'b1), .in_ready_0(), .out_data(y3), .out_valid(), .out_ready(1'b1));

  int errors = 0;

  // ---- Golden: identical math to fu_rounding_decomp.round_lane (proven ref) ----
  function automatic logic [63:0] round_inc_g(logic [2:0] rmm, logic s, logic g, logic st, logic il);
    case (rmm)
      3'b000:  return {63'd0, (s  & (g | st))};
      3'b001:  return {63'd0, (~s & (g | st))};
      3'b011:  return {63'd0, g};
      3'b100:  return {63'd0, (g & (st | il))};
      default: return 64'd0;
    endcase
  endfunction
  function automatic logic [63:0] gold_lane(logic [63:0] xin, logic [2:0] rmm, int EXP_W, int MAN_W);
    logic [63:0] EXP_MASK, MAN_MASK, sig, int_sig, frac_mask, new_sig;
    logic [11:0] EXP_ONES, exp, exp_res;
    logic [51:0] mant, mant_res;
    logic signed [15:0] BIAS, E, F;
    logic s, guard, sticky, int_lsb, inc;
    EXP_MASK = (64'd1 << EXP_W) - 64'd1; MAN_MASK = (64'd1 << MAN_W) - 64'd1;
    EXP_ONES = EXP_MASK[11:0]; BIAS = 16'((1 << (EXP_W-1)) - 1);
    s = xin[EXP_W+MAN_W]; exp = 12'((xin >> MAN_W) & EXP_MASK); mant = 52'(xin & MAN_MASK);
    if (exp == EXP_ONES) return xin;
    if (exp == 12'd0 && mant == 52'd0) return xin;
    sig = ((exp != 12'd0) ? (64'd1 << MAN_W) : 64'd0) | {12'd0, mant};
    E = (exp == 12'd0) ? (16'sd1 - BIAS) : ($signed({4'b0, exp}) - BIAS);
    if (E >= 16'(MAN_W)) return xin;
    F = 16'(MAN_W) - E;
    if (E >= 16'sd0) begin
      frac_mask = (64'd1 << F) - 64'd1;
      guard = |(sig & (64'd1 << (F-16'sd1))); sticky = |(sig & ((64'd1 << (F-16'sd1)) - 64'd1));
      int_lsb = |(sig & (64'd1 << F)); int_sig = sig & ~frac_mask;
      inc = round_inc_g(rmm, s, guard, sticky, int_lsb) [0];
      new_sig = int_sig + (inc ? (64'd1 << F) : 64'd0);
      if (|(new_sig & (64'd1 << (MAN_W+1)))) begin exp_res = exp+12'd1; mant_res = 52'd0; end
      else begin exp_res = exp; mant_res = 52'(new_sig & MAN_MASK); end
      return (64'(s) << (EXP_W+MAN_W)) | ({52'd0, exp_res} << MAN_W) | {12'd0, mant_res};
    end else begin
      if (E == -16'sd1) begin guard = 1'b1; sticky = |mant; end
      else begin guard = 1'b0; sticky = 1'b1; end
      inc = round_inc_g(rmm, s, guard, sticky, 1'b0) [0];
      if (inc) return (64'(s) << (EXP_W+MAN_W)) | ({52'd0, BIAS[11:0]} << MAN_W);
      else     return (64'(s) << (EXP_W+MAN_W));
    end
  endfunction

  function automatic logic [63:0] gold(logic [1:0] m, logic [2:0] rmm, logic [63:0] xin);
    case (m)
      2'b01: return {gold_lane({32'd0, xin[63:32]}, rmm, 8,23)[31:0],
                     gold_lane({32'd0, xin[31:0]},  rmm, 8,23)[31:0]};
      2'b10: return {gold_lane({48'd0, xin[63:48]}, rmm, 5,10)[15:0],
                     gold_lane({48'd0, xin[47:32]}, rmm, 5,10)[15:0],
                     gold_lane({48'd0, xin[31:16]}, rmm, 5,10)[15:0],
                     gold_lane({48'd0, xin[15:0]},  rmm, 5,10)[15:0]};
      default: return gold_lane(xin, rmm, 11,52);
    endcase
  endfunction

  task automatic chk(logic [1:0] m, logic [2:0] rmm, logic [63:0] xin);
    x = xin; mode = m; rm = rmm; #1;
    // g3 supports all modes; g2 modes 0-1; g1 mode 0.
    if (y3 !== gold(m, rmm, xin)) begin $display("FAIL g3 m=%b rm=%b x=%h got %h exp %h", m,rmm,xin,y3,gold(m,rmm,xin)); errors++; end
    if (m[1] == 1'b0 && y2 !== gold(m, rmm, xin)) begin $display("FAIL g2 m=%b rm=%b x=%h got %h exp %h", m,rmm,xin,y2,gold(m,rmm,xin)); errors++; end
    if (m == 2'b00 && y1 !== gold(m, rmm, xin)) begin $display("FAIL g1 rm=%b x=%h got %h exp %h", rmm,xin,y1,gold(m,rmm,xin)); errors++; end
  endtask

  // fp constants
  localparam logic [63:0] F64_2P5 = 64'h4004000000000000; // 2.5
  localparam logic [63:0] F64_NEG2P5 = 64'hC004000000000000;
  localparam logic [63:0] F64_0P3 = 64'h3FD3333333333333; // 0.3
  logic [63:0] xr; int i; logic [2:0] rr; logic [1:0] mm;

  initial begin
    // directed fp64 corners across all 5 rounding modes
    for (int r=0; r<5; r++) begin
      chk(2'b00, r[2:0], F64_2P5);
      chk(2'b00, r[2:0], F64_NEG2P5);
      chk(2'b00, r[2:0], F64_0P3);
      chk(2'b00, r[2:0], 64'h7FF0000000000000);   // +Inf
      chk(2'b00, r[2:0], 64'h7FF8000000000000);   // NaN
      chk(2'b00, r[2:0], 64'h0000000000000000);   // +0
      chk(2'b00, r[2:0], 64'h8000000000000000);   // -0
      chk(2'b00, r[2:0], 64'h4340000000000000);   // 2^53 already integral
    end
    // packed fp32 / fp16 directed: two/four lanes with mixed values
    chk(2'b01, 3'b000, {32'h40200000, 32'hBF800000}); // {2.5f, -1.0f} floor
    chk(2'b01, 3'b001, {32'h3FC00000, 32'h3F000000}); // {1.5f, 0.5f} ceil
    chk(2'b10, 3'b100, {16'h4100, 16'h3E00, 16'hC200, 16'h3C00}); // roundeven mix
    chk(2'b10, 3'b011, {16'h3800, 16'hB800, 16'h4980, 16'h0200}); // round + subnormal

    // randomized
    xr = 64'h123456789ABCDEF0;
    for (i=0;i<40000;i++) begin
      xr = {xr[62:0], xr[63]^xr[60]^xr[7]^xr[0]};
      rr = xr[2:0]; if (rr>4) rr=3'b010;
      mm = xr[5:4]; if (mm==2'b11) mm=2'b00;
      chk(mm, rr, xr);
    end

    if (errors==0) $display("PASS all (genuine == golden)");
    else $display("TOTAL FAILURES: %0d", errors);
    $finish;
  end
endmodule
