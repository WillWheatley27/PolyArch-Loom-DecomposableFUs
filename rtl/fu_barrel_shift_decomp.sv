// fu_barrel_shift_decomp.sv -- Decomposable (subword-SIMD) FU for barrel shift.
// share group 4 (arith.shli / arith.shrsi / arith.shrui), decomposed across lanes.
//
//   mode = 2'b00 -> 1x64 : one 64-bit lane
//   mode = 2'b01 -> 2x32 : two independent 32-bit lanes
//   mode = 2'b10 -> 4x16 : four independent 16-bit lanes
//   mode = 2'b11 -> reserved, behaves as 1x64
//
//   shift_op : 00=SLL (logical left), 01=SRL (logical right), 10=SRA (arithmetic right),
//              11=reserved -> SLL. Global (the shift type is per-instruction).
//   in_data_0 = data ; in_data_1 = per-lane shift amounts (low log2(lane width) bits per lane;
//   higher count bits ignored, as in x86/RISC-V shift-count masking).
//
// Each lane shifts within its own width -> no cross-lane spill. Combinational, latency 0.
// Proves functional decomposition; a physically-shared segmented barrel network (per-stage
// lane blocking, per-lane stage-enables) is the synthesis/area objective (analysis caveat).
module fu_barrel_shift_decomp (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic [1:0]  shift_op,

  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,

  // verilator lint_off UNUSEDSIGNAL
  input  logic [63:0] in_data_1,   // per-lane shift amounts; only low log2(w) bits/lane used
  // verilator lint_on UNUSEDSIGNAL
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

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // ---- Per-lane shift primitives (the shared shifter, at each lane width) ----
  function automatic logic [15:0] sh16(input logic [1:0] op, input logic [15:0] x, input logic [3:0] amt);
    case (op)
      2'b01:   sh16 = x >> amt;             // SRL
      2'b10:   sh16 = $signed(x) >>> amt;   // SRA
      default: sh16 = x << amt;             // SLL (00, reserved 11)
    endcase
  endfunction
  function automatic logic [31:0] sh32(input logic [1:0] op, input logic [31:0] x, input logic [4:0] amt);
    case (op)
      2'b01:   sh32 = x >> amt;
      2'b10:   sh32 = $signed(x) >>> amt;
      default: sh32 = x << amt;
    endcase
  endfunction
  function automatic logic [63:0] sh64(input logic [1:0] op, input logic [63:0] x, input logic [5:0] amt);
    case (op)
      2'b01:   sh64 = x >> amt;
      2'b10:   sh64 = $signed(x) >>> amt;
      default: sh64 = x << amt;
    endcase
  endfunction

  // ---- Per-mode lane evaluations (shared shift primitive at three widths) ----
  logic [63:0] p1, p2, p4;

  assign p1 = sh64(shift_op, in_data_0, in_data_1[5:0]);

  assign p2 = {sh32(shift_op, in_data_0[63:32], in_data_1[36:32]),
               sh32(shift_op, in_data_0[31:0],  in_data_1[4:0])};

  assign p4 = {sh16(shift_op, in_data_0[63:48], in_data_1[51:48]),
               sh16(shift_op, in_data_0[47:32], in_data_1[35:32]),
               sh16(shift_op, in_data_0[31:16], in_data_1[19:16]),
               sh16(shift_op, in_data_0[15:0],  in_data_1[3:0])};

  always_comb begin : outmux
    case (mode)
      M_2X32:  out_data = p2;
      M_4X16:  out_data = p4;
      default: out_data = p1;   // 1x64 and reserved 2'b11
    endcase
  end : outmux

endmodule : fu_barrel_shift_decomp
