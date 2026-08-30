`timescale 1ns / 1ps

//=============================================================
// 文件名       : nf_interp_fir3_shared_preg_256x_ce.v
// 模块名       : nf_interp_fir3_shared_preg_256x_ce
// 功能简述     : 三级共享 FIR 运算单元：复用 DSP 乘加通路完成插值滤波。
// 设计说明     : 本文件采用同步时序设计；复位、时钟使能、
//                有效信号和定点位宽关系均在对应代码段说明。
//                注释仅用于阐明实现，不参与综合结果。
// 设计作者     : kafeizizi
// 版本         : V2025.2
// 开发工具     : Vivado 2025.2
// 修订记录     : 2026-08-30：统一中文文件头、模块编号与结构说明。
//=============================================================

// Isolated 256x shared-FIR redesign seed; not part of the formal project.
//
// One DSP48E1 multiplier is shared by Stage1, Stage2 and Stage3.  The running
// sums live in two fabric registers: one persistent Stage1 context (so the
// long 26-MAC job may be preempted), and one non-preempted Stage2/3 context.
// Stage3 has highest priority, Stage2 is second, and Stage1 consumes the idle
// slots.  A completed short job is rounded with the common fabric adder while
// the DSP starts the first multiply of the next job in the same clock.
//
// This module is deliberately fixed to the verified national-finals word
// lengths and flat Stage3 coefficients.  The original dual-DSP path remains
// available in the parent top-level as the rollback implementation.
//=============================================================
// 1）模块名称：nf_interp_fir3_shared_preg_256x_ce
// 功能说明：三级共享 FIR 运算单元：复用 DSP 乘加通路完成插值滤波。
// 工程版本：Vivado 2025.2。
//=============================================================
module nf_interp_fir3_shared_preg_256x_ce (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ce2_out,
    input  wire                         ce4_out,
    input  wire                         ce8_out,
    input  wire signed [23:0]           x_in,
    input  wire                         x_in_valid,
    output reg  signed [23:0]           y2_out,
    output reg                          y2_out_valid,
    output reg  signed [21:0]           y4_out,
    output reg                          y4_out_valid,
    output reg  signed [19:0]           y8_out,
    output reg                          y8_out_valid,
    output wire [1:0]                   scheduler_owner_dbg,
    output wire [5:0]                   scheduler_index_dbg,
    output wire                         stage1_pending_dbg,
    output wire                         stage2_pending_dbg,
    output wire                         stage3_pending_dbg
);

    localparam integer ACC_W = 42;
    localparam integer FRAC_W = 15;
    localparam integer S1_HISTORY_LEN = 52;
    localparam integer S1_PAIR_COUNT = 26;
    localparam integer S1_DELAY_INDEX = 25;
    localparam integer S1_RAM_DEPTH = 64;
    localparam integer S23_RAM_DEPTH = 16;

    localparam signed [23:0] S1_OUT_MAX = 24'sh7fffff;
    localparam signed [23:0] S1_OUT_MIN = -24'sh800000;
    localparam signed [21:0] S2_OUT_MAX = 22'sh1fffff;
    localparam signed [21:0] S2_OUT_MIN = -22'sh200000;
    localparam signed [19:0] S3_OUT_MAX = 20'sh7ffff;
    localparam signed [19:0] S3_OUT_MIN = -20'sh80000;

    // ------------------------------------------------------------------
    // Stage1 true-dual-port history and polyphase state.
    // ------------------------------------------------------------------
    (* ram_style = "block" *)
    reg signed [23:0] s1_history [0:S1_RAM_DEPTH-1];
    reg signed [23:0] s1_read_a;
    reg signed [23:0] s1_read_b;
    reg [5:0] s1_wr_ptr;
    reg [5:0] s1_fill_count;
    reg s1_phase;
    reg signed [23:0] s1_delay_result;
    reg s1_delay_ready;
    reg s1_delay_capture_pending;

    reg s1_pending;
    reg s1_prefetched;
    reg s1_active;
    reg [5:0] s1_job_base;
    reg [5:0] s1_job_fill;
    reg [4:0] s1_mac_index;
    reg signed [ACC_W-1:0] s1_accumulator;
    reg s1_round_pending;
    reg signed [23:0] s1_filter_result;
    reg s1_filter_ready;

    wire signed [23:0] s1_x_current;
    wire [4:0] s1_process_index;
    wire [4:0] s1_read_index;
    wire [5:0] s1_read_addr_a;
    wire [5:0] s1_read_addr_b;
    wire [5:0] s1_delay_read_addr;
    wire s1_mask_a;
    wire s1_mask_b;
    wire signed [24:0] s1_pair_sum;
    wire [4:0] s1_coeff_addr;
    wire signed [15:0] s1_coeff_data;

    assign s1_x_current = x_in_valid ? x_in : 24'sd0;
    assign s1_process_index = s1_active ? s1_mac_index : 5'd0;

    // ------------------------------------------------------------------
    // Stage2/3 histories, phase queues and one shared short-job context.
    // ------------------------------------------------------------------
    (* ram_style = "block" *)
    reg signed [21:0] s2_history [0:S23_RAM_DEPTH-1];
    (* ram_style = "block" *)
    reg signed [19:0] s3_history [0:S23_RAM_DEPTH-1];
    reg signed [21:0] s2_read_data;
    reg signed [19:0] s3_read_data;
    reg [3:0] s2_head;
    reg [3:0] s3_head;
    reg [3:0] s2_fill_count;
    reg [3:0] s3_fill_count;
    reg s2_phase;
    reg s3_phase;

    reg s2_pending;
    reg s3_pending;
    reg s2_pending_phase;
    reg s3_pending_phase;
    reg [3:0] s2_pending_head;
    reg [3:0] s3_pending_head;
    reg [3:0] s2_pending_fill;
    reg [3:0] s3_pending_fill;
    reg signed [21:0] s2_pending_first;
    reg signed [19:0] s3_pending_first;

    reg short_active;
    reg short_stage3;
    reg short_phase;
    reg [3:0] short_mac_index;
    reg [3:0] short_mac_count;
    reg [3:0] short_history_head;
    reg [3:0] short_fill_count;
    reg signed [21:0] short_first_sample;
    reg signed [ACC_W-1:0] short_accumulator;
    reg short_round_pending;
    reg short_round_stage3;

    wire signed [21:0] y2_to_s2_data;
    wire y2_to_s2_valid;
    wire signed [19:0] y4_to_s3_data;
    wire y4_to_s3_valid;
    wire signed [21:0] s2_x_current;
    wire signed [19:0] s3_x_current;
    wire [3:0] s2_write_addr;
    wire [3:0] s3_write_addr;
    wire [3:0] s2_arrival_head;
    wire [3:0] s3_arrival_head;
    wire [3:0] s2_arrival_fill;
    wire [3:0] s3_arrival_fill;

    wire launch_stage3;
    wire launch_stage2;
    wire launch_short;
    wire launch_phase;
    wire [3:0] launch_head;
    wire [3:0] launch_fill;
    wire [3:0] launch_mac_count;
    wire signed [21:0] launch_first_sample;

    wire [3:0] short_process_index;
    wire [3:0] short_process_count;
    wire short_process_stage3;
    wire short_process_phase;
    wire [3:0] short_process_head;
    wire [3:0] short_process_fill;
    wire signed [21:0] short_process_first;
    wire [3:0] s2_prefetch_index;
    wire [3:0] s3_prefetch_index;
    wire [3:0] s2_read_addr;
    wire [3:0] s3_read_addr;
    wire signed [21:0] short_history_sample;
    wire signed [15:0] short_coeff;

    // 例化说明：调用 bridge_valid_quantized_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(24), .OUT_W(22), .SHIFT_N(2)
    ) u_bridge_s1_to_s2 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y2_out), .in_valid(y2_out_valid),
        .ce_out_next(ce4_out),
        .out_data(y2_to_s2_data), .out_valid(y2_to_s2_valid)
    );

    // 例化说明：调用 bridge_valid_quantized_to_interp2_ce 子模块，承担本级数据通路或控制链中的对应功能；参数和端口连接见下方。
    bridge_valid_quantized_to_interp2_ce #(
        .IN_W(22), .OUT_W(20), .SHIFT_N(2)
    ) u_bridge_s2_to_s3 (
        .clk(clk), .rst_n(rst_n),
        .in_data(y4_out), .in_valid(y4_out_valid),
        .ce_out_next(ce8_out),
        .out_data(y4_to_s3_data), .out_valid(y4_to_s3_valid)
    );

    assign s2_x_current = y2_to_s2_valid ? y2_to_s2_data : 22'sd0;
    assign s3_x_current = y4_to_s3_valid ? y4_to_s3_data : 20'sd0;
    assign s2_write_addr = s2_head - 4'd1;
    assign s3_write_addr = s3_head - 4'd1;
    assign s2_arrival_head = (s2_phase == 1'b0) ? s2_write_addr : s2_head;
    assign s3_arrival_head = (s3_phase == 1'b0) ? s3_write_addr : s3_head;
    assign s2_arrival_fill = (s2_phase == 1'b0 && s2_fill_count < 4'd9) ?
                             s2_fill_count + 4'd1 : s2_fill_count;
    assign s3_arrival_fill = (s3_phase == 1'b0 && s3_fill_count < 4'd6) ?
                             s3_fill_count + 4'd1 : s3_fill_count;

    // A pending Stage3 job always precedes Stage2.  Launching is allowed in
    // the same cycle that the previous short job is rounded because the new
    // first product does not use the fabric accumulator adder.
    assign launch_stage3 = !short_active && s3_pending;
    assign launch_stage2 = !short_active && !s3_pending && s2_pending;
    assign launch_short = launch_stage3 || launch_stage2;
    assign launch_phase = launch_stage3 ? s3_pending_phase : s2_pending_phase;
    assign launch_head = launch_stage3 ? s3_pending_head : s2_pending_head;
    assign launch_fill = launch_stage3 ? s3_pending_fill : s2_pending_fill;
    // Keep the completion phase deterministic.  Odd polyphases naturally
    // contain one fewer nonzero coefficient; executing one final zero-coeff
    // MAC prevents the 9/8 and 6/5 cycle jitter from overwriting the existing
    // valid-only inter-stage bridge.  The fixed schedule is still only
    // 123/128 clocks in the worst supercycle.
    assign launch_mac_count = launch_stage3 ? 4'd6 : 4'd9;
    assign launch_first_sample = launch_stage3 ?
        {{2{s3_pending_first[19]}}, s3_pending_first} : s2_pending_first;

    assign short_process_index = short_active ? short_mac_index : 4'd0;
    assign short_process_count = short_active ? short_mac_count :
                                 launch_mac_count;
    assign short_process_stage3 = short_active ? short_stage3 : launch_stage3;
    assign short_process_phase = short_active ? short_phase : launch_phase;
    assign short_process_head = short_active ? short_history_head : launch_head;
    assign short_process_fill = short_active ? short_fill_count : launch_fill;
    assign short_process_first = short_active ? short_first_sample :
                                  launch_first_sample;

    // Each BRAM bank prefetches independently.  A waiting job holds index0;
    // the cycle that launches index0 simultaneously requests index1.
    assign s2_prefetch_index =
        (short_active && !short_stage3) ?
            ((short_mac_index + 4'd1 < short_mac_count) ?
             short_mac_index + 4'd1 : short_mac_index) :
        (launch_stage2 ? 4'd1 : 4'd0);
    assign s3_prefetch_index =
        (short_active && short_stage3) ?
            ((short_mac_index + 4'd1 < short_mac_count) ?
             short_mac_index + 4'd1 : short_mac_index) :
        (launch_stage3 ? 4'd1 : 4'd0);
    assign s2_read_addr =
        (short_active && !short_stage3) ?
            short_history_head + s2_prefetch_index :
        (s2_pending ? s2_pending_head + s2_prefetch_index : s2_head);
    assign s3_read_addr =
        (short_active && short_stage3) ?
            short_history_head + s3_prefetch_index :
        (s3_pending ? s3_pending_head + s3_prefetch_index : s3_head);

    assign short_history_sample =
        (short_process_index == 4'd0 && !short_process_phase) ?
            short_process_first :
        ((short_process_index >= short_process_fill) ? 22'sd0 :
         (short_process_stage3 ?
          {{2{s3_read_data[19]}}, s3_read_data} : s2_read_data));

    // The flat national-finals Stage2/3 coefficient sequences.  A small
    // combinational selector avoids a second synchronous coefficient port in
    // the first shared-MAC prototype; synthesis decides its exact LUT cost.
    function signed [15:0] select_short_coeff;
        input stage3_sel;
        input phase_sel;
        input [3:0] index_sel;
        begin
            select_short_coeff = 16'sd0;
            if (!stage3_sel && !phase_sel) begin
                case (index_sel)
                    4'd0: select_short_coeff = -16'sd115;
                    4'd1: select_short_coeff = 16'sd534;
                    4'd2: select_short_coeff = -16'sd1302;
                    4'd3: select_short_coeff = 16'sd2116;
                    4'd4: select_short_coeff = 16'sd30298;
                    4'd5: select_short_coeff = 16'sd2116;
                    4'd6: select_short_coeff = -16'sd1302;
                    4'd7: select_short_coeff = 16'sd534;
                    4'd8: select_short_coeff = -16'sd115;
                    default: select_short_coeff = 16'sd0;
                endcase
            end
            else if (!stage3_sel && phase_sel) begin
                case (index_sel)
                    4'd0: select_short_coeff = -16'sd203;
                    4'd1: select_short_coeff = 16'sd1233;
                    4'd2: select_short_coeff = -16'sd4595;
                    4'd3: select_short_coeff = 16'sd19945;
                    4'd4: select_short_coeff = 16'sd19945;
                    4'd5: select_short_coeff = -16'sd4595;
                    4'd6: select_short_coeff = 16'sd1233;
                    4'd7: select_short_coeff = -16'sd203;
                    default: select_short_coeff = 16'sd0;
                endcase
            end
            else if (stage3_sel && !phase_sel) begin
                case (index_sel)
                    // Current signed-off flat Stage3 Q15 coefficients.  The
                    // abandoned v1 prototype accidentally used half-scale
                    // values here, which produced a deterministic -6.02 dB
                    // error at the 8x node.
                    4'd0: select_short_coeff = 16'sd404;
                    4'd1: select_short_coeff = -16'sd3272;
                    4'd2: select_short_coeff = 16'sd19250;
                    4'd3: select_short_coeff = 16'sd19250;
                    4'd4: select_short_coeff = -16'sd3272;
                    4'd5: select_short_coeff = 16'sd404;
                    default: select_short_coeff = 16'sd0;
                endcase
            end
            else begin
                case (index_sel)
                    4'd0: select_short_coeff = -16'sd148;
                    4'd1: select_short_coeff = 16'sd522;
                    4'd2: select_short_coeff = 16'sd32016;
                    4'd3: select_short_coeff = 16'sd522;
                    4'd4: select_short_coeff = -16'sd148;
                    default: select_short_coeff = 16'sd0;
                endcase
            end
        end
    endfunction

    assign short_coeff = select_short_coeff(
        short_process_stage3, short_process_phase, short_process_index);

    // ------------------------------------------------------------------
    // Shared multiplier and common fabric accumulator/rounding adder.
    // ------------------------------------------------------------------
    wire short_mac_cycle;
    wire s1_can_run;
    wire s1_mac_cycle;
    wire s1_first_mac;
    wire short_first_mac;
    wire dsp_uses_short;
    wire signed [29:0] dsp_input_a;
    wire signed [17:0] dsp_input_b;
    wire signed [47:0] dsp_product_full;
    wire signed [ACC_W-1:0] dsp_product;
    wire do_s1_round;
    wire do_short_round;
    wire signed [ACC_W-1:0] add_lhs;
    wire signed [ACC_W-1:0] add_rhs;
    wire signed [ACC_W-1:0] shared_add_result;
    wire signed [ACC_W-FRAC_W-1:0] rounded_shift;
    wire s1_round_fits;
    wire s2_round_fits;
    wire s3_round_fits;
    wire signed [23:0] rounded_s1;
    wire signed [21:0] rounded_s2;
    wire signed [19:0] rounded_s3;
    wire s1_job_complete;

    assign short_mac_cycle = short_active || launch_short;
    assign do_short_round = short_round_pending;
    assign do_s1_round = s1_round_pending && !short_active &&
                         !short_round_pending;
    assign s1_can_run = s1_active || (s1_pending && s1_prefetched);
    assign s1_mac_cycle = s1_can_run && !short_active &&
                          !short_round_pending && !launch_short &&
                          !do_s1_round;
    assign s1_first_mac = s1_mac_cycle && !s1_active;
    assign short_first_mac = launch_short;
    assign dsp_uses_short = short_mac_cycle;
    assign s1_job_complete = s1_mac_cycle && s1_active &&
                             (s1_mac_index == S1_PAIR_COUNT-1);

    // During a running Stage1 job the read address advances only on clocks
    // actually granted to Stage1.  Pausing therefore preserves the prefetched
    // pair exactly at the current MAC index.
    assign s1_read_index = s1_active ?
        ((s1_mac_cycle && s1_mac_index + 5'd1 < S1_PAIR_COUNT) ?
         s1_mac_index + 5'd1 : s1_mac_index) :
        ((s1_pending && s1_prefetched && s1_mac_cycle) ? 5'd1 : 5'd0);
    assign s1_read_addr_a = s1_job_base - s1_read_index;
    assign s1_read_addr_b = s1_job_base -
                            (S1_HISTORY_LEN-1-s1_read_index);
    // Force the delay address arithmetic to the physical six-bit ring.
    // Leaving DELAY_INDEX as an unsized integer makes the expression signed
    // 32-bit; after wr_ptr wraps, simulation then indexes the RAM negatively.
    assign s1_delay_read_addr = s1_wr_ptr - 6'd26;
    assign s1_mask_a = s1_process_index < s1_job_fill;
    assign s1_mask_b = (S1_HISTORY_LEN-1-s1_process_index) < s1_job_fill;
    assign s1_pair_sum =
        $signed({(s1_mask_a ? s1_read_a[23] : 1'b0),
                 (s1_mask_a ? s1_read_a : 24'sd0)}) +
        $signed({(s1_mask_b ? s1_read_b[23] : 1'b0),
                 (s1_mask_b ? s1_read_b : 24'sd0)});
    assign s1_coeff_addr = s1_read_index;

    // 例化说明：调用 nf_unified_fir_coeff_bram 全国赛签核子模块，完成正式数据通路中的存储、运算或控制任务。
    nf_unified_fir_coeff_bram u_shared_coeff_bram (
        .clk(clk),
        .stage1_addr(s1_coeff_addr),
        .stage1_coeff(s1_coeff_data),
        .stage23_addr(6'd0),
        .stage23_coeff()
    );

    assign dsp_input_a = dsp_uses_short ?
        {{8{short_history_sample[21]}}, short_history_sample} :
        {{5{s1_pair_sum[24]}}, s1_pair_sum};
    assign dsp_input_b = dsp_uses_short ?
        {{2{short_coeff[15]}}, short_coeff} :
        {{2{s1_coeff_data[15]}}, s1_coeff_data};

    // 例化说明：调用 DSP48E1 算术原语，完成乘法、加减或累加；各控制字定义当前流水拍的运算功能。
    DSP48E1 #(
        .A_INPUT("DIRECT"),
        .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"),
        .USE_MULT("MULTIPLY"),
        .USE_SIMD("ONE48"),
        .AREG(0), .ACASCREG(0),
        .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(0),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_shared_fir_multiplier (
        .P(dsp_product_full),
        .A(dsp_input_a), .B(dsp_input_b), .C(48'd0), .D(25'd0),
        .INMODE(5'b00000), .OPMODE(7'b0000101),
        .ALUMODE(4'b0000), .CARRYINSEL(3'b000), .CARRYIN(1'b0),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0), .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0), .CEALUMODE(1'b0),
        .CEB1(1'b0), .CEB2(1'b0), .CEC(1'b0), .CECARRYIN(1'b0),
        .CECTRL(1'b0), .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
        .CEP(1'b0), .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
        .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(1'b0),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .PATTERNBDETECT(),
        .PATTERNDETECT(), .PCOUT(), .UNDERFLOW()
    );

    assign dsp_product = dsp_product_full[ACC_W-1:0];

    // Exactly one fabric adder is selected per cycle.  First MACs write the
    // product directly, so a round operation may overlap a first multiply.
    assign add_lhs = do_short_round ? short_accumulator :
                     (do_s1_round ? s1_accumulator :
                      (short_active ? short_accumulator : s1_accumulator));
    assign add_rhs = (do_short_round || do_s1_round) ?
        (add_lhs[ACC_W-1] ? 42'sd16383 : 42'sd16384) : dsp_product;
    assign shared_add_result = add_lhs + add_rhs;
    assign rounded_shift = shared_add_result >>> FRAC_W;

    assign s1_round_fits = rounded_shift[ACC_W-FRAC_W-1:24] ==
                           {(ACC_W-FRAC_W-24){rounded_shift[23]}};
    assign s2_round_fits = rounded_shift[ACC_W-FRAC_W-1:22] ==
                           {(ACC_W-FRAC_W-22){rounded_shift[21]}};
    assign s3_round_fits = rounded_shift[ACC_W-FRAC_W-1:20] ==
                           {(ACC_W-FRAC_W-20){rounded_shift[19]}};
    assign rounded_s1 = s1_round_fits ? rounded_shift[23:0] :
                        (rounded_shift[ACC_W-FRAC_W-1] ?
                         S1_OUT_MIN : S1_OUT_MAX);
    assign rounded_s2 = s2_round_fits ? rounded_shift[21:0] :
                        (rounded_shift[ACC_W-FRAC_W-1] ?
                         S2_OUT_MIN : S2_OUT_MAX);
    assign rounded_s3 = s3_round_fits ? rounded_shift[19:0] :
                        (rounded_shift[ACC_W-FRAC_W-1] ?
                         S3_OUT_MIN : S3_OUT_MAX);

    // ------------------------------------------------------------------
    // Memory ports.
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && ce2_out && s1_phase == 1'b0)
            s1_history[s1_wr_ptr] <= s1_x_current;
        else if (rst_n)
            s1_read_a <= s1_history[
                (ce2_out && s1_phase == 1'b1) ?
                s1_delay_read_addr : s1_read_addr_a];

        if (rst_n)
            s1_read_b <= s1_history[s1_read_addr_b];
    end

    always @(posedge clk) begin
        if (rst_n) begin
            s2_read_data <= s2_history[s2_read_addr];
            s3_read_data <= s3_history[s3_read_addr];
            if (ce4_out && s2_phase == 1'b0)
                s2_history[s2_write_addr] <= s2_x_current;
            if (ce8_out && s3_phase == 1'b0)
                s3_history[s3_write_addr] <= s3_x_current;
        end
    end

    // ------------------------------------------------------------------
    // Phase/history bookkeeping and pending queues.
    // ------------------------------------------------------------------
    // System-domain reset is synchronous here so BRAM address/control pins
    // are never driven by asynchronously reset state (REQP-1840 clean).
    always @(posedge clk) begin
        if (!rst_n) begin
            s1_wr_ptr <= 6'd0;
            s1_fill_count <= 6'd0;
            s1_phase <= 1'b1;
            s1_delay_result <= 24'sd0;
            s1_delay_ready <= 1'b0;
            s1_delay_capture_pending <= 1'b0;
            s1_pending <= 1'b0;
            s1_prefetched <= 1'b0;
            s1_job_base <= 6'd0;
            s1_job_fill <= 6'd0;
            y2_out <= 24'sd0;
            y2_out_valid <= 1'b0;

            s2_head <= 4'd0;
            s3_head <= 4'd0;
            s2_fill_count <= 4'd0;
            s3_fill_count <= 4'd0;
            s2_phase <= 1'b1;
            s3_phase <= 1'b1;
            s2_pending <= 1'b0;
            s3_pending <= 1'b0;
            s2_pending_phase <= 1'b0;
            s3_pending_phase <= 1'b0;
            s2_pending_head <= 4'd0;
            s3_pending_head <= 4'd0;
            s2_pending_fill <= 4'd0;
            s3_pending_fill <= 4'd0;
            s2_pending_first <= 22'sd0;
            s3_pending_first <= 20'sd0;
        end
        else begin
            y2_out_valid <= 1'b0;

            s1_delay_capture_pending <= ce2_out && s1_phase == 1'b1;
            if (s1_delay_capture_pending) begin
                // The BRAM location addressed by the halfband delay branch
                // is uninitialized until 26 real input samples exist.  The
                // original audio-domain prototype omitted this fill mask,
                // allowing startup X values to contaminate Stage2 history.
                s1_delay_result <= (s1_fill_count > S1_DELAY_INDEX) ?
                                   s1_read_a : 24'sd0;
                s1_delay_ready <= 1'b1;
            end

            if (s1_job_complete) begin
                s1_pending <= 1'b0;
                s1_prefetched <= 1'b0;
            end
            else if (s1_pending && !s1_prefetched)
                s1_prefetched <= 1'b1;

            if (ce2_out) begin
                y2_out_valid <= 1'b1;
                if (s1_phase == 1'b0) begin
                    y2_out <= s1_delay_ready ? s1_delay_result : 24'sd0;
                    s1_delay_ready <= 1'b0;
                    s1_job_base <= s1_wr_ptr;
                    s1_job_fill <= (s1_fill_count < S1_HISTORY_LEN) ?
                                   s1_fill_count + 6'd1 : s1_fill_count;
                    s1_pending <= 1'b1;
                    s1_prefetched <= 1'b0;
                    s1_wr_ptr <= s1_wr_ptr + 6'd1;
                    if (s1_fill_count < S1_HISTORY_LEN)
                        s1_fill_count <= s1_fill_count + 6'd1;
                end
                else begin
                    y2_out <= s1_filter_ready ? s1_filter_result : 24'sd0;
                end
                s1_phase <= ~s1_phase;
            end

            if (launch_stage2)
                s2_pending <= 1'b0;
            else if (ce4_out) begin
                s2_pending <= 1'b1;
                s2_pending_phase <= s2_phase;
                s2_pending_head <= s2_arrival_head;
                s2_pending_fill <= s2_arrival_fill;
                s2_pending_first <= s2_x_current;
            end

            if (launch_stage3)
                s3_pending <= 1'b0;
            else if (ce8_out) begin
                s3_pending <= 1'b1;
                s3_pending_phase <= s3_phase;
                s3_pending_head <= s3_arrival_head;
                s3_pending_fill <= s3_arrival_fill;
                s3_pending_first <= s3_x_current;
            end

            if (ce4_out) begin
                if (s2_phase == 1'b0) begin
                    s2_head <= s2_write_addr;
                    s2_fill_count <= s2_arrival_fill;
                end
                s2_phase <= ~s2_phase;
            end
            if (ce8_out) begin
                if (s3_phase == 1'b0) begin
                    s3_head <= s3_write_addr;
                    s3_fill_count <= s3_arrival_fill;
                end
                s3_phase <= ~s3_phase;
            end
        end
    end

    // ------------------------------------------------------------------
    // Shared scheduler and arithmetic state.
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            s1_active <= 1'b0;
            s1_mac_index <= 5'd0;
            s1_accumulator <= {ACC_W{1'b0}};
            s1_round_pending <= 1'b0;
            s1_filter_result <= 24'sd0;
            s1_filter_ready <= 1'b0;

            short_active <= 1'b0;
            short_stage3 <= 1'b0;
            short_phase <= 1'b0;
            short_mac_index <= 4'd0;
            short_mac_count <= 4'd0;
            short_history_head <= 4'd0;
            short_fill_count <= 4'd0;
            short_first_sample <= 22'sd0;
            short_accumulator <= {ACC_W{1'b0}};
            short_round_pending <= 1'b0;
            short_round_stage3 <= 1'b0;
            y4_out <= 22'sd0;
            y4_out_valid <= 1'b0;
            y8_out <= 20'sd0;
            y8_out_valid <= 1'b0;
        end
        else begin
            y4_out_valid <= 1'b0;
            y8_out_valid <= 1'b0;

            if (do_short_round) begin
                if (short_round_stage3) begin
                    y8_out <= rounded_s3;
                    y8_out_valid <= 1'b1;
                end
                else begin
                    y4_out <= rounded_s2;
                    y4_out_valid <= 1'b1;
                end
                short_round_pending <= 1'b0;
            end

            if (do_s1_round) begin
                s1_filter_result <= rounded_s1;
                s1_filter_ready <= 1'b1;
                s1_round_pending <= 1'b0;
            end
            if (ce2_out && s1_phase == 1'b1)
                s1_filter_ready <= 1'b0;

            if (short_active) begin
                short_accumulator <= shared_add_result;
                if (short_mac_index == short_mac_count-4'd1) begin
                    short_active <= 1'b0;
                    short_round_pending <= 1'b1;
                    short_round_stage3 <= short_stage3;
                    short_mac_index <= 4'd0;
                end
                else begin
                    short_mac_index <= short_mac_index + 4'd1;
                end
            end
            else if (launch_short) begin
                short_accumulator <= dsp_product;
                short_stage3 <= launch_stage3;
                short_phase <= launch_phase;
                short_history_head <= launch_head;
                short_fill_count <= launch_fill;
                short_first_sample <= launch_first_sample;
                short_mac_count <= launch_mac_count;
                if (launch_mac_count == 4'd1) begin
                    short_active <= 1'b0;
                    short_round_pending <= 1'b1;
                    short_round_stage3 <= launch_stage3;
                    short_mac_index <= 4'd0;
                end
                else begin
                    short_active <= 1'b1;
                    short_mac_index <= 4'd1;
                end
            end

            if (s1_mac_cycle) begin
                if (s1_first_mac) begin
                    s1_accumulator <= dsp_product;
                    s1_active <= 1'b1;
                    s1_mac_index <= 5'd1;
                end
                else begin
                    s1_accumulator <= shared_add_result;
                    if (s1_mac_index == S1_PAIR_COUNT-1) begin
                        s1_active <= 1'b0;
                        s1_round_pending <= 1'b1;
                        s1_mac_index <= 5'd0;
                    end
                    else begin
                        s1_mac_index <= s1_mac_index + 5'd1;
                    end
                end
            end
        end
    end

    assign scheduler_owner_dbg = short_active ?
        (short_stage3 ? 2'd3 : 2'd2) :
        (launch_short ? (launch_stage3 ? 2'd3 : 2'd2) :
         (s1_mac_cycle ? 2'd1 : 2'd0));
    assign scheduler_index_dbg = short_mac_cycle ?
        {2'b00, short_process_index} : {1'b0, s1_process_index};
    assign stage1_pending_dbg = s1_pending || s1_active || s1_round_pending;
    assign stage2_pending_dbg = s2_pending;
    assign stage3_pending_dbg = s3_pending;

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n) begin
            if (ce2_out && s1_phase == 1'b0 &&
                (s1_pending || s1_active || s1_round_pending))
                $fatal(1, "Shared FIR Stage1 deadline/pending overwrite");
            // The first phase-1 event after reset intentionally emits zero:
            // no phase-0 sample has created a filter job yet.
            if (ce2_out && s1_phase == 1'b1 &&
                s1_fill_count != 0 && !s1_filter_ready)
                $fatal(1, "Shared FIR Stage1 result not ready");
            if (ce4_out && s2_pending && !launch_stage2)
                $fatal(1, "Shared FIR Stage2 pending overwrite");
            if (ce8_out && s3_pending && !launch_stage3)
                $fatal(1, "Shared FIR Stage3 pending overwrite");
        end
    end
`endif

endmodule
