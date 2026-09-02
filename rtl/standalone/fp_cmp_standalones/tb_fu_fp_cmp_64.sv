// Self-checking Verilator TB for standalone FP64 compare.
module tb_fu_fp_cmp_64 #(parameter int unsigned NRAND = 20000);
  logic [3:0] pred;
  logic [63:0] a, b, y;
  logic in_valid_0, in_valid_1, in_ready_0, in_ready_1, out_valid, out_ready;
  integer errors;

  fu_fp_cmp_64 dut (
    .clk(1'b0), .rst_n(1'b1), .pred(pred),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(b), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic logic gold_bit(input logic [3:0] p,
                                    input logic [63:0] x, input logic [63:0] z);
    logic [63:0] xa, za, expa, mana, expz, manz;
    logic sx, sz, uno, lt, gt, eq;
    begin
      xa = x & 64'h7fff_ffff_ffff_ffff;
      za = z & 64'h7fff_ffff_ffff_ffff;
      expa = x[62:52]; mana = x[51:0];
      expz = z[62:52]; manz = z[51:0];
      sx=x[63]; sz=z[63];
      uno = ((expa == 11'h7ff) && (mana != 0)) ||
            ((expz == 11'h7ff) && (manz != 0));
      if ((xa == 0) && (za == 0)) begin lt=0; gt=0; eq=1; end
      else if (sx != sz) begin lt=sx; gt=sz; eq=0; end
      else if (sx) begin lt=(xa > za); gt=(xa < za); eq=(xa == za); end
      else begin lt=(xa < za); gt=(xa > za); eq=(xa == za); end
      case (p)
        4'd0: gold_bit=0; 4'd1: gold_bit=~uno & eq;
        4'd2: gold_bit=~uno & gt; 4'd3: gold_bit=~uno & (gt|eq);
        4'd4: gold_bit=~uno & lt; 4'd5: gold_bit=~uno & (lt|eq);
        4'd6: gold_bit=~uno & (lt|gt); 4'd7: gold_bit=~uno;
        4'd8: gold_bit=uno | eq; 4'd9: gold_bit=uno | gt;
        4'd10: gold_bit=uno | (gt|eq); 4'd11: gold_bit=uno | lt;
        4'd12: gold_bit=uno | (lt|eq); 4'd13: gold_bit=uno | (lt|gt);
        4'd14: gold_bit=uno; default: gold_bit=1;
      endcase
    end
  endfunction

  task automatic check_vec(input logic [3:0] p, input logic [63:0] x,
                           input logic [63:0] z);
    logic [63:0] exp;
    begin
      pred=p; a=x; b=z; in_valid_0=1; in_valid_1=1; out_ready=1; #1;
      exp={64{gold_bit(p,x,z)}};
      if (y !== exp) begin $display("FAIL data p=%0d a=%h b=%h got=%h exp=%h",p,x,z,y,exp); errors++; end
      if (out_valid!==1 || in_ready_0!==1 || in_ready_1!==1) begin $display("FAIL handshake"); errors++; end
    end
  endtask

  initial begin
    errors=0; a='0; b='0; pred='0; in_valid_0=0; in_valid_1=0; out_ready=0;
    for (int p=0;p<16;p++) begin
      check_vec(p[3:0],64'h3ff0_0000_0000_0000,64'h4000_0000_0000_0000);
      check_vec(p[3:0],64'h7ff8_0000_0000_0000,64'h3ff0_0000_0000_0000);
      check_vec(p[3:0],64'h8000_0000_0000_0000,64'h0000_0000_0000_0000);
      check_vec(p[3:0],64'hfff0_0000_0000_0000,64'h7ff0_0000_0000_0000);
      check_vec(p[3:0],64'h0000_0000_0000_0001,64'h8000_0000_0000_0001);
    end
    a=64'hdead_beef_cafe_f00d; b=64'h0123_4567_89ab_cdef; in_valid_0=1; in_valid_1=1; out_ready=0; #1;
    if (out_valid!==1 || in_ready_0!==0 || in_ready_1!==0) begin $display("FAIL backpressure"); errors++; end
    in_valid_1=0; out_ready=1; #1;
    if (out_valid!==0 || in_ready_0!==0) begin $display("FAIL incomplete join"); errors++; end
    for (int i=0;i<NRAND;i++) check_vec($urandom[3:0],$urandom,$urandom);
    if(errors==0)$display("PASS: fu_fp_cmp_64, %0d random vectors",NRAND); else begin $display("FAIL: fu_fp_cmp_64 %0d errors",errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_fp_cmp_64
