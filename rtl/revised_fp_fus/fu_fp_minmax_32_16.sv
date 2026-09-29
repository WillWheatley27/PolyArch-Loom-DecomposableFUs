// Two-level packed FP min/max: one FP32 or two FP16 lanes. The same slice-based
// core as fu_fp_min_max_gen.sv at a 32-bit width (two 16-bit slices).
// The low 32 bits carry the active packet; upper bits are ignored/zeroed.
`include "fu_fp_min_max_gen.sv"

module fu_fp_minmax_revised_32_16 (
  input logic clk,input logic rst_n,input logic mode,input logic [1:0] op_sel,
  input logic [63:0] in_data_0,input logic in_valid_0,output logic in_ready_0,
  input logic [63:0] in_data_1,input logic in_valid_1,output logic in_ready_1,
  output logic [63:0] out_data,output logic out_valid,input logic out_ready
);
  logic [31:0] result;
  fu_fp_min_max_dec #(.W(32), .MIN_LANE_W(16)) core (.clk(clk), .rst_n(rst_n),
    .mode({1'b0, mode}), .op_sel(op_sel),
    .in_data_0(in_data_0[31:0]), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1[31:0]), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(result), .out_valid(out_valid), .out_ready(out_ready));
  assign out_data = {32'd0, result};
endmodule
