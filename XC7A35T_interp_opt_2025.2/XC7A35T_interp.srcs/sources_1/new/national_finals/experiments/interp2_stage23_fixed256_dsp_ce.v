`timescale 1ns / 1ps

//=============================================================
// 文件名       : interp2_stage23_fixed256_dsp_ce.v
// 模块名       : interp2_stage23_fixed256_dsp_ce
// 功能简述     : 第二、三级 2 倍插值滤波器：复用或折叠运算资源完成连续插值。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================

// Experimental Stage2/3 engine for a 256x system clock.  The doubled cycle
// budget permits a simple issue/return pipeline and removes the tight 128x
// prefetch scheduler while retaining one DSP48E1 and one history RAMB18E1.
//=============================================================
// 1）模块名称：interp2_stage23_fixed256_dsp_ce
// 功能说明：第二、三级 2 倍插值滤波器：复用或折叠运算资源完成连续插值。
// 工程版本：Vivado 2025.2。
//=============================================================
module interp2_stage23_fixed256_dsp_ce #(
    parameter integer FOLD_INPUT_QUANT = 0
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    stage2_ce_out,
    input  wire signed [21:0]      stage2_x_in,
    input  wire                    stage2_x_in_valid,
    output reg  signed [21:0]      stage2_y_out,
    output reg                     stage2_y_out_valid,
    input  wire                    stage3_ce_out,
    input  wire signed [19:0]      stage3_x_in,
    input  wire                    stage3_x_in_valid,
    input  wire signed [23:0]      stage2_source_raw,
    input  wire                    stage2_source_raw_valid,
    input  wire signed [21:0]      stage3_source_raw,
    input  wire                    stage3_source_raw_valid,
    input  wire                    stage3_compensated_mode,
    output reg  signed [20:0]      stage3_y_out,
    output reg                     stage3_y_out_valid,
    output wire                    stage2_phase_dbg,
    output wire                    stage3_phase_dbg,
    output wire [2:0]              scheduler_state_dbg,
    output wire [6:0]              external_coeff_addr,
    input  wire signed [17:0]      external_coeff_data
);
    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_MAC   = 3'd1;
    localparam [2:0] ST_ROUND = 3'd2;
    localparam [2:0] ST_WRITE = 3'd3;
    localparam [2:0] ST_QMAC  = 3'd4;
    localparam [2:0] ST_QWRITE = 3'd5;

    reg [2:0] state;
    reg stage2_phase;
    reg stage3_phase;
    reg [3:0] stage2_head;
    reg [3:0] stage3_head;
    reg stage2_history_full;
    reg stage3_history_full;
    reg stage2_pending;
    reg stage3_pending;
    reg stage3_pending_compensated;

    reg job_stage3;
    reg job_phase;
    reg job_compensated;
    reg [3:0] job_head;
    reg job_history_full;
    reg [3:0] issue_index;
    reg return_valid;
    reg return_mask;
    reg [3:0] return_index;
    reg quant_stage3;
    reg quant2_pending;
    reg quant3_pending;
    reg quant2_ready;
    reg quant3_ready;
    reg signed [21:0] quant2_data;
    reg signed [19:0] quant3_data;

    wire signed [21:0] stage2_x_current = FOLD_INPUT_QUANT != 0 ?
        (quant2_ready ? quant2_data : 22'sd0) :
        (stage2_x_in_valid ? stage2_x_in : 22'sd0);
    wire signed [19:0] stage3_x_current = FOLD_INPUT_QUANT != 0 ?
        (quant3_ready ? quant3_data : 20'sd0) :
        (stage3_x_in_valid ? stage3_x_in : 20'sd0);
    wire stage2_write_event = stage2_ce_out && !stage2_phase;
    wire stage3_write_event = stage3_ce_out && !stage3_phase;
    wire [3:0] stage2_write_addr = stage2_head - 4'd1;
    wire [3:0] stage3_write_addr = stage3_head - 4'd1;
    wire history_write_enable = stage2_write_event || stage3_write_event;
    wire [4:0] history_write_addr = stage2_write_event ?
        {1'b0, stage2_write_addr} : {1'b1, stage3_write_addr};
    wire signed [21:0] history_write_data = stage2_write_event ?
        stage2_x_current : {{2{stage3_x_current[19]}}, stage3_x_current};

    wire [3:0] job_mac_count = job_stage3 ?
        (job_phase ? 4'd5 : 4'd6) :
        (job_phase ? 4'd8 : 4'd9);
    wire issue_enable = state == ST_MAC && issue_index < job_mac_count;
    wire [3:0] job_fill_from_head = (~job_head) + 4'd1;
    wire issue_mask = job_history_full || issue_index < job_fill_from_head;
    wire [4:0] history_read_addr = {
        job_stage3, job_head + issue_index
    };
    wire signed [21:0] history_read_data;

    // 例化说明：调用 nf_stage23_history_ramb18_sdp 全国赛签核子模块，完成正式数据通路中的存储、运算或控制任务。
    nf_stage23_history_ramb18_sdp u_history (
        .clk(clk),
        .read_addr(history_read_addr),
        .read_data(history_read_data),
        .write_enable(rst_n && history_write_enable),
        .write_addr(history_write_addr),
        .write_data(history_write_data)
    );

    assign external_coeff_addr = job_compensated && job_stage3 ?
        {2'b11, job_phase, issue_index} :
        {1'b0, job_stage3, job_phase, issue_index};

    wire signed [29:0] dsp_a =
        {{8{history_read_data[21]}}, history_read_data};
    wire signed [47:0] dsp_p;
    wire signed [37:0] accumulator = dsp_p[37:0];
    wire signed [22:0] quotient = accumulator >>> 15;
    wire stage2_fits = quotient[22] == quotient[21];
    wire stage3_fits = quotient[22:21] == {2{quotient[20]}};
    wire job_fits = job_stage3 ? stage3_fits : stage2_fits;
    wire job_negative = accumulator[37];
    wire launch_job = state == ST_IDLE &&
        (stage3_pending || stage2_pending);
    wire launch_quant = FOLD_INPUT_QUANT != 0 && state == ST_IDLE &&
        !stage3_pending && !stage2_pending &&
        (quant3_pending || quant2_pending);
    wire signed [21:0] quant2_truncated = stage2_source_raw >>> 2;
    wire signed [19:0] quant3_truncated = stage3_source_raw >>> 2;
    wire quant2_increment = stage2_source_raw[1] &&
        (!stage2_source_raw[23] || stage2_source_raw[0]) &&
        quant2_truncated != 22'sh1fffff;
    wire quant3_increment = stage3_source_raw[1] &&
        (!stage3_source_raw[21] || stage3_source_raw[0]) &&
        quant3_truncated != 20'sh7ffff;
    wire signed [21:0] selected_quant_truncated = quant_stage3 ?
        {{2{quant3_truncated[19]}}, quant3_truncated} :
        quant2_truncated;
    wire selected_quant_increment = quant_stage3 ?
        quant3_increment : quant2_increment;
    wire signed [29:0] quant_dsp_a =
        {{8{selected_quant_truncated[21]}}, selected_quant_truncated};
    wire signed [24:0] quant_dsp_d = selected_quant_increment ?
        25'sd1 : 25'sd0;
    wire [6:0] dsp_opmode = state == ST_ROUND ?
        7'b0001110 : 7'b0100101;
    wire dsp_ce = (state == ST_MAC && return_valid && return_mask) ||
        state == ST_ROUND || state == ST_QMAC;

    // 例化说明：调用 DSP48E1 算术原语，完成乘法、加减或累加；各控制字定义当前流水拍的运算功能。
    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
        .USE_DPORT("TRUE"), .USE_MULT("MULTIPLY"),
        .USE_PATTERN_DETECT("NO_PATDET"), .USE_SIMD("ONE48"),
        .AREG(0), .ACASCREG(0), .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(1),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_stage23_dsp48e1 (
        .P(dsp_p), .A(state == ST_QMAC ? quant_dsp_a : dsp_a),
        .B(state == ST_QMAC ? 18'sd1 : external_coeff_data),
        .C(48'sd16383), .D(state == ST_QMAC ? quant_dsp_d : 25'sd0),
        .INMODE(state == ST_QMAC ? 5'b00100 : 5'b00000),
        .OPMODE(dsp_opmode), .ALUMODE(4'b0000),
        .CARRYINSEL(3'b000),
        .CARRYIN(state == ST_ROUND && !accumulator[37]),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0), .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0), .CEALUMODE(1'b0),
        .CEB1(1'b0), .CEB2(1'b0), .CEC(1'b0), .CECARRYIN(1'b0),
        .CECTRL(1'b0), .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
        .CEP(dsp_ce), .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
        .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(!rst_n || launch_job || launch_quant),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .PATTERNBDETECT(),
        .PATTERNDETECT(), .PCOUT(), .UNDERFLOW()
    );

    assign stage2_phase_dbg = stage2_phase;
    assign stage3_phase_dbg = stage3_phase;
    assign scheduler_state_dbg = state;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            stage2_phase <= 1'b1;
            stage3_phase <= 1'b1;
            stage2_head <= 4'd0;
            stage3_head <= 4'd0;
            stage2_history_full <= 1'b0;
            stage3_history_full <= 1'b0;
            stage2_pending <= 1'b0;
            stage3_pending <= 1'b0;
            stage3_pending_compensated <= 1'b0;
            job_stage3 <= 1'b0;
            job_phase <= 1'b0;
            job_compensated <= 1'b0;
            job_head <= 4'd0;
            job_history_full <= 1'b0;
            issue_index <= 4'd0;
            return_valid <= 1'b0;
            return_mask <= 1'b0;
            return_index <= 4'd0;
            quant_stage3 <= 1'b0;
            quant2_pending <= 1'b0;
            quant3_pending <= 1'b0;
            quant2_ready <= 1'b0;
            quant3_ready <= 1'b0;
            quant2_data <= 22'sd0;
            quant3_data <= 20'sd0;
            stage2_y_out <= 22'sd0;
            stage2_y_out_valid <= 1'b0;
            stage3_y_out <= 21'sd0;
            stage3_y_out_valid <= 1'b0;
        end
        else begin
            stage2_y_out_valid <= 1'b0;
            stage3_y_out_valid <= 1'b0;
            return_valid <= issue_enable;
            if (issue_enable) begin
                return_mask <= issue_mask;
                return_index <= issue_index;
                issue_index <= issue_index + 4'd1;
            end

            if (FOLD_INPUT_QUANT != 0) begin
                if (stage2_source_raw_valid)
                    quant2_pending <= 1'b1;
                if (stage3_source_raw_valid)
                    quant3_pending <= 1'b1;
                if (stage2_write_event)
                    quant2_ready <= 1'b0;
                if (stage3_write_event)
                    quant3_ready <= 1'b0;
            end

            if (stage2_ce_out) begin
                stage2_pending <= 1'b1;
                if (!stage2_phase) begin
                    stage2_head <= stage2_write_addr;
                    if (stage2_head == 4'd8)
                        stage2_history_full <= 1'b1;
                end
                stage2_phase <= ~stage2_phase;
            end
            if (stage3_ce_out) begin
                stage3_pending <= 1'b1;
                stage3_pending_compensated <= stage3_compensated_mode;
                if (!stage3_phase) begin
                    stage3_head <= stage3_write_addr;
                    if (stage3_head == 4'd11)
                        stage3_history_full <= 1'b1;
                end
                stage3_phase <= ~stage3_phase;
            end

            if (launch_job) begin
                state <= ST_MAC;
                issue_index <= 4'd0;
                return_valid <= 1'b0;
                if (stage3_pending) begin
                    job_stage3 <= 1'b1;
                    job_phase <= ~stage3_phase;
                    job_compensated <= stage3_pending_compensated;
                    job_head <= stage3_head;
                    job_history_full <= stage3_history_full;
                    stage3_pending <= 1'b0;
                end
                else begin
                    job_stage3 <= 1'b0;
                    job_phase <= ~stage2_phase;
                    job_compensated <= 1'b0;
                    job_head <= stage2_head;
                    job_history_full <= stage2_history_full;
                    stage2_pending <= 1'b0;
                end
            end
            else if (launch_quant) begin
                state <= ST_QMAC;
                quant_stage3 <= quant3_pending;
                if (quant3_pending)
                    quant3_pending <= 1'b0;
                else
                    quant2_pending <= 1'b0;
            end
            else begin
                case (state)
                    ST_MAC: begin
                        if (return_valid &&
                            return_index == job_mac_count - 4'd1)
                            state <= ST_ROUND;
                    end
                    ST_ROUND: state <= ST_WRITE;
                    ST_WRITE: begin
                        if (job_stage3) begin
                            stage3_y_out <= job_fits ? quotient[20:0] :
                                (job_negative ? 21'sh100000 : 21'sh0fffff);
                            stage3_y_out_valid <= 1'b1;
                        end
                        else begin
                            stage2_y_out <= job_fits ? quotient[21:0] :
                                (job_negative ? 22'sh200000 : 22'sh1fffff);
                            stage2_y_out_valid <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end
                    ST_QMAC: state <= ST_QWRITE;
                    ST_QWRITE: begin
                        if (quant_stage3) begin
                            quant3_data <= dsp_p[19:0];
                            quant3_ready <= 1'b1;
                        end
                        else begin
                            quant2_data <= dsp_p[21:0];
                            quant2_ready <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n) begin
            if (stage2_write_event && stage3_write_event)
                $fatal(1, "fixed256 Stage2/3 history write collision");
            if (stage2_ce_out && stage2_pending)
                $fatal(1, "fixed256 Stage2 pending overwrite");
            if (stage3_ce_out && stage3_pending)
                $fatal(1, "fixed256 Stage3 pending overwrite");
            if (FOLD_INPUT_QUANT != 0 && stage2_source_raw_valid &&
                (quant2_pending || quant2_ready))
                $fatal(1, "fixed256 Stage2 quantizer input overwrite");
            if (FOLD_INPUT_QUANT != 0 && stage3_source_raw_valid &&
                (quant3_pending || quant3_ready))
                $fatal(1, "fixed256 Stage3 quantizer input overwrite");
            if (FOLD_INPUT_QUANT != 0 && stage2_write_event && !quant2_ready)
                $fatal(1, "fixed256 Stage2 quantizer deadline miss");
            if (FOLD_INPUT_QUANT != 0 && stage3_write_event && !quant3_ready)
                $fatal(1, "fixed256 Stage3 quantizer deadline miss");
        end
    end
`endif
endmodule
