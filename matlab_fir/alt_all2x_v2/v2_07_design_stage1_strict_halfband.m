clc; clear; close all;

%=============================================================
% 文件名       : v2_07_design_stage1_strict_halfband.m
% 脚本名       : v2_07_design_stage1_strict_halfband
% 功能简述     : 搜索 Stage 1 严格半带 FIR 的阶数与定点 Q 格式，
%                强制一个 polyphase 分支退化为纯延时，并强制两相
%                整数系数和精确等于 2^FRAC_W，再检查 128x 总链路。
%
%                输出文件：
%                  stage1_strict_halfband_search.csv
%                  stage1_strict_halfband_pareto.csv
%                  stage1_strict_halfband_candidates.mat
%                  stage1_strict_halfband_summary.txt
%                  stage1_strict_halfband_coeff_int.txt
%                  stage1_strict_halfband_response.png
%                  stage1_strict_halfband_config.mat
%
% 当前默认配置：
%                  Stage 1：44.1kHz -> 88.2kHz
%                  通带    ：10Hz～20kHz
%                  阻带入口：24.1kHz
%                  阶数搜索：40:4:160
%                  FRAC_W  ：[16 15 14 13 12]
%                  Profile A：总通带 <= 0.01dB，总阻带 >= 75dB，
%                             Stage 1 阻带 >= 76dB
%                  Profile B：总通带 <= 0.01dB，总阻带 >= 75dB
%                  Profile C：总通带 <= 0.02dB，总阻带 >= 73dB
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 Stage 1 严格半带搜索脚本。
%                2026-07-11：新增 Profile A/B/C、Q12～Q16、
%                            真实架构成本排序与 Pareto 候选导出。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
stable_dir = fullfile(script_dir, '..', 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
common_dir = fullfile(script_dir, 'common');

addpath(bittrue_dir);
addpath(common_dir);

FS_IN = 44100;
FS_STAGE1 = 88200;
FS_OUT = 5644800;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_STAGE1 = 24100;
PROFILE_A_PASS_DB = 0.01;
PROFILE_A_STOP_DB = 75;
PROFILE_A_STAGE1_STOP_DB = 76;
PROFILE_B_PASS_DB = 0.01;
PROFILE_B_STOP_DB = 75;
PROFILE_C_PASS_DB = 0.02;
PROFILE_C_STOP_DB = 73;
EXPECTED_GAIN = 128;
DATA_W = 24;
N_LIST = 40:4:160;
FRAC_W_LIST = [16 15 14 13 12];
NFFT_SEARCH = 2^16;
NFFT_FINAL = 2^18;

fp_norm = F_PASS_HIGH / (FS_STAGE1/2);
base_config = load_all2x_stage_config(stable_dir, DATA_W);
base_config = apply_canonical_halfband7(base_config, 4);

row_order = [];
row_taps = [];
row_frac_w = [];
row_coeff_w = [];
row_acc_w = [];
row_nonzero_half = [];
row_filter_phase_len = [];
row_mac_pair_count = [];
row_real_history_len = [];
row_phase0_sum = [];
row_phase1_sum = [];
row_stage_pass_abs = [];
row_stage_stop = [];
row_total_pass_abs = [];
row_total_stop = [];
row_total_dc = [];
row_pass_a = [];
row_pass_b = [];
row_pass_c = [];
row_profile = {};
candidate_config = {};

for n = N_LIST
    b_float = 2 * firhalfband(n, fp_norm);

    for frac_w = FRAC_W_LIST
        coeff_int = quantize_strict_halfband(b_float, frac_w);
        coeff_w = required_signed_width(coeff_int);
        acc_w = estimate_acc_width(coeff_int, DATA_W);
        center_idx = (numel(coeff_int) + 1) / 2;
        nonzero_half = nnz(coeff_int(1:center_idx));
        filter_phase_len = floor(numel(coeff_int) / 2);
        mac_pair_count = filter_phase_len / 2;
        real_history_len = filter_phase_len;

        cfg = base_config;
        cfg(1).order_n = n;
        cfg(1).taps = n + 1;
        cfg(1).coeff_int = coeff_int;
        cfg(1).frac_w = frac_w;
        cfg(1).coeff_w_min = coeff_w;
        cfg(1).coeff_w_design = coeff_w;
        cfg(1).acc_w_min = acc_w - 1;
        cfg(1).acc_w_recommended = acc_w;
        cfg(1).nonzero_half = nonzero_half;
        cfg(1).dc_gain = double(sum(coeff_int)) / 2^frac_w;
        cfg(1).phase0_gain = double(sum(coeff_int(1:2:end))) / 2^frac_w;
        cfg(1).phase1_gain = double(sum(coeff_int(2:2:end))) / 2^frac_w;

        stage_res = quick_response(double(coeff_int)/2^frac_w, ...
            FS_STAGE1, F_PASS_LOW, F_PASS_HIGH, F_STOP_STAGE1, ...
            2, NFFT_SEARCH);
        h_total = build_multistage_ir(cfg);
        total_res = quick_response(h_total, FS_OUT, ...
            F_PASS_LOW, F_PASS_HIGH, FS_IN-F_PASS_HIGH, ...
            EXPECTED_GAIN, NFFT_SEARCH);

        pass_a = (total_res.pass_abs_max_db <= PROFILE_A_PASS_DB) && ...
                 (total_res.stop_attn_db >= PROFILE_A_STOP_DB) && ...
                 (stage_res.stop_attn_db >= PROFILE_A_STAGE1_STOP_DB);
        pass_b = (total_res.pass_abs_max_db <= PROFILE_B_PASS_DB) && ...
                 (total_res.stop_attn_db >= PROFILE_B_STOP_DB);
        pass_c = (total_res.pass_abs_max_db <= PROFILE_C_PASS_DB) && ...
                 (total_res.stop_attn_db >= PROFILE_C_STOP_DB);

        if pass_a
            profile_name = 'A';
        elseif pass_b
            profile_name = 'B';
        elseif pass_c
            profile_name = 'C';
        else
            profile_name = 'FAIL';
        end

        row_order(end+1, 1) = n;
        row_taps(end+1, 1) = n + 1;
        row_frac_w(end+1, 1) = frac_w;
        row_coeff_w(end+1, 1) = coeff_w;
        row_acc_w(end+1, 1) = acc_w;
        row_nonzero_half(end+1, 1) = nonzero_half;
        row_filter_phase_len(end+1, 1) = filter_phase_len;
        row_mac_pair_count(end+1, 1) = mac_pair_count;
        row_real_history_len(end+1, 1) = real_history_len;
        row_phase0_sum(end+1, 1) = sum(coeff_int(1:2:end));
        row_phase1_sum(end+1, 1) = sum(coeff_int(2:2:end));
        row_stage_pass_abs(end+1, 1) = stage_res.pass_abs_max_db;
        row_stage_stop(end+1, 1) = stage_res.stop_attn_db;
        row_total_pass_abs(end+1, 1) = total_res.pass_abs_max_db;
        row_total_stop(end+1, 1) = total_res.stop_attn_db;
        row_total_dc(end+1, 1) = total_res.dc_gain;
        row_pass_a(end+1, 1) = pass_a;
        row_pass_b(end+1, 1) = pass_b;
        row_pass_c(end+1, 1) = pass_c;
        row_profile{end+1, 1} = profile_name;
        candidate_config{end+1, 1} = cfg;

        fprintf(['n=%3d taps=%3d Q=%2d coeff=%2d acc=%2d mac=%2d | ' ...
                 'stage_stop=%8.3f total_abs=%8.6f stop=%8.3f profile=%s\n'], ...
                n, n+1, frac_w, coeff_w, acc_w, mac_pair_count, ...
                stage_res.stop_attn_db, total_res.pass_abs_max_db, ...
                total_res.stop_attn_db, profile_name);
    end
end

result_table = table(row_order, row_taps, row_frac_w, row_coeff_w, ...
                     row_acc_w, row_nonzero_half, row_filter_phase_len, ...
                     row_mac_pair_count, row_real_history_len, row_phase0_sum, ...
                     row_phase1_sum, row_stage_pass_abs, row_stage_stop, ...
                     row_total_pass_abs, row_total_stop, row_total_dc, ...
                     row_pass_a, row_pass_b, row_pass_c, row_profile, ...
    'VariableNames', {'ORDER', 'TAPS', 'FRAC_W', 'COEFF_W', 'ACC_W', ...
                      'NONZERO_HALF', 'FILTER_PHASE_LEN', 'MAC_PAIR_COUNT', ...
                      'REAL_HISTORY_LEN', 'PHASE0_SUM_INT', 'PHASE1_SUM_INT', ...
                      'STAGE_PASS_ABS_DB', 'STAGE_STOP_ATTN_DB', ...
                      'TOTAL_PASS_ABS_DB', 'TOTAL_STOP_ATTN_DB', ...
                      'TOTAL_DC_GAIN', 'PASS_A', 'PASS_B', 'PASS_C', ...
                      'PROFILE'});
writetable(result_table, ...
    fullfile(script_dir, 'stage1_strict_halfband_search.csv'));

pass_idx = find(row_pass_a);
if isempty(pass_idx)
    error('未找到满足 Profile A 的 Stage 1 严格半带候选。');
end

rank_matrix = [row_mac_pair_count(pass_idx), ...
               row_real_history_len(pass_idx), ...
               row_coeff_w(pass_idx), ...
               row_acc_w(pass_idx), ...
               -row_total_stop(pass_idx), ...
               row_total_pass_abs(pass_idx)];
[~, rank_order] = sortrows(rank_matrix, [1 2 3 4 5 6]);
best_idx = pass_idx(rank_order(1));
best_config = candidate_config{best_idx};
best_coeff_int = best_config(1).coeff_int;
best_h_total = build_multistage_ir(best_config);
best_res = check_total_chain(best_h_total, FS_IN, FS_OUT, ...
    F_PASS_LOW, F_PASS_HIGH, PROFILE_A_PASS_DB, PROFILE_A_STOP_DB, ...
    EXPECTED_GAIN, NFFT_FINAL);

profile_c_idx = find(row_pass_c);
pareto_cost = [row_mac_pair_count(profile_c_idx), ...
               row_real_history_len(profile_c_idx), ...
               row_coeff_w(profile_c_idx), ...
               row_acc_w(profile_c_idx), ...
               row_total_pass_abs(profile_c_idx), ...
               -row_total_stop(profile_c_idx)];
pareto_local = find_nondominated_rows(pareto_cost);
pareto_idx = profile_c_idx(pareto_local);

[~, shortest_local] = min(row_taps(profile_c_idx));
[~, lowest_frac_local] = min(row_frac_w(profile_c_idx));
[~, lowest_acc_local] = min(row_acc_w(profile_c_idx));
[~, max_stop_local] = max(row_total_stop(profile_c_idx));
reference_idx = find(row_taps == 105 & row_frac_w == 15 & row_pass_a, ...
                     1, 'first');
if isempty(reference_idx)
    reference_idx = best_idx;
end

representative_idx = [profile_c_idx(shortest_local); ...
                      profile_c_idx(lowest_frac_local); ...
                      profile_c_idx(lowest_acc_local); ...
                      profile_c_idx(max_stop_local); ...
                      reference_idx; best_idx];
pareto_idx = unique([pareto_idx; representative_idx], 'stable');

pareto_table = result_table(pareto_idx, :);
pareto_rank = [pareto_table.MAC_PAIR_COUNT, ...
               pareto_table.REAL_HISTORY_LEN, ...
               pareto_table.COEFF_W, pareto_table.ACC_W, ...
               -pareto_table.TOTAL_STOP_ATTN_DB, ...
               pareto_table.TOTAL_PASS_ABS_DB];
[~, pareto_order] = sortrows(pareto_rank, [1 2 3 4 5 6]);
pareto_idx = pareto_idx(pareto_order);
pareto_table = result_table(pareto_idx, :);
writetable(pareto_table, ...
    fullfile(script_dir, 'stage1_strict_halfband_pareto.csv'));

candidate_records = repmat(struct( ...
    'order', 0, 'taps', 0, 'frac_w', 0, 'coeff_w', 0, ...
    'acc_w', 0, 'filter_phase_len', 0, 'mac_pair_count', 0, ...
    'real_history_len', 0, 'coeff_int', int64([])), ...
    numel(row_order), 1);
for candidate_idx = 1:numel(row_order)
    candidate_records(candidate_idx).order = row_order(candidate_idx);
    candidate_records(candidate_idx).taps = row_taps(candidate_idx);
    candidate_records(candidate_idx).frac_w = row_frac_w(candidate_idx);
    candidate_records(candidate_idx).coeff_w = row_coeff_w(candidate_idx);
    candidate_records(candidate_idx).acc_w = row_acc_w(candidate_idx);
    candidate_records(candidate_idx).filter_phase_len = ...
        row_filter_phase_len(candidate_idx);
    candidate_records(candidate_idx).mac_pair_count = ...
        row_mac_pair_count(candidate_idx);
    candidate_records(candidate_idx).real_history_len = ...
        row_real_history_len(candidate_idx);
    candidate_records(candidate_idx).coeff_int = ...
        candidate_config{candidate_idx}(1).coeff_int;
end

save(fullfile(script_dir, 'stage1_strict_halfband_config.mat'), ...
     'best_config', 'best_res', 'best_idx');
save(fullfile(script_dir, 'stage1_strict_halfband_candidates.mat'), ...
     'result_table', 'candidate_records', 'pareto_idx', ...
     'pareto_table', 'best_idx', '-v7.3');
writematrix(best_coeff_int(:), ...
    fullfile(script_dir, 'stage1_strict_halfband_coeff_int.txt'), ...
    'Delimiter', 'tab');

summary_path = fullfile(script_dir, ...
                        'stage1_strict_halfband_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Stage 1 strict halfband search summary\n');
fprintf(fid, '======================================\n');
fprintf(fid, 'Order                 = %d\n', row_order(best_idx));
fprintf(fid, 'Taps                  = %d\n', row_taps(best_idx));
fprintf(fid, 'FRAC_W                = %d\n', row_frac_w(best_idx));
fprintf(fid, 'COEFF_W               = %d\n', row_coeff_w(best_idx));
fprintf(fid, 'ACC_W                 = %d\n', row_acc_w(best_idx));
fprintf(fid, 'Nonzero half          = %d\n', row_nonzero_half(best_idx));
fprintf(fid, 'Filter phase length   = %d\n', row_filter_phase_len(best_idx));
fprintf(fid, 'MAC pair count        = %d\n', row_mac_pair_count(best_idx));
fprintf(fid, 'Real history length   = %d\n', row_real_history_len(best_idx));
fprintf(fid, 'Phase0 sum int        = %.0f\n', row_phase0_sum(best_idx));
fprintf(fid, 'Phase1 sum int        = %.0f\n', row_phase1_sum(best_idx));
fprintf(fid, 'Stage pass abs dB     = %.8f\n', row_stage_pass_abs(best_idx));
fprintf(fid, 'Stage stop attenuation= %.8f dB\n', row_stage_stop(best_idx));
fprintf(fid, 'Total pass abs dB     = %.8f\n', best_res.pass_abs_max_db);
fprintf(fid, 'Total stop attenuation= %.8f dB\n', best_res.stop_attn_db);
fprintf(fid, 'Total DC gain         = %.10f\n', best_res.dc_gain);
fprintf(fid, 'Total group delay     = %.8f samples\n', best_res.gd_mean);
fprintf(fid, 'Pass all              = %d\n', best_res.pass_all);
fprintf(fid, 'Profile A candidates  = %d\n', nnz(row_pass_a));
fprintf(fid, 'Profile B candidates  = %d\n', nnz(row_pass_b));
fprintf(fid, 'Profile C candidates  = %d\n', nnz(row_pass_c));
fprintf(fid, 'Pareto rows exported  = %d\n', height(pareto_table));
fclose(fid);

baseline_h = build_multistage_ir(base_config);
baseline_res = check_total_chain(baseline_h, FS_IN, FS_OUT, ...
    F_PASS_LOW, F_PASS_HIGH, PROFILE_A_PASS_DB, PROFILE_A_STOP_DB, ...
    EXPECTED_GAIN, NFFT_FINAL);

fig = figure('Name', 'Stage1 - 105抽头严格半带FIR系数设计', ...
             'NumberTitle', 'off', 'Color', 'w', 'Visible', 'on', ...
             'Units', 'pixels', 'Position', [80 80 1360 760]);
subplot(1,2,1);
plot(baseline_res.f/1000, baseline_res.H_db, ...
     'Color', [0.16 0.34 0.56], 'LineWidth', 1.1); hold on;
plot(best_res.f/1000, best_res.H_db, ...
     'Color', [0.25 0.13 0.47], 'LineWidth', 1.2);
xlim([0 22]); ylim([-0.012 0.012]); grid on; box on;
xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
title('Stage 1 严格半带：总链路通带');
legend('Phase 2 基线', '严格半带候选', 'Location', 'best');

subplot(1,2,2);
plot(baseline_res.f/1000, baseline_res.H_db, ...
     'Color', [0.16 0.34 0.56], 'LineWidth', 1.1); hold on;
plot(best_res.f/1000, best_res.H_db, ...
     'Color', [0.25 0.13 0.47], 'LineWidth', 1.2);
yline(-75, '--', 'Color', [0.83 0.84 0.10], 'LineWidth', 1.1);
xlim([20 80]); ylim([-120 5]); grid on; box on;
xlabel('频率 / kHz'); ylabel('幅度 / dB');
title('Stage 1 严格半带：总链路阻带入口');
legend('Phase 2 基线', '严格半带候选', '-75 dB', ...
       'Location', 'best');

print(fig, fullfile(script_dir, ...
      'stage1_strict_halfband_response.png'), '-dpng', '-r180');
drawnow;

fprintf('\nStage 1 严格半带最优候选：\n');
fprintf('  order=%d taps=%d FRAC_W=%d COEFF_W=%d nz_half=%d\n', ...
        row_order(best_idx), row_taps(best_idx), ...
        row_frac_w(best_idx), row_coeff_w(best_idx), ...
        row_nonzero_half(best_idx));
fprintf('  total pass abs=%.8f dB, stop=%.8f dB, pass=%d\n', ...
        best_res.pass_abs_max_db, best_res.stop_attn_db, ...
        best_res.pass_all);
fprintf('\n================ Stage1 正式系数设计结论 ================\n');
fprintf('正式结构：105 taps 严格半带 FIR，Q15，17 bit 系数\n');
fprintf('整数系数非零半边数量 = %d\n', row_nonzero_half(best_idx));
fprintf('Stage1 通带最大偏差  = %.8f dB\n', ...
        row_stage_pass_abs(best_idx));
fprintf('Stage1 阻带衰减      = %.8f dB\n', ...
        row_stage_stop(best_idx));
fprintf('整链路候选通带偏差  = %.8f dB\n', best_res.pass_abs_max_db);
fprintf('整链路候选阻带衰减  = %.8f dB\n', best_res.stop_attn_db);
fprintf('最终判定             = PASS\n');
fprintf('CSV1: %s\n', fullfile(script_dir, ...
        'stage1_strict_halfband_search.csv'));
fprintf('CSV2: %s\n', fullfile(script_dir, ...
        'stage1_strict_halfband_pareto.csv'));
fprintf('TXT1: %s\n', fullfile(script_dir, ...
        'stage1_strict_halfband_coeff_int.txt'));
fprintf('TXT2: %s\n', summary_path);
fprintf('MAT1: %s\n', fullfile(script_dir, ...
        'stage1_strict_halfband_config.mat'));
fprintf('MAT2: %s\n', fullfile(script_dir, ...
        'stage1_strict_halfband_candidates.mat'));
fprintf('PNG : %s\n', fullfile(script_dir, ...
        'stage1_strict_halfband_response.png'));
fprintf('========================================================\n');


function coeff_int = quantize_strict_halfband(b_float, frac_w)
    coeff_int = int64(round(b_float(:).' * 2^frac_w));
    center_idx = (numel(coeff_int) + 1) / 2;
    zero_idx = abs(b_float(:).') < 1e-12;
    coeff_int(zero_idx) = 0;
    coeff_int(center_idx) = int64(2^frac_w);
    coeff_int = int64(round((double(coeff_int) + ...
                            fliplr(double(coeff_int))) / 2));

    p0_idx = 1:2:numel(coeff_int);
    p1_idx = 2:2:numel(coeff_int);
    if any(p0_idx == center_idx)
        filtered_idx = p1_idx;
    else
        filtered_idx = p0_idx;
    end

    target_sum = int64(2^frac_w);
    delta = target_sum - sum(coeff_int(filtered_idx));
    if mod(delta, 2) ~= 0
        error('严格半带 filtered phase 的整数和误差不是偶数。');
    end

    left_idx = center_idx - 1;
    right_idx = center_idx + 1;
    coeff_int(left_idx) = coeff_int(left_idx) + delta/2;
    coeff_int(right_idx) = coeff_int(right_idx) + delta/2;

    if sum(coeff_int(p0_idx)) ~= target_sum || ...
            sum(coeff_int(p1_idx)) ~= target_sum
        error('严格半带两相整数和校正失败。');
    end
end


function res = quick_response(h, Fs, f_pass_low, f_pass_high, ...
                              f_stop_begin, expected_gain, nfft)
    [H, f] = freqz(h, 1, nfft, Fs);
    H_db = 20*log10(abs(H/expected_gain) + 1e-15);
    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= Fs/2);
    res.pass_abs_max_db = max(abs(H_db(pass_idx)));
    res.stop_attn_db = -max(H_db(stop_idx));
    res.dc_gain = sum(h);
end


function coeff_w = required_signed_width(coeff_int)
    coeff_w = 2;
    while max(coeff_int) > int64(2^(coeff_w-1)-1) || ...
            min(coeff_int) < int64(-2^(coeff_w-1))
        coeff_w = coeff_w + 1;
    end
end


function acc_w = estimate_acc_width(coeff_int, data_w)
    phase0 = coeff_int(1:2:end);
    phase1 = coeff_int(2:2:end);
    phase_abs_sum = max(sum(abs(double(phase0))), ...
                        sum(abs(double(phase1))));
    acc_max = (2^(data_w-1)-1) * phase_abs_sum;
    acc_w = ceil(log2(acc_max + 1)) + 2;
end


function pareto_idx = find_nondominated_rows(cost_matrix)
    row_count = size(cost_matrix, 1);
    keep = true(row_count, 1);

    for row_idx = 1:row_count
        no_worse = all(cost_matrix <= cost_matrix(row_idx, :), 2);
        strictly_better = any(cost_matrix < cost_matrix(row_idx, :), 2);
        no_worse(row_idx) = false;
        if any(no_worse & strictly_better)
            keep(row_idx) = false;
        end
    end

    pareto_idx = find(keep);
end
