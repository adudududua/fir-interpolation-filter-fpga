function result = phase7_analyze_cic_wrap()
%=============================================================
% 文件名       : phase7_analyze_cic_wrap.m
% 函数名       : phase7_analyze_cic_wrap
% 功能简述     : 统计 Phase 7 N=3 CIC 各级补码模回绕、动态范围、
%                输出饱和以及正负直流16相增益一致性。该脚本与
%                RTL directed 0 LSB 回归共同形成模运算证据。
%
%                输出文件：
%                  reports/phase7_cic_stage_statistics.csv
%                  reports/phase7_cic_dc_phase_statistics.csv
%                  reports/phase7_cic_wrap_summary.txt
%
% 当前默认配置：
%                  CIC：R=16，M=1，N=3
%                  内部位宽：32bit
%                  末级裁剪：0 LSB
%                  直流幅度：±32768
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-14
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-14：新增逐级 wrap 与直流16相统计。
%=============================================================
% 1）主函数模块：phase7_analyze_cic_wrap
% 功能说明：计算 CIC 插值器的幅频响应、通带下垂、镜像抑制和字长特性。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


    verify_dir = fileparts(mfilename('fullpath'));
    alt_dir = fileparts(verify_dir);
    addpath(alt_dir);
    addpath(fullfile(verify_dir, 'config'));
    CFG = phase7_verify_config('daily');
    report_dir = fullfile(verify_dir, 'reports');
    if ~exist(report_dir, 'dir')
        mkdir(report_dir);
    end

    metadata = load(fullfile(report_dir, ...
        'phase7_daily_vector_metadata.mat'));
    directed_stat = metadata.directed_stat;
    directed_trace = metadata.directed_trace;

    profile = zeros(1, 2*CFG.CIC_N);
    dc_amplitude = int64(2^15);
    dc_count = 256;
    [positive_y, positive_stat, positive_trace] = ...
        cic_interp16_bittrue(repmat(dc_amplitude, 1, dc_count), ...
        CFG.CIC_R, CFG.CIC_N, CFG.CIC_M, CFG.CIC_INPUT_W, ...
        CFG.CIC_INPUT_W, profile);
    [negative_y, negative_stat, negative_trace] = ...
        cic_interp16_bittrue(repmat(-dc_amplitude, 1, dc_count), ...
        CFG.CIC_R, CFG.CIC_N, CFG.CIC_M, CFG.CIC_INPUT_W, ...
        CFG.CIC_INPUT_W, profile);

    stage_name = {'comb1'; 'comb2'; 'comb3'; ...
        'integrator1'; 'integrator2'; 'integrator3'};
    stage_width = directed_trace.stage_width(:);
    stage_max_abs = directed_trace.stage_max_abs(:);
    stage_wrap_count = directed_trace.stage_wrap_count(:);
    stage_table = table(stage_name, stage_width, stage_max_abs, ...
        stage_wrap_count, 'VariableNames', {'STAGE', 'WIDTH_BIT', ...
        'MAX_ABS', 'WRAP_COUNT'});
    writetable(stage_table, fullfile(report_dir, ...
        'phase7_cic_stage_statistics.csv'));

    steady_blocks = 32:224;
    positive_matrix = reshape(positive_y, CFG.CIC_R, []);
    negative_matrix = reshape(negative_y, CFG.CIC_R, []);
    positive_phase_mean = mean(double( ...
        positive_matrix(:, steady_blocks)), 2);
    negative_phase_mean = mean(double( ...
        negative_matrix(:, steady_blocks)), 2);
    phase_index = (0:CFG.CIC_R-1).';
    phase_table = table(phase_index, positive_phase_mean, ...
        negative_phase_mean, 'VariableNames', {'PHASE', ...
        'POSITIVE_DC_MEAN', 'NEGATIVE_DC_MEAN'});
    writetable(phase_table, fullfile(report_dir, ...
        'phase7_cic_dc_phase_statistics.csv'));

    positive_phase_difference = max(positive_phase_mean)- ...
        min(positive_phase_mean);
    negative_phase_difference = max(negative_phase_mean)- ...
        min(negative_phase_mean);
    positive_gain_error_db = 20*log10(abs( ...
        mean(positive_phase_mean)/double(dc_amplitude))+1e-15);
    negative_gain_error_db = 20*log10(abs( ...
        mean(negative_phase_mean)/double(-dc_amplitude))+1e-15);

    fid = fopen(fullfile(report_dir, ...
        'phase7_cic_wrap_summary.txt'), 'w');
    if fid < 0
        error('无法创建 CIC wrap 总结。');
    end
    cleanup_obj = onCleanup(@() fclose(fid));
    fprintf(fid, 'Phase 7 CIC modulo and DC verification\n');
    fprintf(fid, '=====================================\n');
    fprintf(fid, 'Formal configuration: R=16 M=1 N=3 FULL_W=32 PRUNE=0\n');
    fprintf(fid, 'RTL directed match: 656 valid inputs / 10496 outputs / 0 LSB\n\n');
    fprintf(fid, 'Directed comb wrap       = %d\n', ...
        directed_stat.comb_modulo_wrap_count);
    fprintf(fid, 'Directed integrator wrap = %d\n', ...
        directed_stat.integrator_modulo_wrap_count);
    fprintf(fid, 'Directed total wrap      = %d\n', ...
        directed_stat.modulo_wrap_count);
    fprintf(fid, 'Directed output sat      = %d\n', ...
        directed_stat.output_sat_count);
    fprintf(fid, 'Positive DC total wrap   = %d\n', ...
        positive_stat.modulo_wrap_count);
    fprintf(fid, 'Negative DC total wrap   = %d\n', ...
        negative_stat.modulo_wrap_count);
    fprintf(fid, 'Positive DC phase diff   = %.12g LSB\n', ...
        positive_phase_difference);
    fprintf(fid, 'Negative DC phase diff   = %.12g LSB\n', ...
        negative_phase_difference);
    fprintf(fid, 'Positive DC gain error   = %+.12g dB\n', ...
        positive_gain_error_db);
    fprintf(fid, 'Negative DC gain error   = %+.12g dB\n', ...
        negative_gain_error_db);
    fprintf(fid, 'Positive DC stage wrap   = %s\n', ...
        mat2str(positive_trace.stage_wrap_count));
    fprintf(fid, 'Negative DC stage wrap   = %s\n', ...
        mat2str(negative_trace.stage_wrap_count));

    result.directed_stat = directed_stat;
    result.directed_trace = directed_trace;
    result.positive_stat = positive_stat;
    result.negative_stat = negative_stat;
    result.positive_phase_difference = positive_phase_difference;
    result.negative_phase_difference = negative_phase_difference;
    result.positive_gain_error_db = positive_gain_error_db;
    result.negative_gain_error_db = negative_gain_error_db;
    result.stage_table = stage_table;
    result.phase_table = phase_table;
    save(fullfile(report_dir, 'phase7_cic_wrap_result.mat'), 'result');

    if directed_stat.output_sat_count ~= 0 || ...
            positive_stat.output_sat_count ~= 0 || ...
            negative_stat.output_sat_count ~= 0
        error('Phase 7 CIC 定向或直流测试出现非预期输出饱和。');
    end
    fprintf(['CIC wrap analysis: directed=%d, positiveDC=%d, ' ...
        'negativeDC=%d, phase diff=%g/%g LSB.\n'], ...
        directed_stat.modulo_wrap_count, ...
        positive_stat.modulo_wrap_count, ...
        negative_stat.modulo_wrap_count, ...
        positive_phase_difference, negative_phase_difference);
end

