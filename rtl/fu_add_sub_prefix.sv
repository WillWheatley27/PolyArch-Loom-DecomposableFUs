// fu_add_sub_prefix.sv -- AddSub built on one explicit parallel-prefix (look-ahead) carry
// network instead of `+`, so the adder architecture is the same at every timing target.
// DesignWare's `+` architectures (pparch/apparch) adapt to the constraint and become ripple
// chains when timing is loose; this core keeps its tree (see fu_add_sub_prefix_dot), which lets the decomposable tiers and the
// fixed bank be compared with one adder architecture throughout.
//
// Lanes come from carry kill in the prefix network: the node feeding a lane-start bit is
// replaced by (generate = the lane's carry-in, propagate = 0), so no carry crosses a lane
// boundary and one 64-bit Sklansky tree serves every mode. The fixed units are this core with
// mode tied; constant propagation removes the cross-boundary prefix nodes.
//
//   mode: 00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> 8x8
//         (a mode whose tier is disabled falls back to 1x64)
//   op_sel[i]: op of the lane whose start is 8-bit block i (0 add, 1 sub).
// Combinational, latency 0.

module fu_add_sub_prefix_core #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1
) (
  input  logic [1:0]  mode,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0,
  input  logic [63:0] in_data_1,
  output logic [63:0] sum_out
);
  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;
  localparam logic [1:0] M_8X8  = 2'b11;
  localparam int LEVELS = 6;   // log2(64)

  // ---- Mode decode: per-block lane-start mask and each block's lane op ----
  logic [7:0] is_start, sub;
  always_comb begin : decode
    logic cur;
    case (mode)
      M_2X32:  is_start = EN32 ? 8'b0001_0001 : 8'b0000_0001;
      M_4X16:  is_start = EN16 ? 8'b0101_0101 : 8'b0000_0001;
      M_8X8:   is_start = EN8  ? 8'b1111_1111 : 8'b0000_0001;
      default: is_start = 8'b0000_0001;   // 1x64
    endcase
    cur = op_sel[0];
    for (int i = 0; i < 8; i++) begin
      if (is_start[i]) cur = op_sel[i];   // block 0 is always a start
      sub[i] = cur;
    end
  end : decode

  // ---- Bit generate/propagate; subtraction is a + ~b + 1 per lane ----
  logic [63:0] be, p;
  // verilator lint_off UNUSEDSIGNAL
  logic [63:0] g;   // g[63] would only feed the carry-out, which is not an output
  // verilator lint_on UNUSEDSIGNAL
  for (genvar i = 0; i < 64; i++) begin : gp
    assign be[i] = in_data_1[i] ^ sub[i/8];
    assign g[i]  = in_data_0[i] & be[i];
    assign p[i]  = in_data_0[i] ^ be[i];
  end

  // ---- Prefix inputs: node j yields the carry into bit j ----
  // A lane start takes (its carry-in, 0); every other node is bit j-1's (g, p).
  logic [63:0] gn [LEVELS+1];
  logic [63:0] pn [LEVELS+1];
  for (genvar j = 0; j < 64; j++) begin : seed
    if (j % 8 == 0) begin : block_start
      if (j == 0) begin : lsb
        assign gn[0][j] = sub[0];
        assign pn[0][j] = 1'b0;
      end else begin : boundary
        assign gn[0][j] = is_start[j/8] ? sub[j/8] : g[j-1];
        assign pn[0][j] = is_start[j/8] ? 1'b0     : p[j-1];
      end
    end else begin : inner
      assign gn[0][j] = g[j-1];
      assign pn[0][j] = p[j-1];
    end
  end

  // ---- Sklansky tree: at level l the upper half of each 2^(l+1) block combines with the
  // last node of its lower half (one dot instance per combine, see fu_add_sub_prefix_dot) ----
  for (genvar l = 0; l < LEVELS; l++) begin : level
    for (genvar j = 0; j < 64; j++) begin : node
      if (((j >> l) & 1) != 0) begin : combine
        localparam int K = ((j >> (l + 1)) << (l + 1)) + (1 << l) - 1;
        fu_add_sub_prefix_dot dot (.g_hi(gn[l][j]), .p_hi(pn[l][j]), .g_lo(gn[l][K]), .p_lo(pn[l][K]),
                                   .g(gn[l+1][j]), .p(pn[l+1][j]));
      end else begin : pass
        assign gn[l+1][j] = gn[l][j];
        assign pn[l+1][j] = pn[l][j];
      end
    end
  end

  assign sum_out = p ^ gn[LEVELS];
endmodule : fu_add_sub_prefix_core

// One prefix combine. Kept as its own module so synthesis (run with -no_autoungroup) keeps the
// tree: flattened, compile_ultra's area recovery folds the prefix logic back into a ripple chain
// at loose targets.
module fu_add_sub_prefix_dot (
  input  logic g_hi, p_hi, g_lo, p_lo,
  output logic g, p
);
  assign g = g_hi | (p_hi & g_lo);
  assign p = p_hi & p_lo;
endmodule : fu_add_sub_prefix_dot

module fu_add_sub_prefix #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;
  fu_add_sub_prefix_core #(.EN32(EN32), .EN16(EN16), .EN8(EN8)) core (
    .mode(mode), .op_sel(op_sel), .in_data_0(in_data_0), .in_data_1(in_data_1), .sum_out(out_data)
  );
endmodule : fu_add_sub_prefix

// ---- Capability tiers: identical ports to fu_add_sub_d2/d4/d8 ----

module fu_add_sub_pd2 (                     // 64 + 2x32
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [7:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_prefix #(.EN32(1), .EN16(0), .EN8(0)) u (.*);
endmodule

module fu_add_sub_pd4 (                     // 64 + 2x32 + 4x16
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [7:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_prefix #(.EN32(1), .EN16(1), .EN8(0)) u (.*);
endmodule

module fu_add_sub_pd8 (                     // 64 + 2x32 + 4x16 + 8x8
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [7:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_prefix #(.EN32(1), .EN16(1), .EN8(1)) u (.*);
endmodule

// ---- Fixed units: the core with mode tied; identical ports to rtl/standalone/fu_add_sub_* ----
// (lane i's op_sel bit drives the op of the block that starts lane i)

module fu_add_sub_p64 (
  input  logic clk, input logic rst_n,
  // verilator lint_off UNUSEDSIGNAL
  input  logic [7:0] op_sel,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_prefix #(.EN32(0), .EN16(0), .EN8(0)) u (.mode(2'b00), .op_sel({7'b0, op_sel[0]}), .*);
endmodule

module fu_add_sub_p32x2 (
  input  logic clk, input logic rst_n, input logic [1:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_prefix #(.EN32(1), .EN16(0), .EN8(0)) u (
    .mode(2'b01), .op_sel({3'b0, op_sel[1], 3'b0, op_sel[0]}), .*);
endmodule

module fu_add_sub_p16x4 (
  input  logic clk, input logic rst_n, input logic [3:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_prefix #(.EN32(0), .EN16(1), .EN8(0)) u (
    .mode(2'b10), .op_sel({1'b0, op_sel[3], 1'b0, op_sel[2], 1'b0, op_sel[1], 1'b0, op_sel[0]}), .*);
endmodule

module fu_add_sub_p8x8 (
  input  logic clk, input logic rst_n, input logic [7:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_prefix #(.EN32(0), .EN16(0), .EN8(1)) u (.mode(2'b11), .*);
endmodule
