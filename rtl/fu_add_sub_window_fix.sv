// fu_add_sub_window_fix.sv -- Three rewrites of the decomposable AddSub (fu_add_sub_gen.sv) aimed
// at the 500-900 MHz gated-bank power window found in reports/addsub_isolation_experiment. There,
// the segmented core (eight 8-bit adds joined by carry-in muxes) had to become a fast adder at
// 450-500 MHz, long before the bank's narrow units, and its fast form glitched heavily.
//
//   fu_add_sub_part    fix 1, partitioned adder: one `+` over the operands widened by a guard bit
//                      at each lane boundary the tier can break. A guard bit either passes the
//                      carry on (1, 0) or replaces it with the lane's carry-in (c, c), so DC sees
//                      a single adder and picks its own architecture for the target.
//   fu_add_sub_blkinc  fix 2, lane-block carry-increment: blocks as wide as the narrowest lane,
//                      each one adder with carry-in 0; block carries come from the blocks'
//                      generate/propagate, and each block adds its carry-in with an incrementer.
//                      The longest adder is one block, as in the bank's narrowest unit.
//   fu_add_sub_pipe    fix 3, fix 1 split into two 32-bit-wide adders, with 64-bit operations
//                      finished in a second cycle: the upper half's carry-in is added from a
//                      register stage (clock-gated, loads only for a 64-bit lane), so no
//                      single-cycle path is longer than 32 bits. Latency 2 in 64-bit mode
//                      (throughput 1), 1 otherwise; leaving 64-bit mode with a result still in
//                      the stage drops it, so a scheduler must drain the stage first.
//
// Tiers are parameters (EN32/EN16/EN8 as in fu_add_sub_gen.sv: d2 = 1,0,0, d4 = 1,1,0,
// d8 = 1,1,1). Ports, mode and op_sel encoding match fu_add_sub_d2/d4/d8:
//   mode: 00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> 8x8
//         (a mode whose tier is disabled falls back to 1x64)
//   op_sel[i]: op of the lane whose start is 8-bit block i (0 add, 1 sub).

// Lane starts and each 8-bit block's lane op (block 0 is always a start).
module fu_add_sub_lane_decode #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1
) (
  input  logic [1:0] mode,
  input  logic [7:0] op_sel,
  output logic [7:0] is_start,
  output logic [7:0] sub
);
  always_comb begin
    logic cur;
    case (mode)
      2'b01:   is_start = EN32 ? 8'b0001_0001 : 8'b0000_0001;
      2'b10:   is_start = EN16 ? 8'b0101_0101 : 8'b0000_0001;
      2'b11:   is_start = EN8  ? 8'b1111_1111 : 8'b0000_0001;
      default: is_start = 8'b0000_0001;   // 1x64
    endcase
    cur = op_sel[0];
    for (int i = 0; i < 8; i++) begin
      if (is_start[i]) cur = op_sel[i];
      sub[i] = cur;
    end
  end
endmodule : fu_add_sub_lane_decode

// Fix 1 datapath. SPLIT64 builds the halves as two separate adders, so no carry path crosses bit
// 32 in any mode: a 64-bit lane's upper half gets carry-in 0, and the carry out of the lower half
// (c32) is returned with lane64 (the lane is 64 bits wide) for fu_add_sub_pipe.
module fu_add_sub_part_core #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1,
  parameter bit SPLIT64 = 0
) (
  input  logic [1:0]  mode,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0,
  input  logic [63:0] in_data_1,
  output logic [63:0] sum_out,
  output logic        c32,
  output logic        lane64
);
  // Boundaries that can break (bit k: below block k; bit 0 carries the lane's +1 for subtract).
  localparam logic [7:0] BRK = {EN8, EN8 | EN16, EN8, EN8 | EN16 | EN32 | SPLIT64, EN8, EN8 | EN16, EN8, 1'b1};
  function automatic int guards_upto(int k);   // guard bits at or below boundary k
    int n = 0;
    for (int i = 0; i <= k; i++) n += int'(BRK[i]);
    return n;
  endfunction
  localparam int W = 64 + guards_upto(7);

  logic [7:0] is_start, sub;
  // verilator lint_off UNUSEDSIGNAL
  logic [7:0] brk;   // read only at boundaries the tier can break
  // verilator lint_on UNUSEDSIGNAL
  fu_add_sub_lane_decode #(.EN32(EN32), .EN16(EN16), .EN8(EN8)) decode (
    .mode(mode), .op_sel(op_sel), .is_start(is_start), .sub(sub));
  always_comb begin
    brk = is_start;
    if (SPLIT64) brk[4] = 1'b1;
  end
  assign lane64 = ~is_start[4];

  logic [W-1:0] xa, xb;
  // verilator lint_off UNUSEDSIGNAL
  logic [W-1:0] xs;   // guard-bit sums are dropped (except c32)
  // verilator lint_on UNUSEDSIGNAL
  for (genvar k = 0; k < 8; k++) begin : blk
    localparam int OFF = 8*k + guards_upto(k);
    if (BRK[k]) begin : guard
      // a lane start injects its carry-in (the op's +1, or 0 for the split 64-bit upper half)
      logic cin;
      assign cin = is_start[k] & sub[k];
      assign xa[OFF-1] = brk[k] ? cin : 1'b1;
      assign xb[OFF-1] = brk[k] ? cin : 1'b0;
    end
    assign xa[OFF +: 8] = in_data_0[8*k +: 8];
    assign xb[OFF +: 8] = in_data_1[8*k +: 8] ^ {8{sub[k]}};
    assign sum_out[8*k +: 8] = xs[OFF +: 8];
  end
  if (SPLIT64) begin : split
    localparam int G4 = 32 + guards_upto(4) - 1;   // the 32-bit boundary's guard bit
    assign {c32, xs[G4-1:0]} = xa[G4-1:0] + xb[G4-1:0];
    assign xs[W-1:G4] = xa[W-1:G4] + xb[W-1:G4];
  end else begin : whole
    assign xs = xa + xb;
    assign c32 = 1'b0;
  end
endmodule : fu_add_sub_part_core

module fu_add_sub_part #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;
  // verilator lint_off UNUSEDSIGNAL
  logic c32_unused, lane64_unused;
  // verilator lint_on UNUSEDSIGNAL
  fu_add_sub_part_core #(.EN32(EN32), .EN16(EN16), .EN8(EN8)) core (
    .mode(mode), .op_sel(op_sel), .in_data_0(in_data_0), .in_data_1(in_data_1),
    .sum_out(out_data), .c32(c32_unused), .lane64(lane64_unused));
endmodule : fu_add_sub_part

module fu_add_sub_pipe #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [1:0]  mode,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  logic [63:0] s;
  logic        c32, m64;
  fu_add_sub_part_core #(.EN32(EN32), .EN16(EN16), .EN8(EN8), .SPLIT64(1)) core (
    .mode(mode), .op_sel(op_sel), .in_data_0(in_data_0), .in_data_1(in_data_1),
    .sum_out(s), .c32(c32), .lane64(m64));

  logic in_v, advance;
  assign in_v    = in_valid_0 & in_valid_1;

  // 64-bit stage: the lower sum, the upper sum without its carry-in, and that carry
  logic        r_valid, r_c;
  logic [63:0] r_s;
  assign advance = m64 & (~r_valid | out_ready);
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) r_valid <= 1'b0;
    else if (advance) r_valid <= in_v;
  always_ff @(posedge clk)
    if (advance & in_v) begin
      r_s <= s;
      r_c <= c32;
    end

  assign out_data   = m64 ? {r_s[63:32] + {31'b0, r_c}, r_s[31:0]} : s;
  assign out_valid  = m64 ? r_valid : in_v;
  assign in_ready_0 = m64 ? advance & in_v : out_ready & in_v;
  assign in_ready_1 = in_ready_0;
endmodule : fu_add_sub_pipe

module fu_add_sub_blkinc #(
  parameter bit EN32 = 1,
  parameter bit EN16 = 1,
  parameter bit EN8  = 1
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic        clk,
  input  logic        rst_n,
  // verilator lint_on UNUSEDSIGNAL
  input  logic [1:0]  mode,
  input  logic [7:0]  op_sel,
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input  logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid  = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  localparam int B  = EN8 ? 8 : EN16 ? 16 : EN32 ? 32 : 64;   // narrowest lane
  localparam int NB = 64 / B;

  // verilator lint_off UNUSEDSIGNAL
  logic [7:0] is_start, sub;   // only the block-start entries are used when B > 8
  // verilator lint_on UNUSEDSIGNAL
  fu_add_sub_lane_decode #(.EN32(EN32), .EN16(EN16), .EN8(EN8)) decode (
    .mode(mode), .op_sel(op_sel), .is_start(is_start), .sub(sub));

  // verilator lint_off UNUSEDSIGNAL
  logic [NB-1:0] g, p, c;   // the top block's generate/propagate have no block above
  // verilator lint_on UNUSEDSIGNAL
  for (genvar i = 0; i < NB; i++) begin : blk
    localparam int K = i * B / 8;   // 8-bit block index of this block's first byte
    logic [B-1:0] be, s0, inc;
    assign be = in_data_1[i*B +: B] ^ {B{sub[K]}};
    assign {g[i], s0} = in_data_0[i*B +: B] + be;
    assign p[i] = &(in_data_0[i*B +: B] ^ be);
    // carry-in: a lane start injects its op's +1; any other block takes the block below's
    // carry-out, g | p & c
    if (i == 0) begin : first
      assign c[i] = sub[0];
    end else begin : next
      assign c[i] = is_start[K] ? sub[K] : g[i-1] | (p[i-1] & c[i-1]);
    end
    // incrementer: bit j flips when the carry-in arrives and every s0 bit below j is 1
    assign inc[0] = c[i];
    for (genvar j = 1; j < B; j++) begin : ripple_and
      assign inc[j] = inc[j-1] & s0[j-1];
    end
    assign out_data[i*B +: B] = s0 ^ inc;
  end
endmodule : fu_add_sub_blkinc
