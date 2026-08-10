`timescale 1ns / 1ps
module tb_qfold256_stage23_front_equiv;
    reg clk=0,rst_n=0;reg[7:0] c=0;reg signed[23:0] x=0;
    reg[31:0] lfsr=32'h3c6ef372;reg comp=0;integer n=0,i;
    integer r2=0,d2=0,r4=0,d4=0,r8=0,d8=0;
    reg signed[23:0] a2[0:1023],b2[0:1023],a4[0:2047],b4[0:2047],a8[0:4095],b8[0:4095];
    wire ce2=c[6:0]==0,ce4=c[5:0]==0,ce8=c[4:0]==0;
    wire signed[23:0] ar2,ar4,ar8,br2,br4,br8;wire av2,av4,av8,bv2,bv4,bv8;
    always #5 clk=~clk;
    baseline_fir_front_direct_wrapper refm(.clk(clk),.rst_n(rst_n),.ce2_out(ce2),.ce4_out(ce4),.ce8_out(ce8),.x_in(x),.x_in_valid(1'b1),.stage3_compensated_mode(comp),.y2(ar2),.y2_valid(av2),.y4(ar4),.y4_valid(av4),.y8(ar8),.y8_valid(av8));
    qfold256_stage23_front_ooc_wrapper dutm(.clk(clk),.rst_n(rst_n),.ce2_out(ce2),.ce4_out(ce4),.ce8_out(ce8),.x_in(x),.x_in_valid(1'b1),.stage3_compensated_mode(comp),.y2(br2),.y2_valid(bv2),.y4(br4),.y4_valid(bv4),.y8(br8),.y8_valid(bv8));
    always @(posedge clk) if(!rst_n) begin c<=0;x<=0;lfsr<=32'h3c6ef372;comp<=0;end else begin c<=c+1'b1;if(c==0)begin lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};x<=lfsr[23:0];if(n>30000)comp<=1;end end
    always @(posedge clk) begin #1;if(rst_n)begin if(av2)begin a2[r2]=ar2;r2=r2+1;end if(bv2)begin b2[d2]=br2;d2=d2+1;end if(av4)begin a4[r4]=ar4;r4=r4+1;end if(bv4)begin b4[d4]=br4;d4=d4+1;end if(av8)begin a8[r8]=ar8;r8=r8+1;end if(bv8)begin b8[d8]=br8;d8=d8+1;end n=n+1;end end
    initial begin repeat(10)@(posedge clk);@(negedge clk);rst_n=1;repeat(64000)@(posedge clk);if(r2!=d2||r4!=d4||r8!=d8)$fatal(1,"count mismatch %0d/%0d/%0d %0d/%0d/%0d",r2,r4,r8,d2,d4,d8);for(i=0;i<r2;i=i+1)if(a2[i]!==b2[i])$fatal(1,"y2 mismatch %0d",i);for(i=0;i<r4;i=i+1)if(a4[i]!==b4[i])$fatal(1,"y4 mismatch %0d ref=%0d dut=%0d",i,a4[i],b4[i]);for(i=0;i<r8;i=i+1)if(a8[i]!==b8[i])$fatal(1,"y8 mismatch %0d ref=%0d dut=%0d",i,a8[i],b8[i]);$display("QFOLD256 STAGE23 STREAM EQUIVALENCE PASS: y2=%0d y4=%0d y8=%0d",r2,r4,r8);$finish;end
endmodule
