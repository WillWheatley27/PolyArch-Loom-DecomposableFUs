// fu_cmp_gen.sv -- GENUINE decomposable integer compare (share via arith.cmpi).
// ONE shared comparator: eight 8-bit block comparators whose three lexicographic
// combines (unsigned a>b, signed a>b, a==b) are BROKEN at lane boundaries by `mode`
// (the same segmentation idea as fu_add_sub_decomp / fu_min_max_decomp). No
// replication: the blocks and chains are computed once and reused across all modes;
// only the break points and lane-top routing change with mode. A per-lane predicate
// mux broadcasts the boolean to an all-ones/all-zeros lane mask (SSE PCMPGT-style).
//
//   mode: 00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> 8x8
//   pred[3:0]: 0 eq,1 ne,2 slt,3 sle,4 sgt,5 sge,6 ult,7 ule,8 ugt,9 uge; >=10 -> all-zeros.
// Combinational, latency 0.
// Capability ladder (see wrappers): c1=1x64, c2=+2x32, c4=+4x16, c8=+8x8.
module fu_cmp_dec (
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
  localparam logic [1:0] M_8X8  = 2'b11;

  function automatic logic pred_eval(input logic [3:0] p, input logic ugt,
                                     input logic sgt, input logic eq);
    case (p)
      4'd0: pred_eval = eq;            4'd1: pred_eval = ~eq;
      4'd2: pred_eval = ~(sgt | eq);   4'd3: pred_eval = ~sgt;
      4'd4: pred_eval = sgt;           4'd5: pred_eval = sgt | eq;
      4'd6: pred_eval = ~(ugt | eq);   4'd7: pred_eval = ~ugt;
      4'd8: pred_eval = ugt;           4'd9: pred_eval = ugt | eq;
      default: pred_eval = 1'b0;
    endcase
  endfunction

  // ---- Eight 8-bit block comparators (computed once, reused across all modes) ----
  logic [7:0] a [0:7];
  logic [7:0] b [0:7];
  logic       gtu [0:7];
  logic       eqb [0:7];
  for (genvar i = 0; i < 8; i++) begin : blk
    assign a[i]   = in_data_0[i*8 +: 8];
    assign b[i]   = in_data_1[i*8 +: 8];
    assign gtu[i] = a[i] > b[i];
    assign eqb[i] = a[i] == b[i];
  end

  // ---- Per-mode masks: brk[i]=cut chain entering block i; top[i]=block i is a lane MSB ----
  logic [7:1] brk;
  logic [7:0] top;
  always_comb begin : masks
    unique case (mode)
      M_8X8:   begin brk = 7'b111_1111; top = 8'b1111_1111; end
      M_4X16:  begin brk = 7'b010_1010; top = 8'b1010_1010; end
      M_2X32:  begin brk = 7'b000_1000; top = 8'b1000_1000; end
      default: begin brk = 7'b000_0000; top = 8'b1000_0000; end
    endcase
  end : masks
  // ---- Signed-adjusted a>b at lane-MSB blocks (differing sign bits flip magnitude order) ----
  logic gts [0:7];
  for (genvar i = 0; i < 8; i++) begin : sgn
    assign gts[i] = (top[i] & (a[i][7] ^ b[i][7])) ? b[i][7] : gtu[i];
  end

  // ---- Three lex chains, accumulating LSB->MSB, cut at lane boundaries by brk ----
  logic ru [0:7];
  logic rs [0:7];
  logic re [0:7];
  assign ru[0] = gtu[0];
  assign rs[0] = gts[0];
  assign re[0] = eqb[0];
  for (genvar i = 1; i < 8; i++) begin : chain
    assign ru[i] = brk[i] ? gtu[i] : (gtu[i] | (eqb[i] & ru[i-1]));
    assign rs[i] = brk[i] ? gts[i] : (gts[i] | (eqb[i] & rs[i-1]));
    assign re[i] = brk[i] ? eqb[i] : (eqb[i] & re[i-1]);
  end

  // ---- Per-block predicate result (meaningful at lane-MSB blocks) ----
  logic res [0:7];
  for (genvar i = 0; i < 8; i++) begin : pr
    assign res[i] = pred_eval(pred, ru[i], rs[i], re[i]);
  end

  // ---- Route each block to its lane's MSB result, broadcast to an 8-bit mask ----
  logic [7:0] m;
  always_comb begin : route
    for (int i = 0; i < 8; i++) m[i] = res[7];        // 1x64 (and 2'b?? default)
    unique case (mode)
      M_2X32: begin
        m[0]=res[3]; m[1]=res[3]; m[2]=res[3]; m[3]=res[3];
        m[4]=res[7]; m[5]=res[7]; m[6]=res[7]; m[7]=res[7];
      end
      M_4X16: begin
        m[0]=res[1]; m[1]=res[1]; m[2]=res[3]; m[3]=res[3];
        m[4]=res[5]; m[5]=res[5]; m[6]=res[7]; m[7]=res[7];
      end
      M_8X8: for (int i = 0; i < 8; i++) m[i] = res[i];
      default: ;
    endcase
  end : route

  assign out_data = {{8{m[7]}}, {8{m[6]}}, {8{m[5]}}, {8{m[4]}},
                     {8{m[3]}}, {8{m[2]}}, {8{m[1]}}, {8{m[0]}}};
endmodule : fu_cmp_dec

// ---- Capability wrappers (mode tied so synthesis prunes unreachable modes) ----
// Ladder by max lane count: c1 = 1x64, c2 = +2x32, c4 = +4x16, c8 = +8x8.
// Each rung structurally cannot reach a finer mode than its name, so DC prunes
// the higher-mode masks/routing -> each rung is a strict logic subset of the next.

module fu_cmp_c1 (                                     // 64 only
  input  logic clk, input logic rst_n,
  input  logic [3:0] pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_cmp_dec core (.clk(clk), .rst_n(rst_n), .mode(2'b00), .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_cmp_c2 (                                     // 64 + 2x32
  input  logic clk, input logic rst_n,
  input  logic mode,                                   // 0 -> 1x64, 1 -> 2x32
  input  logic [3:0] pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_cmp_dec core (.clk(clk), .rst_n(rst_n), .mode({1'b0, mode}), .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_cmp_c4 (                                     // 64 + 2x32 + 4x16 (no 8x8)
  input  logic clk, input logic rst_n,
  input  logic [1:0] mode,                             // 00->64, 01->2x32, 10->4x16
  input  logic [3:0] pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  // Clamp 11 -> 10 so the core never sees M_8X8; DC prunes all 8x8 logic.
  logic [1:0] m_int;
  assign m_int = (mode == 2'b11) ? 2'b10 : mode;
  fu_cmp_dec core (.clk(clk), .rst_n(rst_n), .mode(m_int), .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_cmp_c8 (                                     // 64 + 2x32 + 4x16 + 8x8
  input  logic clk, input logic rst_n,
  input  logic [1:0] mode,
  input  logic [3:0] pred,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_cmp_dec core (.clk(clk), .rst_n(rst_n), .mode(mode), .pred(pred),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
