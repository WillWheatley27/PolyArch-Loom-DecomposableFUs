// fu_barrel_shift_32x2.sv -- Standalone fixed-width 2x32 barrel-shift baseline.
//
// Two independent 32-bit lanes are packed in 64 bits. shift_op selects SLL
// (00), SRL (01), or SRA (10); 11 is reserved and behaves as SLL. Each lane
// uses its own low five count bits. There is no runtime mode or cross-lane bit
// movement. DW_shifter is used because its signed shift coefficient naturally
// selects left/right direction while DATA_TC selects arithmetic fill.
//
// Combinational, latency 0, 2-input join handshake.
module fu_barrel_shift_32x2 (
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

  logic signed [5:0] sh_lo, sh_hi;
  logic tc_lo, tc_hi;
  always_comb begin : decode
    tc_lo = (shift_op == 2'b10);
    tc_hi = tc_lo;
    sh_lo = (shift_op == 2'b01 || shift_op == 2'b10)
      ? -$signed({1'b0, in_data_1[4:0]}) : $signed({1'b0, in_data_1[4:0]});
    sh_hi = (shift_op == 2'b01 || shift_op == 2'b10)
      ? -$signed({1'b0, in_data_1[36:32]}) : $signed({1'b0, in_data_1[36:32]});
  end

  DW_shifter #(.data_width(32), .sh_width(6), .inv_mode(0)) u_lo (
    .data_in(in_data_0[31:0]), .data_tc(tc_lo), .sh(sh_lo), .sh_tc(1'b1),
    .sh_mode(1'b1), .data_out(out_data[31:0])
  );
  DW_shifter #(.data_width(32), .sh_width(6), .inv_mode(0)) u_hi (
    .data_in(in_data_0[63:32]), .data_tc(tc_hi), .sh(sh_hi), .sh_tc(1'b1),
    .sh_mode(1'b1), .data_out(out_data[63:32])
  );
endmodule : fu_barrel_shift_32x2
