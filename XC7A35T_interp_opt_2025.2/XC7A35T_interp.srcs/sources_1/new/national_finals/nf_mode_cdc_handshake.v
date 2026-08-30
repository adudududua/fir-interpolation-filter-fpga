`timescale 1ns / 1ps

//=============================================================
// 文件名       : nf_mode_cdc_handshake.v
// 模块名       : nf_mode_cdc_handshake
// 功能简述     : 控制时钟域到音频时钟域的原子模式切换握手器。
//                控制域在 req_toggle 发起请求后保持 mode_shadow
//                不变，直到同步返回的 ack_toggle 确认传输完成。
//
//                音频域使用两级同步器接收请求，等待多位模式总线
//                达到设定稳定周期后，在静音窗口内同拍锁存两位
//                mode，随后回送确认。复位恢复也执行一次确定性
//                捕获，避免采样率家族切换时丢失同相位请求。
//
// 当前默认配置：
//                  模式总线宽度：2 bit
//                  SETTLE_CYCLES=3
//                  CDC 协议：toggle 请求/应答 + 稳定多位总线
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-29
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-29：新增带静音门控的模式原子传输。
//                2026-08-16：补充 CDC、复位恢复和握手说明。
//=============================================================
//=============================================================
// 1）模块名称：nf_mode_cdc_handshake
// 功能说明：模式跨时钟域握手：安全传递配置并在目标时钟域产生稳定更新事件。
// 工程版本：Vivado 2025.2。
//=============================================================

module nf_mode_cdc_handshake #(
    parameter integer SETTLE_CYCLES = 3
)(
    input  wire       ctrl_clk,
    input  wire       ctrl_rst_n,
    input  wire [1:0] ctrl_mode,
    output wire       ctrl_busy,

    input  wire       audio_clk,
    input  wire       audio_rst_n,
    output reg  [1:0] audio_mode,
    output reg        audio_mute
);

    reg [1:0] mode_shadow = 2'b11;
    reg       req_toggle = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg ack_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg ack_sync = 1'b0;

    reg       ack_toggle = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg req_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg req_sync = 1'b0;
    // 使用独热令牌替代pending标志和二进制递减计数器。当SETTLE_CYCLES=3时，
    // 请求按0001→0010→0100→1000→采样推进，与3→2→1→0→采样逐拍等价，
    // 但可以消除递减器并让综合结构更紧凑。
    reg [SETTLE_CYCLES:0] transfer_pipe =
        {{SETTLE_CYCLES{1'b0}}, 1'b1};
    assign ctrl_busy = (req_toggle != ack_sync);

    // 忙期间收到的多次模式变化只保留最新值；当前请求完成后再发起一次
    // 最新值传输，避免丢失用户最终选择，也不重复提交中间过渡模式。
    always @(posedge ctrl_clk) begin
        if (!ctrl_rst_n) begin
            mode_shadow <= 2'b11;
            req_toggle  <= 1'b0;
            ack_meta    <= 1'b0;
            ack_sync    <= 1'b0;
        end
        else begin
            ack_meta <= ack_toggle;
            ack_sync <= ack_meta;

            if ((req_toggle == ack_sync) && (ctrl_mode != mode_shadow)) begin
                mode_shadow <= ctrl_mode;
                req_toggle  <= ~req_toggle;
            end
        end
    end

    // mode_shadow属于握手保护的bundled-data多位总线；控制域保证它在
    // SETTLE和WARMUP全过程保持稳定，音频域仅在规定稳定窗口后原子采样。
    always @(posedge audio_clk) begin
        if (!audio_rst_n) begin
            req_meta     <= 1'b0;
            req_sync     <= 1'b0;
            ack_toggle   <= 1'b0;
            audio_mode   <= 2'b11;
            audio_mute   <= 1'b1;
            transfer_pipe <= {{SETTLE_CYCLES{1'b0}}, 1'b1};
        end
        else begin
            req_meta <= req_toggle;
            req_sync <= req_meta;

            if (transfer_pipe != {(SETTLE_CYCLES + 1){1'b0}}) begin
                audio_mute <= 1'b1;
                if (transfer_pipe[SETTLE_CYCLES]) begin
                    audio_mode <= mode_shadow;
                    ack_toggle <= req_sync;
                    transfer_pipe <= {(SETTLE_CYCLES + 1){1'b0}};
                end
                else
                    transfer_pipe <= transfer_pipe << 1;
            end
            // ack_toggle同时充当音频域已观察请求的本地令牌；其复位和更新
            // 边沿与原重复req_seen寄存器完全相同，因此一个状态位即可完成
            // 请求去重和应答返回。
            else if (req_sync != ack_toggle) begin
                audio_mute <= 1'b1;
                transfer_pipe <= {{SETTLE_CYCLES{1'b0}}, 1'b1};
            end
            else begin
                audio_mute <= 1'b0;
            end
        end
    end

endmodule
