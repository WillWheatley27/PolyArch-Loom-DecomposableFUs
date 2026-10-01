// fu_barrel_shift_gen.sv -- GENUINE decomposable barrel shift (SLL/SRL/SRA). ONE shared
// datapath: a single 6-stage log-shifter (stages shift by 1,2,4,8,16,32) applied across the
// full 64-bit word. Subword-SIMD reuses the SAME stages -- it only (a) zeroes the bits a
// stage would pull ACROSS a lane boundary (per-mode keep masks) and (b) gates the high
// stages off per lane (a lane's shift amount is only its low log2(W) bits), so a lane never
// shifts past its own width. No replicated shifters: the network is built once; only the
// lane-blocking masks and per-lane stage-enables change with mode -> smaller tiers are strict
// logic subsets of the 64-bit shifter (mode tied in the wrappers prunes the mask muxes).
//
//   mode: 00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> reserved -> 1x64
//   shift_op: 00 SLL, 01 SRL, 10 SRA, 11 reserved -> SLL. Global (per-instruction).
//   in_data_0 = data; in_data_1 = per-lane shift amounts (low log2(W) bits per lane, higher
//   bits ignored -- x86/RISC-V count masking). Combinational, latency 0.
module fu_barrel_shift_dec (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  input  logic [63:0] in_data_1,   // per-lane shift amounts; only low log2(W) bits/lane used
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic [1:0]  shift_op,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic        in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // ---- Compile-time lane-blocking masks: keepL bit p =1 if p-s stays in p's lane (SLL);
  //      keepR bit p =1 if p+s stays in p's lane (SRL/SRA). W = lane width. ----
  function automatic logic [63:0] mkKeepL(input int W, input int s);
    logic [63:0] m; m = '0;
    for (int p=0;p<64;p++) m[p] = ((p % W) >= s);
    mkKeepL = m;
  endfunction
  function automatic logic [63:0] mkKeepR(input int W, input int s);
    logic [63:0] m; m = '0;
    for (int p=0;p<64;p++) m[p] = ((p % W) < (W - s));
    mkKeepR = m;
  endfunction

  // ---- Mode decode (left edge): one-hot lane width; nothing else reads `mode` ----
  logic l64, l32, l16;
  always_comb begin : mode_decode
    l32 = (mode == M_2X32);
    l16 = (mode == M_4X16);
    l64 = ~(l32 | l16);                // 1x64, also for reserved encodings
  end : mode_decode

  // ---- Arithmetic-fill sign broadcast (each lane's original MSB across the lane) ----
  logic [63:0] sgn;
  assign sgn = ({64{l64}} & {64{in_data_0[63]}})
             | ({64{l32}} & {{32{in_data_0[63]}}, {32{in_data_0[31]}}})
             | ({64{l16}} & {{16{in_data_0[63]}}, {16{in_data_0[47]}},
                             {16{in_data_0[31]}}, {16{in_data_0[15]}}});
  // ---- Shared 6-stage log-shifter. lvl[0]=data; stage k shifts magnitude 2^k, per-lane
  //      enabled by that lane's amt bit k, lane-blocked by keepL/keepR. ----
  logic [63:0] lvl [0:6];
  assign lvl[0] = in_data_0;
  for (genvar k=0;k<6;k++) begin : stg
    localparam int S = (1 << k);
    logic [63:0] keepL, keepR, en;
    // Lane-blocking masks: constants selected by the decoded lane width.
    assign keepL = ({64{l64}} & mkKeepL(64,S)) | ({64{l32}} & mkKeepL(32,S)) | ({64{l16}} & mkKeepL(16,S));
    assign keepR = ({64{l64}} & mkKeepR(64,S)) | ({64{l32}} & mkKeepR(32,S)) | ({64{l16}} & mkKeepR(16,S));
    // Per-lane stage enable = that lane's shift-amount bit k, broadcast across the lane.
    // Narrow lanes expose only low log2(W) bits, so high stages self-disable.
    logic [63:0] en32, en16;
    assign en32 = (k < 5) ? {{32{in_data_1[32 + k]}}, {32{in_data_1[k]}}} : 64'd0;
    assign en16 = (k < 4) ? {{16{in_data_1[48 + k]}}, {16{in_data_1[32 + k]}},
                             {16{in_data_1[16 + k]}}, {16{in_data_1[k]}}} : 64'd0;
    assign en = ({64{l64}} & {64{in_data_1[k]}}) | ({64{l32}} & en32) | ({64{l16}} & en16);
    logic [63:0] shl, shrl, shra, sel;
    assign shl  = (lvl[k] << S) & keepL;              // SLL: zero-fill low bits
    assign shrl = (lvl[k] >> S) & keepR;              // SRL: zero-fill high bits
    assign shra = shrl | (sgn & ~keepR);              // SRA: sign-fill high bits
    always_comb begin : opsel
      unique case (shift_op)
        2'b01:   sel = shrl;
        2'b10:   sel = shra;
        default: sel = shl;                           // SLL (00, reserved 11)
      endcase
    end : opsel
    assign lvl[k+1] = (sel & en) | (lvl[k] & ~en);    // per-lane apply/bypass this stage
  end : stg

  assign out_data = lvl[6];
endmodule : fu_barrel_shift_dec

// ---- Capability wrappers (mode tied so synthesis prunes unreachable modes) ----

module fu_bshift_bs1 (                                  // 1x64 only
  input  logic clk, input logic rst_n, input logic [1:0] shift_op,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_barrel_shift_dec core (.clk(clk), .rst_n(rst_n), .mode(2'b00), .shift_op(shift_op),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_bshift_bs2 (                                  // + 2x32
  input  logic clk, input logic rst_n, input logic mode, input logic [1:0] shift_op,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_barrel_shift_dec core (.clk(clk), .rst_n(rst_n), .mode({1'b0, mode}), .shift_op(shift_op),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_bshift_bs3 (                                  // + 4x16
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic [1:0] shift_op,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_barrel_shift_dec core (.clk(clk), .rst_n(rst_n), .mode(mode), .shift_op(shift_op),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(in_data_1), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

