`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_stage23_lutram_cic_dsp_ce.v
// 模块名       : interp2_stage23_lutram_cic_dsp_ce
// 功能简述     : Stage 2/3 共享 DSP 的低 LUT true-polyphase FIR。
//                使用两个 16 深度单读口分布式 RAM 循环缓冲替代
//                历史样点移位寄存器。对称抽头不再并行预加，而是
//                依次送入同一个 DSP48 MAC，以单口 RAM 和更多空闲
//                时钟周期交换更少的 LUT。
//
//                Stage 2：phase0=9 MAC，phase1=8 MAC，Q15
//                Stage 3：phase0=6 MAC，phase1=5 MAC，Q15
//                Stage 3 中心系数 35604 直接使用 18bit signed
//                表示，与 -29932+65536 的 38bit 模运算严格等价。
//
// 当前默认配置：
//                  Stage 2 数据位宽：22bit signed
//                  Stage 3 数据位宽：20bit signed
//                  系数位宽        ：18bit signed Q15
//                  累加位宽        ：38bit signed
//                  历史存储        ：单读口 LUTRAM 循环缓冲
//                  共享 DSP 数量   ：1
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-18
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-18：新增 Stage 2/3 LUTRAM 低 LUT 候选。
//                2026-07-18：串行 MAC 调度改为 Stage 2 优先，保证
//                            4x 样点在下一次 8x CE 前完成。
//=============================================================

`include "all2x_v2_coeff_pkg.vh"

module interp2_stage23_lutram_cic_dsp_ce #(
    parameter integer DATA_W = 24,
    parameter integer STAGE2_DATA_W = 22,
    parameter integer STAGE3_DATA_W = 20,
    parameter integer COEFF_W = 18,
    parameter integer ACC_W = 38,
    parameter integer CIC_ORDER = 3
)(
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire                              stage2_ce_out,
    input  wire signed [STAGE2_DATA_W-1:0]   stage2_x_in,
    input  wire                              stage2_x_in_valid,
    output reg  signed [STAGE2_DATA_W-1:0]   stage2_y_out,
    output reg                               stage2_y_out_valid,

    input  wire                              stage3_ce_out,
    input  wire signed [STAGE3_DATA_W-1:0]   stage3_x_in,
    input  wire                              stage3_x_in_valid,
    output reg  signed [STAGE3_DATA_W-1:0]   stage3_y_out,
    output reg                               stage3_y_out_valid,

    output wire                              stage2_phase_dbg,
    output wire                              stage3_phase_dbg,
    output wire                              scheduler_busy_dbg,
    output wire [1:0]                        scheduler_stage_dbg,
    output wire [3:0]                        scheduler_mac_index_dbg
);

    localparam integer MEM_ADDR_W = 4;
    localparam integer MEM_DEPTH = 16;
    localparam integer FRAC_W = 15;
    localparam integer SHIFT_W = ACC_W - FRAC_W;
    localparam integer ROUND_W = SHIFT_W + 1;
    localparam integer STAGE2_UPPER_W = ROUND_W - STAGE2_DATA_W;
    localparam integer STAGE3_UPPER_W = ROUND_W - STAGE3_DATA_W;

    localparam signed [STAGE2_DATA_W-1:0] STAGE2_OUT_MAX =
        {1'b0, {(STAGE2_DATA_W-1){1'b1}}};
    localparam signed [STAGE2_DATA_W-1:0] STAGE2_OUT_MIN =
        {1'b1, {(STAGE2_DATA_W-1){1'b0}}};
    localparam signed [STAGE3_DATA_W-1:0] STAGE3_OUT_MAX =
        {1'b0, {(STAGE3_DATA_W-1){1'b1}}};
    localparam signed [STAGE3_DATA_W-1:0] STAGE3_OUT_MIN =
        {1'b1, {(STAGE3_DATA_W-1){1'b0}}};

    (* ram_style = "distributed" *)
    reg signed [STAGE2_DATA_W-1:0] stage2_hist_mem [0:MEM_DEPTH-1];
    (* ram_style = "distributed" *)
    reg signed [STAGE3_DATA_W-1:0] stage3_hist_mem [0:MEM_DEPTH-1];

    reg [MEM_ADDR_W-1:0] stage2_head;
    reg [MEM_ADDR_W-1:0] stage3_head;
    reg [MEM_ADDR_W-1:0] stage2_fill_count;
    reg [MEM_ADDR_W-1:0] stage3_fill_count;

    reg stage2_phase;
    reg stage3_phase;
    reg stage2_pending;
    reg stage3_pending;
    reg stage2_pending_phase;
    reg stage3_pending_phase;

    reg job_active;
    reg [1:0] job_stage;
    reg job_phase;
    reg [3:0] job_mac_index;
    reg [3:0] job_mac_count;

    wire [MEM_ADDR_W-1:0] hist_index;
    wire [MEM_ADDR_W-1:0] hist_pair_limit;
    wire [MEM_ADDR_W-1:0] hist_mirror_index;
    wire [MEM_ADDR_W-1:0] coeff_index;
    wire [4:0] coeff_addr;
    wire signed [COEFF_W-1:0] coeff_comb;

    (* rom_style = "distributed" *)
    reg signed [COEFF_W-1:0] coeff_rom [0:31];

    reg signed [ACC_W-1:0] acc_reg;

    wire [MEM_ADDR_W-1:0] stage2_write_addr;
    wire [MEM_ADDR_W-1:0] stage3_write_addr;
    wire [MEM_ADDR_W-1:0] stage2_read_addr;
    wire [MEM_ADDR_W-1:0] stage3_read_addr;

    wire signed [STAGE2_DATA_W-1:0] stage2_x_current;
    wire signed [STAGE3_DATA_W-1:0] stage3_x_current;
    wire signed [STAGE2_DATA_W-1:0] stage2_mem_raw;
    wire signed [STAGE3_DATA_W-1:0] stage3_mem_raw;
    wire signed [STAGE2_DATA_W-1:0] stage2_mem;
    wire signed [STAGE3_DATA_W-1:0] stage3_mem;
    wire signed [STAGE2_DATA_W-1:0] selected_sample;
    wire signed [29:0] dsp_input_a;
    wire signed [24:0] dsp_input_d;
    wire signed [17:0] dsp_coeff_b;
    wire signed [47:0] dsp_acc_c;
    wire signed [47:0] dsp_mac_full;
    wire signed [ACC_W-1:0] mac_sum_comb;
    wire signed [STAGE2_DATA_W-1:0] stage2_q15_rounded;
    wire signed [STAGE3_DATA_W-1:0] stage3_q15_rounded;
    wire signed [SHIFT_W-1:0] truncated_value;
    wire round_increment;
    wire signed [ROUND_W-1:0] rounded_value;
    wire stage2_upper_is_sign_extension;
    wire stage3_upper_is_sign_extension;

    integer coeff_init_idx;

    assign stage2_x_current = stage2_x_in_valid ?
                              stage2_x_in : {STAGE2_DATA_W{1'b0}};
    assign stage3_x_current = stage3_x_in_valid ?
                              stage3_x_in : {STAGE3_DATA_W{1'b0}};

    assign stage2_write_addr = stage2_head - {{(MEM_ADDR_W-1){1'b0}}, 1'b1};
    assign stage3_write_addr = stage3_head - {{(MEM_ADDR_W-1){1'b0}}, 1'b1};
    assign hist_index = job_mac_index[MEM_ADDR_W-1:0];
    assign hist_pair_limit = (job_stage == 2'd2) ?
                             (job_phase ? 4'd7 : 4'd8) :
                             (job_phase ? 4'd4 : 4'd5);
    assign hist_mirror_index = hist_pair_limit - hist_index;
    assign coeff_index = (hist_index <= hist_mirror_index) ?
                         hist_index : hist_mirror_index;
    assign coeff_addr = {(job_stage == 2'd3), job_phase,
                         coeff_index[2:0]};
    assign coeff_comb = coeff_rom[coeff_addr];

    assign stage2_read_addr = stage2_head + hist_index;
    assign stage3_read_addr = stage3_head + hist_index;

    assign stage2_mem_raw = stage2_hist_mem[stage2_read_addr];
    assign stage3_mem_raw = stage3_hist_mem[stage3_read_addr];

    assign stage2_mem = (hist_index < stage2_fill_count) ?
                        stage2_mem_raw : {STAGE2_DATA_W{1'b0}};
    assign stage3_mem = (hist_index < stage3_fill_count) ?
                        stage3_mem_raw : {STAGE3_DATA_W{1'b0}};

    assign selected_sample = (job_stage == 2'd2) ? stage2_mem :
        {{(STAGE2_DATA_W-STAGE3_DATA_W){stage3_mem[STAGE3_DATA_W-1]}},
         stage3_mem};
    assign dsp_input_a =
        {{(30-STAGE2_DATA_W){selected_sample[STAGE2_DATA_W-1]}},
         selected_sample};
    assign dsp_input_d = 25'sd0;
    assign dsp_coeff_b = coeff_comb;
    assign dsp_acc_c = (job_mac_index == 4'd0) ? 48'sd0 :
        {{(48-ACC_W){acc_reg[ACC_W-1]}}, acc_reg};

    // 显式使用一颗 DSP48E1，避免综合器把预加、乘法和累加拆成多颗 DSP。
    // 不使用预加器，OPMODE=0110101 实现 A*B+C。
    DSP48E1 #(
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"),
        .USE_MULT("MULTIPLY"),
        .USE_SIMD("ONE48"),
        .AREG(0),
        .ACASCREG(0),
        .BREG(0),
        .BCASCREG(0),
        .CREG(0),
        .DREG(0),
        .ADREG(0),
        .MREG(0),
        .PREG(0),
        .INMODEREG(0),
        .OPMODEREG(0),
        .ALUMODEREG(0),
        .CARRYINREG(0),
        .CARRYINSELREG(0)
    ) u_stage23_dsp48e1 (
        .P(dsp_mac_full),
        .A(dsp_input_a),
        .B(dsp_coeff_b),
        .C(dsp_acc_c),
        .D(dsp_input_d),
        .INMODE(5'b00000),
        .OPMODE(7'b0110101),
        .ALUMODE(4'b0000),
        .CARRYINSEL(3'b000),
        .CARRYIN(1'b0),
        .ACIN(30'd0),
        .BCIN(18'd0),
        .PCIN(48'd0),
        .CARRYCASCIN(1'b0),
        .MULTSIGNIN(1'b0),
        .CLK(clk),
        .CEA1(1'b0),
        .CEA2(1'b0),
        .CEAD(1'b0),
        .CEALUMODE(1'b0),
        .CEB1(1'b0),
        .CEB2(1'b0),
        .CEC(1'b0),
        .CECARRYIN(1'b0),
        .CECTRL(1'b0),
        .CED(1'b0),
        .CEINMODE(1'b0),
        .CEM(1'b0),
        .CEP(1'b0),
        .RSTA(1'b0),
        .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0),
        .RSTB(1'b0),
        .RSTC(1'b0),
        .RSTCTRL(1'b0),
        .RSTD(1'b0),
        .RSTINMODE(1'b0),
        .RSTM(1'b0),
        .RSTP(1'b0),
        .ACOUT(),
        .BCOUT(),
        .CARRYCASCOUT(),
        .CARRYOUT(),
        .MULTSIGNOUT(),
        .OVERFLOW(),
        .PATTERNBDETECT(),
        .PATTERNDETECT(),
        .PCOUT(),
        .UNDERFLOW()
    );
    assign mac_sum_comb = dsp_mac_full[ACC_W-1:0];

    // 两级只会有一个 job 活动，因此共享一次 Q15 截断和舍入加一，
    // 再分别执行 22bit 与 20bit 的符号扩展检查和饱和。
    assign truncated_value = mac_sum_comb >>> FRAC_W;
    assign round_increment = mac_sum_comb[FRAC_W-1] &&
        (!mac_sum_comb[ACC_W-1] || (|mac_sum_comb[FRAC_W-2:0]));
    assign rounded_value =
        $signed({truncated_value[SHIFT_W-1], truncated_value}) +
        $signed({{SHIFT_W{1'b0}}, round_increment});

    assign stage2_upper_is_sign_extension =
        rounded_value[ROUND_W-1:STAGE2_DATA_W] ==
        {STAGE2_UPPER_W{rounded_value[STAGE2_DATA_W-1]}};
    assign stage3_upper_is_sign_extension =
        rounded_value[ROUND_W-1:STAGE3_DATA_W] ==
        {STAGE3_UPPER_W{rounded_value[STAGE3_DATA_W-1]}};

    assign stage2_q15_rounded = stage2_upper_is_sign_extension ?
        rounded_value[STAGE2_DATA_W-1:0] :
        (rounded_value[ROUND_W-1] ? STAGE2_OUT_MIN : STAGE2_OUT_MAX);
    assign stage3_q15_rounded = stage3_upper_is_sign_extension ?
        rounded_value[STAGE3_DATA_W-1:0] :
        (rounded_value[ROUND_W-1] ? STAGE3_OUT_MIN : STAGE3_OUT_MAX);

    assign stage2_phase_dbg = stage2_phase;
    assign stage3_phase_dbg = stage3_phase;
    assign scheduler_busy_dbg = job_active;
    assign scheduler_stage_dbg = job_stage;
    assign scheduler_mac_index_dbg = job_mac_index;

    initial begin
        for (coeff_init_idx = 0; coeff_init_idx < 32;
             coeff_init_idx = coeff_init_idx + 1)
            coeff_rom[coeff_init_idx] = {COEFF_W{1'b0}};

        coeff_rom[0]  = `V2_S2_P0_C0;
        coeff_rom[1]  = `V2_S2_P0_C1;
        coeff_rom[2]  = `V2_S2_P0_C2;
        coeff_rom[3]  = `V2_S2_P0_C3;
        coeff_rom[4]  = `V2_S2_P0_C4;
        coeff_rom[8]  = `V2_S2_P1_C0;
        coeff_rom[9]  = `V2_S2_P1_C1;
        coeff_rom[10] = `V2_S2_P1_C2;
        coeff_rom[11] = `V2_S2_P1_C3;

        if (CIC_ORDER == 3) begin
            coeff_rom[16] = 18'sd561;
            coeff_rom[17] = -18'sd4234;
            coeff_rom[18] = 18'sd20057;
            coeff_rom[24] = 18'sd137;
            coeff_rom[25] = -18'sd1555;
            coeff_rom[26] = 18'sd35604;
        end
        else begin
            coeff_rom[16] = 18'sd624;
            coeff_rom[17] = -18'sd4587;
            coeff_rom[18] = 18'sd20348;
            coeff_rom[24] = 18'sd153;
            coeff_rom[25] = -18'sd1971;
            coeff_rom[26] = 18'sd36402;
        end
    end

    // LUTRAM 不进行全阵列复位。复位时清空已写深度计数，未重写的
    // 槽位在读出端被强制为零，因此功能等价于历史数组清零。
    always @(posedge clk) begin
        if (rst_n) begin
            if (stage2_ce_out && stage2_phase == 1'b0)
                stage2_hist_mem[stage2_write_addr] <= stage2_x_current;
            if (stage3_ce_out && stage3_phase == 1'b0)
                stage3_hist_mem[stage3_write_addr] <= stage3_x_current;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2_head <= {MEM_ADDR_W{1'b0}};
            stage3_head <= {MEM_ADDR_W{1'b0}};
            stage2_fill_count <= {MEM_ADDR_W{1'b0}};
            stage3_fill_count <= {MEM_ADDR_W{1'b0}};
            stage2_phase <= 1'b1;
            stage3_phase <= 1'b1;
            stage2_pending <= 1'b0;
            stage3_pending <= 1'b0;
            stage2_pending_phase <= 1'b0;
            stage3_pending_phase <= 1'b0;
            job_active <= 1'b0;
            job_stage <= 2'd0;
            job_phase <= 1'b0;
            job_mac_index <= 4'd0;
            job_mac_count <= 4'd0;
            acc_reg <= {ACC_W{1'b0}};
            stage2_y_out <= {STAGE2_DATA_W{1'b0}};
            stage3_y_out <= {STAGE3_DATA_W{1'b0}};
            stage2_y_out_valid <= 1'b0;
            stage3_y_out_valid <= 1'b0;
        end
        else begin
            stage2_y_out_valid <= 1'b0;
            stage3_y_out_valid <= 1'b0;

            if (stage2_ce_out) begin
                stage2_pending <= 1'b1;
                stage2_pending_phase <= stage2_phase;
                if (stage2_phase == 1'b0) begin
                    stage2_head <= stage2_write_addr;
                    if (stage2_fill_count < 4'd9)
                        stage2_fill_count <= stage2_fill_count + 4'd1;
                end
                stage2_phase <= ~stage2_phase;
            end

            if (stage3_ce_out) begin
                stage3_pending <= 1'b1;
                stage3_pending_phase <= stage3_phase;
                if (stage3_phase == 1'b0) begin
                    stage3_head <= stage3_write_addr;
                    if (stage3_fill_count < 4'd6)
                        stage3_fill_count <= stage3_fill_count + 4'd1;
                end
                stage3_phase <= ~stage3_phase;
            end

            if (job_active) begin
                if (job_mac_index == job_mac_count - 4'd1) begin
                    if (job_stage == 2'd2) begin
                        stage2_y_out <= stage2_q15_rounded;
                        stage2_y_out_valid <= 1'b1;
                    end
                    else begin
                        stage3_y_out <= stage3_q15_rounded;
                        stage3_y_out_valid <= 1'b1;
                    end
                    job_active <= 1'b0;
                    job_mac_index <= 4'd0;
                    acc_reg <= {ACC_W{1'b0}};
                end
                else begin
                    acc_reg <= mac_sum_comb;
                    job_mac_index <= job_mac_index + 4'd1;
                end
            end
            else if (stage2_pending) begin
                job_active <= 1'b1;
                job_stage <= 2'd2;
                job_phase <= stage2_pending_phase;
                job_mac_index <= 4'd0;
                job_mac_count <= stage2_pending_phase ? 4'd8 : 4'd9;
                acc_reg <= {ACC_W{1'b0}};
                stage2_pending <= 1'b0;
            end
            else if (stage3_pending) begin
                job_active <= 1'b1;
                job_stage <= 2'd3;
                job_phase <= stage3_pending_phase;
                job_mac_index <= 4'd0;
                job_mac_count <= stage3_pending_phase ? 4'd5 : 4'd6;
                acc_reg <= {ACC_W{1'b0}};
                stage3_pending <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (STAGE2_DATA_W > 24 || STAGE2_DATA_W < STAGE3_DATA_W)
            $fatal(1, "Invalid Stage 2/3 data widths");
        if (COEFF_W != 18)
            $fatal(1, "LUTRAM Stage 2/3 candidate requires 18bit coefficients");
        if (CIC_ORDER != 3 && CIC_ORDER != 4)
            $fatal(1, "CIC_ORDER must be 3 or 4");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (stage2_ce_out && stage2_pending)
                $fatal(1, "Stage 2 LUTRAM pending overwrite");
            if (stage3_ce_out && stage3_pending)
                $fatal(1, "Stage 3 LUTRAM pending overwrite");
        end
    end
`endif

endmodule
