// fu_cmp_32x2.sv -- Standalone fixed-width 2x32 integer compare baseline.
//
// Two independent 32-bit lanes are packed in a 64-bit word.  pred selects the
// same ten predicates as fu_cmp_gen: eq, ne, signed lt/le/gt/ge, and unsigned
// lt/le/gt/ge.  The result is an all-ones/all-zeros mask in each lane.  There is
// no runtime mode and no cross-lane comparison.
//
// DW_cmp_dx supplies the two unsigned lane comparisons.  Signed greater-than
// is derived from the unsigned result and the lane sign bits, so signed and
// unsigned predicates share the same magnitude comparator.
// Combinational, latency 0, 2-input join handshake.
module fu_cmp_32x2 (
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
  logic lt_u0, eq0, gt_u0, lt_u1, eq1, gt_u1;
  // verilator lint_on UNUSEDSIGNAL
  DW_cmp_dx #(.width(64), .p1_width(32)) u_cmp (
    .a(in_data_0), .b(in_data_1), .tc(1'b0), .dplx(1'b1),
    .lt1(lt_u0), .eq1(eq0), .gt1(gt_u0),
    .lt2(lt_u1), .eq2(eq1), .gt2(gt_u1)
  );

  logic gt_s0, gt_s1, result0, result1;
  assign gt_s0 = (in_data_0[31] ^ in_data_1[31])
                 ? ~in_data_0[31] : gt_u0;
  assign gt_s1 = (in_data_0[63] ^ in_data_1[63])
                 ? ~in_data_0[63] : gt_u1;
  assign result0 = pred_eval(pred, gt_u0, gt_s0, eq0);
  assign result1 = pred_eval(pred, gt_u1, gt_s1, eq1);
  assign out_data[31:0]  = {32{result0}};
  assign out_data[63:32] = {32{result1}};
endmodule : fu_cmp_32x2
