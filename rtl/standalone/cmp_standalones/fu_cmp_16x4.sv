// fu_cmp_16x4.sv -- Standalone fixed-width 4x16 integer compare baseline.
//
// Four independent 16-bit lanes are packed in a 64-bit word.  pred selects
// equality, signed, or unsigned integer predicates and each lane produces an
// all-ones/all-zeros mask.  There is no runtime mode and no cross-lane compare.
// DW01_cmp6 is used once per lane for the unsigned magnitude/equality result;
// signed ordering is corrected from the lane sign bits.
// Combinational, latency 0, 2-input join handshake.
module fu_cmp_16x4 (
  // verilator lint_off UNUSEDSIGNAL
  input logic        clk,
  input logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input logic [3:0]  pred,
  input logic [63:0] in_data_0,
  input logic        in_valid_0,
  output logic       in_ready_0,
  input logic [63:0] in_data_1,
  input logic        in_valid_1,
  output logic       in_ready_1,
  output logic [63:0] out_data,
  output logic       out_valid,
  input logic        out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  function automatic logic pred_eval(input logic [3:0] p, input logic ugt,
                                     input logic sgt, input logic eq);
    case (p)
      4'd0: pred_eval = eq;
      4'd1: pred_eval = ~eq;
      4'd2: pred_eval = ~(sgt | eq);
      4'd3: pred_eval = ~sgt;
      4'd4: pred_eval = sgt;
      4'd5: pred_eval = sgt | eq;
      4'd6: pred_eval = ~(ugt | eq);
      4'd7: pred_eval = ~ugt;
      4'd8: pred_eval = ugt;
      4'd9: pred_eval = ugt | eq;
      default: pred_eval = 1'b0;
    endcase
  endfunction

  // verilator lint_off UNUSEDSIGNAL
  logic lane_lt [0:3], lane_eq [0:3], lane_gt [0:3];
  logic lane_le [0:3], lane_ge [0:3], lane_ne [0:3];
  // verilator lint_on UNUSEDSIGNAL
  logic lane_gt_s [0:3], lane_result [0:3];

  for (genvar i = 0; i < 4; i++) begin : lane
    DW01_cmp6 #(.width(16)) u_cmp (
      .A(in_data_0[i*16 +: 16]), .B(in_data_1[i*16 +: 16]), .TC(1'b0),
      .LT(lane_lt[i]), .GT(lane_gt[i]), .EQ(lane_eq[i]),
      .LE(lane_le[i]), .GE(lane_ge[i]), .NE(lane_ne[i])
    );
    assign lane_gt_s[i] = (in_data_0[i*16+15] ^ in_data_1[i*16+15])
                          ? ~in_data_0[i*16+15] : lane_gt[i];
    assign lane_result[i] = pred_eval(pred, lane_gt[i], lane_gt_s[i], lane_eq[i]);
    assign out_data[i*16 +: 16] = {16{lane_result[i]}};
  end
endmodule : fu_cmp_16x4
