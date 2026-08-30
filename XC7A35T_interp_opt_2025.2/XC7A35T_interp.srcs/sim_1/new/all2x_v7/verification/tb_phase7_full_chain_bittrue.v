`timescale 1ns / 1ps

//=============================================================
// 文件名       : tb_phase7_full_chain_bittrue.v
// 模块名       : tb_phase7_full_chain_bittrue
// 功能简述     : Phase 7 正式折叠补偿顶层的端到端位真回归。
//                从24bit输入开始，直接实例化比赛使用的 N=3
//                FIR-CIC 顶层，同时比较4x、8x和128x三个节点。
//                测试包含半满幅冲激和4组固定种子随机PCM，
//                所有节点固定延迟、输出数量和数值均严格检查。
//
// 当前默认配置：
//                  日常规模：4 seed x 1024 input
//                  发布规模：10 seed x 4096 input
//                  固定偏移：4x=3，8x=7，128x=112
//                  比较标准：0 LSB，不允许X
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-14
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     :
//                2026-07-14：新增正式顶层端到端位真回归。
//                2026-07-18：增加单读 LUTRAM Stage 2/3 候选开关。
//                2026-07-18：增加 Phase 8 交叉系数 BRAM 打包开关。
//=============================================================
//=============================================================
// 1）模块名称：tb_phase7_full_chain_bittrue
// 功能说明：仿真测试平台：产生激励、监视被测模块输出并执行自动判定。
// 工程版本：Vivado 2025.2。
//=============================================================

module tb_phase7_full_chain_bittrue;

`ifdef NF_WORDLENGTH_24_22_20
    localparam integer DUT_STAGE2_DATA_W = 22;
`else
    localparam integer DUT_STAGE2_DATA_W = 20;
`endif

`ifdef NF_RELEASE_REGRESSION
    localparam integer MAX_INPUT_COUNT = 4096;
    localparam integer MAX_Y4_COUNT = 16605;
    localparam integer MAX_Y8_COUNT = 33219;
    localparam integer MAX_Y128_COUNT = 531584;
    localparam integer RANDOM_INPUT_COUNT = 4096;
    localparam integer RANDOM_Y4_COUNT = 16605;
    localparam integer RANDOM_Y8_COUNT = 33219;
    localparam integer RANDOM_Y128_COUNT = 531584;
    localparam integer CASE_COUNT = 14;
`else
    localparam integer MAX_INPUT_COUNT = 1024;
    localparam integer MAX_Y4_COUNT = 4317;
    localparam integer MAX_Y8_COUNT = 8643;
    localparam integer MAX_Y128_COUNT = 138368;
    localparam integer RANDOM_INPUT_COUNT = 1024;
    localparam integer RANDOM_Y4_COUNT = 4317;
    localparam integer RANDOM_Y8_COUNT = 8643;
    localparam integer RANDOM_Y128_COUNT = 138368;
    localparam integer CASE_COUNT = 2;
`endif
    localparam integer IMPULSE_INPUT_COUNT = 256;
    localparam integer IMPULSE_Y4_COUNT = 1245;
    localparam integer IMPULSE_Y8_COUNT = 2499;
    localparam integer IMPULSE_Y128_COUNT = 40064;
    localparam integer STRONG_INPUT_COUNT = 2048;
    localparam integer STRONG_Y4_COUNT = 8413;
    localparam integer STRONG_Y8_COUNT = 16835;
    localparam integer STRONG_Y128_COUNT = 269440;
    localparam integer SHIFT_4X = 3;
    localparam integer SHIFT_8X = 7;
    localparam integer SHIFT_128X = 112;
    localparam integer IR_LEN_4X = 225;
    localparam integer IR_LEN_8X = 459;
    localparam integer IR_LEN_128X = 7406;

    reg clk;
    reg rst_n;
    reg [6:0] ce_cnt;
    reg input_phase;
    reg signed [23:0] x_in;
    reg x_in_valid;
    reg signed [23:0] input_mem [0:MAX_INPUT_COUNT-1];
    reg signed [23:0] y4_expected [0:MAX_Y4_COUNT-1];
    reg signed [23:0] y8_expected [0:MAX_Y8_COUNT-1];
    reg signed [23:0] y128_expected [0:MAX_Y128_COUNT-1];

    integer active_case;
    integer active_input_count;
    integer expected_y4_count;
    integer expected_y8_count;
    integer expected_y128_count;
    integer input_index;
    integer y4_skip_count;
    integer y8_skip_count;
    integer y128_skip_count;
    integer y4_index;
    integer y8_index;
    integer y128_index;
    integer mismatch_count;
    integer timeout_count;
    integer case_index;
    integer impulse_y4_file;
    integer impulse_y8_file;
    integer impulse_y128_file;

    wire ce2_out = (ce_cnt[5:0] == 6'b000000);
    wire ce4_out = (ce_cnt[4:0] == 5'b00000);
    wire ce8_out = (ce_cnt[3:0] == 4'b0000);
    wire ce16_out = (ce_cnt[2:0] == 3'b000);
    wire ce32_out = (ce_cnt[1:0] == 2'b00);
    wire ce64_out = (ce_cnt[0] == 1'b0);
    wire ce128_out = 1'b1;

    wire signed [23:0] y_out;
    wire y_out_valid;
    wire signed [23:0] dbg_y4;
    wire dbg_y4_valid;
    wire signed [23:0] dbg_y8;
    wire dbg_y8_valid;

    // 例化说明：调用 nf_signedoff_filter_core 全国赛签核子模块，完成正式数据通路中的存储、运算或控制任务。
    nf_signedoff_filter_core #(
        .STAGE2_DATA_W(DUT_STAGE2_DATA_W)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .ce2_out(ce2_out), .ce4_out(ce4_out),
        .ce8_out(ce8_out), .ce16_out(ce16_out),
        .ce32_out(ce32_out), .ce64_out(ce64_out),
        .ce128_out(ce128_out),
        .x_in(x_in), .x_in_valid(x_in_valid),
        .y_out(y_out), .y_out_valid(y_out_valid),
        .dbg_y2(), .dbg_y2_valid(),
        .dbg_y4(dbg_y4), .dbg_y4_valid(dbg_y4_valid),
        .dbg_y8(dbg_y8), .dbg_y8_valid(dbg_y8_valid),
        .dbg_y16(), .dbg_y16_valid(),
        .dbg_y32(), .dbg_y32_valid(),
        .dbg_y64(), .dbg_y64_valid()
    );

    initial begin
        clk = 1'b0;
        forever #10.416667 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ce_cnt <= 7'd0;
            input_phase <= 1'b1;
            input_index <= 0;
            x_in <= input_mem[0];
        end
        else begin
            ce_cnt <= ce_cnt + 7'd1;
            if (ce2_out) begin
                if (input_phase == 1'b0) begin
                    input_index <= input_index + 1;
                    if (input_index + 1 < active_input_count)
                        x_in <= input_mem[input_index + 1];
                    else
                        x_in <= 24'sd0;
                end
                input_phase <= ~input_phase;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y4_skip_count <= 0;
            y8_skip_count <= 0;
            y128_skip_count <= 0;
            y4_index <= 0;
            y8_index <= 0;
            y128_index <= 0;
            mismatch_count <= 0;
        end
        else if (active_case != 0) begin
            if (dbg_y4_valid) begin
                if (^dbg_y4 === 1'bx)
                    report_unknown(4, y4_index);
                else if (y4_skip_count < SHIFT_4X) begin
                    if (dbg_y4 !== 24'sd0)
                        report_mismatch(4, y4_skip_count-SHIFT_4X,
                            dbg_y4, 24'sd0);
                    y4_skip_count <= y4_skip_count + 1;
                end
                else if (y4_index < expected_y4_count) begin
                    if (dbg_y4 !== y4_expected[y4_index])
                        report_mismatch(4, y4_index, dbg_y4,
                            y4_expected[y4_index]);
                    if (active_case == 1 && y4_index < IR_LEN_4X)
                        $fdisplay(impulse_y4_file, "%0d", $signed(dbg_y4));
                    y4_index <= y4_index + 1;
                end
            end

            if (dbg_y8_valid) begin
                if (^dbg_y8 === 1'bx)
                    report_unknown(8, y8_index);
                else if (y8_skip_count < SHIFT_8X) begin
                    if (dbg_y8 !== 24'sd0)
                        report_mismatch(8, y8_skip_count-SHIFT_8X,
                            dbg_y8, 24'sd0);
                    y8_skip_count <= y8_skip_count + 1;
                end
                else if (y8_index < expected_y8_count) begin
                    if (dbg_y8 !== y8_expected[y8_index])
                        report_mismatch(8, y8_index, dbg_y8,
                            y8_expected[y8_index]);
                    if (active_case == 1 && y8_index < IR_LEN_8X)
                        $fdisplay(impulse_y8_file, "%0d", $signed(dbg_y8));
                    y8_index <= y8_index + 1;
                end
            end

            if (y_out_valid) begin
                if (^y_out === 1'bx)
                    report_unknown(128, y128_index);
                else if (y128_skip_count < SHIFT_128X) begin
                    if (y_out !== 24'sd0)
                        report_mismatch(128,
                            y128_skip_count-SHIFT_128X, y_out, 24'sd0);
                    y128_skip_count <= y128_skip_count + 1;
                end
                else if (y128_index < expected_y128_count) begin
                    if (y_out !== y128_expected[y128_index])
                        report_mismatch(128, y128_index, y_out,
                            y128_expected[y128_index]);
                    if (active_case == 1 && y128_index < IR_LEN_128X)
                        $fdisplay(impulse_y128_file, "%0d", $signed(y_out));
                    y128_index <= y128_index + 1;
                end
            end
        end
    end

    task report_mismatch;
        input integer rate_value;
        input integer sample_index;
        input signed [23:0] actual_value;
        input signed [23:0] expected_value;
        begin
            mismatch_count = mismatch_count + 1;
            if (mismatch_count <= 20)
                $display("Mismatch case=%0d rate=%0dx index=%0d actual=%0d expected=%0d",
                    active_case, rate_value, sample_index,
                    actual_value, expected_value);
        end
    endtask

    task require_asset;
        input [8*96-1:0] filename;
        integer asset_file;
        begin
            asset_file = $fopen(filename, "r");
            if (asset_file == 0)
                $fatal(1, "NF_ASSET_MISSING: %0s", filename);
            $fclose(asset_file);
        end
    endtask

    task preflight_assets;
        begin
            require_asset("impulse_input_24bit.mem");
            require_asset("impulse_y4_golden_24bit.mem");
            require_asset("impulse_y8_golden_24bit.mem");
            require_asset("impulse_y128_golden_24bit.mem");
            require_asset("random_seed01_input_24bit.mem");
            require_asset("random_seed01_y4_golden_24bit.mem");
            require_asset("random_seed01_y8_golden_24bit.mem");
            require_asset("random_seed01_y128_golden_24bit.mem");
`ifdef NF_RELEASE_REGRESSION
            require_asset("random_seed02_input_24bit.mem");
            require_asset("random_seed02_y4_golden_24bit.mem");
            require_asset("random_seed02_y8_golden_24bit.mem");
            require_asset("random_seed02_y128_golden_24bit.mem");
            require_asset("random_seed03_input_24bit.mem");
            require_asset("random_seed03_y4_golden_24bit.mem");
            require_asset("random_seed03_y8_golden_24bit.mem");
            require_asset("random_seed03_y128_golden_24bit.mem");
            require_asset("random_seed04_input_24bit.mem");
            require_asset("random_seed04_y4_golden_24bit.mem");
            require_asset("random_seed04_y8_golden_24bit.mem");
            require_asset("random_seed04_y128_golden_24bit.mem");
            require_asset("random_seed05_input_24bit.mem");
            require_asset("random_seed05_y4_golden_24bit.mem");
            require_asset("random_seed05_y8_golden_24bit.mem");
            require_asset("random_seed05_y128_golden_24bit.mem");
            require_asset("random_seed06_input_24bit.mem");
            require_asset("random_seed06_y4_golden_24bit.mem");
            require_asset("random_seed06_y8_golden_24bit.mem");
            require_asset("random_seed06_y128_golden_24bit.mem");
            require_asset("random_seed07_input_24bit.mem");
            require_asset("random_seed07_y4_golden_24bit.mem");
            require_asset("random_seed07_y8_golden_24bit.mem");
            require_asset("random_seed07_y128_golden_24bit.mem");
            require_asset("random_seed08_input_24bit.mem");
            require_asset("random_seed08_y4_golden_24bit.mem");
            require_asset("random_seed08_y8_golden_24bit.mem");
            require_asset("random_seed08_y128_golden_24bit.mem");
            require_asset("random_seed09_input_24bit.mem");
            require_asset("random_seed09_y4_golden_24bit.mem");
            require_asset("random_seed09_y8_golden_24bit.mem");
            require_asset("random_seed09_y128_golden_24bit.mem");
            require_asset("random_seed10_input_24bit.mem");
            require_asset("random_seed10_y4_golden_24bit.mem");
            require_asset("random_seed10_y8_golden_24bit.mem");
            require_asset("random_seed10_y128_golden_24bit.mem");
            require_asset("fullscale_positive_input_24bit.mem");
            require_asset("fullscale_positive_y4_golden_24bit.mem");
            require_asset("fullscale_positive_y8_golden_24bit.mem");
            require_asset("fullscale_positive_y128_golden_24bit.mem");
            require_asset("fullscale_negative_input_24bit.mem");
            require_asset("fullscale_negative_y4_golden_24bit.mem");
            require_asset("fullscale_negative_y8_golden_24bit.mem");
            require_asset("fullscale_negative_y128_golden_24bit.mem");
            require_asset("strong_44k1_minus1dbfs_input_24bit.mem");
            require_asset("strong_44k1_minus1dbfs_y4_golden_24bit.mem");
            require_asset("strong_44k1_minus1dbfs_y8_golden_24bit.mem");
            require_asset("strong_44k1_minus1dbfs_y128_golden_24bit.mem");
`endif
        end
    endtask

    task report_unknown;
        input integer rate_value;
        input integer sample_index;
        begin
            mismatch_count = mismatch_count + 1;
            $display("Unknown output case=%0d rate=%0dx index=%0d",
                active_case, rate_value, sample_index);
        end
    endtask

    task apply_reset;
        begin
            rst_n = 1'b0;
            x_in_valid = 1'b0;
            repeat (8) @(negedge clk);
            rst_n = 1'b1;
            x_in_valid = 1'b1;
            repeat (4) @(negedge clk);
        end
    endtask

    task load_case;
        input integer case_value;
        begin
            case (case_value)
                1: begin
                    $readmemh("impulse_input_24bit.mem", input_mem);
                    $readmemh("impulse_y4_golden_24bit.mem", y4_expected);
                    $readmemh("impulse_y8_golden_24bit.mem", y8_expected);
                    $readmemh("impulse_y128_golden_24bit.mem", y128_expected);
                    active_input_count = IMPULSE_INPUT_COUNT;
                    expected_y4_count = IMPULSE_Y4_COUNT;
                    expected_y8_count = IMPULSE_Y8_COUNT;
                    expected_y128_count = IMPULSE_Y128_COUNT;
                end
                2: begin
                    $readmemh("random_seed01_input_24bit.mem", input_mem);
                    $readmemh("random_seed01_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed01_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed01_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                3: begin
                    $readmemh("random_seed02_input_24bit.mem", input_mem);
                    $readmemh("random_seed02_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed02_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed02_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                4: begin
                    $readmemh("random_seed03_input_24bit.mem", input_mem);
                    $readmemh("random_seed03_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed03_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed03_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                5: begin
                    $readmemh("random_seed04_input_24bit.mem", input_mem);
                    $readmemh("random_seed04_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed04_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed04_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                6: begin
                    $readmemh("random_seed05_input_24bit.mem", input_mem);
                    $readmemh("random_seed05_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed05_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed05_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                7: begin
                    $readmemh("random_seed06_input_24bit.mem", input_mem);
                    $readmemh("random_seed06_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed06_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed06_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                8: begin
                    $readmemh("random_seed07_input_24bit.mem", input_mem);
                    $readmemh("random_seed07_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed07_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed07_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                9: begin
                    $readmemh("random_seed08_input_24bit.mem", input_mem);
                    $readmemh("random_seed08_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed08_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed08_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                10: begin
                    $readmemh("random_seed09_input_24bit.mem", input_mem);
                    $readmemh("random_seed09_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed09_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed09_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                11: begin
                    $readmemh("random_seed10_input_24bit.mem", input_mem);
                    $readmemh("random_seed10_y4_golden_24bit.mem", y4_expected);
                    $readmemh("random_seed10_y8_golden_24bit.mem", y8_expected);
                    $readmemh("random_seed10_y128_golden_24bit.mem", y128_expected);
                    active_input_count = RANDOM_INPUT_COUNT;
                    expected_y4_count = RANDOM_Y4_COUNT;
                    expected_y8_count = RANDOM_Y8_COUNT;
                    expected_y128_count = RANDOM_Y128_COUNT;
                end
                12: begin
                    $readmemh("fullscale_positive_input_24bit.mem", input_mem);
                    $readmemh("fullscale_positive_y4_golden_24bit.mem", y4_expected);
                    $readmemh("fullscale_positive_y8_golden_24bit.mem", y8_expected);
                    $readmemh("fullscale_positive_y128_golden_24bit.mem", y128_expected);
                    active_input_count = IMPULSE_INPUT_COUNT;
                    expected_y4_count = IMPULSE_Y4_COUNT;
                    expected_y8_count = IMPULSE_Y8_COUNT;
                    expected_y128_count = IMPULSE_Y128_COUNT;
                end
                13: begin
                    $readmemh("fullscale_negative_input_24bit.mem", input_mem);
                    $readmemh("fullscale_negative_y4_golden_24bit.mem", y4_expected);
                    $readmemh("fullscale_negative_y8_golden_24bit.mem", y8_expected);
                    $readmemh("fullscale_negative_y128_golden_24bit.mem", y128_expected);
                    active_input_count = IMPULSE_INPUT_COUNT;
                    expected_y4_count = IMPULSE_Y4_COUNT;
                    expected_y8_count = IMPULSE_Y8_COUNT;
                    expected_y128_count = IMPULSE_Y128_COUNT;
                end
                14: begin
                    $readmemh("strong_44k1_minus1dbfs_input_24bit.mem", input_mem);
                    $readmemh("strong_44k1_minus1dbfs_y4_golden_24bit.mem", y4_expected);
                    $readmemh("strong_44k1_minus1dbfs_y8_golden_24bit.mem", y8_expected);
                    $readmemh("strong_44k1_minus1dbfs_y128_golden_24bit.mem", y128_expected);
                    active_input_count = STRONG_INPUT_COUNT;
                    expected_y4_count = STRONG_Y4_COUNT;
                    expected_y8_count = STRONG_Y8_COUNT;
                    expected_y128_count = STRONG_Y128_COUNT;
                end
                default: begin
                    $fatal(1, "Unsupported full-chain case=%0d", case_value);
                end
            endcase
        end
    endtask

    task run_case;
        input integer case_value;
        begin
            active_case = 0;
            load_case(case_value);
            active_case = case_value;
            apply_reset();

            timeout_count = 0;
            while ((y128_index < expected_y128_count ||
                    y8_index < expected_y8_count ||
                    y4_index < expected_y4_count) &&
                   timeout_count < expected_y128_count + 200000) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (y4_index != expected_y4_count ||
                    y8_index != expected_y8_count ||
                    y128_index != expected_y128_count) begin
                $display("Count error case=%0d y4=%0d/%0d y8=%0d/%0d y128=%0d/%0d",
                    case_value, y4_index, expected_y4_count,
                    y8_index, expected_y8_count,
                    y128_index, expected_y128_count);
                mismatch_count = mismatch_count + 1;
            end
            if (y4_skip_count != SHIFT_4X ||
                    y8_skip_count != SHIFT_8X ||
                    y128_skip_count != SHIFT_128X) begin
                $display("Fixed shift error case=%0d shift=%0d/%0d/%0d",
                    case_value, y4_skip_count,
                    y8_skip_count, y128_skip_count);
                mismatch_count = mismatch_count + 1;
            end
            if (mismatch_count != 0)
                $fatal(1, "PHASE7 FULL CHAIN case=%0d FAIL mismatch=%0d",
                    case_value, mismatch_count);
            $display("PHASE7 FULL CHAIN case=%0d PASS y4=%0d y8=%0d y128=%0d",
                case_value, y4_index, y8_index, y128_index);
            active_case = 0;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        x_in = 24'sd0;
        x_in_valid = 1'b0;
        active_case = 0;
        active_input_count = 0;
        expected_y4_count = 0;
        expected_y8_count = 0;
        expected_y128_count = 0;

        preflight_assets();

        impulse_y4_file = $fopen("rtl_impulse_y4.csv", "w");
        impulse_y8_file = $fopen("rtl_impulse_y8.csv", "w");
        impulse_y128_file = $fopen("rtl_impulse_y128.csv", "w");
        if (impulse_y4_file == 0 || impulse_y8_file == 0 ||
                impulse_y128_file == 0)
            $fatal(1, "Unable to create RTL impulse CSV files");

        run_case(1);
        $fclose(impulse_y4_file);
        $fclose(impulse_y8_file);
        $fclose(impulse_y128_file);
        for (case_index = 2; case_index <= CASE_COUNT;
             case_index = case_index + 1)
            run_case(case_index);

`ifdef NF_RELEASE_REGRESSION
        $display("PHASE7 FULL CHAIN BITTRUE PASS: impulse + 10 seeds + 2 fullscale + strong -1 dBFS, reset-zero prefixes and all nodes 0 LSB.");
`else
        $display("PHASE7 FULL CHAIN BITTRUE PASS: impulse + 1 seeds, reset-zero prefixes and all nodes 0 LSB.");
`endif
        $finish;
    end

endmodule
