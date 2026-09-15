// Revised FP compare: one shared 16-bit lexicographic ordering chain.
// The tier wrappers prune unsupported formats at elaboration.
module revised_fp_cmp_shared_core #(
  parameter bit SUPPORT_32 = 1'b1,
  parameter bit SUPPORT_16 = 1'b1
) (
  input logic [1:0] mode, input logic [3:0] pred,
  input logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  input logic [63:0] in_data_1, input logic in_valid_1, output logic in_ready_1,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
  localparam logic [1:0] M_2X32=2'b01, M_4X16=2'b10;
  logic [1:0] emode;
  always_comb begin : mode_decode
    if (SUPPORT_16 && mode==M_4X16) emode=M_4X16;
    else if (SUPPORT_32 && mode==M_2X32) emode=M_2X32;
    else emode=2'b00;
  end
  assign out_valid=in_valid_0&in_valid_1;
  assign in_ready_0=out_ready&out_valid;
  assign in_ready_1=out_ready&out_valid;

  function automatic logic [63:0] key(input logic [1:0] m,input logic [63:0] x);
    logic [63:0] k; k=x;
    case(m)
      M_2X32: begin
        k[31:0] = x[31] ? ~x[31:0] : {1'b1,x[30:0]};
        k[63:32] = x[63] ? ~x[63:32] : {1'b1,x[62:32]};
      end
      M_4X16: begin
        k[15:0] = x[15] ? ~x[15:0] : {1'b1,x[14:0]};
        k[31:16] = x[31] ? ~x[31:16] : {1'b1,x[30:16]};
        k[47:32] = x[47] ? ~x[47:32] : {1'b1,x[46:32]};
        k[63:48] = x[63] ? ~x[63:48] : {1'b1,x[62:48]};
      end
      default: k = x[63] ? ~x : {1'b1,x[62:0]};
    endcase
    key=k;
  endfunction
  function automatic logic [1:0] flags(input int EW,input int MW,input logic [63:0] x);
    logic [63:0] em,mm,e,m; logic n,z;
    em=(64'd1<<EW)-1; mm=(64'd1<<MW)-1; e=(x>>MW)&em; m=x&mm;
    n=(e==em)&&(m!=0); z=(e==0)&&(m==0); flags={n,z};
  endfunction
  function automatic logic pred_eval(input logic [3:0] p,input logic unordered,input logic l,input logic e,input logic g);
    case(p)
      0:pred_eval=0; 1:pred_eval=~unordered&e; 2:pred_eval=~unordered&g; 3:pred_eval=~unordered&(g|e);
      4:pred_eval=~unordered&l; 5:pred_eval=~unordered&(l|e); 6:pred_eval=~unordered&(l|g); 7:pred_eval=~unordered;
      8:pred_eval=unordered|e; 9:pred_eval=unordered|g; 10:pred_eval=unordered|(g|e); 11:pred_eval=unordered|l;
      12:pred_eval=unordered|(l|e); 13:pred_eval=unordered|(l|g); 14:pred_eval=unordered; default:pred_eval=1;
    endcase
  endfunction
  function automatic logic lane_pred(input logic [3:0] p,input logic kgt,input logic keq,
                                     input int EW,input int MW,input logic [63:0] a,input logic [63:0] b);
    logic [1:0] fa,fb; logic u,bz,e,l,g;
    fa=flags(EW,MW,a); fb=flags(EW,MW,b); u=fa[1]|fb[1]; bz=fa[0]&fb[0];
    e=keq|bz; g=kgt&~bz; l=~kgt&~keq&~bz; lane_pred=pred_eval(p,u,l,e,g);
  endfunction

  logic [63:0] ka,kb; assign ka=key(emode,in_data_0); assign kb=key(emode,in_data_1);
  logic gtu[0:3],eqb[0:3],ru[0:3],re[0:3];
  for(genvar i=0;i<4;i++) begin : blk
    assign gtu[i]=ka[i*16 +: 16]>kb[i*16 +: 16];
    assign eqb[i]=ka[i*16 +: 16]==kb[i*16 +: 16];
  end
  logic [3:1] brk;
  always_comb begin : boundaries
    case(emode)
      M_4X16: brk=3'b111;
      M_2X32: brk=3'b010;
      default: brk=3'b000;
    endcase
  end
  assign ru[0]=gtu[0]; assign re[0]=eqb[0];
  for(genvar j=1;j<4;j++) begin : chain
    assign ru[j]=brk[j] ? gtu[j] : (gtu[j]|(eqb[j]&ru[j-1]));
    assign re[j]=brk[j] ? eqb[j] : (eqb[j]&re[j-1]);
  end

  logic [63:0] p64,p32,p16; logic r64;
  assign r64=lane_pred(pred,ru[3],re[3],11,52,in_data_0,in_data_1); assign p64={64{r64}};
  generate if(SUPPORT_32) begin : fp32
    logic r0,r1;
    assign r0=lane_pred(pred,ru[1],re[1],8,23,{32'd0,in_data_0[31:0]},{32'd0,in_data_1[31:0]});
    assign r1=lane_pred(pred,ru[3],re[3],8,23,{32'd0,in_data_0[63:32]},{32'd0,in_data_1[63:32]});
    assign p32={{32{r1}},{32{r0}}};
  end else begin : no_fp32 assign p32=64'd0; end endgenerate
  generate if(SUPPORT_16) begin : fp16
    for(genvar q=0;q<4;q++) begin : lane
      logic r;
      assign r=lane_pred(pred,ru[q],re[q],5,10,{48'd0,in_data_0[q*16 +: 16]},{48'd0,in_data_1[q*16 +: 16]});
      assign p16[q*16 +: 16]={16{r}};
    end
  end else begin : no_fp16 assign p16=64'd0; end endgenerate
  always_comb begin : output_select
    out_data=p64; if(SUPPORT_32&&emode==M_2X32) out_data=p32; if(SUPPORT_16&&emode==M_4X16) out_data=p16;
  end
endmodule

module fu_fp_cmp_revised_shared64 (
  input logic clk,input logic rst_n,input logic [1:0] mode,input logic [3:0] pred,
  input logic [63:0] in_data_0,input logic in_valid_0,output logic in_ready_0,
  input logic [63:0] in_data_1,input logic in_valid_1,output logic in_ready_1,
  output logic [63:0] out_data,output logic out_valid,input logic out_ready);
  revised_fp_cmp_shared_core #(.SUPPORT_32(0),.SUPPORT_16(0)) core_inst(.mode(mode),.pred(pred),.in_data_0(in_data_0),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(in_data_1),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(out_data),.out_valid(out_valid),.out_ready(out_ready));
endmodule
module fu_fp_cmp_revised_shared64_32 (
  input logic clk,input logic rst_n,input logic [1:0] mode,input logic [3:0] pred,
  input logic [63:0] in_data_0,input logic in_valid_0,output logic in_ready_0,
  input logic [63:0] in_data_1,input logic in_valid_1,output logic in_ready_1,
  output logic [63:0] out_data,output logic out_valid,input logic out_ready);
  revised_fp_cmp_shared_core #(.SUPPORT_32(1),.SUPPORT_16(0)) core_inst(.mode(mode),.pred(pred),.in_data_0(in_data_0),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(in_data_1),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(out_data),.out_valid(out_valid),.out_ready(out_ready));
endmodule
module fu_fp_cmp_revised_shared64_32_16 (
  input logic clk,input logic rst_n,input logic [1:0] mode,input logic [3:0] pred,
  input logic [63:0] in_data_0,input logic in_valid_0,output logic in_ready_0,
  input logic [63:0] in_data_1,input logic in_valid_1,output logic in_ready_1,
  output logic [63:0] out_data,output logic out_valid,input logic out_ready);
  revised_fp_cmp_shared_core #(.SUPPORT_32(1),.SUPPORT_16(1)) core_inst(.mode(mode),.pred(pred),.in_data_0(in_data_0),.in_valid_0(in_valid_0),.in_ready_0(in_ready_0),.in_data_1(in_data_1),.in_valid_1(in_valid_1),.in_ready_1(in_ready_1),.out_data(out_data),.out_valid(out_valid),.out_ready(out_ready));
endmodule
