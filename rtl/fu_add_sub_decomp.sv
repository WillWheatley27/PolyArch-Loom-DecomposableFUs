// fu_add_sub_decomp.sv -- Decomposable (subword-SIMD) FU for share group add_sub.
// op_list: arith.addi, arith.subi, decomposed across subword lanes.
//
//   mode = 2'b00 -> 1x64 : one 64-bit lane
//   mode = 2'b01 -> 2x32 : two independent 32-bit lanes
//   mode = 2'b10 -> 4x16 : four independent 16-bit lanes
//   mode = 2'b11 -> reserved, behaves as 1x64
//
//   op_sel[i] selects per-lane op: 0 -> add, 1 -> subtract (~B + carry-in).
//
// One shared 64-bit adder viewed as four 16-bit blocks; carries across the
// 16/32/48-bit boundaries are gated by mode. Combinational, intrinsic latency 0.
module fu_add_sub_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic [3:0]  op_sel,

  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,

  input  logic [63:0] in_data_1,
  input  logic        in_valid_1,
  output logic        in_ready_1,

  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready
);

  // Handshake: 2-input join, combinational, lossless backpressure.
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // verilator lint_off UNUSEDPARAM
  localparam logic [1:0] M_1X64 = 2'b00;
  // verilator lint_on UNUSEDPARAM
  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // ---- Mode decode: boundary carry breaks + per-block op governance ----
  logic brk16, brk32, brk48;
  logic gov0, gov1, gov2, gov3;   // op controlling each 16-bit block's lane
  always_comb begin : decode
    brk16 = 1'b0; brk32 = 1'b0; brk48 = 1'b0;
    gov0  = op_sel[0]; gov1 = op_sel[0]; gov2 = op_sel[0]; gov3 = op_sel[0];
    case (mode)
      M_2X32: begin : d2x32
        brk32 = 1'b1;
        gov2  = op_sel[2]; gov3 = op_sel[2];
      end : d2x32
      M_4X16: begin : d4x16
        brk16 = 1'b1; brk32 = 1'b1; brk48 = 1'b1;
        gov1  = op_sel[1]; gov2 = op_sel[2]; gov3 = op_sel[3];
      end : d4x16
      default: ;  // M_1X64 and reserved 2'b11 -> defaults (single 64-bit lane)
    endcase
  end : decode

  // ---- Split operands into four 16-bit blocks (little-endian by lane) ----
  logic [15:0] a0, a1, a2, a3;
  logic [15:0] b0, b1, b2, b3;
  assign {a3, a2, a1, a0} = in_data_0;
  assign {b3, b2, b1, b0} = in_data_1;

  // Per-block operand-B invert (subtract = ~B).
  logic [15:0] be0, be1, be2, be3;
  assign be0 = gov0 ? ~b0 : b0;
  assign be1 = gov1 ? ~b1 : b1;
  assign be2 = gov2 ? ~b2 : b2;
  assign be3 = gov3 ? ~b3 : b3;

  // ---- Segmented carry-propagate: carry-in per block is either the propagated
  //      carry-out of the block below, or a fresh lane-start seed (= gov = +1 for sub).
  logic       c0i, c1i, c2i, c3i;
  logic       co0, co1, co2;
  logic [15:0] sum0, sum1, sum2, sum3;

  assign c0i            = gov0;                       // block 0 is always a lane start
  assign {co0, sum0}    = {1'b0, a0} + {1'b0, be0} + {16'b0, c0i};

  assign c1i            = brk16 ? gov1 : co0;
  assign {co1, sum1}    = {1'b0, a1} + {1'b0, be1} + {16'b0, c1i};

  assign c2i            = brk32 ? gov2 : co1;
  assign {co2, sum2}    = {1'b0, a2} + {1'b0, be2} + {16'b0, c2i};

  assign c3i            = brk48 ? gov3 : co2;
  assign sum3           = a3 + be3 + {15'b0, c3i};    // top block carry-out discarded (no flags)

  assign out_data = {sum3, sum2, sum1, sum0};

endmodule : fu_add_sub_decomp
