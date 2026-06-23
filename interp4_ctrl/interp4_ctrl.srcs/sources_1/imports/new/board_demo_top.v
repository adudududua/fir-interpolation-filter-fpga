`default_nettype none
`timescale 1ns / 1ps

module board_demo_top(
    input  wire clk,      // 板载 50MHz 时钟
    input  wire rst_n     // 低有效复位（可接按键或固定高）
);

    //====================================================
    // 1) 产生输出采样使能 ce_out
    //
    // 目标：
    //   50MHz -> 200kHz
    //
    // 计算：
    //   50,000,000 / 200,000 = 250
    //
    // 所以每计满 250 个时钟，产生一个周期为 1 个 clk 的 ce_out 脉冲
    //====================================================
    localparam integer CE_DIV = 250;

    reg [7:0] ce_cnt;     // 8 位足够计到 249
    reg       ce_out;
    reg       ce_out_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ce_cnt <= 8'd0;
            ce_out <= 1'b0;
        end
        else begin
            if (ce_cnt == CE_DIV-1) begin
                ce_cnt <= 8'd0;
                ce_out <= 1'b1;    // 只拉高 1 个时钟周期
            end
            else begin
                ce_cnt <= ce_cnt + 8'd1;
                ce_out <= 1'b0;
            end
        end
    end
    
    //====================================================
    // 把 ce_out 延迟 1 个 clk
    //
    // 原始 ce_out：用于在 board_demo_top 中"准备输入样本"
    // 延迟后的 ce_out_d：用于驱动插值滤波器真正去采样输入
    //====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ce_out_d <= 1'b0;
        else
            ce_out_d <= ce_out;
    end

    //====================================================
    // 2) 产生原始输入样本节拍
    //
    // 每 4 个 ce_out 才送 1 个新的原始输入样本，
    // 这样：
    //   输入样本率 = 200kHz / 4 = 50kHz
    //
    // input_phase 的含义：
    //   0 -> 本次 ce_out 需要送真实输入
    //   1 -> 后续补零阶段
    //   2 -> 后续补零阶段
    //   3 -> 后续补零阶段
    //====================================================
    reg [1:0] input_phase;

    // 原始输入数据
    reg signed [23:0] x_in;
    reg               x_in_valid;

    // ROM 地址
    reg [3:0] rom_addr;

    //====================================================
    // 3) 测试输入 ROM
    //
    // 这里放一组固定测试序列，重复循环输出。
    // 这不是正式音频输入，而是板级验证用的内部激励。
    //
    // 我这里放一个 16 点近似正弦波，幅度约 600 万，
    // 不会超出 24 位有符号范围（±8388608）。
    //====================================================
    reg signed [23:0] test_rom [0:15];

    initial begin
        test_rom[0]  =  24'sd0;
        test_rom[1]  =  24'sd2296100;
        test_rom[2]  =  24'sd4242641;
        test_rom[3]  =  24'sd5543277;
        test_rom[4]  =  24'sd6000000;
        test_rom[5]  =  24'sd5543277;
        test_rom[6]  =  24'sd4242641;
        test_rom[7]  =  24'sd2296100;
        test_rom[8]  =  24'sd0;
        test_rom[9]  = -24'sd2296100;
        test_rom[10] = -24'sd4242641;
        test_rom[11] = -24'sd5543277;
        test_rom[12] = -24'sd6000000;
        test_rom[13] = -24'sd5543277;
        test_rom[14] = -24'sd4242641;
        test_rom[15] = -24'sd2296100;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_phase <= 2'd0;
            x_in        <= 24'sd0;
            x_in_valid  <= 1'b0;
            rom_addr    <= 4'd0;
        end
        else begin
            //================================================
            // 默认情况下，不主动清零 x_in，
            // 只在合适的时候更新 x_in_valid
            //================================================
    
            // 当延迟后的 ce_out_d 到来时，说明插值控制器已经在这一拍真正采样了输入
            // 所以这里把 x_in_valid 清掉，避免一直保持为高
            if (ce_out_d)
                x_in_valid <= 1'b0;
    
            // 原始 ce_out 到来时，提前准备下一次给控制器采样的输入样本
            if (ce_out) begin
                if (input_phase == 2'd0) begin
                    // 每 4 个 ce_out 的第 1 个，准备一个真实输入样本
                    x_in       <= test_rom[rom_addr];
                    x_in_valid <= 1'b1;
    
                    // ROM 地址循环递增
                    if (rom_addr == 4'd15)
                        rom_addr <= 4'd0;
                    else
                        rom_addr <= rom_addr + 4'd1;
                end
    
                // 输入相位推进
                if (input_phase == 2'd3)
                    input_phase <= 2'd0;
                else
                    input_phase <= input_phase + 2'd1;
            end
        end
    end

    //====================================================
    // 4) 实例化"带 ce_out 的对称优化版插值顶层"
    //
    // 注意：
    // 这里增加 dont_touch，防止整条滤波链在没有顶层输出直连时
    // 被综合器当成"无用逻辑"优化掉。
    //====================================================
    wire signed [23:0] y_out;
    wire               y_out_valid;
    wire [1:0]         phase_dbg;
    wire signed [23:0] fir_in_dbg;
    wire               fir_in_valid_dbg;

    (* dont_touch = "true" *) interp4_top_symm_ce u_interp4_top_symm_ce (
        .clk              (clk),
        .rst_n            (rst_n),
        .ce_out           (ce_out_d),
        .x_in             (x_in),
        .x_in_valid       (x_in_valid),
        .y_out            (y_out),
        .y_out_valid      (y_out_valid),
        .phase_dbg        (phase_dbg),
        .fir_in_dbg       (fir_in_dbg),
        .fir_in_valid_dbg (fir_in_valid_dbg)
    );

    //====================================================
    // 5) 调试信号
    //
    // 这些信号将直接接到手动例化的 ILA IP 上
    //====================================================
    wire        dbg_ce_out;
    wire        dbg_x_in_valid;
    wire [23:0] dbg_x_in;
    wire [1:0]  dbg_phase;
    wire [23:0] dbg_fir_in;
    wire        dbg_fir_val;
    wire [23:0] dbg_y_out;
    wire        dbg_y_valid;

    assign dbg_ce_out     = ce_out_d;
    assign dbg_x_in_valid = x_in_valid;
    assign dbg_x_in       = x_in;
    assign dbg_phase      = phase_dbg;
    assign dbg_fir_in     = fir_in_dbg;
    assign dbg_fir_val    = fir_in_valid_dbg;
    assign dbg_y_out      = y_out;
    assign dbg_y_valid    = y_out_valid;
    
    //====================================================
    // 6) 手动例化 ILA
    //
    // 采样时钟必须选系统时钟 clk
    // 不能选 ce_out
    //====================================================
    ila_0 u_ila_0 (
        .clk    (clk),            // ILA 采样时钟：50MHz 系统时钟

        .probe0 (dbg_ce_out),     // 1 bit
        .probe1 (dbg_x_in_valid), // 1 bit
        .probe2 (dbg_x_in),       // 24 bit
        .probe3 (dbg_phase),      // 2 bit
        .probe4 (dbg_fir_in),     // 24 bit
        .probe5 (dbg_fir_val),    // 1 bit
        .probe6 (dbg_y_out),      // 24 bit
        .probe7 (dbg_y_valid)     // 1 bit
    );

endmodule
`default_nettype wire