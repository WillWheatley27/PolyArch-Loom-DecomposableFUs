// fu_fp_cmp_16x4.sv -- Standalone fixed-width 4xFP16 compare baseline.
//
// Four independent IEEE binary16 lanes are packed in a 64-bit word.  pred uses
// the decomposable FP-CMP ordered/unordered encoding and each lane returns an
// all-ones/all-zeros mask.  DW_fp_cmp is instantiated once per fixed lane;
// there is no runtime mode or cross-lane comparison.
// Combinational, latency 0, 2-input join handshake.
module fu_fp_cmp_16x4 (
  // verilator lint_off UNUSEDSIGNAL
  input logic        clk,
  input logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input logic [3:0]  pred,
  input logic [63:0] in_data_0,
  input logic        in_valid_0,
  output logic       in_ready_0,
  input logic [63:0] in_data_1,
  input logic        in_valid_1,
  output logic       in_ready_1,
  output logic [63:0] out_data,
  output logic       out_valid,
  input logic        out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  function automatic logic pred_eval(input logic [3:0] p, input logic uno,
                                     input logic lt, input logic gt, input logic eq);
    case (p)
      4'd0: pred_eval = 1'b0;
      4'd1: pred_eval = ~uno & eq;
      4'd2: pred_eval = ~uno & gt;
      4'd3: pred_eval = ~uno & (gt | eq);
      4'd4: pred_eval = ~uno & lt;
      4'd5: pred_eval = ~uno & (lt | eq);
      4'd6: pred_eval = ~uno & (lt | gt);
      4'd7: pred_eval = ~uno;
      4'd8: pred_eval = uno | eq;
      4'd9: pred_eval = uno | gt;
      4'd10: pred_eval = uno | (gt | eq);
      4'd11: pred_eval = uno | lt;
      4'd12: pred_eval = uno | (lt | eq);
      4'd13: pred_eval = uno | (lt | gt);
      4'd14: pred_eval = uno;
      default: pred_eval = 1'b1;
    endcase
  endfunction

  // verilator lint_off UNUSEDSIGNAL
  logic aeqb [0:3], altb [0:3], agtb [0:3], unordered [0:3];
  logic [15:0] z0 [0:3], z1 [0:3];
  logic [7:0] status0 [0:3], status1 [0:3];
  // verilator lint_on UNUSEDSIGNAL
  for (genvar i = 0; i < 4; i++) begin : lane
    DW_fp_cmp #(.sig_width(10), .exp_width(5), .ieee_compliance(1)) u_cmp (
      .a(in_data_0[i*16 +: 16]), .b(in_data_1[i*16 +: 16]), .zctr(1'b0),
      .aeqb(aeqb[i]), .altb(altb[i]), .agtb(agtb[i]), .unordered(unordered[i]),
      .z0(z0[i]), .z1(z1[i]), .status0(status0[i]), .status1(status1[i])
    );
    assign out_data[i*16 +: 16] =
      {16{pred_eval(pred, unordered[i], altb[i], agtb[i], aeqb[i])}};
  end
endmodule : fu_fp_cmp_16x4
