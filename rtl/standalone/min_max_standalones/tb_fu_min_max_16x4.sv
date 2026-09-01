// Self-checking Verilator TB for fu_min_max_16x4.
module tb_fu_min_max_16x4 #(
  parameter int unsigned NRAND = 20000
);
  logic is_signed;
  logic [3:0] op_sel;
  logic [63:0] a, b, y;
  logic in_valid_0, in_valid_1, in_ready_0, in_ready_1, out_valid, out_ready;
  integer errors;
  fu_min_max_16x4 dut (
    .clk(1'b0), .rst_n(1'b1), .is_signed(is_signed), .op_sel(op_sel),
    .in_data_0(a), .in_valid_0(in_valid_0), .in_ready_0(in_ready_0),
    .in_data_1(b), .in_valid_1(in_valid_1), .in_ready_1(in_ready_1),
    .out_data(y), .out_valid(out_valid), .out_ready(out_ready)
  );

  function automatic logic [63:0] golden(input logic sg, input logic [3:0] ops,
                                         input logic [63:0] x, input logic [63:0] z);
    logic [63:0] r; logic signed [15:0] sx, sz;
    begin
      r='0;
      for (int l=0;l<4;l++) begin
        sx=x[l*16 +: 16]; sz=z[l*16 +: 16];
        if (sg) begin
          if (ops[l]) r[l*16 +: 16]=(sx>sz)?x[l*16 +: 16]:z[l*16 +: 16];
          else       r[l*16 +: 16]=(sx>sz)?z[l*16 +: 16]:x[l*16 +: 16];
        end else begin
          if (ops[l]) r[l*16 +: 16]=(x[l*16 +: 16]>z[l*16 +: 16])?x[l*16 +: 16]:z[l*16 +: 16];
          else       r[l*16 +: 16]=(x[l*16 +: 16]>z[l*16 +: 16])?z[l*16 +: 16]:x[l*16 +: 16];
        end
      end
      golden=r;
    end
  endfunction

  task automatic check_vec(input logic sg, input logic [3:0] ops,
                           input logic [63:0] x, input logic [63:0] z);
    logic [63:0] exp;
    begin
      is_signed=sg; op_sel=ops; a=x; b=z; in_valid_0=1; in_valid_1=1; out_ready=1; #1;
      exp=golden(sg,ops,x,z);
      if (y!==exp) begin $display("FAIL data: sg=%b op=%b a=%h b=%h got=%h exp=%h",sg,ops,x,z,y,exp); errors++; end
      if (out_valid!==1 || in_ready_0!==1 || in_ready_1!==1) begin $display("FAIL handshake"); errors++; end
    end
  endtask

  initial begin
    errors=0; a='0; b='0; op_sel='0; is_signed=0; in_valid_0=0; in_valid_1=0; out_ready=0;
    check_vec(1,4'b0101,64'h8000_7FFF_FFFF_0001,64'h7FFF_8000_0001_FFFF);
    check_vec(0,4'b1010,64'hFFFF_0000_1234_8000,64'h0001_FFFF_4321_7FFF);
    check_vec(1,4'b0000,64'h0001_0001_0001_0001,64'h0002_0000_0002_0000);
    a=64'hDEAD_BEEF_CAFE_F00D; b=64'h0123_4567_89AB_CDEF; in_valid_0=1; in_valid_1=1; out_ready=0; #1;
    if (out_valid!==1 || in_ready_0!==0 || in_ready_1!==0) begin $display("FAIL backpressure"); errors++; end
    in_valid_1=0; out_ready=1; #1;
    if (out_valid!==0 || in_ready_0!==0) begin $display("FAIL incomplete join"); errors++; end
    for (int i=0;i<NRAND;i++) check_vec($random,$random,{$random,$random},{$random,$random});
    if (errors==0) $display("PASS: fu_min_max_16x4, %0d random vectors", NRAND);
    else begin $display("FAIL: fu_min_max_16x4 %0d mismatches", errors); $fatal(1); end
    $finish;
  end
endmodule : tb_fu_min_max_16x4
