// fu_fp_min_max_gen.sv -- GENUINE decomposable packed-FP min/max (IEEE-754-2019). ONE shared
// datapath: the SAME per-lane IEEE->monotonic-unsigned KEY transform + ONE segmented unsigned
// compare chain (eight 8-bit blocks, lex-combined, BROKEN at lane boundaries by `mode`) used by
// fu_fp_cmp_gen; here the shared per-lane less-than decision drives a per-lane 2:1 operand
// select (min/max via op_sel) with a per-lane NaN->canonical-qNaN override. No replicated
// comparators: the chain is computed once and reused across all modes; smaller tiers are strict
// logic subsets of larger ones. Unlike compare, NO -0==+0 fixup: min/max needs -0 < +0, which
// the raw key order already encodes.
//
//   mode: 00 -> 1x fp64, 01 -> 2x fp32, 10 -> 4x fp16, 11 -> reserved -> 1x fp64
//   op_sel[i] per lane: 0 -> min, 1 -> max.
//   IEEE-2019: NaN-propagating (canonical qNaN if either operand NaN); -0 < +0. Comb, latency 0.
module fu_fp_min_max_dec (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic [3:0]  op_sel,
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
  //      positives set the sign bit; unsigned compare of keys == float order (-0 < +0). ----
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

  function automatic logic fp_is_nan(input int EXP_W, input int MAN_W, input logic [63:0] x);
    logic [63:0] EXP_MASK, MAN_MASK, e, mn;
    EXP_MASK = (64'd1 << EXP_W) - 64'd1;
    MAN_MASK = (64'd1 << MAN_W) - 64'd1;
    e  = (x >> MAN_W) & EXP_MASK;
    mn = x & MAN_MASK;
    fp_is_nan = (e == EXP_MASK) && (mn != 64'd0);
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

  // ---- Per-lane result from shared chain: a_lt = a's key strictly below b's key.
  //      min -> a_lt?a:b ; max -> a_lt?b:a ; NaN(either) -> canonical qNaN. ----
  function automatic logic [63:0] lane_res(input logic is_max, input logic kgt, input logic keq,
                                           input int EXP_W, input int MAN_W,
                                           input logic [63:0] xa, input logic [63:0] xb);
    logic [63:0] MAN_MASK, EXP_MASK, qnan; logic a_lt;
    EXP_MASK = (64'd1 << EXP_W) - 64'd1;
    MAN_MASK = (64'd1 << MAN_W) - 64'd1;
    qnan = (EXP_MASK << MAN_W) | (64'd1 << (MAN_W-1));
    if (fp_is_nan(EXP_W, MAN_W, xa) || fp_is_nan(EXP_W, MAN_W, xb))
      lane_res = qnan;
    else begin
      a_lt = ~kgt & ~keq;
      lane_res = is_max ? (a_lt ? xb : xa) : (a_lt ? xa : xb);
    end
  endfunction

  logic [63:0] r;
  always_comb begin : route
    r = lane_res(op_sel[0], ru[7], re[7], 11, 52, in_data_0, in_data_1);   // fp64 default
    unique case (mode)
      M_2X32: begin
        logic [63:0] l0, l1;
        l0 = lane_res(op_sel[0], ru[3], re[3], 8, 23,  in_data_0 & 64'hFFFF_FFFF, in_data_1 & 64'hFFFF_FFFF);
        l1 = lane_res(op_sel[2], ru[7], re[7], 8, 23,  in_data_0 >> 32,           in_data_1 >> 32);
        r = {l1[31:0], l0[31:0]};
      end
      M_4X16: begin
        logic [63:0] g0, g1, g2, g3;
        g0 = lane_res(op_sel[0], ru[1], re[1], 5, 10,  in_data_0 & 64'hFFFF,          in_data_1 & 64'hFFFF);
        g1 = lane_res(op_sel[1], ru[3], re[3], 5, 10, (in_data_0 >> 16) & 64'hFFFF,  (in_data_1 >> 16) & 64'hFFFF);
        g2 = lane_res(op_sel[2], ru[5], re[5], 5, 10, (in_data_0 >> 32) & 64'hFFFF,  (in_data_1 >> 32) & 64'hFFFF);
        g3 = lane_res(op_sel[3], ru[7], re[7], 5, 10, (in_data_0 >> 48) & 64'hFFFF,  (in_data_1 >> 48) & 64'hFFFF);
        r = {g3[15:0], g2[15:0], g1[15:0], g0[15:0]};
      end
      default: ;   // fp64 (and reserved 2'b11)
    endcase
  end : route

  assign out_data = r;
endmodule : fu_fp_min_max_dec

// ---- Capability wrappers (mode tied so synthesis prunes unreachable modes) ----

module fu_fp_min_max_m1 (                               // fp64 only
  input  logic clk, input logic rst_n, input logic [3:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_fp_min_max_dec core (.clk(clk), .rst_n(rst_n), .mode(2'b00), .op_sel(op_sel),
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
  fu_fp_min_max_dec core (.clk(clk), .rst_n(rst_n), .mode({1'b0, mode}), .op_sel(op_sel),
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
  fu_fp_min_max_dec core (.clk(clk), .rst_n(rst_n), .mode(mode), .op_sel(op_sel),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
