%% 1）主流程：phase7_04_search_hogenauer_pruning
% 功能说明：执行参数搜索和 Pareto 筛选，在满足指标的前提下降低字长或资源开销。

clc; clear; close all;

%=============================================================
% 文件名       : phase7_04_search_hogenauer_pruning.m
% 脚本名       : phase7_04_search_hogenauer_pruning
% 功能简述     : Phase 7 CIC 的 Hogenauer 风格逐级 LSB 剪枝搜索。
%                以全精度 CIC 为起点，每次尝试从某一级开始对其后
%                所有级累计丢弃 1 个 LSB，保持二进制小数点一致，
%                并用随机 PCM Delta-SNR、冲激频响与饱和计数约束
%                搜索。N=3 与 N=4 候选分别独立执行。
%
%                输出文件：
%                  hogenauer_results/phase7_hogenauer_search.csv
%                  hogenauer_results/phase7_hogenauer_selected.csv
%                  hogenauer_results/phase7_hogenauer_selected.mat
%                  hogenauer_results/phase7_hogenauer_summary.txt
%                  bittrue_golden/phase7_*_pruned_*_20bit.mem
%                  figures/phase7_hogenauer_pruning.png
%
% 当前默认配置：
%                  随机 PCM Delta-SNR：>=94dB
%                  通带最大绝对误差：<0.01dB
%                  阻带衰减        ：>70dB
%                  输出饱和        ：0
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 CIC 逐级 LSB 剪枝搜索。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
stable_dir = fullfile(repo_matlab_dir, 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
result_dir = fullfile(script_dir, 'hogenauer_results');
golden_dir = fullfile(script_dir, 'bittrue_golden');
figure_dir = fullfile(script_dir, 'figures');

addpath(bittrue_dir);
addpath(script_dir);
for one_dir = {result_dir, golden_dir, figure_dir}
    if ~exist(one_dir{1}, 'dir')
        mkdir(one_dir{1});
    end
end

load(fullfile(script_dir, 'bittrue_results', ...
    'phase7_bittrue_candidates.mat'), 'candidate_result', ...
    'stage3', 'stimulus', 'pareto');

FS_IN = 44100;
FS_OUT = 5644800;
R_CIC = 16;
M_CIC = 1;
STAGE3_W = 20;
COMP_ACC_W = 40;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_BEGIN = 24100;
EXPECTED_GAIN = 128;
PASS_LIMIT_DB = 0.01;
STOP_LIMIT_DB = 70;
DELTA_SNR_LIMIT_DB = 94;
NFFT_SEARCH = 2^18;
NFFT_FINAL = 2^20;

search_candidate = {};
search_profile = {};
search_bit_cost = [];
search_delta_snr = [];
search_pass_abs = [];
search_stop = [];
search_saturation = [];
search_pass = [];
search_iteration = [];
search_start_stage = [];
search_row = 0;

selected_name = cell(numel(pareto), 1);
selected_order = zeros(numel(pareto), 1);
selected_profile = cell(numel(pareto), 1);
selected_full_cost = zeros(numel(pareto), 1);
selected_pruned_cost = zeros(numel(pareto), 1);
selected_saved_bits = zeros(numel(pareto), 1);
selected_delta_snr = zeros(numel(pareto), 1);
selected_pass_abs = zeros(numel(pareto), 1);
selected_stop = zeros(numel(pareto), 1);
selected_sinad15 = zeros(numel(pareto), 1);
selected_sinad20 = zeros(numel(pareto), 1);
selected_saturation = zeros(numel(pareto), 1);
selected_pass = false(numel(pareto), 1);
selected = repmat(struct(), 1, numel(pareto));

for candidate_idx = 1:numel(pareto)
    candidate = pareto(candidate_idx);
    candidate_name = candidate.name;
    cic_order = candidate.row.CIC_ORDER;
    coeff_int = int64(candidate.coeff_int);
    frac_w = candidate.row.FRAC_W;
    normalization_shift = (cic_order-1)*log2(R_CIC);

    compensated = struct();
    for one_name = fieldnames(stage3).'
        stimulus_name = one_name{1};
        [compensated.(stimulus_name), comp_stat] = ...
            fir_compensation_bittrue(stage3.(stimulus_name), ...
            coeff_int, frac_w, STAGE3_W, COMP_ACC_W);
        if comp_stat.acc_overflow_count ~= 0 || ...
                comp_stat.output_sat_count ~= 0
            error('%s 补偿 FIR 发生溢出或饱和。', candidate_name);
        end
    end

    current_profile = zeros(1, 2*cic_order);
    [current_eval, current_output] = evaluate_profile( ...
        current_profile, compensated, candidate_result(candidate_idx), ...
        stimulus.impulse(1), R_CIC, cic_order, M_CIC, STAGE3_W, ...
        FS_IN, FS_OUT, F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, ...
        EXPECTED_GAIN, NFFT_SEARCH, PASS_LIMIT_DB, STOP_LIMIT_DB, ...
        DELTA_SNR_LIMIT_DB);
    accepted_iteration = 0;

    while true
        trial_found = false;
        best_trial_profile = [];
        best_trial_eval = struct();
        best_trial_output = struct();
        best_saved_bits = -inf;
        best_delta_snr = -inf;

        for start_stage = 1:2*cic_order
            trial_profile = current_profile;
            trial_profile(start_stage:end) = ...
                trial_profile(start_stage:end)+1;
            if trial_profile(end) > normalization_shift
                continue;
            end

            [trial_eval, trial_output] = evaluate_profile( ...
                trial_profile, compensated, ...
                candidate_result(candidate_idx), stimulus.impulse(1), ...
                R_CIC, cic_order, M_CIC, STAGE3_W, FS_IN, FS_OUT, ...
                F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, ...
                NFFT_SEARCH, PASS_LIMIT_DB, STOP_LIMIT_DB, ...
                DELTA_SNR_LIMIT_DB);

            search_row = search_row+1;
            search_candidate{search_row, 1} = candidate_name; %#ok<SAGROW>
            search_profile{search_row, 1} = profile_text(trial_profile); %#ok<SAGROW>
            search_bit_cost(search_row, 1) = trial_eval.bit_cost; %#ok<SAGROW>
            search_delta_snr(search_row, 1) = trial_eval.delta_snr_db; %#ok<SAGROW>
            search_pass_abs(search_row, 1) = trial_eval.pass_abs_max_db; %#ok<SAGROW>
            search_stop(search_row, 1) = trial_eval.stop_attn_db; %#ok<SAGROW>
            search_saturation(search_row, 1) = trial_eval.saturation; %#ok<SAGROW>
            search_pass(search_row, 1) = trial_eval.pass; %#ok<SAGROW>
            search_iteration(search_row, 1) = accepted_iteration+1; %#ok<SAGROW>
            search_start_stage(search_row, 1) = start_stage; %#ok<SAGROW>

            saved_bits = current_eval.full_bit_cost-trial_eval.bit_cost;
            if trial_eval.pass && (saved_bits > best_saved_bits || ...
                    (saved_bits == best_saved_bits && ...
                     trial_eval.delta_snr_db > best_delta_snr))
                trial_found = true;
                best_trial_profile = trial_profile;
                best_trial_eval = trial_eval;
                best_trial_output = trial_output;
                best_saved_bits = saved_bits;
                best_delta_snr = trial_eval.delta_snr_db;
            end
        end

        if ~trial_found
            break;
        end
        current_profile = best_trial_profile;
        current_eval = best_trial_eval;
        current_output = best_trial_output;
        accepted_iteration = accepted_iteration+1;
    end

    % 舍入误差并不保证随剪枝位数单调变化，再补做单起点直扫，
    % 避免因为中间某一位未通过而错过后续重新落入误差谷的候选。
    direct_best_profile = current_profile;
    direct_best_eval = current_eval;
    direct_best_output = current_output;
    for start_stage = 1:2*cic_order
        for drop_count = 1:normalization_shift
            trial_profile = zeros(1, 2*cic_order);
            trial_profile(start_stage:end) = drop_count;
            [trial_eval, trial_output] = evaluate_profile( ...
                trial_profile, compensated, ...
                candidate_result(candidate_idx), stimulus.impulse(1), ...
                R_CIC, cic_order, M_CIC, STAGE3_W, FS_IN, FS_OUT, ...
                F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, ...
                NFFT_SEARCH, PASS_LIMIT_DB, STOP_LIMIT_DB, ...
                DELTA_SNR_LIMIT_DB);

            search_row = search_row+1;
            search_candidate{search_row, 1} = candidate_name; %#ok<SAGROW>
            search_profile{search_row, 1} = profile_text(trial_profile); %#ok<SAGROW>
            search_bit_cost(search_row, 1) = trial_eval.bit_cost; %#ok<SAGROW>
            search_delta_snr(search_row, 1) = trial_eval.delta_snr_db; %#ok<SAGROW>
            search_pass_abs(search_row, 1) = trial_eval.pass_abs_max_db; %#ok<SAGROW>
            search_stop(search_row, 1) = trial_eval.stop_attn_db; %#ok<SAGROW>
            search_saturation(search_row, 1) = trial_eval.saturation; %#ok<SAGROW>
            search_pass(search_row, 1) = trial_eval.pass; %#ok<SAGROW>
            search_iteration(search_row, 1) = -1; %#ok<SAGROW>
            search_start_stage(search_row, 1) = start_stage; %#ok<SAGROW>

            if trial_eval.pass && ...
                    (trial_eval.bit_cost < direct_best_eval.bit_cost || ...
                     (trial_eval.bit_cost == direct_best_eval.bit_cost && ...
                      trial_eval.delta_snr_db > ...
                      direct_best_eval.delta_snr_db))
                direct_best_profile = trial_profile;
                direct_best_eval = trial_eval;
                direct_best_output = trial_output;
            end
        end
    end
    current_profile = direct_best_profile;
    current_eval = direct_best_eval;
    current_output = direct_best_output;

    % 用更高 FFT 点数复核最终剪枝候选。
    [final_eval, final_output] = evaluate_profile( ...
        current_profile, compensated, candidate_result(candidate_idx), ...
        stimulus.impulse(1), R_CIC, cic_order, M_CIC, STAGE3_W, ...
        FS_IN, FS_OUT, F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, ...
        EXPECTED_GAIN, NFFT_FINAL, PASS_LIMIT_DB, STOP_LIMIT_DB, ...
        DELTA_SNR_LIMIT_DB);
    [sinad15, thd15] = measure_sinad_thd( ...
        final_output.sine15k, 15000, FS_OUT);
    [sinad20, thd20] = measure_sinad_thd( ...
        final_output.sine20k, 20000, FS_OUT);

    write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
        'phase7_%s_pruned_impulse_golden_20bit.mem', candidate_name)), ...
        final_output.impulse, STAGE3_W);
    write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
        'phase7_%s_pruned_random_golden_20bit.mem', candidate_name)), ...
        final_output.random, STAGE3_W);

    selected_name{candidate_idx} = candidate_name;
    selected_order(candidate_idx) = cic_order;
    selected_profile{candidate_idx} = profile_text(current_profile);
    selected_full_cost(candidate_idx) = final_eval.full_bit_cost;
    selected_pruned_cost(candidate_idx) = final_eval.bit_cost;
    selected_saved_bits(candidate_idx) = ...
        final_eval.full_bit_cost-final_eval.bit_cost;
    selected_delta_snr(candidate_idx) = final_eval.delta_snr_db;
    selected_pass_abs(candidate_idx) = final_eval.pass_abs_max_db;
    selected_stop(candidate_idx) = final_eval.stop_attn_db;
    selected_sinad15(candidate_idx) = sinad15;
    selected_sinad20(candidate_idx) = sinad20;
    selected_saturation(candidate_idx) = final_eval.saturation;
    selected_pass(candidate_idx) = final_eval.pass;

    selected(candidate_idx).name = candidate_name;
    selected(candidate_idx).profile = current_profile;
    selected(candidate_idx).evaluation = final_eval;
    selected(candidate_idx).output = final_output;
    selected(candidate_idx).sinad15_db = sinad15;
    selected(candidate_idx).thd15_db = thd15;
    selected(candidate_idx).sinad20_db = sinad20;
    selected(candidate_idx).thd20_db = thd20;

    fprintf('%s 剪枝完成：profile=%s，saved=%d bit，SNR=%.2fdB。\n', ...
        candidate_name, profile_text(current_profile), ...
        selected_saved_bits(candidate_idx), final_eval.delta_snr_db);
end

search_table = table(search_candidate, search_iteration, ...
    search_start_stage, search_profile, search_bit_cost, ...
    search_delta_snr, search_pass_abs, search_stop, ...
    search_saturation, search_pass, 'VariableNames', ...
    {'CANDIDATE', 'ITERATION', 'START_STAGE', 'PRUNE_LSB', ...
     'STAGE_BIT_COST', 'RANDOM_DELTA_SNR_DB', 'PASS_ABS_MAX_DB', ...
     'STOP_ATTN_DB', 'SATURATION', 'PASS'});
selected_table = table(selected_name, selected_order, selected_profile, ...
    selected_full_cost, selected_pruned_cost, selected_saved_bits, ...
    selected_delta_snr, selected_pass_abs, selected_stop, ...
    selected_sinad15, selected_sinad20, selected_saturation, ...
    selected_pass, 'VariableNames', ...
    {'CANDIDATE', 'CIC_ORDER', 'PRUNE_LSB', 'FULL_STAGE_BIT_COST', ...
     'PRUNED_STAGE_BIT_COST', 'SAVED_STAGE_BITS', ...
     'RANDOM_DELTA_SNR_DB', 'PASS_ABS_MAX_DB', 'STOP_ATTN_DB', ...
     'SINAD_15K_DB', 'SINAD_20K_DB', 'SATURATION', 'PASS'});

writetable(search_table, fullfile(result_dir, ...
    'phase7_hogenauer_search.csv'));
writetable(selected_table, fullfile(result_dir, ...
    'phase7_hogenauer_selected.csv'));
save(fullfile(result_dir, 'phase7_hogenauer_selected.mat'), ...
    'selected', 'selected_table');
write_summary(fullfile(result_dir, 'phase7_hogenauer_summary.txt'), ...
    selected_table);
plot_selected(fullfile(figure_dir, 'phase7_hogenauer_pruning.png'), ...
    selected, selected_table);

disp(selected_table);
if all(selected_table.PASS)
    fprintf('Phase 7-C 剪枝结论：两条候选均通过。\n');
else
    error('Phase 7-C 剪枝后存在未通过候选。');
end


% 2）局部函数模块：evaluate_profile


% 功能说明：封装 evaluate_profile 对应的局部计算，供主流程复用并保持代码层次清晰。
function [evaluation, output] = evaluate_profile( ...
        profile, compensated, baseline_result, impulse_amplitude, ...
        rate_change, cic_order, diff_delay, data_w, fs_in, fs_out, ...
        pass_low, pass_high, stop_begin, expected_gain, nfft, ...
        pass_limit, stop_limit, snr_limit)
    names = fieldnames(compensated);
    saturation = 0;
    output = struct();
    trace = struct();
    for name_idx = 1:numel(names)
        one_name = names{name_idx};
        [output.(one_name), stat, trace.(one_name)] = ...
            cic_interp16_bittrue(compensated.(one_name), ...
            rate_change, cic_order, diff_delay, data_w, data_w, profile);
        saturation = saturation+stat.output_sat_count;
    end

    if any(output.impulse ~= 0)
        impulse_segment = trim_impulse(output.impulse);
        h_bittrue = double(impulse_segment)*16/double(impulse_amplitude);
        metric = analyze_cic_response(h_bittrue, fs_in, fs_out, ...
            pass_low, pass_high, stop_begin, expected_gain, nfft);
    else
        metric.f = [];
        metric.H_db = [];
        metric.pass_abs_max_db = inf;
        metric.stop_attn_db = -inf;
        metric.gd_pp = inf;
    end
    delta_snr = delta_snr_db( ...
        output.random, baseline_result.reference.random);

    evaluation.full_bit_cost = ...
        numel(profile)*(data_w+ceil(cic_order*log2(rate_change*diff_delay)));
    evaluation.bit_cost = sum(trace.impulse.stage_width);
    evaluation.delta_snr_db = delta_snr;
    evaluation.pass_abs_max_db = metric.pass_abs_max_db;
    evaluation.stop_attn_db = metric.stop_attn_db;
    evaluation.gd_ripple_sample = metric.gd_pp;
    evaluation.saturation = saturation;
    evaluation.metric = metric;
    evaluation.pass = metric.pass_abs_max_db < pass_limit && ...
        metric.stop_attn_db > stop_limit && delta_snr >= snr_limit && ...
        saturation == 0;
end


% 3）局部函数模块：trim_impulse


% 功能说明：按指定插值倍率展开冲激响应并构造当前级或完整链路的等效响应。
function segment = trim_impulse(data)
    nonzero = find(data ~= 0);
    if isempty(nonzero)
        error('剪枝冲激响应全零。');
    end
    segment = data(nonzero(1):nonzero(end));
end


% 4）局部函数模块：delta_snr_db


% 功能说明：封装 delta_snr_db 对应的局部计算，供主流程复用并保持代码层次清晰。
function snr_db = delta_snr_db(candidate, reference)
    compare_count = min(numel(candidate), numel(reference));
    candidate = double(candidate(1:compare_count));
    reference = double(reference(1:compare_count));
    error_signal = candidate-reference;
    snr_db = 20*log10(norm(reference)/max(norm(error_signal), eps));
end


% 5）局部函数模块：profile_text


% 功能说明：封装 profile_text 对应的局部计算，供主流程复用并保持代码层次清晰。
function text_value = profile_text(profile)
    text_value = sprintf('%d-', profile);
    text_value(end) = [];
end


% 6）局部函数模块：measure_sinad_thd


% 功能说明：封装 measure_sinad_thd 对应的局部计算，供主流程复用并保持代码层次清晰。
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


% 7）局部函数模块：write_signed_hex_mem


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
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


% 8）局部函数模块：write_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_summary(filename, selected_table)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Phase 7-C Hogenauer-style LSB pruning\n');
    fprintf(fid, '========================================\n');
    fprintf(fid, 'Limits: pass<0.01dB, stop>70dB, ');
    fprintf(fid, 'random delta SNR>=94dB, saturation=0\n\n');
    for row_idx = 1:height(selected_table)
        fprintf(fid, ['%s N=%d profile=%s fullCost=%d prunedCost=%d ' ...
            'saved=%d deltaSNR=%.3fdB pass=%.8fdB stop=%.8fdB ' ...
            'SINAD15=%.3fdB SINAD20=%.3fdB sat=%d result=%d\n'], ...
            selected_table.CANDIDATE{row_idx}, ...
            selected_table.CIC_ORDER(row_idx), ...
            selected_table.PRUNE_LSB{row_idx}, ...
            selected_table.FULL_STAGE_BIT_COST(row_idx), ...
            selected_table.PRUNED_STAGE_BIT_COST(row_idx), ...
            selected_table.SAVED_STAGE_BITS(row_idx), ...
            selected_table.RANDOM_DELTA_SNR_DB(row_idx), ...
            selected_table.PASS_ABS_MAX_DB(row_idx), ...
            selected_table.STOP_ATTN_DB(row_idx), ...
            selected_table.SINAD_15K_DB(row_idx), ...
            selected_table.SINAD_20K_DB(row_idx), ...
            selected_table.SATURATION(row_idx), ...
            selected_table.PASS(row_idx));
    end
end


% 9）局部函数模块：plot_selected


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function plot_selected(filename, selected, selected_table)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_yellow = [0.82 0.88 0.05];
    line_color = {color_blue, color_purple};
    figure('Color', 'w', 'Position', [80 60 1500 850]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    for idx = 1:numel(selected)
        metric = selected(idx).evaluation.metric;
        plot(metric.f/1e3, metric.H_db, 'Color', line_color{idx}, ...
            'LineWidth', 1.7); hold on;
    end
    yline(0.01, '--', 'Color', color_yellow);
    yline(-0.01, '--', 'Color', color_yellow);
    xline(20, '--', 'Color', color_green);
    xlim([0 22]); ylim([-0.025 0.025]);
    title('剪枝后通带'); xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    legend(selected_table.CANDIDATE{:}, '+/-0.01 dB', '20 kHz', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    for idx = 1:numel(selected)
        metric = selected(idx).evaluation.metric;
        plot(metric.f/1e3, metric.H_db, 'Color', line_color{idx}, ...
            'LineWidth', 1.4); hold on;
    end
    yline(-70, '--', 'Color', color_yellow);
    xline(24.1, '--', 'Color', color_green);
    xlim([0 500]); ylim([-150 5]);
    title('剪枝后首个镜像区'); xlabel('频率 / kHz'); ylabel('幅度 / dB');
    legend(selected_table.CANDIDATE{:}, '-70 dB', '24.1 kHz', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    cost_value = [selected_table.FULL_STAGE_BIT_COST, ...
                  selected_table.PRUNED_STAGE_BIT_COST];
    bar(categorical(selected_table.CANDIDATE), cost_value, 'grouped');
    title('CIC 逐级寄存位成本'); ylabel('总 stage bits');
    legend('全精度', '剪枝后', 'Location', 'southwest');
    style_axes(gca);

    nexttile;
    bar(categorical(selected_table.CANDIDATE), ...
        selected_table.RANDOM_DELTA_SNR_DB, 0.55, ...
        'FaceColor', color_green);
    yline(94, '--', 'Color', color_yellow);
    title('剪枝后随机 PCM 误差'); ylabel('Delta SNR / dB');
    style_axes(gca);
    sgtitle('Phase 7-C Hogenauer 风格 LSB 剪枝');
    exportgraphics(gcf, filename, 'Resolution', 180);
end


% 10）局部函数模块：style_axes


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
