// Self-checking Verilator TB for the 64/32 Karatsuba multiply-low FU.
module tb_fu_mult_karatsuba_64_32 #(parameter int unsigned NRAND = 20000);
  logic [1:0] mode;
  logic [63:0] a, b, y;
  logic in_valid_0, in_valid_1, in_ready_0, in_ready_1, out_valid, out_ready;
  integer errors;

  fu_mult_karatsuba_64_32 dut (
    .clk(1'b0), .rst_n(1'b1), .mode(mode),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(b), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic logic [63:0] golden(input logic [1:0] m,
                                         input logic [63:0] x, input logic [63:0] z);
    logic [63:0] lo, hi;
    begin
      if (m == 2'b01) begin
        lo = x[31:0] * z[31:0]; hi = x[63:32] * z[63:32];
        golden = {hi[31:0], lo[31:0]};
      end else golden = x * z;
    end
  endfunction

  task automatic check_vec(input logic [1:0] m, input logic [63:0] x,
                           input logic [63:0] z);
    logic [63:0] exp;
    begin
      mode=m; a=x; b=z; in_valid_0=1; in_valid_1=1; out_ready=1; #1;
      exp=golden(m,x,z);
      if (y !== exp) begin $display("FAIL data mode=%b a=%h b=%h got=%h exp=%h",m,x,z,y,exp); errors++; end
      if (out_valid!==1 || in_ready_0!==1 || in_ready_1!==1) begin $display("FAIL handshake"); errors++; end
    end
  endtask

  initial begin
    errors=0; mode=0; a=0; b=0; in_valid_0=0; in_valid_1=0; out_ready=0;
    check_vec(2'b00,64'h0000_0000_FFFF_FFFF,64'h0000_0000_FFFF_FFFF);
    check_vec(2'b01,64'h0000_0000_FFFF_FFFF,64'h0000_0000_FFFF_FFFF);
    check_vec(2'b00,64'h0000_0001_0000_0000,64'h0000_0000_0000_0002);
    check_vec(2'b01,64'h0000_0003_0000_0005,64'h0000_0007_0000_0009);
    check_vec(2'b10,64'h0000_0000_FFFF_FFFF,64'h0000_0000_FFFF_FFFF);
    a=64'hDEAD_BEEF_CAFE_F00D; b=64'h0123_4567_89AB_CDEF;
    in_valid_0=1; in_valid_1=1; out_ready=0; #1;
    if (out_valid!==1 || in_ready_0!==0 || in_ready_1!==0) begin $display("FAIL backpressure"); errors++; end
    in_valid_1=0; out_ready=1; #1;
    if (out_valid!==0 || in_ready_0!==0) begin $display("FAIL incomplete join"); errors++; end
    for (int i=0; i<NRAND; i++) check_vec($urandom[1:0], {$urandom,$urandom}, {$urandom,$urandom});
    if (errors==0) $display("PASS: fu_mult_karatsuba_64_32, %0d random vectors",NRAND);
    else begin $display("FAIL: fu_mult_karatsuba_64_32 %0d errors",errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_mult_karatsuba_64_32
