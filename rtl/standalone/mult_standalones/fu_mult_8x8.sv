// fu_mult_8x8.sv -- Standalone fixed-width 8x8 multiply-low baseline.
//
// Eight independent 8x8 products are packed in a 64-bit word.  Each lane
// returns its low 8 bits.  There is no runtime mode and no cross-lane
// interaction.  DW02_mult is used for each fixed-width lane; its unsigned
// product is truncated to the lane width.
//
// Combinational, latency 0, 2-input join handshake.
module fu_mult_8x8 (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,

  input  logic [63:0] in_data_1,
  input logic        in_valid_1,
  output logic        in_ready_1,

  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  wire [15:0] product [0:7];
  for (genvar i = 0; i < 8; i++) begin : lane
    DW02_mult #(.A_width(8), .B_width(8)) u_mult (
      .A       (in_data_0[i*8 +: 8]),
      .B       (in_data_1[i*8 +: 8]),
      .TC      (1'b0),
      .PRODUCT (product[i])
    );
    assign out_data[i*8 +: 8] = product[i][7:0];
  end
endmodule : fu_mult_8x8
