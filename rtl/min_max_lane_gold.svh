// Lane golden for the integer Min/Max testbenches (include inside a module).
// Lane op (0 min, 1 max) at byte-lane [lo..lo+nbytes-1], op taken from op[lo]; sg: signed lanes.
//   m: 00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> 8x8
// On equality min returns A and max returns B (the values are equal).
function automatic logic [63:0] mm_gold(input logic sg, input logic [1:0] m, input logic [7:0] op,
                                        input logic [63:0] av, input logic [63:0] bv);
  logic [63:0] r;
  int nb;   // bytes per lane
  r = 64'd0;
  case (m)
    2'b01: nb = 4;   // 2x32
    2'b10: nb = 2;   // 4x16
    2'b11: nb = 1;   // 8x8
    default: nb = 8; // 1x64
  endcase
  for (int lo = 0; lo < 8; lo += nb) begin
    logic [63:0] al, bl, lmask;
    logic signed [63:0] sal, sbl;
    logic gt;
    int w;
    w = nb * 8;
    lmask = (w == 64) ? {64{1'b1}} : ((64'd1 << w) - 64'd1);
    al = (av >> (lo*8)) & lmask;
    bl = (bv >> (lo*8)) & lmask;
    sal = $signed(al << (64 - w)) >>> (64 - w);
    sbl = $signed(bl << (64 - w)) >>> (64 - w);
    gt = sg ? (sal > sbl) : (al > bl);
    r |= ((op[lo] ? (gt ? al : bl) : (gt ? bl : al)) & lmask) << (lo*8);
  end
  mm_gold = r;
endfunction
