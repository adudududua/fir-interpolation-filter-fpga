clc; clear; close all;

%=============================================================
% 文件名       : phase7_03_validate_bittrue.m
% 脚本名       : phase7_03_validate_bittrue
% 功能简述     : Phase 7 FIR-CIC 两条 Pareto 候选的整数位真验证。
%                前三级沿用 Phase 6 的 24/22/20bit 模型，随后依次
%                执行低速补偿 FIR、低速 comb、16 倍插零、高速
%                integrator 和 CIC 增益归一化。
%
%                验证激励：
%                  1. 半满幅冲激；
%                  2. 固定随机 PCM；
%                  3. 15kHz 正弦；
%                  4. 20kHz 正弦。
%
%                输出文件：
%                  bittrue_results/phase7_bittrue_candidates.csv
%                  bittrue_results/phase7_bittrue_summary.txt
%                  bittrue_golden/phase7_stage3_*_20bit.mem
%                  bittrue_golden/phase7_*_golden_20bit.mem
%                  figures/phase7_bittrue_response.png
%
% 当前默认配置：
%                  候选 A：N=3，15tap，Q12
%                  候选 B：N=4，15tap，Q12
%                  CIC    ：R=16，M=1，全精度内部位宽
%                  输入输出：Stage3 内部 20bit Q 格式
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 Phase 7 FIR-CIC 位真验证。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
stable_dir = fullfile(repo_matlab_dir, 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
v2_dir = fullfile(repo_matlab_dir, 'alt_all2x_v2');
result_dir = fullfile(script_dir, 'bittrue_results');
golden_dir = fullfile(script_dir, 'bittrue_golden');
figure_dir = fullfile(script_dir, 'figures');

addpath(bittrue_dir);
addpath(script_dir);
for one_dir = {result_dir, golden_dir, figure_dir}
    if ~exist(one_dir{1}, 'dir')
        mkdir(one_dir{1});
    end
end

load(fullfile(v2_dir, 'stage1_strict_halfband_config.mat'), ...
     'best_config');
best_config(3).coeff_int = int64(best_config(3).coeff_int)*2;
best_config(3).frac_w = best_config(3).frac_w+1;
best_config(3).acc_w_recommended = 38;
load(fullfile(script_dir, 'results', ...
    'cic_compensation_pareto.mat'), 'pareto');

FS_IN = 44100;
FS_OUT = 5644800;
R_CIC = 16;
M_CIC = 1;
DATA_W = 24;
STAGE3_W = 20;
COMP_ACC_W = 40;
WIDTH_PROFILE = [24 22 20];
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_BEGIN = 24100;
EXPECTED_GAIN = 128;
NFFT = 2^20;

source_golden_dir = fullfile(v2_dir, 'golden');
stimulus.impulse = read_signed_hex_mem(fullfile(source_golden_dir, ...
    'stage1_strict_impulse_input_24bit.mem'), DATA_W);
stimulus.random = read_signed_hex_mem(fullfile(source_golden_dir, ...
    'stage1_strict_random_input_24bit.mem'), DATA_W);
stimulus.sine15k = make_sine(15000, -12, 2048, FS_IN, DATA_W);
stimulus.sine20k = make_sine(20000, -12, 2048, FS_IN, DATA_W);
stimulus_name = fieldnames(stimulus);

stage3 = struct();
front_stat = struct();
for stimulus_idx = 1:numel(stimulus_name)
    one_name = stimulus_name{stimulus_idx};
    [stage3.(one_name), front_stat.(one_name)] = simulate_front3( ...
        stimulus.(one_name), best_config(1:3), WIDTH_PROFILE, DATA_W);
end

write_signed_hex_mem(fullfile(golden_dir, ...
    'phase7_stage3_impulse_input_20bit.mem'), stage3.impulse, STAGE3_W);
write_signed_hex_mem(fullfile(golden_dir, ...
    'phase7_stage3_random_input_20bit.mem'), stage3.random, STAGE3_W);

row_name = cell(numel(pareto), 1);
row_order = zeros(numel(pareto), 1);
row_taps = zeros(numel(pareto), 1);
row_frac = zeros(numel(pareto), 1);
row_full_w = zeros(numel(pareto), 1);
row_pass_abs = zeros(numel(pareto), 1);
row_ripple = zeros(numel(pareto), 1);
row_stop = zeros(numel(pareto), 1);
row_gd = zeros(numel(pareto), 1);
row_random_snr = zeros(numel(pareto), 1);
row_sinad15 = zeros(numel(pareto), 1);
row_thd15 = zeros(numel(pareto), 1);
row_sinad20 = zeros(numel(pareto), 1);
row_thd20 = zeros(numel(pareto), 1);
row_acc_overflow = zeros(numel(pareto), 1);
row_saturation = zeros(numel(pareto), 1);
row_pass = false(numel(pareto), 1);
candidate_result = repmat(struct(), 1, numel(pareto));

for candidate_idx = 1:numel(pareto)
    candidate = pareto(candidate_idx);
    candidate_name = candidate.name;
    cic_order = candidate.row.CIC_ORDER;
    frac_w = candidate.row.FRAC_W;
    coeff_int = int64(candidate.coeff_int);
    total_overflow = 0;
    total_saturation = 0;
    output = struct();
    reference = struct();
    comp_stat = struct();
    cic_stat = struct();

    for stimulus_idx = 1:numel(stimulus_name)
        one_name = stimulus_name{stimulus_idx};
        [compensated, comp_stat.(one_name)] = ...
            fir_compensation_bittrue(stage3.(one_name), coeff_int, ...
            frac_w, STAGE3_W, COMP_ACC_W);
        [output.(one_name), cic_stat.(one_name)] = ...
            cic_interp16_bittrue(compensated, R_CIC, cic_order, ...
            M_CIC, STAGE3_W, STAGE3_W, zeros(1, 2*cic_order));
        reference.(one_name) = floating_tail_reference( ...
            stage3.(one_name), candidate.h_comp, candidate.h_cic, R_CIC);
        total_overflow = total_overflow + ...
            front_stat.(one_name).total_acc_overflow + ...
            comp_stat.(one_name).acc_overflow_count;
        total_saturation = total_saturation + ...
            front_stat.(one_name).total_saturation + ...
            comp_stat.(one_name).output_sat_count + ...
            cic_stat.(one_name).output_sat_count;
    end

    impulse_segment = trim_impulse(output.impulse);
    impulse_amplitude = double(stimulus.impulse(1));
    h_bittrue = double(impulse_segment)*2^(DATA_W-STAGE3_W) / ...
                impulse_amplitude;
    response_metric = analyze_cic_response(h_bittrue, FS_IN, FS_OUT, ...
        F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, NFFT);

    random_snr = delta_snr_db(output.random, reference.random);
    [sinad15, thd15] = measure_sinad_thd( ...
        output.sine15k, 15000, FS_OUT);
    [sinad20, thd20] = measure_sinad_thd( ...
        output.sine20k, 20000, FS_OUT);

    write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
        'phase7_%s_impulse_golden_20bit.mem', candidate_name)), ...
        output.impulse, STAGE3_W);
    write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
        'phase7_%s_random_golden_20bit.mem', candidate_name)), ...
        output.random, STAGE3_W);

    row_name{candidate_idx} = candidate_name;
    row_order(candidate_idx) = cic_order;
    row_taps(candidate_idx) = candidate.row.COMP_TAPS;
    row_frac(candidate_idx) = frac_w;
    row_full_w(candidate_idx) = cic_stat.impulse.full_width;
    row_pass_abs(candidate_idx) = response_metric.pass_abs_max_db;
    row_ripple(candidate_idx) = response_metric.ripple_pp_db;
    row_stop(candidate_idx) = response_metric.stop_attn_db;
    row_gd(candidate_idx) = response_metric.gd_pp;
    row_random_snr(candidate_idx) = random_snr;
    row_sinad15(candidate_idx) = sinad15;
    row_thd15(candidate_idx) = thd15;
    row_sinad20(candidate_idx) = sinad20;
    row_thd20(candidate_idx) = thd20;
    row_acc_overflow(candidate_idx) = total_overflow;
    row_saturation(candidate_idx) = total_saturation;
    row_pass(candidate_idx) = response_metric.pass_abs_max_db < 0.01 && ...
        response_metric.stop_attn_db > 70 && ...
        random_snr >= 90 && total_overflow == 0 && total_saturation == 0;

    candidate_result(candidate_idx).name = candidate_name;
    candidate_result(candidate_idx).output = output;
    candidate_result(candidate_idx).reference = reference;
    candidate_result(candidate_idx).response_metric = response_metric;
    candidate_result(candidate_idx).comp_stat = comp_stat;
    candidate_result(candidate_idx).cic_stat = cic_stat;
end

result_table = table(row_name, row_order, row_taps, row_frac, row_full_w, ...
    row_pass_abs, row_ripple, row_stop, row_gd, row_random_snr, ...
    row_sinad15, row_thd15, row_sinad20, row_thd20, ...
    row_acc_overflow, row_saturation, row_pass, 'VariableNames', ...
    {'CANDIDATE', 'CIC_ORDER', 'COMP_TAPS', 'FRAC_W', 'FULL_WIDTH', ...
     'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', 'STOP_ATTN_DB', ...
     'GD_RIPPLE_SAMPLE', 'RANDOM_DELTA_SNR_DB', 'SINAD_15K_DB', ...
     'THD_15K_DB', 'SINAD_20K_DB', 'THD_20K_DB', ...
     'ACC_OVERFLOW', 'SATURATION', 'PASS'});
writetable(result_table, fullfile(result_dir, ...
    'phase7_bittrue_candidates.csv'));
save(fullfile(result_dir, 'phase7_bittrue_candidates.mat'), ...
    'candidate_result', 'result_table', 'stage3', 'stimulus', 'pareto');
write_summary(fullfile(result_dir, 'phase7_bittrue_summary.txt'), ...
    result_table);
plot_result(fullfile(figure_dir, 'phase7_bittrue_response.png'), ...
    candidate_result, result_table, F_PASS_HIGH, F_STOP_BEGIN);

disp(result_table);
if all(result_table.PASS)
    fprintf('Phase 7-C 结论：两条候选均通过全精度 bit-true。\n');
else
    error('Phase 7-C 存在未通过的候选，请检查结果表。');
end


function [y, stat] = simulate_front3( ...
        x, stage_config, width_profile, final_data_w)
    y = int64(x(:).');
    current_w = final_data_w;
    total_overflow = 0;
    total_saturation = 0;
    for stage_idx = 1:numel(stage_config)
        target_w = width_profile(stage_idx);
        if target_w < current_w
            [y, boundary_stat] = round_shift_sat_signed( ...
                y, current_w-target_w, target_w);
            total_saturation = total_saturation + ...
                               boundary_stat.output_sat_count;
            current_w = target_w;
        end
        cfg = stage_config(stage_idx);
        [y, one_stat] = interp2_polyphase_bittrue( ...
            y, cfg.coeff_int, cfg.frac_w, current_w, ...
            cfg.acc_w_recommended);
        total_overflow = total_overflow+one_stat.acc_overflow_count;
        total_saturation = total_saturation+one_stat.output_sat_count;
    end
    stat.total_acc_overflow = total_overflow;
    stat.total_saturation = total_saturation;
end


function y_ref = floating_tail_reference(x, h_comp, h_cic, rate_change)
    low = conv(double(x), double(h_comp));
    upsampled = zeros(1, rate_change*(numel(low)-1)+1);
    upsampled(1:rate_change:end) = low;
    y_ref = conv(upsampled, double(h_cic));
end


function segment = trim_impulse(data)
    nonzero = find(data ~= 0);
    if isempty(nonzero)
        error('位真冲激响应全零。');
    end
    segment = data(nonzero(1):nonzero(end));
end


function snr_db = delta_snr_db(candidate, reference)
    compare_count = min(numel(candidate), numel(reference));
    candidate = double(candidate(1:compare_count));
    reference = double(reference(1:compare_count));
    error_signal = candidate-reference;
    snr_db = 20*log10(norm(reference)/max(norm(error_signal), eps));
end


function [sinad_db, thd_db] = measure_sinad_thd(y, tone_hz, sample_rate)
    y = double(y(:));
    first_idx = floor(numel(y)*0.25)+1;
    last_idx = floor(numel(y)*0.75);
    y = y(first_idx:last_idx);
    n = (0:numel(y)-1).';
    basis = ones(numel(y), 11);
    for harmonic_idx = 1:5
        phase = 2*pi*harmonic_idx*tone_hz*n/sample_rate;
        basis(:, 2*harmonic_idx) = sin(phase);
        basis(:, 2*harmonic_idx+1) = cos(phase);
    end
    fit_coeff = basis\y;
    fundamental = basis(:, 2:3)*fit_coeff(2:3);
    harmonic = basis(:, 4:end)*fit_coeff(4:end);
    residual = y-basis*fit_coeff;
    signal_rms = rms(fundamental);
    harmonic_rms = rms(harmonic);
    noise_dist_rms = rms(harmonic+residual);
    sinad_db = 20*log10(signal_rms/max(noise_dist_rms, eps));
    thd_db = 20*log10(max(harmonic_rms, eps)/max(signal_rms, eps));
end


function x = make_sine(freq_hz, dbfs, sample_count, sample_rate, data_w)
    amplitude = (2^(data_w-1)-1)*10^(dbfs/20);
    n = 0:sample_count-1;
    x = int64(round(amplitude*sin(2*pi*freq_hz*n/sample_rate)));
end


function data = read_signed_hex_mem(filename, data_w)
    fid = fopen(filename, 'r');
    if fid < 0
        error('无法打开输入文件：%s', filename);
    end
    raw = textscan(fid, '%s');
    fclose(fid);
    data = int64(hex2dec(raw{1}).');
    threshold = int64(2^(data_w-1));
    modulus = int64(2^data_w);
    data(data >= threshold) = data(data >= threshold)-modulus;
end


function write_signed_hex_mem(filename, data, data_w)
    digits = ceil(data_w/4);
    unsigned_data = mod(double(int64(data(:))), 2^data_w);
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建输出文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for sample_idx = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], ...
            unsigned_data(sample_idx));
    end
end


function write_summary(filename, result_table)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Phase 7-C full-precision bit-true validation\n');
    fprintf(fid, '================================================\n');
    fprintf(fid, 'Architecture: Stage1-3 FIR -> compensation FIR -> ');
    fprintf(fid, 'comb -> upsample16 -> integrator\n');
    fprintf(fid, 'Stage3 data width = 20bit\n');
    fprintf(fid, 'Pass limits: pass<0.01dB, stop>70dB, ');
    fprintf(fid, 'random delta SNR>=90dB, overflow=0, saturation=0\n\n');
    for row_idx = 1:height(result_table)
        fprintf(fid, ['%s N=%d fullW=%d pass=%.8fdB stop=%.8fdB ' ...
            'deltaSNR=%.3fdB SINAD15=%.3fdB THD15=%.3fdB ' ...
            'SINAD20=%.3fdB THD20=%.3fdB overflow=%d sat=%d pass=%d\n'], ...
            result_table.CANDIDATE{row_idx}, ...
            result_table.CIC_ORDER(row_idx), ...
            result_table.FULL_WIDTH(row_idx), ...
            result_table.PASS_ABS_MAX_DB(row_idx), ...
            result_table.STOP_ATTN_DB(row_idx), ...
            result_table.RANDOM_DELTA_SNR_DB(row_idx), ...
            result_table.SINAD_15K_DB(row_idx), ...
            result_table.THD_15K_DB(row_idx), ...
            result_table.SINAD_20K_DB(row_idx), ...
            result_table.THD_20K_DB(row_idx), ...
            result_table.ACC_OVERFLOW(row_idx), ...
            result_table.SATURATION(row_idx), ...
            result_table.PASS(row_idx));
    end
end


function plot_result(filename, candidate_result, result_table, ...
        pass_edge, stop_begin)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_yellow = [0.82 0.88 0.05];
    line_color = {color_blue, color_purple};
    figure('Color', 'w', 'Position', [80 60 1500 900]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    for idx = 1:numel(candidate_result)
        metric = candidate_result(idx).response_metric;
        plot(metric.f/1e3, metric.H_db, 'Color', line_color{idx}, ...
            'LineWidth', 1.7); hold on;
    end
    xline(pass_edge/1e3, '--', 'Color', color_green);
    yline(0.01, '--', 'Color', color_yellow);
    yline(-0.01, '--', 'Color', color_yellow);
    xlim([0 22]); ylim([-0.025 0.025]);
    title('位真通带'); xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    legend(result_table.CANDIDATE{:}, '20 kHz', '+/-0.01 dB', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    for idx = 1:numel(candidate_result)
        metric = candidate_result(idx).response_metric;
        plot(metric.f/1e3, metric.H_db, 'Color', line_color{idx}, ...
            'LineWidth', 1.5); hold on;
    end
    xline(stop_begin/1e3, '--', 'Color', color_green);
    yline(-70, '--', 'Color', color_yellow);
    xlim([0 500]); ylim([-150 5]);
    title('位真首个镜像区'); xlabel('频率 / kHz'); ylabel('幅度 / dB');
    legend(result_table.CANDIDATE{:}, '24.1 kHz', '-70 dB', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    bar(categorical(result_table.CANDIDATE), ...
        result_table.RANDOM_DELTA_SNR_DB, 0.55, ...
        'FaceColor', color_green);
    yline(90, '--', 'Color', color_yellow);
    title('随机 PCM 相对浮点尾链误差'); ylabel('Delta SNR / dB');
    style_axes(gca);

    nexttile;
    values = [result_table.SINAD_15K_DB result_table.SINAD_20K_DB];
    bar(categorical(result_table.CANDIDATE), values, 'grouped');
    title('位真正弦 SINAD'); ylabel('SINAD / dB');
    legend('15 kHz', '20 kHz', 'Location', 'southwest');
    style_axes(gca);
    sgtitle('Phase 7-C FIR-CIC 全精度位真验证');
    exportgraphics(gcf, filename, 'Resolution', 180);
end


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
