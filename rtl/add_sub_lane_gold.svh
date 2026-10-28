// Lane golden for the AddSub testbenches (include inside a module).
// Lane op (add/sub) at byte-lane [lo..lo+nbytes-1], op taken from op_sel[lo].
//   m: 00 -> 1x64, 01 -> 2x32, 10 -> 4x16, 11 -> 8x8
function automatic logic [63:0] gold(input logic [1:0] m, input logic [7:0] op,
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
    logic [63:0] al, bl, res, lmask;
    int w;
    w = nb * 8;
    lmask = (w == 64) ? {64{1'b1}} : ((64'd1 << w) - 64'd1);
    al = (av >> (lo*8)) & lmask;
    bl = (bv >> (lo*8)) & lmask;
    res = (op[lo] ? (al - bl) : (al + bl)) & lmask;
    r |= (res << (lo*8));
  end
  gold = r;
endfunction
