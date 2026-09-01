// fu_mult_32x2.sv -- Standalone fixed-width 2x32 multiply-low baseline.
//
// Two independent 32x32 products are packed in a 64-bit word.  Each lane
// returns its low 32 bits, matching the multiply-low semantics of the
// decomposable integer multiply.  There is no runtime mode and no cross-lane
// interaction.  DW02_mult is used because it is the natural DesignWare
// combinational multiplier; only the low half of each product is exposed.
//
// Combinational, latency 0, 2-input join handshake.
module fu_mult_32x2 (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

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

  wire [63:0] product [0:1];
  for (genvar i = 0; i < 2; i++) begin : lane
    DW02_mult #(.A_width(32), .B_width(32)) u_mult (
      .A       (in_data_0[i*32 +: 32]),
      .B       (in_data_1[i*32 +: 32]),
      .TC      (1'b0),
      .PRODUCT (product[i])
    );
    assign out_data[i*32 +: 32] = product[i][31:0];
  end
endmodule : fu_mult_32x2
