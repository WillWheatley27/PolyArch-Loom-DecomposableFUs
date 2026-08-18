// fu_abs_gen.sv -- GENUINE decomposable absolute value (integer + FP). ONE shared datapath:
// a single 64-bit byte-ripple two's-complement negate chain (invert-then-add-1, the +1
// entering as carry-in at each lane's LSB) with the carry BROKEN at lane boundaries by a
// mode-selected mask. No replicated negators: the chain is built once; only break points
// and per-lane sign routing change with mode, so smaller tiers are strict logic subsets of
// the 64-bit chain. FP abs is a trivial per-lane sign-bit clear (mode-selected mask AND).
//
//   mode: 00 -> 1x int64/fp64, 01 -> 2x int32/fp32, 10 -> 4x int16/fp16, 11 -> reserved -> 1x64
//   is_float: 1 = absf (clear each lane's sign bit; IEEE abs), 0 = absi (per-lane two's-
//             complement negate of negative lanes; INT_MIN wraps to itself). Comb, latency 0.
module fu_abs_dec (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic        is_float,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0;
  assign in_ready_0 = out_ready & out_valid;

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // ---- Per-byte negate flag (lane sign, for absi) + lane-LSB flag, from mode ----
  // brk[i]=1 marks byte i as the low byte of a new lane -> carry break + fresh +1 seed.
  logic       negb [0:7];   // negate this byte's lane (absi only)
  logic [7:0] brk;
  always_comb begin : lanes
    unique case (mode)
      M_4X16: begin
        brk = 8'b0101_0100;
        negb[0]=in_data_0[15]; negb[1]=in_data_0[15];
        negb[2]=in_data_0[31]; negb[3]=in_data_0[31];
        negb[4]=in_data_0[47]; negb[5]=in_data_0[47];
        negb[6]=in_data_0[63]; negb[7]=in_data_0[63];
      end
      M_2X32: begin
        brk = 8'b0001_0000;
        negb[0]=in_data_0[31]; negb[1]=in_data_0[31];
        negb[2]=in_data_0[31]; negb[3]=in_data_0[31];
        negb[4]=in_data_0[63]; negb[5]=in_data_0[63];
        negb[6]=in_data_0[63]; negb[7]=in_data_0[63];
      end
      default: begin
        brk = 8'b0000_0000;
        for (int i=0;i<8;i++) negb[i]=in_data_0[63];
      end
    endcase
  end : lanes

  // ---- Shared byte-ripple negate chain: xb = invert-if-negating; carry-in at each lane LSB
  //      is the negate flag (the two's-complement +1); carry broken at lane boundaries. ----
  logic [7:0] db  [0:7];
  logic [7:0] xb  [0:7];
  logic       cin [0:7];
  logic [8:0] sm  [0:7];
  for (genvar i=0;i<8;i++) begin : split
    assign db[i] = in_data_0[i*8 +: 8];
    assign xb[i] = negb[i] ? ~db[i] : db[i];
  end
  // byte 0 is always a lane LSB (seed = negb[0]); byte i seeds when brk[i], else takes carry.
  assign cin[0] = negb[0];
  assign sm[0]  = {1'b0, xb[0]} + {8'd0, cin[0]};
  for (genvar i=1;i<8;i++) begin : chain
    assign cin[i] = brk[i] ? negb[i] : sm[i-1][8];
    assign sm[i]  = {1'b0, xb[i]} + {8'd0, cin[i]};
  end

  logic [63:0] absi_res;
  for (genvar i=0;i<8;i++) begin : pack
    assign absi_res[i*8 +: 8] = sm[i][7:0];
  end

  // ---- FP abs: clear per-lane sign bit (mode-selected mask) ----
  logic [63:0] sign_mask;
  always_comb begin : fmask
    unique case (mode)
      M_2X32:  sign_mask = 64'h8000_0000_8000_0000;
      M_4X16:  sign_mask = 64'h8000_8000_8000_8000;
      default: sign_mask = 64'h8000_0000_0000_0000;
    endcase
  end : fmask

  assign out_data = is_float ? (in_data_0 & ~sign_mask) : absi_res;
endmodule : fu_abs_dec

// ---- Capability wrappers (mode tied so synthesis prunes unreachable modes) ----

module fu_abs_a1 (                                     // int64/fp64 only
  input  logic clk, input logic rst_n, input logic is_float,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_abs_dec core (.clk(clk), .rst_n(rst_n), .mode(2'b00), .is_float(is_float),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_abs_a2 (                                     // + 2x int32/fp32
  input  logic clk, input logic rst_n, input logic mode, input logic is_float,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_abs_dec core (.clk(clk), .rst_n(rst_n), .mode({1'b0, mode}), .is_float(is_float),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_abs_a3 (                                     // + 4x int16/fp16
  input  logic clk, input logic rst_n, input logic [1:0] mode, input logic is_float,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_abs_dec core (.clk(clk), .rst_n(rst_n), .mode(mode), .is_float(is_float),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
