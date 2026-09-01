// fu_min_max_32x2.sv -- Standalone fixed-width 2x32 integer min/max baseline.
//
// Two independent 32-bit lanes are packed in a 64-bit word.  is_signed selects
// signed or unsigned ordering for both lanes; op_sel[i] selects min (0) or max
// (1) for lane i.  There is no runtime mode and no cross-lane comparison.
// DW_cmp_dx is the natural duplex comparator for this fixed 2x32 datapath.
// Equal values preserve the existing FU convention: min returns A, max returns B.
//
// Combinational, latency 0, 2-input join handshake.
module fu_min_max_32x2 (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic        is_signed,
  input  logic [1:0]  op_sel,

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
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // DW_cmp_dx exposes the full trichotomy; all outputs remain connected so the
  // vendor model and synthesis view are identical.
  // verilator lint_off UNUSEDSIGNAL
  logic lt0, eq0, gt0, lt1, eq1, gt1;
  // verilator lint_on UNUSEDSIGNAL
  DW_cmp_dx #(.width(64), .p1_width(32)) u_cmp (
    .a(in_data_0), .b(in_data_1), .tc(is_signed), .dplx(1'b1),
    .lt1(lt0), .eq1(eq0), .gt1(gt0), .lt2(lt1), .eq2(eq1), .gt2(gt1)
  );

  // Use all comparator outputs to form strict a>b, preserving tie behavior.
  logic a_gt_b0, a_gt_b1;
  assign a_gt_b0 = ~lt0 & ~eq0;
  assign a_gt_b1 = ~lt1 & ~eq1;
  assign out_data[31:0]  = (op_sel[0] ? ~a_gt_b0 : a_gt_b0)
                           ? in_data_1[31:0] : in_data_0[31:0];
  assign out_data[63:32] = (op_sel[1] ? ~a_gt_b1 : a_gt_b1)
                           ? in_data_1[63:32] : in_data_0[63:32];
endmodule : fu_min_max_32x2
