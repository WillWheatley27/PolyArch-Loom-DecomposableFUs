// fu_add_sub_16x4.sv -- Standalone fixed-width 4x16 add/sub baseline.
//
// This module always performs four independent 16-bit lane operations packed
// in 64 bits.  It is a bank component, not a runtime-decomposable unit: there
// is no mode input and no carry can cross a 16-bit lane boundary.  DesignWare
// has no 4-way addsub duplex primitive, so one fixed-width DW01_addsub is used
// per lane.  A lane op_sel bit of 0 selects addition and 1 subtraction.
//
// Combinational, latency 0, 2-input join handshake.
module fu_add_sub_16x4 (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

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

  wire [15:0] lane_sum [0:3];
  wire        lane_co_unused [0:3];
  for (genvar i = 0; i < 4; i++) begin : lane
    DW01_addsub #(.width(16)) u_addsub (
      .A      (in_data_0[i*16 +: 16]),
      .B      (in_data_1[i*16 +: 16]),
      .CI     (1'b0),
      .ADD_SUB(op_sel[i]),
      .SUM    (lane_sum[i]),
      .CO     (lane_co_unused[i])
    );
    assign out_data[i*16 +: 16] = lane_sum[i];
  end
endmodule : fu_add_sub_16x4
