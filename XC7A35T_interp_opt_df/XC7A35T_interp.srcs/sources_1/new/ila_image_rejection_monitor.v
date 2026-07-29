`timescale 1ns / 1ps
//=============================================================
// 文件名       : ila_image_rejection_monitor.v
// 模块名       : ila_image_rejection_monitor
// 功能简述     : 对第一级 2x FIR 前后的 15kHz 与 40kHz 分量
//                进行固定频点相干检测。检测窗口为 882 个
//                88.2kHz 样本（10ms），四组 I/Q 乘法共用一个
//                DSP48；无需通用 FFT 即可直观显示镜像衰减。
//
//                滤波后幅值除以 2，以抵消插值 FIR 的 2 倍
//                频谱增益，使 PRE/POST 柱状图采用相同标度。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-19
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-19：新增 15kHz/40kHz 相干幅值检测。
//=============================================================

module ila_image_rejection_monitor #(
    parameter integer WARMUP_SAMPLES = 2048,
    parameter integer BLOCK_SAMPLES = 882,
    parameter integer REF_DEPTH = 441,
    parameter REF_MEM_FILE = "ila_demo_refs_15k_40k_441.mem"
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    input  wire                     sample_ce,
    input  wire signed [23:0]       sample_pre,
    input  wire signed [23:0]       sample_post,

    output reg [15:0]               magnitude_15k_pre,
    output reg [15:0]               magnitude_15k_post,
    output reg [15:0]               magnitude_40k_pre,
    output reg [15:0]               magnitude_40k_post,
    output reg [7:0]                suppression_40k_db,
    output reg                      measurement_valid,
    output reg                      result_strobe
);

    // 每个 64bit ROM 字依次存放 cos15/sin15/cos40/sin40。
    (* rom_style = "block" *)
    reg [63:0] reference_rom [0:REF_DEPTH-1];
    reg [63:0] reference_data_q;
    reg [8:0]  reference_address;

    initial begin
        $readmemh(REF_MEM_FILE, reference_rom);
    end

    always @(posedge clk) begin
        reference_data_q <= reference_rom[reference_address];
    end

    reg signed [23:0] sample_pre_latched;
    reg signed [23:0] sample_post_latched;
    reg signed [15:0] ref_15k_i_latched;
    reg signed [15:0] ref_15k_q_latched;
    reg signed [15:0] ref_40k_i_latched;
    reg signed [15:0] ref_40k_q_latched;

    reg [11:0] warmup_count;
    reg [9:0]  block_count;
    reg        last_sample_latched;
    reg        multiply_busy;
    reg [3:0]  multiply_state;

    reg signed [63:0] acc_15k_pre_i;
    reg signed [63:0] acc_15k_pre_q;
    reg signed [63:0] acc_15k_post_i;
    reg signed [63:0] acc_15k_post_q;
    reg signed [63:0] acc_40k_pre_i;
    reg signed [63:0] acc_40k_pre_q;
    reg signed [63:0] acc_40k_post_i;
    reg signed [63:0] acc_40k_post_q;

    reg signed [23:0] multiplier_data;
    reg signed [15:0] multiplier_reference;
    (* use_dsp = "yes" *) wire signed [39:0] multiplier_product;
    wire signed [63:0] multiplier_product_ext;

    assign multiplier_product = multiplier_data * multiplier_reference;
    assign multiplier_product_ext =
        {{24{multiplier_product[39]}}, multiplier_product};

    always @(*) begin
        multiplier_data      = sample_pre_latched;
        multiplier_reference = ref_15k_i_latched;

        case (multiply_state)
            4'd0: begin
                multiplier_data      = sample_pre_latched;
                multiplier_reference = ref_15k_i_latched;
            end
            4'd1: begin
                multiplier_data      = sample_pre_latched;
                multiplier_reference = ref_15k_q_latched;
            end
            4'd2: begin
                multiplier_data      = sample_post_latched;
                multiplier_reference = ref_15k_i_latched;
            end
            4'd3: begin
                multiplier_data      = sample_post_latched;
                multiplier_reference = ref_15k_q_latched;
            end
            4'd4: begin
                multiplier_data      = sample_pre_latched;
                multiplier_reference = ref_40k_i_latched;
            end
            4'd5: begin
                multiplier_data      = sample_pre_latched;
                multiplier_reference = ref_40k_q_latched;
            end
            4'd6: begin
                multiplier_data      = sample_post_latched;
                multiplier_reference = ref_40k_i_latched;
            end
            4'd7: begin
                multiplier_data      = sample_post_latched;
                multiplier_reference = ref_40k_q_latched;
            end
            default: begin
                multiplier_data      = 24'sd0;
                multiplier_reference = 16'sd0;
            end
        endcase
    end

    function [63:0] absolute_64;
        input signed [63:0] value;
        begin
            absolute_64 = value[63] ? ((~value) + 64'd1) : value;
        end
    endfunction

    function [63:0] magnitude_approx;
        input signed [63:0] i_value;
        input signed [63:0] q_value;
        reg [63:0] abs_i;
        reg [63:0] abs_q;
        begin
            abs_i = absolute_64(i_value);
            abs_q = absolute_64(q_value);
            if (abs_i >= abs_q)
                magnitude_approx = abs_i + (abs_q >> 1);
            else
                magnitude_approx = abs_q + (abs_i >> 1);
        end
    endfunction

    function [15:0] scaled_magnitude;
        input [63:0] value;
        begin
            // 2^30 标度使 0.20FS 的相干分量接近 16bit 中量程。
            if (|value[63:46])
                scaled_magnitude = 16'hFFFF;
            else
                scaled_magnitude = value[45:30];
        end
    endfunction

    function [5:0] highest_one_position;
        input [63:0] value;
        integer bit_index;
        begin
            highest_one_position = 6'd0;
            for (bit_index = 0; bit_index < 64; bit_index = bit_index + 1) begin
                if (value[bit_index])
                    highest_one_position = bit_index[5:0];
            end
        end
    endfunction

    function [7:0] suppression_db_approx;
        input [63:0] magnitude_before;
        input [63:0] magnitude_after_normalized;
        reg [6:0] bit_difference;
        reg [9:0] db_value;
        begin
            if (magnitude_after_normalized == 64'd0) begin
                suppression_db_approx = 8'd99;
            end
            else if (magnitude_before <= magnitude_after_normalized) begin
                suppression_db_approx = 8'd0;
            end
            else begin
                bit_difference = highest_one_position(magnitude_before) -
                                 highest_one_position(magnitude_after_normalized);
                db_value = bit_difference * 10'd6;
                suppression_db_approx = (db_value > 10'd99) ?
                                        8'd99 : db_value[7:0];
            end
        end
    endfunction

    wire [63:0] magnitude_15k_pre_full;
    wire [63:0] magnitude_15k_post_full;
    wire [63:0] magnitude_40k_pre_full;
    wire [63:0] magnitude_40k_post_full;
    wire [63:0] magnitude_15k_post_normalized;
    wire [63:0] magnitude_40k_post_normalized;

    assign magnitude_15k_pre_full =
        magnitude_approx(acc_15k_pre_i, acc_15k_pre_q);
    assign magnitude_15k_post_full =
        magnitude_approx(acc_15k_post_i, acc_15k_post_q);
    assign magnitude_40k_pre_full =
        magnitude_approx(acc_40k_pre_i, acc_40k_pre_q);
    assign magnitude_40k_post_full =
        magnitude_approx(acc_40k_post_i, acc_40k_post_q);
    assign magnitude_15k_post_normalized = magnitude_15k_post_full >> 1;
    assign magnitude_40k_post_normalized = magnitude_40k_post_full >> 1;

    always @(posedge clk) begin
        if (!rst_n || !enable) begin
            reference_address   <= 9'd0;
            warmup_count        <= 12'd0;
            block_count         <= 10'd0;
            last_sample_latched <= 1'b0;
            multiply_busy       <= 1'b0;
            multiply_state      <= 4'd0;

            sample_pre_latched  <= 24'sd0;
            sample_post_latched <= 24'sd0;
            ref_15k_i_latched   <= 16'sd0;
            ref_15k_q_latched   <= 16'sd0;
            ref_40k_i_latched   <= 16'sd0;
            ref_40k_q_latched   <= 16'sd0;

            acc_15k_pre_i  <= 64'sd0;
            acc_15k_pre_q  <= 64'sd0;
            acc_15k_post_i <= 64'sd0;
            acc_15k_post_q <= 64'sd0;
            acc_40k_pre_i  <= 64'sd0;
            acc_40k_pre_q  <= 64'sd0;
            acc_40k_post_i <= 64'sd0;
            acc_40k_post_q <= 64'sd0;

            magnitude_15k_pre  <= 16'd0;
            magnitude_15k_post <= 16'd0;
            magnitude_40k_pre  <= 16'd0;
            magnitude_40k_post <= 16'd0;
            suppression_40k_db <= 8'd0;
            measurement_valid  <= 1'b0;
            result_strobe       <= 1'b0;
        end
        else begin
            result_strobe <= 1'b0;

            if (sample_ce && !multiply_busy) begin
                if (reference_address == REF_DEPTH - 1)
                    reference_address <= 9'd0;
                else
                    reference_address <= reference_address + 9'd1;

                if (warmup_count < WARMUP_SAMPLES) begin
                    warmup_count <= warmup_count + 12'd1;
                    block_count  <= 10'd0;
                end
                else begin
                    sample_pre_latched  <= sample_pre;
                    sample_post_latched <= sample_post;
                    ref_15k_i_latched   <= reference_data_q[63:48];
                    ref_15k_q_latched   <= reference_data_q[47:32];
                    ref_40k_i_latched   <= reference_data_q[31:16];
                    ref_40k_q_latched   <= reference_data_q[15:0];

                    last_sample_latched <= (block_count == BLOCK_SAMPLES - 1);
                    if (block_count == BLOCK_SAMPLES - 1)
                        block_count <= 10'd0;
                    else
                        block_count <= block_count + 10'd1;

                    multiply_busy  <= 1'b1;
                    multiply_state <= 4'd0;
                end
            end

            if (multiply_busy) begin
                case (multiply_state)
                    4'd0: begin
                        acc_15k_pre_i <= acc_15k_pre_i + multiplier_product_ext;
                        multiply_state <= 4'd1;
                    end
                    4'd1: begin
                        acc_15k_pre_q <= acc_15k_pre_q + multiplier_product_ext;
                        multiply_state <= 4'd2;
                    end
                    4'd2: begin
                        acc_15k_post_i <= acc_15k_post_i + multiplier_product_ext;
                        multiply_state <= 4'd3;
                    end
                    4'd3: begin
                        acc_15k_post_q <= acc_15k_post_q + multiplier_product_ext;
                        multiply_state <= 4'd4;
                    end
                    4'd4: begin
                        acc_40k_pre_i <= acc_40k_pre_i + multiplier_product_ext;
                        multiply_state <= 4'd5;
                    end
                    4'd5: begin
                        acc_40k_pre_q <= acc_40k_pre_q + multiplier_product_ext;
                        multiply_state <= 4'd6;
                    end
                    4'd6: begin
                        acc_40k_post_i <= acc_40k_post_i + multiplier_product_ext;
                        multiply_state <= 4'd7;
                    end
                    4'd7: begin
                        acc_40k_post_q <= acc_40k_post_q + multiplier_product_ext;
                        if (last_sample_latched)
                            multiply_state <= 4'd8;
                        else begin
                            multiply_state <= 4'd0;
                            multiply_busy  <= 1'b0;
                        end
                    end
                    4'd8: begin
                        magnitude_15k_pre <=
                            scaled_magnitude(magnitude_15k_pre_full);
                        magnitude_15k_post <=
                            scaled_magnitude(magnitude_15k_post_normalized);
                        magnitude_40k_pre <=
                            scaled_magnitude(magnitude_40k_pre_full);
                        magnitude_40k_post <=
                            scaled_magnitude(magnitude_40k_post_normalized);
                        suppression_40k_db <=
                            suppression_db_approx(
                                magnitude_40k_pre_full,
                                magnitude_40k_post_normalized);
                        measurement_valid <= 1'b1;
                        result_strobe      <= 1'b1;

                        acc_15k_pre_i  <= 64'sd0;
                        acc_15k_pre_q  <= 64'sd0;
                        acc_15k_post_i <= 64'sd0;
                        acc_15k_post_q <= 64'sd0;
                        acc_40k_pre_i  <= 64'sd0;
                        acc_40k_pre_q  <= 64'sd0;
                        acc_40k_post_i <= 64'sd0;
                        acc_40k_post_q <= 64'sd0;
                        multiply_state <= 4'd0;
                        multiply_busy  <= 1'b0;
                    end
                    default: begin
                        multiply_state <= 4'd0;
                        multiply_busy  <= 1'b0;
                    end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && enable && sample_ce && multiply_busy)
            $fatal(1, "ILA image monitor multiplier schedule overrun");
    end
`endif

endmodule
