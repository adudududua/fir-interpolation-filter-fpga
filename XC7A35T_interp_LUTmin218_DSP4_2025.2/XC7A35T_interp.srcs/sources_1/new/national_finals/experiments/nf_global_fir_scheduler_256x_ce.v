`timescale 1ns / 1ps

// Experimental 256x-clock FIR scheduler.  One DSP48E1 executes the Stage1,
// Stage2 and Stage3 MAC streams.  Short Stage2/3 jobs may pre-empt the long
// Stage1 scan; the Stage1 P value is saved and restored around the short job.
// The signed-off coefficient and history RAMB18 blocks are retained.
module nf_global_fir_scheduler_256x_ce (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    ce2_out,
    input  wire                    ce4_out,
    input  wire                    ce8_out,
    input  wire signed [23:0]      x_in,
    input  wire                    x_in_valid,
    input  wire signed [21:0]      stage2_x_in,
    input  wire                    stage2_x_in_valid,
    input  wire signed [19:0]      stage3_x_in,
    input  wire                    stage3_x_in_valid,
    input  wire                    stage3_compensated_mode,
    output reg  signed [23:0]      y2_out,
    output reg                     y2_out_valid,
    output reg  signed [21:0]      y4_out,
    output reg                     y4_out_valid,
    output reg  signed [20:0]      y8_out,
    output reg                     y8_out_valid,
    output wire                    stage2_phase_dbg,
    output wire                    stage3_phase_dbg,
    output wire [3:0]              scheduler_state_dbg,
    output wire [1:0]              scheduler_owner_dbg,
    output wire [5:0]              stage1_coeff_addr,
    input  wire signed [15:0]      stage1_coeff_data,
    output wire [6:0]              stage23_coeff_addr,
    input  wire signed [17:0]      stage23_coeff_data
);

    localparam [1:0] OWNER_S1 = 2'd0;
    localparam [1:0] OWNER_S2 = 2'd1;
    localparam [1:0] OWNER_S3 = 2'd2;

    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_S1_RUN       = 4'd1;
    localparam [3:0] ST_S1_DRAIN     = 4'd2;
    localparam [3:0] ST_SHORT_MAC    = 4'd3;
    localparam [3:0] ST_SHORT_ROUND  = 4'd4;
    localparam [3:0] ST_SHORT_SAT    = 4'd5;
    localparam [3:0] ST_SHORT_WRITE  = 4'd6;
    localparam [3:0] ST_S1_RESTORE   = 4'd7;
    localparam [3:0] ST_S1_ROUND     = 4'd8;
    localparam [3:0] ST_S1_SAT       = 4'd9;
    localparam [3:0] ST_S1_WRITE     = 4'd10;

    reg [3:0] state;
    reg [1:0] short_owner;
    reg short_phase;
    reg short_compensated;
    reg [3:0] short_head;
    reg [3:0] short_fill;
    reg [5:0] short_issue_index;
    reg short_return_valid;
    reg short_return_mask;
    reg [5:0] short_return_index;

    reg s1_active;
    reg s1_all_mac_done;
    reg [5:0] s1_job_head;
    reg [5:0] s1_job_fill;
    reg [5:0] s1_issue_index;
    reg s1_return_valid;
    reg s1_return_mask;
    reg [5:0] s1_return_index;
    reg signed [40:0] s1_saved_acc;

    reg s1_pending;
    reg [5:0] s1_pending_head;
    reg [5:0] s1_pending_fill;
    reg s2_pending;
    reg s2_pending_phase;
    reg [3:0] s2_pending_head;
    reg [3:0] s2_pending_fill;
    reg s3_pending;
    reg s3_pending_phase;
    reg s3_pending_compensated;
    reg [3:0] s3_pending_head;
    reg [3:0] s3_pending_fill;

    reg s1_phase;
    reg s2_phase;
    reg s3_phase;
    reg [5:0] s1_wr_ptr;
    reg [5:0] s1_fill_count;
    reg [3:0] s2_head;
    reg [3:0] s3_head;
    reg [3:0] s2_fill_count;
    reg [3:0] s3_fill_count;
    reg signed [23:0] s1_delay_result;
    reg signed [23:0] s1_filter_result;

    wire signed [23:0] s1_x_current = x_in_valid ? x_in : 24'sd0;
    wire signed [21:0] s2_x_current = stage2_x_in_valid ?
        stage2_x_in : 22'sd0;
    wire signed [19:0] s3_x_current = stage3_x_in_valid ?
        stage3_x_in : 20'sd0;

    wire s1_write_event = ce2_out && !s1_phase;
    wire s2_write_event = ce4_out && !s2_phase;
    wire s3_write_event = ce8_out && !s3_phase;
    wire [3:0] s2_write_addr = s2_head - 4'd1;
    wire [3:0] s3_write_addr = s3_head - 4'd1;

    wire short_pending = s3_pending || s2_pending;
    wire choose_s3 = s3_pending;
    wire launch_short_idle = state == ST_IDLE && short_pending;
    wire launch_short_drain = state == ST_S1_DRAIN &&
        !s1_return_valid && short_pending;
    wire launch_short_after_short = state == ST_SHORT_WRITE && short_pending;
    wire launch_short_after_s1 = state == ST_S1_WRITE && short_pending;
    wire launch_short = launch_short_idle || launch_short_drain ||
        launch_short_after_short || launch_short_after_s1;
    wire launch_s1 = state == ST_IDLE && !short_pending && s1_pending;

    wire [5:0] short_mac_count = short_owner == OWNER_S3 ?
        (short_phase ? 6'd5 : 6'd6) :
        (short_phase ? 6'd8 : 6'd9);
    wire s1_issue_enable = state == ST_S1_RUN && !short_pending &&
        s1_issue_index < 6'd52;
    wire short_issue_enable = state == ST_SHORT_MAC &&
        short_issue_index < short_mac_count;
    wire s1_issue_mask = s1_issue_index < s1_job_fill;
    wire short_issue_mask = short_issue_index < {2'b00, short_fill};

    wire [5:0] s1_read_addr = s1_job_head - s1_issue_index;
    wire signed [23:0] s1_read_data;
    wire [4:0] s23_read_addr = {
        short_owner == OWNER_S3,
        short_head + short_issue_index[3:0]
    };
    wire signed [21:0] s23_read_data;
    wire s23_write_enable = s2_write_event || s3_write_event;
    wire [4:0] s23_write_addr = s2_write_event ?
        {1'b0, s2_write_addr} : {1'b1, s3_write_addr};
    wire signed [21:0] s23_write_data = s2_write_event ? s2_x_current :
        {{2{s3_x_current[19]}}, s3_x_current};

    nf_stage1_history_ramb18_sdp u_s1_history (
        .clk(clk),
        .read_addr(s1_read_addr),
        .read_data(s1_read_data),
        .write_enable(rst_n && s1_write_event),
        .write_addr(s1_wr_ptr),
        .write_data(s1_x_current)
    );

    nf_stage23_history_ramb18_sdp u_s23_history (
        .clk(clk),
        .read_addr(s23_read_addr),
        .read_data(s23_read_data),
        .write_enable(rst_n && s23_write_enable),
        .write_addr(s23_write_addr),
        .write_data(s23_write_data)
    );

    assign stage1_coeff_addr = s1_issue_index;
    assign stage23_coeff_addr = short_compensated &&
                                short_owner == OWNER_S3 ?
        {2'b11, short_phase, short_issue_index[3:0]} :
        {1'b0, short_owner == OWNER_S3, short_phase,
         short_issue_index[3:0]};

    wire signed [29:0] dsp_a =
        (state == ST_S1_RUN || state == ST_S1_DRAIN) ?
        {{6{s1_read_data[23]}}, s1_read_data} :
        {{8{s23_read_data[21]}}, s23_read_data};
    wire signed [17:0] dsp_b =
        (state == ST_S1_RUN || state == ST_S1_DRAIN) ?
        {{2{stage1_coeff_data[15]}}, stage1_coeff_data} :
        stage23_coeff_data;
    wire dsp_s1_mac = (state == ST_S1_RUN || state == ST_S1_DRAIN) &&
        s1_return_valid && s1_return_mask;
    wire dsp_short_mac = state == ST_SHORT_MAC &&
        short_return_valid && short_return_mask;

    wire signed [47:0] dsp_p;
    wire signed [25:0] s1_quotient = $signed(dsp_p[40:0]) >>> 15;
    wire signed [22:0] short_quotient = $signed(dsp_p[37:0]) >>> 15;
    wire s1_fits = s1_quotient[25:24] == {2{s1_quotient[23]}};
    wire s2_fits = short_quotient[22] == short_quotient[21];
    wire s3_fits = short_quotient[22:21] == {2{short_quotient[20]}};
    wire short_fits = short_owner == OWNER_S3 ? s3_fits : s2_fits;

    wire signed [47:0] s1_max_scaled =
        {{9{1'b0}}, 24'sh7fffff, 15'b0};
    wire signed [47:0] s1_min_scaled =
        {{9{1'b1}}, 24'sh800000, 15'b0};
    wire signed [47:0] s2_max_scaled =
        {{11{1'b0}}, 22'sh1fffff, 15'b0};
    wire signed [47:0] s2_min_scaled =
        {{11{1'b1}}, 22'sh200000, 15'b0};
    wire signed [47:0] s3_max_scaled =
        {{12{1'b0}}, 21'sh0fffff, 15'b0};
    wire signed [47:0] s3_min_scaled =
        {{12{1'b1}}, 21'sh100000, 15'b0};
    wire s1_negative = dsp_p[40];
    wire short_negative = dsp_p[37];
    wire signed [47:0] short_limit = short_owner == OWNER_S3 ?
        (short_negative ? s3_min_scaled : s3_max_scaled) :
        (short_negative ? s2_min_scaled : s2_max_scaled);
    wire restore_s1_on_short_write = state == ST_SHORT_WRITE &&
        s1_active && !short_pending;
    wire signed [47:0] dsp_c =
        (state == ST_S1_RESTORE || restore_s1_on_short_write) ?
        {{7{s1_saved_acc[40]}}, s1_saved_acc} :
        48'sd16383;
    wire [6:0] dsp_opmode =
        (state == ST_S1_RESTORE || restore_s1_on_short_write) ?
         7'b0001100 :
        ((state == ST_S1_ROUND || state == ST_SHORT_ROUND) ?
         7'b0001110 : 7'b0100101);
    wire dsp_carry = (state == ST_S1_ROUND && !dsp_p[40]) ||
                     (state == ST_SHORT_ROUND && !dsp_p[37]);
    wire dsp_ce = dsp_s1_mac || dsp_short_mac ||
        state == ST_S1_RESTORE || restore_s1_on_short_write ||
        state == ST_S1_ROUND || state == ST_SHORT_ROUND;
    wire dsp_reset = !rst_n || launch_short || launch_s1;

    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"), .USE_MULT("MULTIPLY"),
        .USE_PATTERN_DETECT("NO_PATDET"), .USE_SIMD("ONE48"),
        .AREG(0), .ACASCREG(0), .BREG(0), .BCASCREG(0),
        .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(1),
        .INMODEREG(0), .OPMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_shared_fir_dsp48e1 (
        .P(dsp_p), .A(dsp_a), .B(dsp_b), .C(dsp_c), .D(25'sd0),
        .INMODE(5'b00000), .OPMODE(dsp_opmode), .ALUMODE(4'b0000),
        .CARRYINSEL(3'b000), .CARRYIN(dsp_carry),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0),
        .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0), .CLK(clk),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0), .CEALUMODE(1'b0),
        .CEB1(1'b0), .CEB2(1'b0), .CEC(1'b0), .CECARRYIN(1'b0),
        .CECTRL(1'b0), .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
        .CEP(dsp_ce), .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0),
        .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(dsp_reset),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .PATTERNBDETECT(),
        .PATTERNDETECT(), .PCOUT(), .UNDERFLOW()
    );

    assign stage2_phase_dbg = s2_phase;
    assign stage3_phase_dbg = s3_phase;
    assign scheduler_state_dbg = state;
    assign scheduler_owner_dbg =
        (state == ST_S1_RUN || state == ST_S1_DRAIN ||
         state == ST_S1_RESTORE || state == ST_S1_ROUND ||
         state == ST_S1_SAT || state == ST_S1_WRITE) ? OWNER_S1 :
        short_owner;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            short_owner <= OWNER_S2;
            short_phase <= 1'b0;
            short_compensated <= 1'b0;
            short_head <= 4'd0;
            short_fill <= 4'd0;
            short_issue_index <= 6'd0;
            short_return_valid <= 1'b0;
            short_return_mask <= 1'b0;
            short_return_index <= 6'd0;
            s1_active <= 1'b0;
            s1_all_mac_done <= 1'b0;
            s1_job_head <= 6'd0;
            s1_job_fill <= 6'd0;
            s1_issue_index <= 6'd0;
            s1_return_valid <= 1'b0;
            s1_return_mask <= 1'b0;
            s1_return_index <= 6'd0;
            s1_saved_acc <= 41'sd0;
            s1_pending <= 1'b0;
            s1_pending_head <= 6'd0;
            s1_pending_fill <= 6'd0;
            s2_pending <= 1'b0;
            s2_pending_phase <= 1'b0;
            s2_pending_head <= 4'd0;
            s2_pending_fill <= 4'd0;
            s3_pending <= 1'b0;
            s3_pending_phase <= 1'b0;
            s3_pending_compensated <= 1'b0;
            s3_pending_head <= 4'd0;
            s3_pending_fill <= 4'd0;
            s1_phase <= 1'b1;
            s2_phase <= 1'b1;
            s3_phase <= 1'b1;
            s1_wr_ptr <= 6'd0;
            s1_fill_count <= 6'd0;
            s2_head <= 4'd0;
            s3_head <= 4'd0;
            s2_fill_count <= 4'd0;
            s3_fill_count <= 4'd0;
            s1_delay_result <= 24'sd0;
            s1_filter_result <= 24'sd0;
            y2_out <= 24'sd0;
            y2_out_valid <= 1'b0;
            y4_out <= 22'sd0;
            y4_out_valid <= 1'b0;
            y8_out <= 21'sd0;
            y8_out_valid <= 1'b0;
        end
        else begin
            y2_out_valid <= 1'b0;
            y4_out_valid <= 1'b0;
            y8_out_valid <= 1'b0;

            s1_return_valid <= s1_issue_enable;
            if (s1_issue_enable) begin
                s1_return_mask <= s1_issue_mask;
                s1_return_index <= s1_issue_index;
                s1_issue_index <= s1_issue_index + 6'd1;
            end
            short_return_valid <= short_issue_enable;
            if (short_issue_enable) begin
                short_return_mask <= short_issue_mask;
                short_return_index <= short_issue_index;
                short_issue_index <= short_issue_index + 6'd1;
            end

            if (s1_return_valid && s1_return_mask &&
                s1_return_index == 6'd25)
                s1_delay_result <= s1_read_data;
            if (s1_return_valid && s1_return_index == 6'd51)
                s1_all_mac_done <= 1'b1;

            if (ce2_out) begin
                y2_out_valid <= 1'b1;
                y2_out <= s1_phase ? s1_filter_result : s1_delay_result;
                if (!s1_phase) begin
                    s1_pending <= 1'b1;
                    s1_pending_head <= s1_wr_ptr;
                    s1_pending_fill <= s1_fill_count < 6'd52 ?
                        s1_fill_count + 6'd1 : 6'd52;
                    s1_wr_ptr <= s1_wr_ptr + 6'd1;
                    if (s1_fill_count < 6'd52)
                        s1_fill_count <= s1_fill_count + 6'd1;
                end
                s1_phase <= ~s1_phase;
            end

            if (ce4_out) begin
                s2_pending <= 1'b1;
                s2_pending_phase <= s2_phase;
                s2_pending_head <= !s2_phase ? s2_write_addr : s2_head;
                s2_pending_fill <= (!s2_phase && s2_fill_count < 4'd9) ?
                    s2_fill_count + 4'd1 : s2_fill_count;
                if (!s2_phase) begin
                    s2_head <= s2_write_addr;
                    if (s2_fill_count < 4'd9)
                        s2_fill_count <= s2_fill_count + 4'd1;
                end
                s2_phase <= ~s2_phase;
            end

            if (ce8_out) begin
                s3_pending <= 1'b1;
                s3_pending_phase <= s3_phase;
                s3_pending_compensated <= stage3_compensated_mode;
                s3_pending_head <= !s3_phase ? s3_write_addr : s3_head;
                s3_pending_fill <= (!s3_phase && s3_fill_count < 4'd6) ?
                    s3_fill_count + 4'd1 : s3_fill_count;
                if (!s3_phase) begin
                    s3_head <= s3_write_addr;
                    if (s3_fill_count < 4'd6)
                        s3_fill_count <= s3_fill_count + 4'd1;
                end
                s3_phase <= ~s3_phase;
            end

            if (launch_s1) begin
                state <= ST_S1_RUN;
                s1_active <= 1'b1;
                s1_all_mac_done <= 1'b0;
                s1_job_head <= s1_pending_head;
                s1_job_fill <= s1_pending_fill;
                s1_issue_index <= 6'd0;
                s1_return_valid <= 1'b0;
                s1_pending <= 1'b0;
            end
            else if (launch_short) begin
                // A completed job is committed even when the next short job
                // launches on the same edge.  This removes an idle bubble
                // without dropping a valid output request.
                if (state == ST_SHORT_WRITE) begin
                    if (short_owner == OWNER_S3) begin
                        y8_out <= short_fits ? short_quotient[20:0] :
                            (short_negative ? 21'sh100000 : 21'sh0fffff);
                        y8_out_valid <= 1'b1;
                    end
                    else begin
                        y4_out <= short_fits ? short_quotient[21:0] :
                            (short_negative ? 22'sh200000 : 22'sh1fffff);
                        y4_out_valid <= 1'b1;
                    end
                end
                if (state == ST_S1_WRITE) begin
                    s1_filter_result <= s1_fits ? s1_quotient[23:0] :
                        (s1_negative ? 24'sh800000 : 24'sh7fffff);
                    s1_active <= 1'b0;
                end
                state <= ST_SHORT_MAC;
                short_owner <= choose_s3 ? OWNER_S3 : OWNER_S2;
                short_phase <= choose_s3 ?
                    s3_pending_phase : s2_pending_phase;
                short_compensated <= choose_s3 ?
                    s3_pending_compensated : 1'b0;
                short_head <= choose_s3 ? s3_pending_head : s2_pending_head;
                short_fill <= choose_s3 ? s3_pending_fill : s2_pending_fill;
                short_issue_index <= 6'd0;
                short_return_valid <= 1'b0;
                if (choose_s3)
                    s3_pending <= 1'b0;
                else
                    s2_pending <= 1'b0;
                if (launch_short_drain)
                    s1_saved_acc <= dsp_p[40:0];
            end
            else begin
                case (state)
                    ST_IDLE: begin
                    end
                    ST_S1_RUN: begin
                        if (short_pending)
                            state <= ST_S1_DRAIN;
                        else if (s1_return_valid &&
                                 s1_return_index == 6'd51)
                            state <= ST_S1_ROUND;
                    end
                    ST_S1_DRAIN: begin
                    end
                    ST_SHORT_MAC: begin
                        if (short_return_valid &&
                            short_return_index == short_mac_count - 6'd1)
                            state <= ST_SHORT_ROUND;
                    end
                    ST_SHORT_ROUND: state <= ST_SHORT_WRITE;
                    ST_SHORT_SAT: state <= ST_SHORT_WRITE;
                    ST_SHORT_WRITE: begin
                        if (short_owner == OWNER_S3) begin
                            y8_out <= short_fits ? short_quotient[20:0] :
                                (short_negative ? 21'sh100000 : 21'sh0fffff);
                            y8_out_valid <= 1'b1;
                        end
                        else begin
                            y4_out <= short_fits ? short_quotient[21:0] :
                                (short_negative ? 22'sh200000 : 22'sh1fffff);
                            y4_out_valid <= 1'b1;
                        end
                        if (s1_active)
                            state <= s1_all_mac_done ?
                                ST_S1_ROUND : ST_S1_RUN;
                        else
                            state <= ST_IDLE;
                    end
                    ST_S1_RESTORE: begin
                        state <= s1_all_mac_done ?
                            ST_S1_ROUND : ST_S1_RUN;
                    end
                    ST_S1_ROUND: state <= ST_S1_WRITE;
                    ST_S1_SAT: state <= ST_S1_WRITE;
                    ST_S1_WRITE: begin
                        s1_filter_result <= s1_fits ? s1_quotient[23:0] :
                            (s1_negative ? 24'sh800000 : 24'sh7fffff);
                        s1_active <= 1'b0;
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
            if (s2_write_event && s3_write_event)
                $fatal(1, "global FIR Stage2/3 history write collision");
            if (ce2_out && !s1_phase && s1_pending)
                $fatal(1, "global FIR Stage1 pending overwrite");
            if (ce4_out && s2_pending)
                $fatal(1, "global FIR Stage2 pending overwrite");
            if (ce8_out && s3_pending)
                $fatal(1, "global FIR Stage3 pending overwrite");
            if (ce2_out && s1_phase && (s1_active || s1_pending))
                $fatal(1, "global FIR Stage1 result deadline miss");
        end
    end
`endif

endmodule
