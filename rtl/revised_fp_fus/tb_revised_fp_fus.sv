module tb_revised_fp_fus;
  logic [1:0] mode;
  logic [3:0] pred, op_sel;
  logic [63:0] a, b;
  logic [63:0] c64, c32, c3216, m64, m32, m3216;
  logic [63:0] x, y;
  int errors = 0;

  fu_fp_cmp_revised_shared64 c0 (.clk(0), .rst_n(1), .mode(mode), .pred(pred), .in_data_0(a), .in_valid_0(1), .in_ready_0(), .in_data_1(b), .in_valid_1(1), .in_ready_1(), .out_data(c64), .out_valid(), .out_ready(1));
  fu_fp_cmp_revised_shared64_32 c1 (.clk(0), .rst_n(1), .mode(mode), .pred(pred), .in_data_0(a), .in_valid_0(1), .in_ready_0(), .in_data_1(b), .in_valid_1(1), .in_ready_1(), .out_data(c32), .out_valid(), .out_ready(1));
  fu_fp_cmp_revised_shared64_32_16 c2 (.clk(0), .rst_n(1), .mode(mode), .pred(pred), .in_data_0(a), .in_valid_0(1), .in_ready_0(), .in_data_1(b), .in_valid_1(1), .in_ready_1(), .out_data(c3216), .out_valid(), .out_ready(1));
  fu_fp_minmax_revised_shared64 m0 (.clk(0), .rst_n(1), .mode(mode), .op_sel(op_sel), .in_data_0(a), .in_valid_0(1), .in_ready_0(), .in_data_1(b), .in_valid_1(1), .in_ready_1(), .out_data(m64), .out_valid(), .out_ready(1));
  fu_fp_minmax_revised_shared64_32 m1 (.clk(0), .rst_n(1), .mode(mode), .op_sel(op_sel), .in_data_0(a), .in_valid_0(1), .in_ready_0(), .in_data_1(b), .in_valid_1(1), .in_ready_1(), .out_data(m32), .out_valid(), .out_ready(1));
  fu_fp_minmax_revised_shared64_32_16 m2 (.clk(0), .rst_n(1), .mode(mode), .op_sel(op_sel), .in_data_0(a), .in_valid_0(1), .in_ready_0(), .in_data_1(b), .in_valid_1(1), .in_ready_1(), .out_data(m3216), .out_valid(), .out_ready(1));

  function automatic logic cmp_bit(input int EW, input int MW, input logic [3:0] p, input logic [63:0] x, input logic [63:0] y);
    logic sx, sy, nx, ny, zx, zy, lt, gt, eq, u;
    logic [63:0] ex, ey, mx, my, mask_e, mask_m;
    mask_e=(64'd1<<EW)-1; mask_m=(64'd1<<MW)-1;
    sx=x[EW+MW]; sy=y[EW+MW]; ex=(x>>MW)&mask_e; ey=(y>>MW)&mask_e; mx=x&mask_m; my=y&mask_m;
    nx=(ex==mask_e)&&(mx!=0); ny=(ey==mask_e)&&(my!=0); zx=(ex==0)&&(mx==0); zy=(ey==0)&&(my==0); u=nx|ny;
    lt=0; gt=0; eq=0;
    if (!u) begin
      if (zx&&zy) eq=1;
      else if (sx!=sy) begin lt=sx; gt=sy; end
      else if (sx) begin lt=(ex>ey)||((ex==ey)&&(mx>my)); gt=(ex<ey)||((ex==ey)&&(mx<my)); eq=(ex==ey)&&(mx==my); end
      else begin lt=(ex<ey)||((ex==ey)&&(mx<my)); gt=(ex>ey)||((ex==ey)&&(mx>my)); eq=(ex==ey)&&(mx==my); end
    end
    case(p)
      0:cmp_bit=0; 1:cmp_bit=~u&eq; 2:cmp_bit=~u&gt; 3:cmp_bit=~u&(gt|eq); 4:cmp_bit=~u&lt; 5:cmp_bit=~u&(lt|eq); 6:cmp_bit=~u&(lt|gt); 7:cmp_bit=~u;
      8:cmp_bit=u|eq; 9:cmp_bit=u|gt; 10:cmp_bit=u|(gt|eq); 11:cmp_bit=u|lt; 12:cmp_bit=u|(lt|eq); 13:cmp_bit=u|(lt|gt); 14:cmp_bit=u; default:cmp_bit=1;
    endcase
  endfunction

  function automatic logic [63:0] gold_cmp(input logic [1:0] md, input logic [3:0] p, input logic [63:0] x, input logic [63:0] y);
    logic [63:0] r; r='0;
    case(md)
      2'b01: begin r[31:0]={32{cmp_bit(8,23,p,x[31:0],y[31:0])}}; r[63:32]={32{cmp_bit(8,23,p,x[63:32],y[63:32])}}; end
      2'b10: for(int i=0;i<4;i++) r[i*16 +: 16]={16{cmp_bit(5,10,p,x>>(i*16),y>>(i*16))}};
      default:r={64{cmp_bit(11,52,p,x,y)}};
    endcase gold_cmp=r;
  endfunction

  function automatic logic [63:0] gold_mm_lane(input int EW, input int MW, input logic mx, input logic [63:0] x, input logic [63:0] y);
    logic sx, sy, nx, ny, lt; logic [63:0] ex, ey, fx, fy, mask_e, mask_m, q;
    mask_e=(64'd1<<EW)-1; mask_m=(64'd1<<MW)-1; sx=x[EW+MW]; sy=y[EW+MW]; ex=(x>>MW)&mask_e; ey=(y>>MW)&mask_e; fx=x&mask_m; fy=y&mask_m; nx=(ex==mask_e)&&(fx!=0); ny=(ey==mask_e)&&(fy!=0); q=(mask_e<<MW)|(64'd1<<(MW-1));
    if(nx||ny) gold_mm_lane=q;
    else begin if(sx!=sy) lt=sx; else if(sx) lt=(ex>ey)||((ex==ey)&&(fx>fy)); else lt=(ex<ey)||((ex==ey)&&(fx<fy)); gold_mm_lane=mx?(lt?y:x):(lt?x:y); end
  endfunction

  function automatic logic [63:0] gold_mm(input logic [1:0] md, input logic [3:0] op, input logic [63:0] x, input logic [63:0] y);
    logic [63:0] r; r='0;
    case(md)
      2'b01: begin r[31:0]=gold_mm_lane(8,23,op[0],x[31:0],y[31:0]); r[63:32]=gold_mm_lane(8,23,op[2],x[63:32],y[63:32]); end
      2'b10: for(int i=0;i<4;i++) r[i*16 +: 16]=gold_mm_lane(5,10,op[i],x>>(i*16),y>>(i*16));
      default:r=gold_mm_lane(11,52,op[0],x,y);
    endcase gold_mm=r;
  endfunction

  task automatic check(input logic [1:0] md, input logic [3:0] p, input logic [3:0] op, input logic [63:0] x, input logic [63:0] y);
    logic [63:0] gc, gm; a=x; b=y; mode=md; pred=p; op_sel=op; #1; gc=gold_cmp(md,p,x,y); gm=gold_mm(md,op,x,y);
    if(c3216!==gc) begin $display("FAIL cmp rev64_32_16 m=%b",md); errors++; end
    if(m3216!==gm) begin $display("FAIL mm rev64_32_16 m=%b",md); errors++; end
    if(md==2'b00 && (c64!==gc || m64!==gm)) begin $display("FAIL scalar tier"); errors++; end
    if(md!=2'b10 && (c32!==gc || m32!==gm)) begin $display("FAIL 64/32 tier"); errors++; end
  endtask

  initial begin
    for(int p=0;p<16;p++) begin
      check(2'b00,p,4'h1,64'h3ff0000000000000,64'h4000000000000000);
      check(2'b00,p,4'h0,64'h7ff8000000000000,64'h3ff0000000000000);
      check(2'b00,p,4'h1,64'h8000000000000000,64'h0000000000000000);
      check(2'b01,p,4'h4,64'h3f800000_c0000000,64'h40000000_bf800000);
      check(2'b10,p,4'h6,64'h3c00_c000_7e00_0000,64'h4000_bc00_3c00_8000);
    end
    x=64'h123456789abcdef0; y=64'h0fedcba987654321;
    for(int i=0;i<20000;i++) begin x={x[62:0],x[63]^x[60]^x[7]^x[0]}; y={y[62:0],y[63]^y[59]^y[4]^y[1]}; check(y[1:0],x[3:0],y[3:0],x,y); end
    if(errors==0) $display("PASS revised FP compare/minmax"); else $display("FAILURES %0d",errors); $finish;
  end
endmodule
