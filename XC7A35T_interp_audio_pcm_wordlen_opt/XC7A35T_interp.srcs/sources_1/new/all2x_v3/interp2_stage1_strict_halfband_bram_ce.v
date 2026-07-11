`timescale 1ns / 1ps

`include "all2x_v3_stage1_coeff_pkg.vh"

//=============================================================
// 文件名       : interp2_stage1_strict_halfband_bram_ce.v
// 模块名       : interp2_stage1_strict_halfband_bram_ce
// 功能简述     : Stage 1 strict-halfband true-polyphase BRAM 版本。
//                使用 64x24bit true dual-port 循环缓冲保存真实输入，
//                两个读端口逐周期读取对称样点，26 次 MAC 完成滤波相。
//                纯延迟相在前一相位预读，并在下一次 ce_out 输出。
//
//                BRAM 内容不做运行时复位。fill_count 对尚未写入的
//                历史样点进行零值屏蔽，只复位指针、状态机和 valid。
//
// 当前默认配置：
//                  存储深度      ：64
//                  有效历史长度  ：52
//                  对称 MAC 对数 ：26
//                  系数格式      ：17bit signed Q15
//                  累加器位宽    ：42bit signed
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-11：新增 Stage 1 strict-halfband BRAM 版本。
//=============================================================

module interp2_stage1_strict_halfband_bram_ce #(
    parameter integer DATA_W      = 24,
    parameter integer COEFF_W     = `V3_S1_COEFF_W,
    parameter integer ACC_W       = `V3_S1_ACC_W,
    parameter integer FRAC_W      = `V3_S1_FRAC_W,
    parameter integer HISTORY_LEN = `V3_S1_HISTORY_LEN,
    parameter integer PAIR_COUNT  = `V3_S1_PAIR_COUNT,
    parameter integer DELAY_INDEX = `V3_S1_DELAY_INDEX,
    parameter integer RAM_DEPTH   = 64
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce_out,

    input  wire signed [DATA_W-1:0]     x_in,
    input  wire                         x_in_valid,

    output reg  signed [DATA_W-1:0]     y_out,
    output reg                          y_out_valid,

    output reg                          phase_dbg,
    output wire signed [DATA_W-1:0]     fir_in_dbg,
    output wire                         fir_in_valid_dbg
);

    localparam integer ADDR_W = 6;
    localparam integer PAIR_W = DATA_W + 1;
    localparam integer PROD_W = PAIR_W + COEFF_W;

    (* ram_style = "block" *)
    reg signed [DATA_W-1:0] sample_mem [0:RAM_DEPTH-1];

    reg signed [DATA_W-1:0] read_data_a;
    reg signed [DATA_W-1:0] read_data_b;
    reg [ADDR_W-1:0] read_addr_a;
    reg [ADDR_W-1:0] read_addr_b;
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] base_ptr;
    reg [5:0] fill_count;
    reg [5:0] active_fill_count;

    reg phase_cnt;
    reg mac_active;
    reg filter_ready;
    reg delay_ready;
    reg issue_active;
    reg read_issue_valid;
    reg issue_is_delay;
    reg issue_mask_a;
    reg issue_mask_b;
    reg [4:0] issue_index;

    reg read_data_valid;
    reg read_is_delay;
    reg read_mask_a;
    reg read_mask_b;
    reg [4:0] read_coeff_index;

    reg signed [ACC_W-1:0] acc_reg;
    reg signed [ACC_W-1:0] filter_result;
    reg signed [DATA_W-1:0] delay_result;

    wire signed [DATA_W-1:0] x_current;
    reg signed [PAIR_W-1:0] pair_sum_comb;
    reg signed [COEFF_W-1:0] coeff_comb;
    (* use_dsp = "yes" *)
    wire signed [PROD_W-1:0] product_comb;
    wire signed [ACC_W-1:0] product_ext;
    wire signed [DATA_W-1:0] filter_rounded;

    assign x_current = x_in_valid ? x_in : {DATA_W{1'b0}};
    assign fir_in_dbg = x_current;
    assign fir_in_valid_dbg = ce_out && (phase_cnt == 1'b0);

    assign product_comb = pair_sum_comb * coeff_comb;
    assign product_ext = {{(ACC_W-PROD_W){product_comb[PROD_W-1]}},
                          product_comb};

    always @(*) begin
        pair_sum_comb =
            $signed({(read_mask_a ? read_data_a[DATA_W-1] : 1'b0),
                     (read_mask_a ? read_data_a : {DATA_W{1'b0}})}) +
            $signed({(read_mask_b ? read_data_b[DATA_W-1] : 1'b0),
                     (read_mask_b ? read_data_b : {DATA_W{1'b0}})});

        case (read_coeff_index)
            5'd0:  coeff_comb = `V3_S1_C00;
            5'd1:  coeff_comb = `V3_S1_C01;
            5'd2:  coeff_comb = `V3_S1_C02;
            5'd3:  coeff_comb = `V3_S1_C03;
            5'd4:  coeff_comb = `V3_S1_C04;
            5'd5:  coeff_comb = `V3_S1_C05;
            5'd6:  coeff_comb = `V3_S1_C06;
            5'd7:  coeff_comb = `V3_S1_C07;
            5'd8:  coeff_comb = `V3_S1_C08;
            5'd9:  coeff_comb = `V3_S1_C09;
            5'd10: coeff_comb = `V3_S1_C10;
            5'd11: coeff_comb = `V3_S1_C11;
            5'd12: coeff_comb = `V3_S1_C12;
            5'd13: coeff_comb = `V3_S1_C13;
            5'd14: coeff_comb = `V3_S1_C14;
            5'd15: coeff_comb = `V3_S1_C15;
            5'd16: coeff_comb = `V3_S1_C16;
            5'd17: coeff_comb = `V3_S1_C17;
            5'd18: coeff_comb = `V3_S1_C18;
            5'd19: coeff_comb = `V3_S1_C19;
            5'd20: coeff_comb = `V3_S1_C20;
            5'd21: coeff_comb = `V3_S1_C21;
            5'd22: coeff_comb = `V3_S1_C22;
            5'd23: coeff_comb = `V3_S1_C23;
            5'd24: coeff_comb = `V3_S1_C24;
            5'd25: coeff_comb = `V3_S1_C25;
            default: coeff_comb = {COEFF_W{1'b0}};
        endcase
    end

    round_sat_q16_to24 #(
        .IN_W   (ACC_W),
        .OUT_W  (DATA_W),
        .FRAC_W (FRAC_W)
    ) u_round_sat_q15_to_data (
        .din_full (filter_result),
        .dout_24  (filter_rounded)
    );

    // Port A：phase0 写入，其余周期作为第一个同步读端口。
    always @(posedge clk) begin
        if (rst_n && ce_out && phase_cnt == 1'b0)
            sample_mem[wr_ptr] <= x_current;
        else if (read_issue_valid)
            read_data_a <= sample_mem[read_addr_a];
    end

    // Port B：第二个同步读端口。
    always @(posedge clk) begin
        if (read_issue_valid)
            read_data_b <= sample_mem[read_addr_b];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            read_data_valid <= 1'b0;
            read_is_delay <= 1'b0;
            read_mask_a <= 1'b0;
            read_mask_b <= 1'b0;
            read_coeff_index <= 5'd0;
        end
        else begin
            read_data_valid <= read_issue_valid;
            if (read_issue_valid) begin
                read_is_delay <= issue_is_delay;
                read_mask_a <= issue_mask_a;
                read_mask_b <= issue_mask_b;
                read_coeff_index <= issue_index;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_W{1'b0}};
            base_ptr <= {ADDR_W{1'b0}};
            fill_count <= 6'd0;
            active_fill_count <= 6'd0;
            phase_cnt <= 1'b1;
            phase_dbg <= 1'b1;
            mac_active <= 1'b0;
            filter_ready <= 1'b0;
            delay_ready <= 1'b0;
            issue_active <= 1'b0;
            read_issue_valid <= 1'b0;
            issue_is_delay <= 1'b0;
            issue_mask_a <= 1'b0;
            issue_mask_b <= 1'b0;
            issue_index <= 5'd0;
            read_addr_a <= {ADDR_W{1'b0}};
            read_addr_b <= {ADDR_W{1'b0}};
            acc_reg <= {ACC_W{1'b0}};
            filter_result <= {ACC_W{1'b0}};
            delay_result <= {DATA_W{1'b0}};
            y_out <= {DATA_W{1'b0}};
            y_out_valid <= 1'b0;
        end
        else begin
            y_out_valid <= 1'b0;
            read_issue_valid <= 1'b0;

            if (read_data_valid) begin
                if (read_is_delay) begin
                    delay_result <= read_mask_a ? read_data_a :
                                    {DATA_W{1'b0}};
                    delay_ready <= 1'b1;
                end
                else if (read_coeff_index == PAIR_COUNT-1) begin
                    filter_result <= acc_reg + product_ext;
                    filter_ready <= 1'b1;
                    mac_active <= 1'b0;
                end
                else begin
                    acc_reg <= acc_reg + product_ext;
                end
            end

            if (issue_active) begin
                issue_is_delay <= 1'b0;

                if (issue_index < PAIR_COUNT-1) begin
                    read_issue_valid <= 1'b1;
                    issue_index <= issue_index + 5'd1;
                    read_addr_a <= base_ptr - (issue_index + 5'd1);
                    read_addr_b <= base_ptr -
                        (HISTORY_LEN-1-(issue_index + 5'd1));
                    issue_mask_a <= (issue_index + 5'd1) <
                                    active_fill_count;
                    issue_mask_b <=
                        (HISTORY_LEN-1-(issue_index + 5'd1)) <
                        active_fill_count;
                end
                else begin
                    read_issue_valid <= 1'b0;
                    issue_active <= 1'b0;
                end
            end

            if (ce_out) begin
                phase_dbg <= phase_cnt;
                y_out_valid <= 1'b1;

                if (phase_cnt == 1'b0) begin
                    y_out <= delay_ready ? delay_result :
                             {DATA_W{1'b0}};
                    delay_ready <= 1'b0;

                    base_ptr <= wr_ptr;
                    wr_ptr <= wr_ptr + 6'd1;
                    if (fill_count < HISTORY_LEN)
                        fill_count <= fill_count + 6'd1;
                    active_fill_count <=
                        (fill_count < HISTORY_LEN) ?
                        (fill_count + 6'd1) : fill_count;

                    acc_reg <= {ACC_W{1'b0}};
                    mac_active <= 1'b1;
                    filter_ready <= 1'b0;
                    issue_active <= 1'b1;
                    read_issue_valid <= 1'b1;
                    issue_is_delay <= 1'b0;
                    issue_index <= 5'd0;
                    read_addr_a <= wr_ptr;
                    read_addr_b <= wr_ptr - (HISTORY_LEN-1);
                    issue_mask_a <= 1'b1;
                    issue_mask_b <= (HISTORY_LEN-1) <
                        ((fill_count < HISTORY_LEN) ?
                         (fill_count + 6'd1) : fill_count);
                end
                else begin
                    y_out <= filter_ready ? filter_rounded :
                             {DATA_W{1'b0}};
                    filter_ready <= 1'b0;

                    read_issue_valid <= 1'b1;
                    issue_is_delay <= 1'b1;
                    issue_index <= 5'd0;
                    read_addr_a <= wr_ptr - (DELAY_INDEX + 1);
                    read_addr_b <= {ADDR_W{1'b0}};
                    issue_mask_a <= fill_count > DELAY_INDEX;
                    issue_mask_b <= 1'b0;
                end

                phase_cnt <= ~phase_cnt;
            end
        end
    end

`ifndef SYNTHESIS
    reg input_seen;

    always @(posedge clk) begin
        if (!rst_n) begin
            input_seen <= 1'b0;
        end
        else if (ce_out && phase_cnt == 1'b0) begin
            input_seen <= 1'b1;
            if (mac_active || issue_active)
                $fatal(1, "Stage 1 BRAM MAC deadline miss");
        end
        else if (ce_out && phase_cnt == 1'b1 && input_seen &&
                 !filter_ready) begin
            $fatal(1, "Stage 1 BRAM filter result not ready");
        end
    end
`endif

endmodule
