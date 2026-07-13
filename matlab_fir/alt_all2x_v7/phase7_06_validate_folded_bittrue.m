clc; clear; close all;

%=============================================================
% 文件名       : phase7_06_validate_folded_bittrue.m
% 脚本名       : phase7_06_validate_folded_bittrue
% 功能简述     : Stage3 折叠 CIC 补偿方案的完整整数位真验证。
%                Stage1/2 保持 Phase 6，Stage3 使用搜索得到的
%                11tap Q14 系数，随后直接进入剪枝后的 N=3/N=4
%                CIC16。验证冲激、随机 PCM、15kHz 与 20kHz。
%
%                输出文件：
%                  folded_bittrue_results/folded_bittrue_candidates.csv
%                  folded_bittrue_results/folded_bittrue_summary.txt
%                  folded_bittrue_golden/phase7_folded_*_20bit.mem
%                  figures/folded_stage3_bittrue.png
%
% 当前默认配置：
%                  数据字长：24/22/20bit
%                  Stage3 ：11tap Q14 / 16bit
%                  N=3 profile：0-0-0-0-0-3
%                  N=4 profile：0-0-0-0-0-0-0-6
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增折叠 Stage3 完整位真验证。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
stable_dir = fullfile(repo_matlab_dir, 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
v2_dir = fullfile(repo_matlab_dir, 'alt_all2x_v2');
result_dir = fullfile(script_dir, 'folded_bittrue_results');
golden_dir = fullfile(script_dir, 'folded_bittrue_golden');
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
load(fullfile(script_dir, 'folded_stage3_results', ...
    'folded_stage3_pareto.mat'), 'pareto');
FS_IN = 44100;
FS_OUT = 5644800;
R_CIC = 16;
M_CIC = 1;
DATA_W = 24;
STAGE3_W = 20;
WIDTH_PROFILE = [24 22 20];
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_BEGIN = 24100;
EXPECTED_GAIN = 128;
DELTA_SNR_LIMIT_DB = 94;
NFFT = 2^20;

source_golden_dir = fullfile(v2_dir, 'golden');
stimulus.impulse = read_signed_hex_mem(fullfile(source_golden_dir, ...
    'stage1_strict_impulse_input_24bit.mem'), DATA_W);
stimulus.random = read_signed_hex_mem(fullfile(source_golden_dir, ...
    'stage1_strict_random_input_24bit.mem'), DATA_W);
stimulus.sine15k = make_sine(15000, -12, 2048, FS_IN, DATA_W);
stimulus.sine20k = make_sine(20000, -12, 2048, FS_IN, DATA_W);
stimulus_name = fieldnames(stimulus);

row_name = cell(numel(pareto), 1);
row_order = zeros(numel(pareto), 1);
row_taps = zeros(numel(pareto), 1);
row_frac = zeros(numel(pareto), 1);
row_profile = cell(numel(pareto), 1);
row_pass_abs = zeros(numel(pareto), 1);
row_stop = zeros(numel(pareto), 1);
row_delta_snr = zeros(numel(pareto), 1);
row_sinad15 = zeros(numel(pareto), 1);
row_thd15 = zeros(numel(pareto), 1);
row_sinad20 = zeros(numel(pareto), 1);
row_thd20 = zeros(numel(pareto), 1);
row_overflow = zeros(numel(pareto), 1);
row_saturation = zeros(numel(pareto), 1);
row_pass = false(numel(pareto), 1);
candidate_result = repmat(struct(), 1, numel(pareto));

for candidate_idx = 1:numel(pareto)
    candidate = pareto(candidate_idx);
    cic_order = candidate.row.CIC_ORDER;
    stage_config = best_config(1:3);
    stage_config(3).coeff_int = int64(candidate.coeff_int);
    stage_config(3).frac_w = candidate.row.FRAC_W;
    stage_config(3).acc_w_recommended = 38;

    best_found = false;
    normalization_shift = (cic_order-1)*log2(R_CIC);
    for final_prune = 0:normalization_shift
        trial_profile = zeros(1, 2*cic_order);
        trial_profile(end) = final_prune;
        trial_output = struct();
        trial_reference = struct();
        trial_stage3_output = struct();
        trial_overflow = 0;
        trial_saturation = 0;
        for stimulus_idx = 1:numel(stimulus_name)
            one_name = stimulus_name{stimulus_idx};
            [trial_stage3_output.(one_name), front_stat] = ...
                simulate_front3(stimulus.(one_name), stage_config, ...
                    WIDTH_PROFILE, DATA_W);
            [trial_output.(one_name), cic_stat] = ...
                cic_interp16_bittrue(trial_stage3_output.(one_name), ...
                    R_CIC, cic_order, M_CIC, STAGE3_W, STAGE3_W, ...
                    trial_profile);
            trial_reference.(one_name) = floating_full_reference( ...
                stimulus.(one_name), candidate.h_total, 128);
            trial_overflow = trial_overflow+front_stat.total_acc_overflow;
            trial_saturation = trial_saturation+ ...
                front_stat.total_saturation+cic_stat.output_sat_count;
        end

        impulse_segment = trim_impulse(trial_output.impulse);
        h_bittrue = double(impulse_segment)*16/ ...
                    double(stimulus.impulse(1));
        trial_metric = analyze_cic_response(h_bittrue, FS_IN, FS_OUT, ...
            F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, NFFT);
        trial_snr = delta_snr_db( ...
            trial_output.random*int64(16), trial_reference.random);
        trial_pass = trial_metric.pass_abs_max_db < 0.01 && ...
            trial_metric.stop_attn_db > 70 && ...
            trial_snr >= DELTA_SNR_LIMIT_DB && ...
            trial_overflow == 0 && trial_saturation == 0;

        fprintf(['%s prune=%d pass=%.8fdB stop=%.3fdB ' ...
            'deltaSNR=%.3fdB result=%d\n'], candidate.name, ...
            final_prune, trial_metric.pass_abs_max_db, ...
            trial_metric.stop_attn_db, trial_snr, trial_pass);
        if trial_pass
            best_found = true;
            prune_profile = trial_profile;
            output = trial_output;
            reference = trial_reference;
            stage3_output = trial_stage3_output;
            total_overflow = trial_overflow;
            total_saturation = trial_saturation;
            metric = trial_metric;
            random_snr = trial_snr;
        end
    end
    if ~best_found
        error('%s 未找到满足定点门限的剪枝档位。', candidate.name);
    end

    [sinad15, thd15] = measure_sinad_thd( ...
        output.sine15k, 15000, FS_OUT);
    [sinad20, thd20] = measure_sinad_thd( ...
        output.sine20k, 20000, FS_OUT);

    write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
        'phase7_%s_stage3_impulse_20bit.mem', candidate.name)), ...
        stage3_output.impulse, STAGE3_W);
    write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
        'phase7_%s_stage3_random_20bit.mem', candidate.name)), ...
        stage3_output.random, STAGE3_W);
    write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
        'phase7_%s_impulse_golden_20bit.mem', candidate.name)), ...
        output.impulse, STAGE3_W);
    write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
        'phase7_%s_random_golden_20bit.mem', candidate.name)), ...
        output.random, STAGE3_W);

    row_name{candidate_idx} = candidate.name;
    row_order(candidate_idx) = cic_order;
    row_taps(candidate_idx) = candidate.row.STAGE3_TAPS;
    row_frac(candidate_idx) = candidate.row.FRAC_W;
    row_profile{candidate_idx} = profile_text(prune_profile);
    row_pass_abs(candidate_idx) = metric.pass_abs_max_db;
    row_stop(candidate_idx) = metric.stop_attn_db;
    row_delta_snr(candidate_idx) = random_snr;
    row_sinad15(candidate_idx) = sinad15;
    row_thd15(candidate_idx) = thd15;
    row_sinad20(candidate_idx) = sinad20;
    row_thd20(candidate_idx) = thd20;
    row_overflow(candidate_idx) = total_overflow;
    row_saturation(candidate_idx) = total_saturation;
    row_pass(candidate_idx) = metric.pass_abs_max_db < 0.01 && ...
        metric.stop_attn_db > 70 && ...
        random_snr >= DELTA_SNR_LIMIT_DB && ...
        total_overflow == 0 && total_saturation == 0;

    candidate_result(candidate_idx).name = candidate.name;
    candidate_result(candidate_idx).metric = metric;
    candidate_result(candidate_idx).output = output;
    candidate_result(candidate_idx).stage3_output = stage3_output;
end

result_table = table(row_name, row_order, row_taps, row_frac, ...
    row_profile, row_pass_abs, row_stop, row_delta_snr, row_sinad15, ...
    row_thd15, row_sinad20, row_thd20, row_overflow, row_saturation, ...
    row_pass, 'VariableNames', ...
    {'CANDIDATE', 'CIC_ORDER', 'STAGE3_TAPS', 'FRAC_W', 'PRUNE_LSB', ...
     'PASS_ABS_MAX_DB', 'STOP_ATTN_DB', 'RANDOM_DELTA_SNR_DB', ...
     'SINAD_15K_DB', 'THD_15K_DB', 'SINAD_20K_DB', 'THD_20K_DB', ...
     'ACC_OVERFLOW', 'SATURATION', 'PASS'});
writetable(result_table, fullfile(result_dir, ...
    'folded_bittrue_candidates.csv'));
save(fullfile(result_dir, 'folded_bittrue_candidates.mat'), ...
    'candidate_result', 'result_table', 'pareto');
write_summary(fullfile(result_dir, 'folded_bittrue_summary.txt'), ...
    result_table);
plot_result(fullfile(figure_dir, 'folded_stage3_bittrue.png'), ...
    candidate_result, result_table, F_PASS_HIGH, F_STOP_BEGIN);

disp(result_table);
if all(result_table.PASS)
    fprintf('Stage3 折叠补偿位真验证通过。\n');
else
    error('Stage3 折叠补偿存在未通过候选。');
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
            total_saturation = total_saturation+ ...
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


function y_ref = floating_full_reference(x, h_total, rate_change)
    upsampled = zeros(1, rate_change*(numel(x)-1)+1);
    upsampled(1:rate_change:end) = double(x);
    y_ref = conv(upsampled, double(h_total));
end


function segment = trim_impulse(data)
    nonzero = find(data ~= 0);
    if isempty(nonzero)
        error('折叠方案冲激响应全零。');
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


function text_value = profile_text(profile)
    text_value = sprintf('%d-', profile);
    text_value(end) = [];
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
    fprintf(fid, 'Phase 7 folded Stage3 bit-true validation\n');
    fprintf(fid, '==========================================\n');
    fprintf(fid, 'Architecture: Stage1 -> Stage2 -> folded Stage3 -> CIC16\n');
    fprintf(fid, 'Limits: pass<0.01dB, stop>70dB, delta SNR>=94dB, ');
    fprintf(fid, 'overflow=0, saturation=0\n\n');
    for idx = 1:height(result_table)
        fprintf(fid, ['%s N=%d profile=%s pass=%.8fdB stop=%.8fdB ' ...
            'deltaSNR=%.3fdB SINAD15=%.3fdB THD15=%.3fdB ' ...
            'SINAD20=%.3fdB THD20=%.3fdB overflow=%d sat=%d pass=%d\n'], ...
            result_table.CANDIDATE{idx}, result_table.CIC_ORDER(idx), ...
            result_table.PRUNE_LSB{idx}, ...
            result_table.PASS_ABS_MAX_DB(idx), ...
            result_table.STOP_ATTN_DB(idx), ...
            result_table.RANDOM_DELTA_SNR_DB(idx), ...
            result_table.SINAD_15K_DB(idx), result_table.THD_15K_DB(idx), ...
            result_table.SINAD_20K_DB(idx), result_table.THD_20K_DB(idx), ...
            result_table.ACC_OVERFLOW(idx), result_table.SATURATION(idx), ...
            result_table.PASS(idx));
    end
end


function plot_result(filename, candidate_result, result_table, ...
        pass_edge, stop_begin)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_yellow = [0.82 0.88 0.05];
    line_color = {color_blue, color_purple};
    figure('Color', 'w', 'Position', [80 60 1500 760]);
    tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    for idx = 1:numel(candidate_result)
        metric = candidate_result(idx).metric;
        plot(metric.f/1e3, metric.H_db, 'Color', line_color{idx}, ...
            'LineWidth', 1.7); hold on;
    end
    yline(0.01, '--', 'Color', color_yellow);
    yline(-0.01, '--', 'Color', color_yellow);
    xline(pass_edge/1e3, '--', 'Color', color_green);
    xlim([0 22]); ylim([-0.025 0.025]);
    title('折叠方案位真通带'); xlabel('频率 / kHz');
    ylabel('相对幅度 / dB');
    legend(result_table.CANDIDATE{:}, '+/-0.01 dB', '20 kHz', ...
        'Location', 'southwest'); style_axes(gca);
    nexttile;
    for idx = 1:numel(candidate_result)
        metric = candidate_result(idx).metric;
        plot(metric.f/1e3, metric.H_db, 'Color', line_color{idx}, ...
            'LineWidth', 1.4); hold on;
    end
    yline(-70, '--', 'Color', color_yellow);
    xline(stop_begin/1e3, '--', 'Color', color_green);
    xlim([0 500]); ylim([-150 5]);
    title('折叠方案位真阻带'); xlabel('频率 / kHz');
    ylabel('幅度 / dB');
    legend(result_table.CANDIDATE{:}, '-70 dB', '24.1 kHz', ...
        'Location', 'southwest'); style_axes(gca);
    sgtitle('Phase 7-E Stage3 折叠补偿位真验证');
    exportgraphics(gcf, filename, 'Resolution', 180);
end


function style_axes(ax)
    grid(ax, 'on'); box(ax, 'on');
    ax.FontName = 'Microsoft YaHei'; ax.FontSize = 11;
    ax.LineWidth = 1.1;
    ax.XMinorTick = 'on'; ax.YMinorTick = 'on';
    ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';
end
