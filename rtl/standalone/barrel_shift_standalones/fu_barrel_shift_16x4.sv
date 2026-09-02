// fu_barrel_shift_16x4.sv -- Standalone fixed-width 4x16 barrel-shift baseline.
//
// Four independent 16-bit lanes are packed in 64 bits. shift_op selects SLL
// (00), SRL (01), or SRA (10); 11 is reserved and behaves as SLL. Each lane
// uses its own low four count bits. There is no runtime mode or cross-lane bit
// movement. DW_shifter is used per lane; its signed coefficient selects the
// direction and DATA_TC selects arithmetic fill.
//
// Combinational, latency 0, 2-input join handshake.
module fu_barrel_shift_16x4 (
  // verilator lint_off UNUSEDSIGNAL
  input logic clk, input logic rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input logic [1:0] shift_op,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  // verilator lint_off UNUSEDSIGNAL
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  // verilator lint_on UNUSEDSIGNAL
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  logic signed [4:0] sh [0:3];
  logic data_tc;
  always_comb begin : decode
    data_tc = (shift_op == 2'b10);
    for (int i = 0; i < 4; i++) begin
      sh[i] = (shift_op == 2'b01 || shift_op == 2'b10)
        ? -$signed({1'b0, in_data_1[i*16 +: 4]})
        : $signed({1'b0, in_data_1[i*16 +: 4]});
    end
  end

  for (genvar i = 0; i < 4; i++) begin : lane
    DW_shifter #(.data_width(16), .sh_width(5), .inv_mode(0)) u_shift (
      .data_in(in_data_0[i*16 +: 16]), .data_tc(data_tc), .sh(sh[i]), .sh_tc(1'b1),
      .sh_mode(1'b1), .data_out(out_data[i*16 +: 16])
    );
  end
endmodule : fu_barrel_shift_16x4
