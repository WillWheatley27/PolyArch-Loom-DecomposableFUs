// fu_add_sub_minmax_gen.sv -- Min/Max side function for the shared decomposable
// AddSub carry chain. This includes the canonical AddSub engine rather than
// instantiating fu_min_max_dec, so Min/Max has no independent comparator path.
`include "fu_add_sub_gen.sv"

// is_min_max=0: existing AddSub behavior (op_sel lane value: 0 add, 1 sub).
// is_min_max=1: force a lane-local A-B through the same carry chain and select
//               min/max (op_sel lane value: 0 min, 1 max).
// is_signed is used only for Min/Max. Lane controls always use the AddSub byte
// start convention: 64->op_sel[0], 2x32->op_sel[0]/[4], 4x16->0/2/4/6,
// 8x8->all eight bits. Ties preserve the integer Min/Max convention: min=A,
// max=B. Combinational, latency 0.
module fu_add_sub_minmax_dec #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic        is_min_max,
  input  logic        is_signed,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  logic [63:0] difference;
  logic [7:0] lane_start, lane_op, block_cout;
  fu_add_sub_segmented #(.EN32(EN32), .EN16(EN16), .EN8(EN8)) segmented (
    .mode(mode), .op_sel(op_sel), .force_sub(is_min_max),
    .in_data_0(in_data_0), .in_data_1(in_data_1), .sum_out(difference),
    .lane_start_out(lane_start), .lane_op_out(lane_op),
    .block_cout_out(block_cout)
  );

  // A lane's top block is immediately before the next lane start. In Min/Max
  // mode, the subtraction result, lane carry, and sign/overflow are all from
  // the one segmented AddSub chain above.
  logic [7:0] lane_top, lane_eq, lane_gt;
  always_comb begin : compare_from_subtract
    logic zero_run;
    logic overflow;
    zero_run = 1'b1;
    overflow = 1'b0;
    for (int i = 0; i < 8; i++) begin
      lane_top[i] = (i == 7) ? 1'b1 : lane_start[i+1];
      if (lane_start[i]) zero_run = ~(|difference[i*8 +: 8]);
      else               zero_run = zero_run & ~(|difference[i*8 +: 8]);
      lane_eq[i] = zero_run;
      lane_gt[i] = 1'b0;
      if (lane_top[i]) begin
        // For A-B: unsigned A>B is carry-out and nonzero. Signed A>B is
        // !Z && !(N xor V), where V is subtraction overflow.
        overflow = (in_data_0[i*8+7] ^ in_data_1[i*8+7])
                 & (difference[i*8+7] ^ in_data_0[i*8+7]);
        lane_gt[i] = is_signed
                   ? (~lane_eq[i] & ~(difference[i*8+7] ^ overflow))
                   : (block_cout[i] & ~lane_eq[i]);
      end
    end
  end : compare_from_subtract

  logic [63:0] minmax_out;
  always_comb begin : select_minmax
    logic choose_b;
    choose_b = 1'b0;
    minmax_out = '0;
    for (int i = 7; i >= 0; i--) begin
      if (lane_top[i]) begin
        // min: choose B when A>B. max: choose B when A<=B, including ties.
        choose_b = lane_op[i] ? ~lane_gt[i] : lane_gt[i];
      end
      minmax_out[i*8 +: 8] = choose_b ? in_data_1[i*8 +: 8]
                                        : in_data_0[i*8 +: 8];
    end
  end : select_minmax

  assign out_data = is_min_max ? minmax_out : difference;
endmodule : fu_add_sub_minmax_dec

module fu_add_sub_minmax_d1 (
  input logic clk, input logic rst_n, input logic [1:0] mode,
  input logic is_min_max, input logic is_signed, input logic [7:0] op_sel,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_minmax_dec #(.EN32(0), .EN16(0), .EN8(0)) core (.*);
endmodule

module fu_add_sub_minmax_d2 (
  input logic clk, input logic rst_n, input logic [1:0] mode,
  input logic is_min_max, input logic is_signed, input logic [7:0] op_sel,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_minmax_dec #(.EN32(1), .EN16(0), .EN8(0)) core (.*);
endmodule

module fu_add_sub_minmax_d4 (
  input logic clk, input logic rst_n, input logic [1:0] mode,
  input logic is_min_max, input logic is_signed, input logic [7:0] op_sel,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_minmax_dec #(.EN32(1), .EN16(1), .EN8(0)) core (.*);
endmodule

module fu_add_sub_minmax_d8 (
  input logic clk, input logic rst_n, input logic [1:0] mode,
  input logic is_min_max, input logic is_signed, input logic [7:0] op_sel,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_add_sub_minmax_dec #(.EN32(1), .EN16(1), .EN8(1)) core (.*);
endmodule
