// fu_fp_min_max_32x2.sv -- Standalone fixed-width 2xFP32 min/max baseline.
//
// Two independent IEEE FP32 lanes packed in 64 bits.  op_sel[0/1] selects
// minimum/maximum per lane. NaNs produce canonical qNaN; -0.0 < +0.0.
// DW_fp_cmp is instantiated once per fixed lane (no runtime mode).
// Combinational, latency 0, 2-input join handshake.
module fu_fp_min_max_32x2 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic [1:0] op_sel,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // verilator lint_off UNUSEDSIGNAL
  logic aeqb [0:1], altb [0:1], agtb [0:1], unordered [0:1];
  // verilator lint_on UNUSEDSIGNAL
  // verilator lint_off UNUSEDSIGNAL
  logic [31:0] z0 [0:1], z1 [0:1];
  logic [7:0] status0 [0:1], status1 [0:1];
  // verilator lint_on UNUSEDSIGNAL
  logic [31:0] lane_result [0:1];
  logic [31:0] lane_a [0:1], lane_b [0:1];
  for (genvar i = 0; i < 2; i++) begin : lane
    assign lane_a[i] = in_data_0[i*32 +: 32];
    assign lane_b[i] = in_data_1[i*32 +: 32];
    DW_fp_cmp #(.sig_width(23), .exp_width(8), .ieee_compliance(1)) u_cmp (
      .a(lane_a[i]), .b(lane_b[i]), .zctr(op_sel[i]),
      .aeqb(aeqb[i]), .altb(altb[i]), .agtb(agtb[i]), .unordered(unordered[i]),
      .z0(z0[i]), .z1(z1[i]), .status0(status0[i]), .status1(status1[i])
    );

    logic both_zero, a_nan, b_nan, a_lt;
    assign both_zero = (lane_a[i][30:0] == 31'd0) && (lane_b[i][30:0] == 31'd0);
    assign a_nan = (&lane_a[i][30:23]) && (|lane_a[i][22:0]);
    assign b_nan = (&lane_b[i][30:23]) && (|lane_b[i][22:0]);
    assign a_lt = lane_a[i][31];
    assign lane_result[i] = (a_nan || b_nan) ? 32'h7FC0_0000
      : both_zero ? (op_sel[i] ? (a_lt ? lane_b[i] : lane_a[i])
                                : (a_lt ? lane_a[i] : lane_b[i]))
                  : z0[i];
    assign out_data[i*32 +: 32] = lane_result[i];
  end
endmodule : fu_fp_min_max_32x2
