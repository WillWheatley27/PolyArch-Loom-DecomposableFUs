// fu_fp_min_max_gen.sv -- GENUINE decomposable packed-FP min/max (IEEE-754-2019). The wide
// format is COMPOSED from the narrow ones: the word is split into 16-bit slices (the fp16
// lanes), and a radix-2 tree combines two slices into an fp32 lane and two fp32 lanes into
// the fp64 lane. The tree is mode-independent -- it is the fp64 datapath, and every narrower
// format is an intermediate node of it. `mode` only chooses, per slice, which tree level its
// lane decision is read from. No datapath logic belongs to a single format.
//
//   * Order: IEEE sign-magnitude order is decided on the raw bits -- equal signs use the
//     unsigned magnitude order (reversed when negative), differing signs pick the negative
//     operand (so -0 < +0). The unsigned order of a node combines its halves: the high half
//     decides unless equal. No float-to-integer key transform.
//   * NaN: a lane's exponent always lies in its top slice (exp <= 11 bits < 15), and the
//     fp16/fp32/fp64 exponent fields are nested prefixes of that slice (bits 14:10, 14:7,
//     14:4) while their top-slice mantissas are nested suffixes (9:0, 6:0, 3:0). One AND chain
//     and one OR chain per slice therefore serve every format; the rest of a lane's mantissa
//     is the OR of its lower slices, again a tree node.
// Lane evaluators (sign fixup + NaN combine) sit one per slice, not one per tree node: a slice
// is the top of at most one lane in any mode, so `mode` selects which tree level feeds its
// evaluator. Hardware therefore follows the finest supported mode and nothing is built per
// format. Capability tiers (MIN_LANE_W) drop the evaluators and select inputs of unsupported
// levels, so each tier is a strict logic subset of the next.
//
//   lane width = W >> mode (mode 00 -> 1x fp64, 01 -> 2x fp32, 10 -> 4x fp16 for W=64);
//   a mode narrower than MIN_LANE_W (incl. reserved 11) falls back to one full-width lane.
//   op_sel[i]: op of the lane whose lowest slice is i (0 min, 1 max).
//   IEEE-2019: NaN-propagating (canonical qNaN if either operand NaN); -0 < +0. Comb, latency 0.
module fu_fp_min_max_dec #(
  parameter int W          = 64,   // datapath width: 16, 32 or 64
  parameter int MIN_LANE_W = 16    // narrowest supported lane (capability tier)
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic          clk,
  input  logic          rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]    mode,
  input  logic [W/16-1:0] op_sel,
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

  // ---- Mode decode (left edge): one-hot lane level shared by every slice ----
  // lvl[l] = 1 when lanes are (16 << l) bits wide (mode = L - l). Encodings the tier does
  // not support, including reserved ones, select the full-width lane (level L).
  logic [L:0] lvl;
  always_comb begin : mode_decode
    lvl = '0;
    for (int l = L_MIN; l < L; l++) lvl[l] = (mode == 2'(L - l));
    lvl[L] = (lvl == '0);
  end : mode_decode

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
  function automatic logic [15:0] qnan_mask(input int l);   // top slice of the canonical qNaN
    return exp_mask(l) | 16'(1 << (14 - exp_w(l)));
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
    // Mantissa-nonzero: each narrower format's top-slice mantissa extends the wider one upward.
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
    assign fa_n[LEAF] = ta_n[LEAF] | |(a & ~tail_mask(0));   // whole slice
    assign fb_n[LEAF] = tb_n[LEAF] | |(b & ~tail_mask(0));
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
  // `mode` selects which tree level feeds it; the sign bits are the slice's own bit 15.
  // Evaluators therefore follow the finest supported mode's lane count.
  logic gt_s [NS], nan_s [NS];
  for (genvar j = 0; j < NS; j++) begin : lane_eval
    localparam int TL = top_level(j);
    if (TL >= L_MIN) begin : evaluator
      // Candidate inputs {gt, oa, ob, ta, tb, la, lb} of each level this slice tops.
      logic [6:0] cand [L_MIN:TL];
      for (genvar l = L_MIN; l <= TL; l++) begin : level_in
        localparam int N = node(l, j >> l);
        assign cand[l] = {gt_n[N], oa_n[N], ob_n[N], ta_n[N], tb_n[N], la_n[N], lb_n[N]};
      end : level_in
      logic gt_r, oa, ob, ta, tb, la, lb;
      always_comb begin : level_inputs
        // One-hot AND-OR over the levels this slice tops (zero when it tops no lane: unused).
        {gt_r, oa, ob, ta, tb, la, lb} = '0;
        for (int l = L_MIN; l <= TL; l++)
          {gt_r, oa, ob, ta, tb, la, lb} = {gt_r, oa, ob, ta, tb, la, lb} | ({7{lvl[l]}} & cand[l]);
      end : level_inputs
      logic sa, sb;
      assign sa = in_data_0[16*j + 15];
      assign sb = in_data_1[16*j + 15];
      assign gt_s[j]  = (sa ^ sb) ? sb : (sa ^ gt_r);
      assign nan_s[j] = (oa & (ta | la)) | (ob & (tb | lb));
    end : evaluator
  end : lane_eval

  // ---- Per slice: read its lane's top-slice decision at the selected level, then select ----
  function automatic int lane_top(input int j, input int l);   // top slice of j's level-l lane
    return (((j >> l) + 1) << l) - 1;
  endfunction
  for (genvar j = 0; j < NS; j++) begin : out_slice
    logic gt, nan, op;
    logic [15:0] q;
    always_comb begin : level_select
      gt = 1'b0; nan = 1'b0; op = 1'b0; q = '0;
      for (int l = L_MIN; l <= L; l++) begin   // one-hot AND-OR over the supported levels
        gt  = gt  | (lvl[l] & gt_s[lane_top(j, l)]);
        nan = nan | (lvl[l] & nan_s[lane_top(j, l)]);
        op  = op  | (lvl[l] & op_sel[(j >> l) << l]);
        q   = q   | ({16{lvl[l]}} & ((((j + 1) % (1 << l)) == 0) ? qnan_mask(l) : 16'h0000));
      end
    end : level_select
    // min picks b when a > b; max picks b when a <= b (ties are bit-identical).
    logic choose_b;
    assign choose_b = op ? ~gt : gt;
    assign out_data[16*j +: 16] = nan ? q
                                : (choose_b ? in_data_1[16*j +: 16] : in_data_0[16*j +: 16]);
  end : out_slice
endmodule : fu_fp_min_max_dec

// ---- Capability wrappers: identical ports, differ only in the narrowest supported lane ----
module fu_fp_min_max_m1 (                               // fp64 only
  input  logic clk, input logic rst_n, input logic [3:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_fp_min_max_dec #(.W(64), .MIN_LANE_W(64)) core (.clk(clk), .rst_n(rst_n), .mode(2'b00),
    .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
module fu_fp_min_max_m2 (                               // fp64 + 2x fp32
  input  logic clk, input logic rst_n, input logic mode, input logic [3:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_fp_min_max_dec #(.W(64), .MIN_LANE_W(32)) core (.clk(clk), .rst_n(rst_n),
    .mode({1'b0, mode}), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
module fu_fp_min_max_m3 (                               // fp64 + 2x fp32 + 4x fp16
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [3:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_fp_min_max_dec #(.W(64), .MIN_LANE_W(16)) core (.clk(clk), .rst_n(rst_n), .mode(mode),
    .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
