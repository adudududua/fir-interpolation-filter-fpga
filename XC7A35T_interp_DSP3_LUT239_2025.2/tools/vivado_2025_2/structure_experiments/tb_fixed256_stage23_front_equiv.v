`timescale 1ns / 1ps

module tb_fixed256_stage23_front_equiv;
    reg clk=0, rst_n=0;
    reg [7:0] ce_counter=0;
    reg signed [23:0] x_in=0;
    reg [31:0] lfsr=32'hbb67ae85;
    reg compensated=0;
    integer cycles=0, i;
    integer r2=0,d2=0,r4=0,d4=0,r8=0,d8=0;
    reg signed [23:0] ry2[0:1023],dy2[0:1023];
    reg signed [23:0] ry4[0:2047],dy4[0:2047];
    reg signed [23:0] ry8[0:4095],dy8[0:4095];
    wire ce2=ce_counter[6:0]==0;
    wire ce4=ce_counter[5:0]==0;
    wire ce8=ce_counter[4:0]==0;
    wire signed [23:0] ref2,ref4,ref8,dut2,dut4,dut8;
    wire rv2,rv4,rv8,dv2,dv4,dv8;
    always #5 clk=~clk;
    baseline_fir_front_direct_wrapper u_ref(
        .clk(clk),.rst_n(rst_n),.ce2_out(ce2),.ce4_out(ce4),.ce8_out(ce8),
        .x_in(x_in),.x_in_valid(1'b1),.stage3_compensated_mode(compensated),
        .y2(ref2),.y2_valid(rv2),.y4(ref4),.y4_valid(rv4),
        .y8(ref8),.y8_valid(rv8));
    fixed256_stage23_front_ooc_wrapper u_dut(
        .clk(clk),.rst_n(rst_n),.ce2_out(ce2),.ce4_out(ce4),.ce8_out(ce8),
        .x_in(x_in),.x_in_valid(1'b1),.stage3_compensated_mode(compensated),
        .y2(dut2),.y2_valid(dv2),.y4(dut4),.y4_valid(dv4),
        .y8(dut8),.y8_valid(dv8));
    always @(posedge clk) begin
        if(!rst_n) begin ce_counter<=0; x_in<=0; lfsr<=32'hbb67ae85; compensated<=0; end
        else begin
            ce_counter<=ce_counter+1'b1;
            if(ce_counter==0) begin
                lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
                x_in<=lfsr[23:0];
                if(cycles>30000) compensated<=1;
            end
        end
    end
    always @(posedge clk) begin #1; if(rst_n) begin
        if(rv2) begin ry2[r2]=ref2; r2=r2+1; end
        if(dv2) begin dy2[d2]=dut2; d2=d2+1; end
        if(rv4) begin ry4[r4]=ref4; r4=r4+1; end
        if(dv4) begin dy4[d4]=dut4; d4=d4+1; end
        if(rv8) begin ry8[r8]=ref8; r8=r8+1; end
        if(dv8) begin dy8[d8]=dut8; d8=d8+1; end
        cycles=cycles+1;
    end end
    initial begin
        repeat(10) @(posedge clk); @(negedge clk); rst_n=1;
        repeat(64000) @(posedge clk);
        if(r2!=d2||r4!=d4||r8!=d8) $fatal(1,"count mismatch ref=%0d/%0d/%0d dut=%0d/%0d/%0d",r2,r4,r8,d2,d4,d8);
        for(i=0;i<r2;i=i+1) if(ry2[i]!==dy2[i]) $fatal(1,"y2 mismatch %0d",i);
        for(i=0;i<r4;i=i+1) if(ry4[i]!==dy4[i]) $fatal(1,"y4 mismatch %0d ref=%0d dut=%0d",i,ry4[i],dy4[i]);
        for(i=0;i<r8;i=i+1) if(ry8[i]!==dy8[i]) $fatal(1,"y8 mismatch %0d ref=%0d dut=%0d",i,ry8[i],dy8[i]);
        $display("FIXED256 STAGE23 STREAM EQUIVALENCE PASS: y2=%0d y4=%0d y8=%0d",r2,r4,r8);
        $finish;
    end
endmodule
