// Revised FP min/max tiers: thin wrappers over the one slice-based core in
// fu_fp_min_max_gen.sv. Every tier keeps a 2-bit mode port; encodings the tier
// does not support fall back to one FP64 lane.
`include "fu_fp_min_max_gen.sv"

module fu_fp_minmax_revised_shared64(input logic clk,input logic rst_n,input logic [1:0] mode,input logic [3:0] op_sel,input logic [63:0] in_data_0,input logic in_valid_0,output logic in_ready_0,input logic [63:0] in_data_1,input logic in_valid_1,output logic in_ready_1,output logic [63:0] out_data,output logic out_valid,input logic out_ready);
  fu_fp_min_max_dec #(.W(64),.MIN_LANE_W(64)) core_inst(.*); endmodule
module fu_fp_minmax_revised_shared64_32(input logic clk,input logic rst_n,input logic [1:0] mode,input logic [3:0] op_sel,input logic [63:0] in_data_0,input logic in_valid_0,output logic in_ready_0,input logic [63:0] in_data_1,input logic in_valid_1,output logic in_ready_1,output logic [63:0] out_data,output logic out_valid,input logic out_ready);
  fu_fp_min_max_dec #(.W(64),.MIN_LANE_W(32)) core_inst(.*); endmodule
module fu_fp_minmax_revised_shared64_32_16(input logic clk,input logic rst_n,input logic [1:0] mode,input logic [3:0] op_sel,input logic [63:0] in_data_0,input logic in_valid_0,output logic in_ready_0,input logic [63:0] in_data_1,input logic in_valid_1,output logic in_ready_1,output logic [63:0] out_data,output logic out_valid,input logic out_ready);
  fu_fp_min_max_dec #(.W(64),.MIN_LANE_W(16)) core_inst(.*); endmodule
