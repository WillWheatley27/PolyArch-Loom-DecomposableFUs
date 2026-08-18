// fu_fp_cmp_gen.sv -- GENUINE decomposable packed-FP compare. ONE shared datapath:
// a per-lane IEEE->monotonic-unsigned KEY transform feeds ONE segmented unsigned
// compare chain (eight 8-bit blocks, lex-combined, BROKEN at lane boundaries by
// `mode`); per-lane NaN/zero fixups and a 16-way predicate mux broadcast an
// all-ones/all-zeros lane mask (SSE CMPPS-style). No replicated comparators: the
// chain is computed once and reused across all modes; only break points and lane-MSB
// routing change with mode -> smaller tiers are strict logic subsets of larger ones.
//
//   mode: 00 -> 1x fp64, 01 -> 2x fp32, 10 -> 4x fp16, 11 -> reserved -> 1x fp64
//   pred[3:0]: 0 false,1 OEQ,2 OGT,3 OGE,4 OLT,5 OLE,6 ONE,7 ORD,
//              8 UEQ,9 UGT,10 UGE,11 ULT,12 ULE,13 UNE,14 UNO,15 true
//   IEEE: unordered if either operand NaN; -0 == +0 (unlike min/max). Comb, latency 0.
module fu_fp_cmp_dec (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic [3:0]  pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // ---- IEEE bits -> monotonic unsigned key (per lane): negatives invert all bits,
  //      positives set the sign bit; unsigned compare of keys == float order. ----
  function automatic logic [63:0] fp_key(input logic [1:0] m, input logic [63:0] x);
    logic [63:0] k;
    k = x;
    unique case (m)
      M_2X32: for (int L=0;L<2;L++)
                if (x[L*32+31]) k[L*32 +: 32] = ~x[L*32 +: 32]; else k[L*32+31] = 1'b1;
      M_4X16: for (int L=0;L<4;L++)
                if (x[L*16+15]) k[L*16 +: 16] = ~x[L*16 +: 16]; else k[L*16+15] = 1'b1;
      default: if (x[63]) k = ~x; else k[63] = 1'b1;
    endcase
    fp_key = k;
  endfunction

  // ---- Per-lane NaN / zero from ORIGINAL low bits: exp all-ones & mant!=0 ; exp==0 & mant==0 ----
  function automatic logic [1:0] fp_flags(input int EXP_W, input int MAN_W, input logic [63:0] x);
    logic [63:0] EXP_MASK, MAN_MASK, e, mn; logic nan, zero;
    EXP_MASK = (64'd1 << EXP_W) - 64'd1;
    MAN_MASK = (64'd1 << MAN_W) - 64'd1;
    e  = (x >> MAN_W) & EXP_MASK;
    mn = x & MAN_MASK;
    nan  = (e == EXP_MASK) && (mn != 64'd0);
    zero = (e == 64'd0)    && (mn == 64'd0);
    fp_flags = {nan, zero};
  endfunction

  function automatic logic fp_pred(input logic [3:0] p, input logic uno,
                                   input logic lt, input logic gt, input logic eq);
    case (p)
      4'd0: fp_pred=1'b0;              4'd1: fp_pred=~uno & eq;
      4'd2: fp_pred=~uno & gt;         4'd3: fp_pred=~uno & (gt|eq);
      4'd4: fp_pred=~uno & lt;         4'd5: fp_pred=~uno & (lt|eq);
      4'd6: fp_pred=~uno & (lt|gt);    4'd7: fp_pred=~uno;
      4'd8: fp_pred=uno | eq;          4'd9: fp_pred=uno | gt;
      4'd10:fp_pred=uno | (gt|eq);     4'd11:fp_pred=uno | lt;
      4'd12:fp_pred=uno | (lt|eq);     4'd13:fp_pred=uno | (lt|gt);
      4'd14:fp_pred=uno;               default: fp_pred=1'b1;
    endcase
  endfunction

  // ---- Shared segmented unsigned compare over keys (eight 8-bit blocks) ----
  logic [63:0] ka, kb;
  assign ka = fp_key(mode, in_data_0);
  assign kb = fp_key(mode, in_data_1);
  logic gtu [0:7]; logic eqb [0:7];
  for (genvar i=0;i<8;i++) begin : blk
    assign gtu[i] = ka[i*8 +: 8] > kb[i*8 +: 8];
    assign eqb[i] = ka[i*8 +: 8] == kb[i*8 +: 8];
  end
  logic [7:0] brk;
  always_comb begin : masks
    unique case (mode)
      M_4X16:  brk = 8'b0101_0100;
      M_2X32:  brk = 8'b0001_0000;
      default: brk = 8'b0000_0000;
    endcase
  end
  logic ru [0:7]; logic re [0:7];
  assign ru[0]=gtu[0]; assign re[0]=eqb[0];
  for (genvar i=1;i<8;i++) begin : chain
    assign ru[i] = brk[i] ? gtu[i] : (gtu[i] | (eqb[i] & ru[i-1]));
    assign re[i] = brk[i] ? eqb[i] : (eqb[i] & re[i-1]);
  end
  // ---- Per-lane predicate from shared chain (kgt/keq) + per-lane NaN/zero fixups ----
  function automatic logic lane_res(input logic [3:0] p, input logic kgt, input logic keq,
                                    input int EXP_W, input int MAN_W,
                                    input logic [63:0] xa, input logic [63:0] xb);
    logic [1:0] fa, fb; logic uno, bz, eq_, gt_, lt_;
    fa = fp_flags(EXP_W, MAN_W, xa); fb = fp_flags(EXP_W, MAN_W, xb);
    uno = fa[1] | fb[1];       // either NaN
    bz  = fa[0] & fb[0];       // both zero -> -0 == +0
    eq_ = keq | bz;
    gt_ = kgt & ~bz;
    lt_ = ~kgt & ~keq & ~bz;
    lane_res = fp_pred(p, uno, lt_, gt_, eq_);
  endfunction

  logic [7:0] m;
  always_comb begin : route
    logic r;
    r = lane_res(pred, ru[7], re[7], 11, 52, in_data_0, in_data_1);   // fp64 default
    for (int i=0;i<8;i++) m[i] = r;
    unique case (mode)
      M_2X32: begin
        logic r0, r1;
        r0 = lane_res(pred, ru[3], re[3], 8, 23,  in_data_0 & 64'hFFFF_FFFF,        in_data_1 & 64'hFFFF_FFFF);
        r1 = lane_res(pred, ru[7], re[7], 8, 23,  in_data_0 >> 32,                  in_data_1 >> 32);
        m = {{4{r1}}, {4{r0}}};
      end
      M_4X16: begin
        logic h0, h1, h2, h3;
        h0 = lane_res(pred, ru[1], re[1], 5, 10,  in_data_0 & 64'hFFFF,             in_data_1 & 64'hFFFF);
        h1 = lane_res(pred, ru[3], re[3], 5, 10, (in_data_0 >> 16) & 64'hFFFF,     (in_data_1 >> 16) & 64'hFFFF);
        h2 = lane_res(pred, ru[5], re[5], 5, 10, (in_data_0 >> 32) & 64'hFFFF,     (in_data_1 >> 32) & 64'hFFFF);
        h3 = lane_res(pred, ru[7], re[7], 5, 10, (in_data_0 >> 48) & 64'hFFFF,     (in_data_1 >> 48) & 64'hFFFF);
        m = {{2{h3}}, {2{h2}}, {2{h1}}, {2{h0}}};
      end
      default: ;   // fp64 (and reserved 2'b11)
    endcase
  end : route

  assign out_data = {{8{m[7]}}, {8{m[6]}}, {8{m[5]}}, {8{m[4]}},
                     {8{m[3]}}, {8{m[2]}}, {8{m[1]}}, {8{m[0]}}};
endmodule : fu_fp_cmp_dec

// ---- Capability wrappers (mode tied so synthesis prunes unreachable modes) ----

module fu_fp_cmp_g1 (                                   // fp64 only
  input  logic clk, input logic rst_n, input logic [3:0] pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_fp_cmp_dec core (.clk(clk), .rst_n(rst_n), .mode(2'b00), .pred(pred),
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
  fu_fp_cmp_dec core (.clk(clk), .rst_n(rst_n), .mode({1'b0, mode}), .pred(pred),
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
  fu_fp_cmp_dec core (.clk(clk), .rst_n(rst_n), .mode(mode), .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

