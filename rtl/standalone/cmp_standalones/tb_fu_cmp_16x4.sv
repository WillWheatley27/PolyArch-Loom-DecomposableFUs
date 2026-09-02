// Self-checking Verilator TB for standalone 4x16 integer compare.
module tb_fu_cmp_16x4 #(parameter int unsigned NRAND = 20000);
  logic [3:0] pred;
  logic [63:0] a, b, y;
  logic in_valid_0, in_valid_1, in_ready_0, in_ready_1, out_valid, out_ready;
  integer errors;

  fu_cmp_16x4 dut (
    .clk(1'b0), .rst_n(1'b1), .pred(pred),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(b), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic logic cmp_bit(input int W, input logic [3:0] p,
                                   input logic [63:0] x, input logic [63:0] z);
    logic [63:0] mask, xm, zm;
    logic signed [63:0] sx, sz;
    begin
      mask = (W == 64) ? {64{1'b1}} : ((64'd1 << W) - 64'd1);
      xm = x & mask; zm = z & mask;
      sx = $signed(xm << (64-W)) >>> (64-W);
      sz = $signed(zm << (64-W)) >>> (64-W);
      case (p)
        4'd0: cmp_bit = (xm == zm); 4'd1: cmp_bit = (xm != zm);
        4'd2: cmp_bit = (sx < sz);   4'd3: cmp_bit = (sx <= sz);
        4'd4: cmp_bit = (sx > sz);   4'd5: cmp_bit = (sx >= sz);
        4'd6: cmp_bit = (xm < zm);   4'd7: cmp_bit = (xm <= zm);
        4'd8: cmp_bit = (xm > zm);   4'd9: cmp_bit = (xm >= zm);
        default: cmp_bit = 1'b0;
      endcase
    end
  endfunction

  function automatic logic [63:0] golden(input logic [3:0] p,
                                         input logic [63:0] x, input logic [63:0] z);
    logic [63:0] r;
    begin
      r='0;
      for (int l=0; l<4; l++)
        r[l*16 +: 16] = {16{cmp_bit(16,p,x>>(l*16),z>>(l*16))}};
      golden=r;
    end
  endfunction

  task automatic check_vec(input logic [3:0] p, input logic [63:0] x,
                           input logic [63:0] z);
    logic [63:0] exp;
    begin
      pred=p; a=x; b=z; in_valid_0=1'b1; in_valid_1=1'b1; out_ready=1'b1; #1;
      exp=golden(p,x,z);
      if (y !== exp) begin
        $display("FAIL data: pred=%0d a=%h b=%h got=%h exp=%h",p,x,z,y,exp); errors++;
      end
      if (out_valid !== 1'b1 || in_ready_0 !== 1'b1 || in_ready_1 !== 1'b1) begin
        $display("FAIL handshake: out_valid=%b ready=%b/%b",out_valid,in_ready_0,in_ready_1); errors++;
      end
    end
  endtask

  initial begin
    errors=0; a='0; b='0; pred='0; in_valid_0=0; in_valid_1=0; out_ready=0;
    for (int p=0; p<10; p++) begin
      check_vec(p[3:0],64'h0000_0000_0005_0003,64'h0000_0000_0003_0005);
      check_vec(p[3:0],64'h8000_7FFF_FFFF_8000,64'h7FFF_8000_0001_0001);
      check_vec(p[3:0],64'h0123_0123_0123_0123,64'h0123_0123_0123_0123);
    end
    check_vec(4'd15,64'hFFFF_FFFF_FFFF_FFFF,64'd0);

    a=64'hDEAD_BEEF_CAFE_F00D; b=64'h0123_4567_89AB_CDEF;
    in_valid_0=1; in_valid_1=1; out_ready=0; #1;
    if (out_valid!==1'b1 || in_ready_0!==1'b0 || in_ready_1!==1'b0) begin $display("FAIL backpressure"); errors++; end
    in_valid_1=0; out_ready=1; #1;
    if (out_valid!==1'b0 || in_ready_0!==1'b0) begin $display("FAIL incomplete join"); errors++; end

    for (int i=0; i<NRAND; i++)
      check_vec(($urandom % 10), {$urandom,$urandom}, {$urandom,$urandom});
    if (errors==0) $display("PASS: fu_cmp_16x4, %0d random vectors",NRAND);
    else begin $display("FAIL: fu_cmp_16x4 %0d errors",errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_cmp_16x4
