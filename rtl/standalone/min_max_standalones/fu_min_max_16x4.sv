// fu_min_max_16x4.sv -- Standalone fixed-width 4x16 integer min/max baseline.
//
// Four independent 16-bit lanes are packed in a 64-bit word.  is_signed selects
// signed or unsigned ordering for all lanes; op_sel[i] selects min (0) or max
// (1).  There is no runtime mode and no cross-lane comparison.  No 4-way
// DesignWare duplex comparator exists, so each lane uses DW01_cmp6.
// Equal values preserve the existing FU convention: min returns A, max returns B.
//
// Combinational, latency 0, 2-input join handshake.
module fu_min_max_16x4 (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic        is_signed,
  input  logic [3:0]  op_sel,

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

  // verilator lint_off UNUSEDSIGNAL
  logic lane_lt [0:3], lane_gt [0:3], lane_eq [0:3];
  logic lane_le [0:3], lane_ge [0:3], lane_ne [0:3];
  // verilator lint_on UNUSEDSIGNAL
  for (genvar i = 0; i < 4; i++) begin : lane
    DW01_cmp6 #(.width(16)) u_cmp (
      .A  (in_data_0[i*16 +: 16]),
      .B  (in_data_1[i*16 +: 16]),
      .TC (is_signed),
      .LT (lane_lt[i]), .GT (lane_gt[i]), .EQ (lane_eq[i]),
      .LE (lane_le[i]), .GE (lane_ge[i]), .NE (lane_ne[i])
    );
    assign out_data[i*16 +: 16] = (op_sel[i] ? ~lane_gt[i] : lane_gt[i])
                                  ? in_data_1[i*16 +: 16] : in_data_0[i*16 +: 16];
  end
endmodule : fu_min_max_16x4
