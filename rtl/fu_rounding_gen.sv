// fu_rounding_gen.sv -- GENUINE decomposable FP round-to-integral (share group 17:
// math.floor/ceil/trunc/round/roundeven). Unlike fu_rounding_decomp.sv (which
// instantiates 1 fp64 + 2 fp32 + 4 fp16 rounders and muxes = replication), this
// uses ONE physically shared datapath: one 64-bit fractional-mask AND, and one
// 64-bit incrementer whose carry is BROKEN at lane boundaries by `mode` (the same
// segmentation idea as fu_add_sub_decomp). Per-lane exponent decode is cheap; the
// wide mask-apply + increment-add + repack are shared, not replicated.
//
//   round_mode: 000 floor(->-inf) 001 ceil(->+inf) 010 trunc(->0)
//               011 round(nearest,ties away) 100 roundeven(nearest,ties even)
//               other -> trunc.
//
// Parameterized by which decompositions are supported:
//   EN32=0,EN16=0 -> 1x fp64 only            (mode ignored)
//   EN32=1,EN16=0 -> 1x fp64 / 2x fp32       (mode: 0,1)
//   EN32=1,EN16=1 -> 1x fp64 / 2x fp32 / 4x fp16 (mode: 0,1,2)
//   mode 2'b00 -> fp64, 2'b01 -> 2x fp32, 2'b10 -> 4x fp16, 2'b11 -> fp64.
// Combinational, latency 0.
module fu_rounding_dec #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL

  input  logic [1:0]  mode,
  input  logic [2:0]  round_mode,

  input  logic [63:0] in_data_0,
  input  logic        in_valid_0,
  output logic        in_ready_0,

  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready
);

  assign out_valid  = in_valid_0;
  assign in_ready_0 = out_ready & out_valid;

  localparam logic [1:0] M_2X32 = 2'b01;
  localparam logic [1:0] M_4X16 = 2'b10;

  // Increment decision: should the integer-part magnitude round up by 1?
  function automatic logic round_inc(input logic [2:0] rm, input logic s,
                                     input logic guard, input logic sticky, input logic int_lsb);
    case (rm)
      3'b000:  round_inc = s  & (guard | sticky);        // floor
      3'b001:  round_inc = ~s & (guard | sticky);        // ceil
      3'b011:  round_inc = guard;                         // round (ties away)
      3'b100:  round_inc = guard & (sticky | int_lsb);    // roundeven
      default: round_inc = 1'b0;                          // trunc / reserved
    endcase
  endfunction

  // Per-lane control -> positioned 64-bit contributions to the SHARED datapath:
  //   fm : fractional-mask bits to clear      iv : increment bit (ULP at bit F)
  //   om : override mask (|x|<1 lanes)         ov : override value (+-0 / +-1.0)
  // Returns {fm, iv, om, ov}, each already shifted to the lane's base position.
  function automatic logic [255:0] lane_terms(input logic [63:0] word, input int base,
                                              input int EXP_W, input int MAN_W,
                                              input logic [2:0] rm);
    logic [63:0] fm, iv, om, ov, sig, lanemask, laneval, field;
    logic [11:0] exp, EXP_ONES;
    logic [51:0] mant;
    logic signed [15:0] E, BIAS, F;
    logic s, guard, sticky, int_lsb, inc, isNaNInf, isZero, already;
    begin : body
      EXP_ONES = 12'((64'd1 << EXP_W) - 64'd1);
      BIAS     = 16'((1 << (EXP_W - 1)) - 1);
      lanemask = (64'd1 << (EXP_W + MAN_W + 1)) - 64'd1;   // all-ones for fp64 via wrap

      field = (word >> base) & lanemask;
      s     = field[EXP_W + MAN_W];
      exp   = 12'((field >> MAN_W) & ((64'd1 << EXP_W) - 64'd1));
      mant  = 52'(field & ((64'd1 << MAN_W) - 64'd1));

      fm = 64'd0; iv = 64'd0; om = 64'd0; ov = 64'd0;

      isNaNInf = (exp == EXP_ONES);
      isZero   = (exp == 12'd0) && (mant == 52'd0);
      sig      = ((exp != 12'd0) ? (64'd1 << MAN_W) : 64'd0) | {12'd0, mant};
      E        = (exp == 12'd0) ? (16'sd1 - BIAS) : ($signed({4'b0, exp}) - BIAS);
      already  = (E >= 16'(MAN_W));

      if (isNaNInf || isZero || already) begin
        // bypass: contribute nothing -> datapath passes original bits through.
      end
      else if (E >= 16'sd0) begin : general           // 0 <= E < MAN_W : shared datapath
        F       = 16'(MAN_W) - E;                       // fractional bits, >= 1
        guard   = |(sig & (64'd1 << (F - 16'sd1)));
        sticky  = |(sig & ((64'd1 << (F - 16'sd1)) - 64'd1));
        int_lsb = |(sig & (64'd1 << F));
        inc     = round_inc(rm, s, guard, sticky, int_lsb);
        fm      = ((64'd1 << F) - 64'd1) << base;        // clear fractional mantissa bits
        iv      = inc ? ((64'd1 << F) << base) : 64'd0;  // +1 ULP at bit F (ripples into exp)
      end : general
      else begin : sub1                                 // E < 0 : |x| < 1 -> +-0 / +-1.0
        if (E == -16'sd1) begin guard = 1'b1;      sticky = |mant; end
        else              begin guard = 1'b0;      sticky = 1'b1;  end
        inc     = round_inc(rm, s, guard, sticky, 1'b0);
        laneval = (64'(s) << (EXP_W + MAN_W)) | (inc ? ({52'd0, BIAS[11:0]} << MAN_W) : 64'd0);
        om      = lanemask << base;
        ov      = laneval << base;
      end : sub1

      return {fm, iv, om, ov};
    end : body
  endfunction

  // ---- Per-candidate-lane control (cheap decode; NOT full rounders) ----
  logic [63:0] fm64, iv64, om64, ov64;
  logic [63:0] fm32, iv32, om32, ov32;
  logic [63:0] fm16, iv16, om16, ov16;

  logic [63:0] fmask, incv, omask, oval, masked, summed;
  logic c0, c1, c2, c3, cin1, cin2, cin3, brk16, brk32;
  logic [15:0] r0, r1, r2, r3;

  always_comb begin : ctrl
    logic [255:0] t, ta, tb, h0, h1, h2, h3;

    // fp64 lane
    t = lane_terms(in_data_0, 0, 11, 52, round_mode);
    {fm64, iv64, om64, ov64} = t;

    // 2x fp32 lanes
    fm32 = 64'd0; iv32 = 64'd0; om32 = 64'd0; ov32 = 64'd0;
    if (EN32) begin
      ta = lane_terms(in_data_0, 0,  8, 23, round_mode);
      tb = lane_terms(in_data_0, 32, 8, 23, round_mode);
      fm32 = ta[255:192] | tb[255:192];
      iv32 = ta[191:128] | tb[191:128];
      om32 = ta[127:64]  | tb[127:64];
      ov32 = ta[63:0]    | tb[63:0];
    end

    // 4x fp16 lanes
    fm16 = 64'd0; iv16 = 64'd0; om16 = 64'd0; ov16 = 64'd0;
    if (EN16) begin
      h0 = lane_terms(in_data_0, 0,  5, 10, round_mode);
      h1 = lane_terms(in_data_0, 16, 5, 10, round_mode);
      h2 = lane_terms(in_data_0, 32, 5, 10, round_mode);
      h3 = lane_terms(in_data_0, 48, 5, 10, round_mode);
      fm16 = h0[255:192] | h1[255:192] | h2[255:192] | h3[255:192];
      iv16 = h0[191:128] | h1[191:128] | h2[191:128] | h3[191:128];
      om16 = h0[127:64]  | h1[127:64]  | h2[127:64]  | h3[127:64];
      ov16 = h0[63:0]    | h1[63:0]    | h2[63:0]    | h3[63:0];
    end

    // ---- mode-mux the CONTROL (one datapath below, not one per mode) ----
    unique case (mode)
      M_2X32:  begin fmask = fm32; incv = iv32; omask = om32; oval = ov32; end
      M_4X16:  begin fmask = fm16; incv = iv16; omask = om16; oval = ov16; end
      default: begin fmask = fm64; incv = iv64; omask = om64; oval = ov64; end
    endcase
  end : ctrl

  // ---- SHARED datapath: one 64-bit mask-AND + one segmented incrementer ----
  assign masked = in_data_0 & ~fmask;

  assign brk16 = (mode == M_4X16);                 // break carry at 16 & 48
  assign brk32 = (mode == M_2X32) || (mode == M_4X16);  // break carry at 32

  always_comb begin : segadd
    {c0, r0} = {1'b0, masked[15:0]}  + {1'b0, incv[15:0]};
    cin1     = brk16 ? 1'b0 : c0;
    {c1, r1} = {1'b0, masked[31:16]} + {1'b0, incv[31:16]} + {16'b0, cin1};
    cin2     = brk32 ? 1'b0 : c1;
    {c2, r2} = {1'b0, masked[47:32]} + {1'b0, incv[47:32]} + {16'b0, cin2};
    cin3     = brk16 ? 1'b0 : c2;
    {c3, r3} = {1'b0, masked[63:48]} + {1'b0, incv[63:48]} + {16'b0, cin3};
  end : segadd
  assign summed = {r3, r2, r1, r0};

  // |x|<1 lanes override the datapath result with +-0 / +-1.0.
  assign out_data = (summed & ~omask) | (oval & omask);

endmodule : fu_rounding_dec

// ---- Capability wrappers (only the supported modes; rest pruned by synthesis) ----

module fu_rounding_g1 (                    // 64 only
  input  logic clk, input logic rst_n,
  input  logic [2:0] round_mode,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_rounding_dec #(.EN32(0), .EN16(0)) core (
    .clk(clk), .rst_n(rst_n), .mode(2'b00), .round_mode(round_mode),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_rounding_g2 (                    // 64 + 2x32
  input  logic clk, input logic rst_n,
  input  logic mode,                       // 0 -> fp64, 1 -> 2x fp32
  input  logic [2:0] round_mode,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_rounding_dec #(.EN32(1), .EN16(0)) core (
    .clk(clk), .rst_n(rst_n), .mode({1'b0, mode}), .round_mode(round_mode),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule

module fu_rounding_g3 (                    // 64 + 2x32 + 4x16
  input  logic clk, input logic rst_n,
  input  logic [1:0] mode,
  input  logic [2:0] round_mode,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  fu_rounding_dec #(.EN32(1), .EN16(1)) core (
    .clk(clk), .rst_n(rst_n), .mode(mode), .round_mode(round_mode),
    .in_data_0(in_data_0), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready));
endmodule
