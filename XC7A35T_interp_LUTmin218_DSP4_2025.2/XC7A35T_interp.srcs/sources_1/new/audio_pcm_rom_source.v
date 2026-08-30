`timescale 1ns / 1ps
//=============================================================
// 文件名       : audio_pcm_rom_source.v
// 模块名       : audio_pcm_rom_source
// 功能简述     : 24bit signed 音频 PCM ROM 读取模块。
//                本模块用于把 .mem 文件中的音频采样点读出，
//                作为 FIR 插值滤波器的输入信号。
//                
//                每当 sample_ce 有效一次，本模块输出一个新的
//                24bit signed 音频采样点。
//                
//                当前默认配置：
//                  采样点数：147 点
//                  数据位宽：24bit signed
//                  数据文件：demo_sine_15k_44k1_24bit_147.mem
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-06-20
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-06-20：新增音频 PCM ROM 输入源。
//                2026-07-12：默认数据切换为 44.1kHz 采样的
//                            15kHz 单正弦示波器对比信号。
//                2026-07-17：在 0.50FS 板测基线下重新启用
//                            Block RAM ROM 推断试验。
//=============================================================

module audio_pcm_rom_source #(
    parameter DATA_W   = 24,                               // PCM 数据位宽
    parameter ADDR_W   = 8,                                // 147 点需要 8bit 地址
    parameter DEPTH    = 147,                              // ROM 深度
    parameter MEM_FILE = "demo_sine_15k_44k1_24bit_147.mem"
)(
    input  wire                       clk,                 // 工作时钟，接 clk_audio_128x
    input  wire                       rst_n,               // 低有效复位
    input  wire                       sample_ce,           // 输入采样更新节拍，当前为 44.1kHz

    output reg  signed [DATA_W-1:0]   sample_out,          // 输出音频采样点
    output reg                        sample_update,       // 输出采样更新脉冲
    output reg  [ADDR_W-1:0]          sample_addr_dbg      // 当前读地址，方便仿真/调试
);

    //=========================================================
    // 0）末地址参数
    //
    // DEPTH = 147 时：
    //   LAST_ADDR = 146
    //
    // 用这个参数判断 ROM 是否读到最后一个地址。
    //=========================================================
    localparam [ADDR_W-1:0] LAST_ADDR = DEPTH - 1;

    //=========================================================
    // 1）ROM 定义
    //
    // rom_style = "block"：
    //   提示 Vivado 尽量使用 Block RAM 存储音频采样点。
    //
    // pcm_rom：
    //   存储 DEPTH 个 24bit signed PCM 采样点。
    //=========================================================
    (* rom_style = "block" *)
    reg signed [DATA_W-1:0] pcm_rom [0:DEPTH-1];

    //=========================================================
    // 2）读地址和 ROM 输出寄存器
    //
    // rd_addr：
    //   当前 ROM 读取地址。
    //
    // rom_data_q：
    //   同步 ROM 读出的数据。
    //
    // 说明：
    //   这里采用同步读 ROM，更容易综合成 FPGA 的 Block RAM。
    //   因为 sample_ce 每 128 个 clk_audio_128x 周期才来一次，
    //   所以同步读多出的 1 拍延迟完全可以接受。
    //=========================================================
    reg [ADDR_W-1:0]        rd_addr;
    reg signed [DATA_W-1:0] rom_data_q;

    //=========================================================
    // 3）ROM 初始化
    //
    // .mem 文件中每一行是一个 24bit 十六进制补码数据。
    //
    // 例如：
    //   000000
    //   0A12BC
    //   F54321
    //
    // 注意：
    //   MEM_FILE 对应的 .mem 文件需要添加进 Vivado 工程。
    //=========================================================
    initial begin
        // .mem 覆盖 0 至 DEPTH-1 的全部地址。不要增加逐项清零
        // 循环，以免 Vivado 2025.2 放弃 Block RAM ROM 推断。
        $readmemh(MEM_FILE, pcm_rom);
    end

    // 同步读位于无异步复位的独立进程中，使 Vivado 2025.2
    // 可以把 rom_data_q 吸收到 RAMB18E1 的输出寄存器。
    always @(posedge clk) begin
        rom_data_q <= pcm_rom[rd_addr];
    end

    //=========================================================
    // 4）ROM 同步读与采样输出
    //
    // 工作方式：
    //   - 每个 clk 周期都根据 rd_addr 读 ROM；
    //   - 当 sample_ce 有效时，把当前 rom_data_q 输出；
    //   - 地址加 1；
    //   - 读到最后一个采样点后回到 0，实现循环播放。
    //
    // sample_update：
    //   只在 sample_ce 对应的那个周期拉高 1 拍。
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_addr         <= {ADDR_W{1'b0}};
            sample_out      <= {DATA_W{1'b0}};
            sample_update   <= 1'b0;
            sample_addr_dbg <= {ADDR_W{1'b0}};
        end
        else begin
            // 默认 sample_update 只保持 1 个周期
            sample_update <= 1'b0;

            // 到达输入采样节拍时，输出一个新的 PCM 采样点
            if (sample_ce) begin
                sample_out      <= rom_data_q;
                sample_update   <= 1'b1;
                sample_addr_dbg <= rd_addr;

                // 循环播放
                if (rd_addr == LAST_ADDR)
                    rd_addr <= {ADDR_W{1'b0}};
                else
                    rd_addr <= rd_addr + 1'b1;
            end
        end
    end

endmodule
