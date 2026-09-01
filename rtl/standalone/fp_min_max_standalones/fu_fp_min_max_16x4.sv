// fu_fp_min_max_16x4.sv -- Standalone fixed-width 4xFP16 min/max baseline.
//
// Four independent IEEE binary16 lanes packed in 64 bits.  op_sel[i] selects
// minimum/maximum per lane. NaNs produce canonical qNaN; -0.0 < +0.0.
// DW_fp_cmp is instantiated once per fixed lane (no runtime mode).
// Combinational, latency 0, 2-input join handshake.
module fu_fp_min_max_16x4 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic [3:0] op_sel,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  // verilator lint_off UNUSEDSIGNAL
  logic aeqb [0:3], altb [0:3], agtb [0:3], unordered [0:3];
  // verilator lint_on UNUSEDSIGNAL
  // verilator lint_off UNUSEDSIGNAL
  logic [15:0] z0 [0:3], z1 [0:3];
  logic [7:0] status0 [0:3], status1 [0:3];
  // verilator lint_on UNUSEDSIGNAL
  logic [15:0] lane_result [0:3];
  logic [15:0] lane_a [0:3], lane_b [0:3];
  for (genvar i = 0; i < 4; i++) begin : lane
    assign lane_a[i] = in_data_0[i*16 +: 16];
    assign lane_b[i] = in_data_1[i*16 +: 16];
    DW_fp_cmp #(.sig_width(10), .exp_width(5), .ieee_compliance(1)) u_cmp (
      .a(lane_a[i]), .b(lane_b[i]), .zctr(op_sel[i]),
      .aeqb(aeqb[i]), .altb(altb[i]), .agtb(agtb[i]), .unordered(unordered[i]),
      .z0(z0[i]), .z1(z1[i]), .status0(status0[i]), .status1(status1[i])
    );

    logic both_zero, a_nan, b_nan, a_lt;
    assign both_zero = (lane_a[i][14:0] == 15'd0) && (lane_b[i][14:0] == 15'd0);
    assign a_nan = (&lane_a[i][14:10]) && (|lane_a[i][9:0]);
    assign b_nan = (&lane_b[i][14:10]) && (|lane_b[i][9:0]);
    assign a_lt = lane_a[i][15];
    assign lane_result[i] = (a_nan || b_nan) ? 16'h7E00
      : both_zero ? (op_sel[i] ? (a_lt ? lane_b[i] : lane_a[i])
                                : (a_lt ? lane_a[i] : lane_b[i]))
                  : z0[i];
    assign out_data[i*16 +: 16] = lane_result[i];
  end
endmodule : fu_fp_min_max_16x4
