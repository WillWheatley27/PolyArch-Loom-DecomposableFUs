// fu_add_sub_gen.sv -- GENUINE decomposable integer add/sub, ONE shared core with
// capability tiers derived by parameter (SSOT). Unlike the earlier three separate
// AddSub designs (fu_add_sub_decomp8 8-block, fu_add_sub_decomp 4-block, and the
// DesignWare duplex fu_add_sub_dx), every tier here is the SAME 8-block segmented
// datapath with identical ports; EN32/EN16/EN8 only gate which lane-boundary carry
// breaks exist. Each smaller tier is therefore a strict logic subset of the larger
// one, so area / leakage / dynamic power are monotonic in capability.
//
//   mode: 00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> 8x8
//         (a mode whose tier is disabled falls back to 1x64)
//   op_sel[i]: op of the lane whose start is 8-bit block i (0 add, 1 sub); blocks
//              that are not lane starts inherit their lane's op.
// One shared 64-bit adder as eight 8-bit blocks; carries across the 8/16/.../56-bit
// boundaries are gated by mode. Combinational, latency 0.
module fu_add_sub_dec #(
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

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;
  localparam logic [1:0] M_8X8  = 2'b11;

  // ---- Split operands into eight 8-bit blocks (little-endian by lane) ----
  logic [7:0] a [8];
  logic [7:0] b [8];
  always_comb begin : split
    for (int i = 0; i < 8; i++) begin
      a[i] = in_data_0[i*8 +: 8];
      b[i] = in_data_1[i*8 +: 8];
    end
  end : split

  // ---- Mode decode: per-block lane-start mask (EN* prunes disabled tiers) ----
  logic [7:0] is_start;
  logic       gov [8];
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
      gov[i] = cur;
    end
  end : decode

  // ---- Segmented carry-propagate over eight 8-bit blocks ----
  logic [7:0] be  [8];
  logic       cin [8];
  logic [7:0] sum [8];
  always_comb begin : add
    logic carry;
    logic co_i;
    carry = 1'b0;
    for (int i = 0; i < 8; i++) begin
      be[i]  = gov[i] ? ~b[i] : b[i];
      cin[i] = is_start[i] ? gov[i] : carry;
      {co_i, sum[i]} = {1'b0, a[i]} + {1'b0, be[i]} + {8'b0, cin[i]};
      carry = co_i;
    end
  end : add

  always_comb begin : pack
    for (int i = 0; i < 8; i++) out_data[i*8 +: 8] = sum[i];
  end : pack
endmodule : fu_add_sub_dec

// ---- Capability wrappers: identical ports, differ only in enabled tiers ----

module fu_add_sub_d1 (                      // 64 only
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [7:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_dec #(.EN32(0), .EN16(0), .EN8(0)) core (.*);
endmodule

module fu_add_sub_d2 (                      // 64 + 2x32
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [7:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_dec #(.EN32(1), .EN16(0), .EN8(0)) core (.*);
endmodule

module fu_add_sub_d4 (                      // 64 + 2x32 + 4x16
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [7:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_dec #(.EN32(1), .EN16(1), .EN8(0)) core (.*);
endmodule

module fu_add_sub_d8 (                      // 64 + 2x32 + 4x16 + 8x8
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [7:0] op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_dec #(.EN32(1), .EN16(1), .EN8(1)) core (.*);
endmodule
