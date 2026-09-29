// fu_fp_cmp_gen.sv -- GENUINE decomposable packed-FP compare (arith.cmpf). The wide format is
// COMPOSED from the narrow ones, exactly as in fu_fp_min_max_gen.sv: the word is split into
// 16-bit slices (the fp16 lanes), and a radix-2 tree combines two slices into an fp32 lane and
// two fp32 lanes into the fp64 lane. The tree is mode-independent -- it is the fp64 datapath,
// and every narrower format is an intermediate node of it. `mode` only chooses, per slice,
// which tree level its lane result is read from. No datapath logic belongs to a single format.
//
//   * Order: decided on the raw bits -- equal signs use the unsigned magnitude order (reversed
//     when negative), differing signs make the negative operand smaller. A node's unsigned
//     order combines its halves: the high half decides unless equal.
//   * Equality: raw bits equal, or both operands zero (-0 == +0). A lane's magnitude is always
//     bits 14:0 of its top slice plus all of its lower slices, whatever the format, so the
//     zero test is one 15-bit OR per slice plus the tree's "any bit below the top slice".
//   * NaN: the exponent lies in the lane's top slice, and the fp16/fp32/fp64 exponent fields
//     are nested prefixes of it (bits 14:10, 14:7, 14:4) while their top-slice mantissas are
//     nested suffixes (9:0, 6:0, 3:0): one AND chain and one OR chain per slice serve every
//     format; the rest of the mantissa is the OR of the lower slices, again a tree node.
//   * Predicate: every MLIR cmpf predicate is an enable pattern over {unordered, lt, eq, gt}.
//     It is decoded once for the whole word; each lane only ANDs it with its relation.
// Lane evaluators (sign fixup, NaN / zero combine, predicate AND-OR) sit one per slice, not
// one per tree node: a slice is the top of at most one lane in any mode, so `mode` selects
// which tree level feeds its evaluator. Hardware therefore follows the finest supported
// mode -- each added lane costs one evaluator plus level-select inputs -- and nothing is
// built per format. Capability tiers (MIN_LANE_W) drop the evaluators and select inputs of
// unsupported levels, so each tier is a strict logic subset of the next.
//
//   lane width = W >> mode (mode 00 -> 1x fp64, 01 -> 2x fp32, 10 -> 4x fp16 for W=64);
//   a mode narrower than MIN_LANE_W (incl. reserved 11) falls back to one full-width lane.
//   pred[3:0]: 0 false,1 OEQ,2 OGT,3 OGE,4 OLT,5 OLE,6 ONE,7 ORD,
//              8 UEQ,9 UGT,10 UGE,11 ULT,12 ULE,13 UNE,14 UNO,15 true
//   IEEE: unordered if either operand NaN; -0 == +0. Per-lane all-ones / all-zeros mask
//   (SSE CMPPS-style). Comb, latency 0.
module fu_fp_cmp_dec #(
  parameter int W          = 64,   // datapath width: 16, 32 or 64
  parameter int MIN_LANE_W = 16    // narrowest supported lane (capability tier)
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic          clk,
  input  logic          rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]    mode,
  input  logic [3:0]    pred,
  input  logic [W-1:0]  in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [W-1:0]  in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [W-1:0]  out_data,  output logic out_valid,  input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  localparam int NS    = W / 16;                  // slices = fp16 lanes
  localparam int L     = $clog2(NS);              // tree levels: level l holds (16 << l)-bit lanes
  localparam int L_MIN = $clog2(MIN_LANE_W / 16); // narrowest supported level

  // Effective split: lane width = W >> k; unsupported encodings fall back to one full lane.
  logic [1:0] k;
  assign k = (mode <= 2'(L - L_MIN)) ? mode : 2'd0;

  // ---- Format of a level-l lane, as seen by its top slice (elaboration-time constants) ----
  function automatic int exp_w(input int l);
    return (l == 2) ? 11 : (l == 1) ? 8 : 5;
  endfunction
  function automatic logic [15:0] exp_mask(input int l);    // bits 14 .. 15-E
    return 16'(((1 << exp_w(l)) - 1) << (15 - exp_w(l)));
  endfunction
  function automatic logic [15:0] tail_mask(input int l);   // mantissa bits of the top slice
    return 16'((1 << (15 - exp_w(l))) - 1);
  endfunction
  // Flat index of tree node (level l, position i): leaves 0..NS-1, then each level above.
  function automatic int node(input int l, input int i);
    return 2*NS - ((2*NS) >> l) + i;
  endfunction
  // Highest level at which slice j is the top slice of its node.
  function automatic int top_level(input int j);
    int t;
    t = 0;
    while (t < L && ((j + 1) % (2 << t)) == 0) t++;
    return t;
  endfunction

  // ---- Predicate -> enables {unordered, lt, eq, gt}; one decode for the whole word ----
  logic en_u, en_l, en_e, en_g;
  always_comb begin : predicate
    unique case (pred)
      4'd0:  {en_u, en_l, en_e, en_g} = 4'b0000;   // false
      4'd1:  {en_u, en_l, en_e, en_g} = 4'b0010;   // OEQ
      4'd2:  {en_u, en_l, en_e, en_g} = 4'b0001;   // OGT
      4'd3:  {en_u, en_l, en_e, en_g} = 4'b0011;   // OGE
      4'd4:  {en_u, en_l, en_e, en_g} = 4'b0100;   // OLT
      4'd5:  {en_u, en_l, en_e, en_g} = 4'b0110;   // OLE
      4'd6:  {en_u, en_l, en_e, en_g} = 4'b0101;   // ONE
      4'd7:  {en_u, en_l, en_e, en_g} = 4'b0111;   // ORD
      4'd8:  {en_u, en_l, en_e, en_g} = 4'b1010;   // UEQ
      4'd9:  {en_u, en_l, en_e, en_g} = 4'b1001;   // UGT
      4'd10: {en_u, en_l, en_e, en_g} = 4'b1011;   // UGE
      4'd11: {en_u, en_l, en_e, en_g} = 4'b1100;   // ULT
      4'd12: {en_u, en_l, en_e, en_g} = 4'b1110;   // ULE
      4'd13: {en_u, en_l, en_e, en_g} = 4'b1101;   // UNE
      4'd14: {en_u, en_l, en_e, en_g} = 4'b1000;   // UNO
      default: {en_u, en_l, en_e, en_g} = 4'b1111; // true
    endcase
  end : predicate

  // ---- Tree nodes (index = node(level, position)) ----
  // Nodes read their children in the same array; split_var tells Verilator the
  // elements are independent signals (the tree has no combinational cycle).
  // The root's eq / full-OR have no consumer.
  // verilator lint_off UNUSEDSIGNAL
  logic gt_n [2*NS-1] /*verilator split_var*/;  // unsigned raw a > b over the node
  logic eq_n [2*NS-1] /*verilator split_var*/;  // raw a == b over the node
  logic fa_n [2*NS-1] /*verilator split_var*/;  // any bit of a set over the node
  logic fb_n [2*NS-1] /*verilator split_var*/;
  logic la_n [2*NS-1] /*verilator split_var*/;  // any bit of a set below the node's top slice
  logic lb_n [2*NS-1] /*verilator split_var*/;
  logic oa_n [2*NS-1] /*verilator split_var*/;  // top slice: this level's exponent of a all ones
  logic ob_n [2*NS-1] /*verilator split_var*/;
  logic ta_n [2*NS-1] /*verilator split_var*/;  // top slice: this level's mantissa of a nonzero
  logic tb_n [2*NS-1] /*verilator split_var*/;
  // verilator lint_on UNUSEDSIGNAL
  logic va [NS], vb [NS];                       // slice bits 14:0 nonzero (a lane-top magnitude)

  // ---- Slices: raw compare leaf + nested IEEE field chains ----
  for (genvar j = 0; j < NS; j++) begin : slice
    localparam int TL   = top_level(j);
    localparam int LEAF = node(0, j);
    logic [15:0] a, b;
    assign a = in_data_0[16*j +: 16];
    assign b = in_data_1[16*j +: 16];
    assign gt_n[LEAF] = a > b;
    assign eq_n[LEAF] = a == b;
    assign la_n[LEAF] = 1'b0;
    assign lb_n[LEAF] = 1'b0;

    // Exponent all-ones: each wider format extends the narrower exponent downward.
    for (genvar l = 0; l <= TL; l++) begin : exponent
      localparam int N = node(l, j >> l);
      if (l == 0) begin : narrowest
        assign oa_n[N] = &(a | ~exp_mask(0));
        assign ob_n[N] = &(b | ~exp_mask(0));
      end else begin : extend
        localparam int NP = node(l - 1, j >> (l - 1));
        assign oa_n[N] = oa_n[NP] & &(a | ~(exp_mask(l) & ~exp_mask(l - 1)));
        assign ob_n[N] = ob_n[NP] & &(b | ~(exp_mask(l) & ~exp_mask(l - 1)));
      end
    end : exponent
    // Mantissa-nonzero: each narrower format's top-slice mantissa extends the wider one upward;
    // adding the fp16 exponent gives the slice magnitude, adding the sign gives the whole slice.
    for (genvar l = TL; l >= 0; l--) begin : mantissa
      localparam int N = node(l, j >> l);
      if (l == TL) begin : widest
        assign ta_n[N] = |(a & tail_mask(l));
        assign tb_n[N] = |(b & tail_mask(l));
      end else begin : extend
        localparam int NW = node(l + 1, j >> (l + 1));
        assign ta_n[N] = ta_n[NW] | |(a & (tail_mask(l) & ~tail_mask(l + 1)));
        assign tb_n[N] = tb_n[NW] | |(b & (tail_mask(l) & ~tail_mask(l + 1)));
      end
    end : mantissa
    assign va[j] = ta_n[LEAF] | |(a & exp_mask(0));
    assign vb[j] = tb_n[LEAF] | |(b & exp_mask(0));
    assign fa_n[LEAF] = va[j] | a[15];
    assign fb_n[LEAF] = vb[j] | b[15];
  end : slice

  // ---- Tree: a node combines its halves (hi = the half holding the top slice) ----
  for (genvar l = 1; l <= L; l++) begin : level
    for (genvar i = 0; i < (NS >> l); i++) begin : pair
      localparam int N  = node(l, i);
      localparam int HI = node(l - 1, 2*i + 1);
      localparam int LO = node(l - 1, 2*i);
      assign gt_n[N] = gt_n[HI] | (eq_n[HI] & gt_n[LO]);
      assign eq_n[N] = eq_n[HI] & eq_n[LO];
      assign fa_n[N] = fa_n[HI] | fa_n[LO];
      assign fb_n[N] = fb_n[HI] | fb_n[LO];
      assign la_n[N] = la_n[HI] | fa_n[LO];
      assign lb_n[N] = lb_n[HI] | fb_n[LO];
    end : pair
  end : level

  // ---- Lane evaluators: one per slice that can top a lane in this tier ----
  // A slice is the top of at most one lane in any mode, so each slice holds one evaluator and
  // `mode` selects which tree level feeds it; the sign bits and the magnitude OR are the
  // slice's own. Evaluators therefore follow the finest supported mode's lane count.
  logic res_s [NS];
  for (genvar j = 0; j < NS; j++) begin : lane_eval
    localparam int TL = top_level(j);
    if (TL >= L_MIN) begin : evaluator
      // Candidate inputs {gt, eq, oa, ob, ta, tb, la, lb} of each level this slice tops.
      logic [7:0] cand [L_MIN:TL];
      for (genvar l = L_MIN; l <= TL; l++) begin : level_in
        localparam int N = node(l, j >> l);
        assign cand[l] = {gt_n[N], eq_n[N], oa_n[N], ob_n[N], ta_n[N], tb_n[N], la_n[N], lb_n[N]};
      end : level_in
      logic gt_r, eq_r, oa, ob, ta, tb, la, lb;
      always_comb begin : level_inputs
        // Widest level this slice tops; also covers modes where it tops no lane (unused).
        {gt_r, eq_r, oa, ob, ta, tb, la, lb} = cand[TL];
        for (int kk = 1; kk <= L - L_MIN; kk++)
          if (k == 2'(kk) && L - kk < TL)
            {gt_r, eq_r, oa, ob, ta, tb, la, lb} = cand[L - kk];
      end : level_inputs
      logic sa, sb, uno, zero, eq, gt, lt;
      assign sa   = in_data_0[16*j + 15];
      assign sb   = in_data_1[16*j + 15];
      assign uno  = (oa & (ta | la)) | (ob & (tb | lb));
      assign zero = ~(va[j] | la) & ~(vb[j] | lb);
      assign eq   = eq_r | zero;
      assign gt   = ~eq & ((sa ^ sb) ? sb : (sa ^ gt_r));
      assign lt   = ~eq & ~gt;
      assign res_s[j] = uno ? en_u : ((lt & en_l) | (eq & en_e) | (gt & en_g));
    end : evaluator
  end : lane_eval

  // ---- Per slice: read its lane's top-slice result at the selected level, broadcast as a mask ----
  function automatic int lane_top(input int j, input int l);   // top slice of j's level-l lane
    return (((j >> l) + 1) << l) - 1;
  endfunction
  for (genvar j = 0; j < NS; j++) begin : out_slice
    logic r;
    always_comb begin : level_select
      r = res_s[lane_top(j, L)];
      for (int kk = 1; kk <= L - L_MIN; kk++)
        if (k == 2'(kk)) r = res_s[lane_top(j, L - kk)];
    end : level_select
    assign out_data[16*j +: 16] = {16{r}};
  end : out_slice
endmodule : fu_fp_cmp_dec

// ---- Capability wrappers: identical ports, differ only in the narrowest supported lane ----
module fu_fp_cmp_g1 (                                   // fp64 only
  input  logic clk, input logic rst_n, input logic [3:0] pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_fp_cmp_dec #(.W(64), .MIN_LANE_W(64)) core (.clk(clk), .rst_n(rst_n), .mode(2'b00),
    .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
module fu_fp_cmp_g2 (                                   // fp64 + 2x fp32
  input  logic clk, input logic rst_n, input logic mode, input logic [3:0] pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_fp_cmp_dec #(.W(64), .MIN_LANE_W(32)) core (.clk(clk), .rst_n(rst_n),
    .mode({1'b0, mode}), .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
module fu_fp_cmp_g3 (                                   // fp64 + 2x fp32 + 4x fp16
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [3:0] pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_fp_cmp_dec #(.W(64), .MIN_LANE_W(16)) core (.clk(clk), .rst_n(rst_n), .mode(mode),
    .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
