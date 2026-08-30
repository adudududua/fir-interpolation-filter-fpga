function result = phase7_analyze_full_rtl_impulse()
%=============================================================
% 文件名       : phase7_analyze_full_rtl_impulse.m
% 函数名       : phase7_analyze_full_rtl_impulse
% 功能简述     : 从正式 Phase 7 顶层 XSim 导出的完整 RTL 冲激
%                CSV 直接计算 4x、8x、128x 频响与相位指标。
%                4x 按独立插值节点验收；8x 仅按 CIC 预补偿
%                内部节点说明；128x 按赛题和内部发布门槛验收。
%
%                输出文件：
%                  reports/phase7_rtl_impulse_metrics.csv
%                  reports/phase7_rtl_impulse_summary.txt
%                  figures/phase7_rtl_impulse_response.png
%                  figures/phase7_rtl_linear_phase.png
%
% 当前默认配置：
%                  RTL冲激长度：225 / 459 / 7374
%                  输入冲激幅度：2^22
%                  FFT点数：2^20
%                  最终门槛：±0.05dB、70dB、严格线性相位
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-14
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-14：新增 RTL 完整冲激频率与相位验收。
%=============================================================
% 1）主函数模块：phase7_analyze_full_rtl_impulse
% 功能说明：读取 RTL/XSim 冲激响应，恢复频率响应并计算通带、阻带和线性相位指标。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


    verify_dir = fileparts(mfilename('fullpath'));
    addpath(fullfile(verify_dir, 'config'));
    CFG = phase7_verify_config('daily');
    rtl_dir = fullfile(verify_dir, 'rtl_outputs');
    report_dir = fullfile(verify_dir, 'reports');
    figure_dir = fullfile(verify_dir, 'figures');
    ensure_directory(report_dir);
    ensure_directory(figure_dir);

    y4 = read_rtl_csv(fullfile(rtl_dir, 'rtl_impulse_y4.csv'), ...
        CFG.IR_LEN_4X);
    y8 = read_rtl_csv(fullfile(rtl_dir, 'rtl_impulse_y8.csv'), ...
        CFG.IR_LEN_8X);
    y128 = read_rtl_csv(fullfile(rtl_dir, 'rtl_impulse_y128.csv'), ...
        CFG.IR_LEN_128X);

    impulse_amplitude = 2^(CFG.INPUT_W-2);
    nfft = 2^20;
    metric4 = analyze_one_node(y4, CFG.FS_4X, CFG.GAIN_4X, ...
        impulse_amplitude, CFG, nfft);
    metric8 = analyze_one_node(y8, CFG.FS_8X, CFG.GAIN_8X, ...
        impulse_amplitude, CFG, nfft);
    metric128 = analyze_one_node(y128, CFG.FS_128X, CFG.GAIN_128X, ...
        impulse_amplitude, CFG, nfft);
    metric128 = add_linear_phase_metric(metric128, y128, ...
        CFG.FS_128X, CFG);

    metric8.gain_15k_db = interpolate_response(metric8, 15e3);
    metric8.gain_20k_db = interpolate_response(metric8, 20e3);
    hard_pass_4x = metric4.pass_abs_max_db <= CFG.SPEC_PASS_DB && ...
        metric4.stop_attn_db >= CFG.SPEC_STOP_DB;
    hard_pass_128x = metric128.pass_abs_max_db <= CFG.SPEC_PASS_DB && ...
        metric128.stop_attn_db >= CFG.SPEC_STOP_DB && ...
        metric128.impulse_symmetry_lsb == 0 && ...
        abs(metric128.gd_mean-CFG.GROUP_DELAY_128X) < 1e-6;
    release_pass_128x = ...
        metric128.pass_abs_max_db <= CFG.RELEASE_PASS_DB && ...
        metric128.stop_attn_db >= CFG.WARN_STOP_DB && hard_pass_128x;

    node_name = {'4x'; '8x_precomp'; '128x'};
    fs_hz = [CFG.FS_4X; CFG.FS_8X; CFG.FS_128X];
    impulse_length = [numel(y4); numel(y8); numel(y128)];
    pass_abs_max_db = [metric4.pass_abs_max_db; ...
        metric8.pass_abs_max_db; metric128.pass_abs_max_db];
    pass_peak_db = [metric4.pass_peak_db; metric8.pass_peak_db; ...
        metric128.pass_peak_db];
    pass_min_db = [metric4.pass_min_db; metric8.pass_min_db; ...
        metric128.pass_min_db];
    ripple_pp_db = [metric4.ripple_pp_db; metric8.ripple_pp_db; ...
        metric128.ripple_pp_db];
    stop_attn_db = [metric4.stop_attn_db; metric8.stop_attn_db; ...
        metric128.stop_attn_db];
    dc_gain = [metric4.dc_gain; metric8.dc_gain; metric128.dc_gain];
    dc_gain_error_db = [metric4.dc_gain_error_db; ...
        metric8.dc_gain_error_db; metric128.dc_gain_error_db];
    symmetry_lsb = [metric4.impulse_symmetry_lsb; ...
        metric8.impulse_symmetry_lsb; metric128.impulse_symmetry_lsb];
    acceptance_scope = {'FINAL_NODE_SPEC'; 'PRECOMP_GOLDEN_ONLY'; ...
        'FINAL_NODE_SPEC'};
    metric_table = table(node_name, fs_hz, impulse_length, ...
        pass_abs_max_db, pass_peak_db, pass_min_db, ripple_pp_db, ...
        stop_attn_db, dc_gain, dc_gain_error_db, symmetry_lsb, ...
        acceptance_scope, 'VariableNames', {'NODE', 'FS_HZ', ...
        'IMPULSE_LENGTH', 'PASS_ABS_MAX_DB', 'PASS_PEAK_DB', ...
        'PASS_MIN_DB', 'RIPPLE_PP_DB', 'STOP_ATTN_DB', 'DC_GAIN', ...
        'DC_GAIN_ERROR_DB', 'SYMMETRY_LSB', 'ACCEPTANCE_SCOPE'});
    writetable(metric_table, fullfile(report_dir, ...
        'phase7_rtl_impulse_metrics.csv'));

    write_summary(fullfile(report_dir, ...
        'phase7_rtl_impulse_summary.txt'), CFG, metric4, metric8, ...
        metric128, hard_pass_4x, hard_pass_128x, release_pass_128x);
    plot_frequency_result(fullfile(figure_dir, ...
        'phase7_rtl_impulse_response.png'), CFG, metric4, metric8, ...
        metric128);
    plot_phase_result(fullfile(figure_dir, ...
        'phase7_rtl_linear_phase.png'), CFG, metric128, y128);
    plot_fullband_acceptance(fullfile(figure_dir, ...
        'phase7_rtl_128x_fullband.png'), CFG, metric128, ...
        hard_pass_128x, release_pass_128x);

    result.CFG = CFG;
    result.metric4 = metric4;
    result.metric8 = metric8;
    result.metric128 = metric128;
    result.hard_pass_4x = hard_pass_4x;
    result.hard_pass_128x = hard_pass_128x;
    result.release_pass_128x = release_pass_128x;
    result.table = metric_table;
    saved_result = result;
    saved_result.metric4 = compact_metric(metric4);
    saved_result.metric8 = compact_metric(metric8);
    saved_result.metric128 = compact_metric(metric128);
    save(fullfile(report_dir, 'phase7_rtl_impulse_result.mat'), ...
        'saved_result');

    if ~hard_pass_128x
        error('Phase 7 RTL 128x 冲激未满足赛题硬门槛。');
    end

    drawnow;
    disp(metric_table);
    fprintf('\n================ Phase 7 正式RTL结论 ================\n');
    fprintf('4x通带最大偏差    = %.8f dB\n', metric4.pass_abs_max_db);
    fprintf('4x阻带衰减        = %.8f dB\n', metric4.stop_attn_db);
    fprintf('128x通带最大偏差  = %.8f dB\n', metric128.pass_abs_max_db);
    fprintf('128x阻带衰减      = %.8f dB\n', metric128.stop_attn_db);
    fprintf('128x冲激对称误差  = %.0f output LSB\n', ...
        metric128.impulse_symmetry_lsb);
    fprintf('128x群延迟        = %.9f samples\n', metric128.gd_mean);
    fprintf('相位拟合残差      = %.3g rad\n', ...
        metric128.phase_fit_residual_rad);
    fprintf('最终判定          = PASS\n');
    fprintf('CSV : %s\n', fullfile(report_dir, ...
        'phase7_rtl_impulse_metrics.csv'));
    fprintf('TXT : %s\n', fullfile(report_dir, ...
        'phase7_rtl_impulse_summary.txt'));
    fprintf('MAT : %s\n', fullfile(report_dir, ...
        'phase7_rtl_impulse_result.mat'));
    fprintf('PNG1: %s\n', fullfile(figure_dir, ...
        'phase7_rtl_impulse_response.png'));
    fprintf('PNG2: %s\n', fullfile(figure_dir, ...
        'phase7_rtl_linear_phase.png'));
    fprintf('PNG3: %s\n', fullfile(figure_dir, ...
        'phase7_rtl_128x_fullband.png'));
    fprintf('=====================================================\n');
end


% 2）局部函数模块：read_rtl_csv


% 功能说明：读取外部配置、RTL结果或数据文件，并转换为主流程使用的统一数据格式。
function data = read_rtl_csv(filename, expected_length)
    if ~exist(filename, 'file')
        error('缺少 RTL 冲激文件：%s', filename);
    end
    data = readmatrix(filename);
    data = data(:).';
    if numel(data) ~= expected_length || any(~isfinite(data))
        error('RTL 冲激长度或内容错误：%s，实际%d，期望%d。', ...
            filename, numel(data), expected_length);
    end
end


% 3）局部函数模块：analyze_one_node


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric = analyze_one_node(y, fs_hz, expected_gain, ...
        impulse_amplitude, CFG, nfft)
    h = double(y)/double(impulse_amplitude);
    [H, frequency] = freqz(h, 1, nfft, fs_hz);
    H_normalized = H/expected_gain;
    response_db = 20*log10(abs(H_normalized)+1e-15);
    pass_index = frequency >= CFG.FPASS_LOW & ...
        frequency <= CFG.FPASS_HIGH;
    stop_index = frequency >= CFG.FSTOP & frequency <= fs_hz/2;
    pass_response = response_db(pass_index);
    stop_response = response_db(stop_index);

    metric.h = h;
    metric.H = H;
    metric.f = frequency;
    metric.H_db = response_db;
    metric.pass_abs_max_db = max(abs(pass_response));
    metric.pass_peak_db = max(pass_response);
    metric.pass_min_db = min(pass_response);
    metric.ripple_pp_db = metric.pass_peak_db-metric.pass_min_db;
    metric.stop_attn_db = -max(stop_response);
    metric.dc_gain = sum(h);
    metric.dc_gain_error_db = ...
        20*log10(abs(metric.dc_gain/expected_gain)+1e-15);
    metric.impulse_symmetry_lsb = max(abs(double(y)-fliplr(double(y))));
end


% 4）局部函数模块：add_linear_phase_metric


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric = add_linear_phase_metric(metric, y, fs_hz, CFG)
    pass_index = metric.f >= CFG.FPASS_LOW & ...
        metric.f <= CFG.FPASS_HIGH;
    pass_frequency = metric.f(pass_index);
    omega = 2*pi*metric.f(pass_index)/fs_hz;
    phase = unwrap(angle(metric.H(pass_index)));
    phase_fit = polyfit(omega, phase, 1);
    phase_residual = phase-polyval(phase_fit, omega);
    group_delay = -diff(phase)./diff(omega);
    block_size = 128;
    block_count = floor(numel(omega)/block_size);
    block_group_delay = zeros(block_count, 1);
    block_frequency = zeros(block_count, 1);
    for block_idx = 1:block_count
        first_index = (block_idx-1)*block_size+1;
        block_index = first_index:first_index+block_size-1;
        one_fit = polyfit(omega(block_index), phase(block_index), 1);
        block_group_delay(block_idx) = -one_fit(1);
        block_frequency(block_idx) = mean(pass_frequency(block_index));
    end

    metric.phase_frequency = metric.f(pass_index);
    metric.phase_residual = phase_residual;
    metric.group_delay_frequency = ...
        (metric.phase_frequency(1:end-1)+metric.phase_frequency(2:end))/2;
    metric.group_delay = group_delay;
    metric.block_group_delay_frequency = block_frequency;
    metric.block_group_delay = block_group_delay;
    metric.phase_fit_residual_rad = max(abs(phase_residual));
    metric.gd_mean = -phase_fit(1);
    metric.gd_pp = max(group_delay)-min(group_delay);
    metric.block_gd_pp = max(block_group_delay)-min(block_group_delay);
    metric.impulse_symmetry_lsb = ...
        max(abs(double(y)-fliplr(double(y))));
end


% 5）局部函数模块：interpolate_response


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function value_db = interpolate_response(metric, frequency_hz)
    value_db = interp1(metric.f, metric.H_db, frequency_hz, 'linear');
end


% 6）局部函数模块：write_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_summary(filename, CFG, metric4, metric8, metric128, ...
        hard_pass_4x, hard_pass_128x, release_pass_128x)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建 RTL 冲激总结：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid));
    fprintf(fid, 'Phase 7 formal RTL impulse verification\n');
    fprintf(fid, '=======================================\n');
    fprintf(fid, 'Source: XSim output of interp128_all2x_v7_folded_fir_cic_top_ce\n');
    fprintf(fid, 'Formal parameters: CIC_ORDER=3, FINAL_PRUNE_LSB=0\n');
    fprintf(fid, 'Impulse lengths: 4x=%d, 8x=%d, 128x=%d\n\n', ...
        CFG.IR_LEN_4X, CFG.IR_LEN_8X, CFG.IR_LEN_128X);
    fprintf(fid, '4x pass abs max       = %.10f dB\n', ...
        metric4.pass_abs_max_db);
    fprintf(fid, '4x stop attenuation   = %.10f dB\n', ...
        metric4.stop_attn_db);
    fprintf(fid, '4x hard spec pass     = %d\n\n', hard_pass_4x);
    fprintf(fid, '8x node scope         = CIC pre-emphasis internal node\n');
    fprintf(fid, '8x gain at 15 kHz     = %+.10f dB\n', metric8.gain_15k_db);
    fprintf(fid, '8x gain at 20 kHz     = %+.10f dB\n', metric8.gain_20k_db);
    fprintf(fid, '8x final +/-0.05 dB   = not applicable\n\n');
    fprintf(fid, '128x pass abs max     = %.10f dB\n', ...
        metric128.pass_abs_max_db);
    fprintf(fid, '128x pass peak/min    = %+.10f / %+.10f dB\n', ...
        metric128.pass_peak_db, metric128.pass_min_db);
    fprintf(fid, '128x ripple pp        = %.10f dB\n', ...
        metric128.ripple_pp_db);
    fprintf(fid, '128x stop attenuation = %.10f dB\n', ...
        metric128.stop_attn_db);
    fprintf(fid, '128x DC gain          = %.12f\n', metric128.dc_gain);
    fprintf(fid, '128x DC gain error    = %+.12f dB\n', ...
        metric128.dc_gain_error_db);
    fprintf(fid, '128x symmetry error   = %.0f output LSB\n', ...
        metric128.impulse_symmetry_lsb);
    fprintf(fid, '128x group delay mean = %.12f samples\n', ...
        metric128.gd_mean);
    fprintf(fid, '128x group delay pp   = %.12g samples\n', ...
        metric128.gd_pp);
    fprintf(fid, '128x block-fit GD pp  = %.12g samples\n', ...
        metric128.block_gd_pp);
    fprintf(fid, '128x phase residual   = %.12g rad\n', ...
        metric128.phase_fit_residual_rad);
    fprintf(fid, '128x hard spec pass   = %d\n', hard_pass_128x);
    fprintf(fid, '128x release pass     = %d\n', release_pass_128x);
end


% 7）局部函数模块：plot_frequency_result


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function plot_frequency_result(filename, CFG, metric4, metric8, metric128)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_yellow = [0.82 0.88 0.05];
    figure('Name', 'Phase 7 - 正式RTL完整冲激频响', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [80 50 1500 900]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    plot(metric4.f/1e3, metric4.H_db, 'Color', color_purple, ...
        'LineWidth', 1.6); hold on;
    yline(CFG.SPEC_PASS_DB, '--', 'Color', color_yellow);
    yline(-CFG.SPEC_PASS_DB, '--', 'Color', color_yellow);
    xline(CFG.FPASS_HIGH/1e3, '--', 'Color', color_green);
    xlim([0 22]); ylim([-0.08 0.08]);
    title('RTL 4x 通带'); xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    legend('4x RTL', '+0.05 dB', '-0.05 dB', '20 kHz', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(metric8.f/1e3, metric8.H_db, 'Color', color_blue, ...
        'LineWidth', 1.6); hold on;
    xline(15, '--', 'Color', color_green);
    xline(20, '--', 'Color', color_green);
    xlim([0 22]); ylim([-0.05 0.18]);
    title('RTL 8x CIC 预补偿节点'); xlabel('频率 / kHz');
    ylabel('相对幅度 / dB');
    legend('8x 预加重', '15 kHz', '20 kHz', 'Location', 'northwest');
    style_axes(gca);

    nexttile;
    plot(metric128.f/1e3, metric128.H_db, 'Color', color_purple, ...
        'LineWidth', 1.6); hold on;
    yline(CFG.RELEASE_PASS_DB, '--', 'Color', color_yellow);
    yline(-CFG.RELEASE_PASS_DB, '--', 'Color', color_yellow);
    xline(CFG.FPASS_HIGH/1e3, '--', 'Color', color_green);
    xlim([0 22]); ylim([-0.02 0.02]);
    title('RTL 128x 最终通带'); xlabel('频率 / kHz');
    ylabel('相对幅度 / dB');
    legend('128x RTL', '+0.01 dB', '-0.01 dB', '20 kHz', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(metric128.f/1e3, metric128.H_db, 'Color', color_blue, ...
        'LineWidth', 1.35); hold on;
    yline(-CFG.SPEC_STOP_DB, '--', 'Color', color_yellow);
    xline(CFG.FSTOP/1e3, '--', 'Color', color_green);
    xlim([20 80]); ylim([-130 5]);
    title('RTL 128x 通带到阻带入口'); xlabel('频率 / kHz');
    ylabel('幅度 / dB');
    legend('128x RTL', '-70 dB', '24.1 kHz', 'Location', 'southwest');
    style_axes(gca);

    sgtitle('Phase 7 正式 RTL 完整冲激频响');
    exportgraphics(gcf, filename, 'Resolution', 200);
end


% 8）局部函数模块：plot_phase_result


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function plot_phase_result(filename, CFG, metric, y)
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    figure('Name', 'Phase 7 - 正式RTL严格线性相位', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [100 80 1450 620]);
    tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    plot(0:numel(y)-1, double(y)-fliplr(double(y)), ...
        'Color', color_green, 'LineWidth', 1.1);
    xlim([0 numel(y)-1]);
    title('RTL 128x 冲激镜像差'); xlabel('最终输出样点');
    ylabel('差值 / LSB'); style_axes(gca);
    nexttile;
    plot(metric.block_group_delay_frequency/1e3, ...
        metric.block_group_delay-CFG.GROUP_DELAY_128X, 'o-', ...
        'Color', color_purple, 'MarkerSize', 3.5, 'LineWidth', 1.1);
    xlim([0 20]);
    title('RTL 128x 通带群延迟偏差'); xlabel('频率 / kHz');
    ylabel('偏差 / 最终样点'); style_axes(gca);
    sgtitle('Phase 7 严格线性相位 RTL 证据');
    exportgraphics(gcf, filename, 'Resolution', 200);
end


% 9）局部函数模块：plot_fullband_acceptance


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function plot_fullband_acceptance(filename, CFG, metric, ...
        hard_pass, release_pass)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_yellow = [0.82 0.88 0.05];
    figure('Name', 'Phase 7 - RTL 128x全频带验收', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [70 45 1540 900]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    plot(metric.f/1e3, metric.H_db, 'Color', color_purple, ...
        'LineWidth', 1.8); hold on;
    yline(CFG.SPEC_PASS_DB, '--', 'Color', color_yellow, 'LineWidth', 1.1);
    yline(-CFG.SPEC_PASS_DB, '--', 'Color', color_yellow, 'LineWidth', 1.1);
    xline(CFG.FPASS_HIGH/1e3, '--', 'Color', color_green, 'LineWidth', 1.1);
    xlim([0 22]); ylim([-0.06 0.06]);
    title('RTL 128x 通带纹波'); xlabel('频率 / kHz');
    ylabel('相对幅度 / dB');
    legend('RTL 冲激响应', '+0.05 dB', '-0.05 dB', '20 kHz', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(metric.f/1e3, metric.H_db, 'Color', color_blue, ...
        'LineWidth', 1.55); hold on;
    yline(-CFG.SPEC_STOP_DB, '--', 'Color', color_yellow, 'LineWidth', 1.1);
    xline(CFG.FSTOP/1e3, '--', 'Color', color_green, 'LineWidth', 1.1);
    xlim([20 80]); ylim([-140 5]);
    title('RTL 通带至阻带入口'); xlabel('频率 / kHz');
    ylabel('相对幅度 / dB');
    legend('RTL 冲激响应', '-70 dB', '24.1 kHz', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(metric.f/1e6, metric.H_db, 'Color', color_blue, ...
        'LineWidth', 1.05); hold on;
    yline(-CFG.SPEC_STOP_DB, '--', 'Color', color_yellow, 'LineWidth', 1.0);
    xline(CFG.FSTOP/1e6, '--', 'Color', color_green, 'LineWidth', 1.0);
    xlim([0 CFG.FS_128X/2/1e6]); ylim([-160 5]);
    title('RTL 128x 输出全奈奎斯特频带'); xlabel('频率 / MHz');
    ylabel('相对幅度 / dB');
    legend('0 ~ 2.8224 MHz', '-70 dB', '24.1 kHz', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    axis off;
    hard_text = 'FAIL';
    release_text = 'FAIL';
    if hard_pass
        hard_text = 'PASS';
    end
    if release_pass
        release_text = 'PASS';
    end
    summary_text = {
        '正式 RTL 128x 验收结果'
        ' '
        sprintf('采样率：44.1 kHz -> %.4f MHz', CFG.FS_128X/1e6)
        '倍率分解：2 x 2 x 2 x 16 = 128'
        sprintf('通带最大偏差：%.8f dB  (要求 <= %.2f dB)', ...
            metric.pass_abs_max_db, CFG.SPEC_PASS_DB)
        sprintf('通带峰峰纹波：%.8f dB', metric.ripple_pp_db)
        sprintf('阻带衰减：%.8f dB  (要求 >= %.0f dB)', ...
            metric.stop_attn_db, CFG.SPEC_STOP_DB)
        sprintf('冲激对称误差：%.0f output LSB', ...
            metric.impulse_symmetry_lsb)
        sprintf('群延迟：%.9f samples', metric.gd_mean)
        sprintf('相位拟合残差：%.3g rad', metric.phase_fit_residual_rad)
        sprintf('赛题硬指标：%s；工程发布指标：%s', ...
            hard_text, release_text)};
    text(0.04, 0.95, summary_text, 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'FontName', 'Microsoft YaHei', ...
        'FontSize', 13, 'Color', color_purple);
    rectangle('Position', [0.015 0.05 0.97 0.90], ...
        'EdgeColor', color_green, 'LineWidth', 1.4, 'Curvature', 0.02);

    sgtitle('44.1 kHz -> 5.6448 MHz：正式 RTL 128x 完整链路验收');
    exportgraphics(gcf, filename, 'Resolution', 220);
end


% 10）局部函数模块：compact_metric


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric_out = compact_metric(metric_in)
    large_fields = {'h', 'H', 'f', 'H_db', 'phase_frequency', ...
        'phase_residual', 'group_delay_frequency', 'group_delay', ...
        'block_group_delay_frequency', 'block_group_delay'};
    present_fields = intersect(large_fields, fieldnames(metric_in));
    metric_out = rmfield(metric_in, present_fields);
end


% 11）局部函数模块：style_axes


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function style_axes(ax)
    grid(ax, 'on'); box(ax, 'on');
    ax.FontName = 'Microsoft YaHei';
    ax.FontSize = 11;
    ax.LineWidth = 1.1;
    ax.XMinorTick = 'on';
    ax.YMinorTick = 'on';
    ax.XMinorGrid = 'off';
    ax.YMinorGrid = 'off';
end


% 12）局部函数模块：ensure_directory


% 功能说明：检查目标目录是否存在，并在缺失时创建，保证后续文件导出路径有效。
function ensure_directory(path_value)
    if ~exist(path_value, 'dir')
        mkdir(path_value);
    end
end
