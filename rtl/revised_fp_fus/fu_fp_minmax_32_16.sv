// Two-level packed FP min/max: one FP32 or two FP16 lanes.
// The low 32 bits carry the active packet; upper bits are ignored/zeroed.
module revised_fp_minmax_32_16_core (
  input logic mode, input logic [1:0] op_sel,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  assign out_valid = in_valid_0 & in_valid_1;
  assign in_ready_0 = out_ready & out_valid;
  assign in_ready_1 = out_ready & out_valid;

  function automatic logic [31:0] key32(input logic [31:0] x);
    key32 = x[31] ? ~x : {1'b1,x[30:0]};
  endfunction
  function automatic logic [15:0] key16(input logic [15:0] x);
    key16 = x[15] ? ~x : {1'b1,x[14:0]};
  endfunction
  function automatic logic [1:0] flags(input int EW, input int MW, input logic [63:0] x);
    logic [63:0] em,mm,e,m;
    em=(64'd1<<EW)-1; mm=(64'd1<<MW)-1; e=(x>>MW)&em; m=x&mm;
    flags={(e==em)&&(m!=0),(e==0)&&(m==0)};
  endfunction
  function automatic logic [63:0] lane_result(input logic is_max, input logic kgt, input logic keq,
                                               input int EW, input int MW,
                                               input logic [63:0] a, input logic [63:0] b);
    logic [1:0] fa,fb; logic unordered,a_lt; logic [63:0] em,qnan;
    em=(64'd1<<EW)-1; qnan=(em<<MW)|(64'd1<<(MW-1));
    fa=flags(EW,MW,a); fb=flags(EW,MW,b); unordered=fa[1]|fb[1]; a_lt=~kgt&~keq;
    if(unordered) lane_result=qnan;
    else lane_result=is_max ? (a_lt ? b : a) : (a_lt ? a : b);
  endfunction

  logic [31:0] k32a,k32b; logic [15:0] k16a0,k16a1,k16b0,k16b1;
  assign k32a=key32(in_data_0[31:0]); assign k32b=key32(in_data_1[31:0]);
  assign k16a0=key16(in_data_0[15:0]); assign k16a1=key16(in_data_0[31:16]);
  assign k16b0=key16(in_data_1[15:0]); assign k16b1=key16(in_data_1[31:16]);

  logic gt0,eq0,gt1,eq1; logic [15:0] r16_0,r16_1;
  assign gt0=k16a0>k16b0; assign eq0=k16a0==k16b0;
  assign gt1=k16a1>k16b1; assign eq1=k16a1==k16b1;
  assign r16_0=16'(lane_result(op_sel[0],gt0,eq0,5,10,{48'd0,in_data_0[15:0]},{48'd0,in_data_1[15:0]}));
  assign r16_1=16'(lane_result(op_sel[1],gt1,eq1,5,10,{48'd0,in_data_0[31:16]},{48'd0,in_data_1[31:16]}));

  logic gt32,eq32; logic [31:0] r32;
  assign gt32=k32a>k32b; assign eq32=k32a==k32b;
  assign r32=32'(lane_result(op_sel[0],gt32,eq32,8,23,{32'd0,in_data_0[31:0]},{32'd0,in_data_1[31:0]}));
  always_comb begin
    if(mode) out_data={32'd0,r16_1,r16_0};
    else out_data={32'd0,r32};
  end
endmodule

module fu_fp_minmax_revised_32_16 (
  input logic clk,input logic rst_n,input logic mode,input logic [1:0] op_sel,
  input logic [63:0] in_data_0,input logic in_valid_0,output logic in_ready_0,
  input logic [63:0] in_data_1,input logic in_valid_1,output logic in_ready_1,
  output logic [63:0] out_data,output logic out_valid,input logic out_ready
);
  revised_fp_minmax_32_16_core core(.mode(mode),.op_sel(op_sel),.in_data_0(in_data_0),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(in_data_1),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(out_data),.out_valid(out_valid),.out_ready(out_ready));
endmodule
