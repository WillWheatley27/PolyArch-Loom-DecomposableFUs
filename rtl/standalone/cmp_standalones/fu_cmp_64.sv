// fu_cmp_64.sv -- Standalone fixed-width 1x64 integer compare baseline.
// pred encoding matches fu_cmp_gen: eq, ne, signed lt/le/gt/ge, unsigned
// lt/le/gt/ge. The result is a 64-bit all-ones/all-zeros predicate mask.
module fu_cmp_64 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic [3:0] pred,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;
  function automatic logic pred_eval(input logic [3:0] p, input logic ugt,
                                     input logic sgt, input logic eq);
    case (p)
      4'd0: pred_eval = eq;               4'd1: pred_eval = ~eq;
      4'd2: pred_eval = ~(sgt | eq);     4'd3: pred_eval = ~sgt;
      4'd4: pred_eval = sgt;             4'd5: pred_eval = sgt | eq;
      4'd6: pred_eval = ~(ugt | eq);     4'd7: pred_eval = ~ugt;
      4'd8: pred_eval = ugt;             4'd9: pred_eval = ugt | eq;
      default: pred_eval = 1'b0;
    endcase
  endfunction
  // verilator lint_off UNUSEDSIGNAL
  logic lane_lt, lane_eq, lane_gt, lane_le, lane_ge, lane_ne;
  // verilator lint_on UNUSEDSIGNAL
  DW01_cmp6 #(.width(64)) u_cmp (
    .A(in_data_0), .B(in_data_1), .TC(1'b0),
    .LT(lane_lt), .GT(lane_gt), .EQ(lane_eq),
    .LE(lane_le), .GE(lane_ge), .NE(lane_ne)
  );
  logic signed_gt;
  assign signed_gt = (in_data_0[63] ^ in_data_1[63])
                   ? ~in_data_0[63] : lane_gt;
  assign out_data = {64{pred_eval(pred, lane_gt, signed_gt, lane_eq)}};
endmodule
