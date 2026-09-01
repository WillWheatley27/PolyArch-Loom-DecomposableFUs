// fu_fp_min_max_64.sv -- Standalone fixed-width IEEE FP64 min/max baseline.
//
// One fp64 lane.  op_sel=0 selects minimum and op_sel=1 selects maximum.
// NaNs are propagated as the canonical quiet NaN used by the decomposable FU;
// -0.0 is less than +0.0.  DW_fp_cmp supplies the IEEE compare and operand
// selection; the small fixup logic handles canonical NaN and signed-zero policy.
// Combinational, latency 0, 2-input join handshake.
module fu_fp_min_max_64 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic op_sel,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // DW_fp_cmp provides the IEEE min/max result in z0 (zctr=0 min, 1 max).
  // Other status/trichotomy outputs are retained for a complete, portable
  // DesignWare connection but are not needed by this FU.
  // verilator lint_off UNUSEDSIGNAL
  logic aeqb, altb, agtb, unordered;
  logic [63:0] z0, z1;
  logic [7:0] status0, status1;
  // verilator lint_on UNUSEDSIGNAL
  DW_fp_cmp #(.sig_width(52), .exp_width(11), .ieee_compliance(1)) u_cmp (
    .a(in_data_0), .b(in_data_1), .zctr(op_sel),
    .aeqb(aeqb), .altb(altb), .agtb(agtb), .unordered(unordered),
    .z0(z0), .z1(z1), .status0(status0), .status1(status1)
  );

  logic both_zero, a_nan, b_nan;
  assign both_zero = (in_data_0[62:0] == 63'd0) && (in_data_1[62:0] == 63'd0);
  assign a_nan = (&in_data_0[62:52]) && (|in_data_0[51:0]);
  assign b_nan = (&in_data_1[62:52]) && (|in_data_1[51:0]);

  logic [63:0] qnan;
  assign qnan = 64'h7FF8_0000_0000_0000;
  // DW treats signed zeros as equal; min/max needs -0 < +0.
  logic a_lt;
  assign a_lt = both_zero ? in_data_0[63] : altb;
  assign out_data = (a_nan || b_nan) ? qnan
                   : both_zero ? (op_sel ? (a_lt ? in_data_1 : in_data_0)
                                          : (a_lt ? in_data_0 : in_data_1))
                   : z0;
endmodule : fu_fp_min_max_64
