clc; clear; close all;

%=============================================================
% 文件名       : v3_01_select_stage1_pareto.m
% 脚本名       : v3_01_select_stage1_pareto
% 功能简述     : 从 Stage 1 严格半带 Pareto 搜索结果中选择代表候选，
%                使用高分辨率频响重新检查完整 128x 插值链路，并
%                导出每个候选的整数系数、最终指标和对比图。
%
%                输出文件：
%                  stage1_strict_halfband_selected.csv
%                  stage1_strict_halfband_selected.mat
%                  stage1_strict_halfband_selected_response.png
%                  coeff_v3/stage1_*_coeff_int.txt
%
% 当前默认配置：
%                  保守候选：105 tap Q15
%                  系统候选：101 tap Q15
%                  最短候选： 97 tap Q15
%                  低字长点：101 tap Q13
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 Stage 1 Pareto 代表点复核脚本。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
stable_dir = fullfile(script_dir, '..', 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
common_dir = fullfile(script_dir, 'common');
addpath(bittrue_dir);
addpath(common_dir);

candidate_path = fullfile(script_dir, ...
                           'stage1_strict_halfband_candidates.mat');
if ~exist(candidate_path, 'file')
    error('请先运行 v2_07_design_stage1_strict_halfband.m。');
end
load(candidate_path, 'candidate_records');

FS_IN = 44100;
FS_STAGE1 = 88200;
FS_OUT = 5644800;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_STAGE1 = 24100;
EXPECTED_GAIN = 128;
DATA_W = 24;
NFFT_FINAL = 2^19;

selected_name = {'conservative_A'; 'system_B'; ...
                 'shortest_C'; 'low_width_C'};
selected_taps = [105; 101; 97; 101];
selected_frac = [15; 15; 15; 13];

base_config = load_all2x_stage_config(stable_dir, DATA_W);
base_config = apply_canonical_halfband7(base_config, 4);
baseline_h = build_multistage_ir(base_config);
baseline_res = check_total_chain(baseline_h, FS_IN, FS_OUT, ...
    F_PASS_LOW, F_PASS_HIGH, 0.01, 75, EXPECTED_GAIN, NFFT_FINAL);

coeff_dir = fullfile(script_dir, 'coeff_v3');
if ~exist(coeff_dir, 'dir')
    mkdir(coeff_dir);
end

selected_config = cell(numel(selected_name), 1);
selected_result = cell(numel(selected_name), 1);
row_profile = cell(numel(selected_name), 1);
row_order = zeros(numel(selected_name), 1);
row_taps = zeros(numel(selected_name), 1);
row_frac_w = zeros(numel(selected_name), 1);
row_coeff_w = zeros(numel(selected_name), 1);
row_acc_w = zeros(numel(selected_name), 1);
row_mac_pairs = zeros(numel(selected_name), 1);
row_history = zeros(numel(selected_name), 1);
row_stage_stop = zeros(numel(selected_name), 1);
row_total_pass = zeros(numel(selected_name), 1);
row_total_stop = zeros(numel(selected_name), 1);
row_total_dc = zeros(numel(selected_name), 1);
row_group_delay = zeros(numel(selected_name), 1);
row_pass_a = false(numel(selected_name), 1);
row_pass_b = false(numel(selected_name), 1);
row_pass_c = false(numel(selected_name), 1);

for selected_idx = 1:numel(selected_name)
    record_idx = find([candidate_records.taps].' == ...
                      selected_taps(selected_idx) & ...
                      [candidate_records.frac_w].' == ...
                      selected_frac(selected_idx), 1, 'first');
    if isempty(record_idx)
        error('找不到候选 %d tap Q%d。', ...
              selected_taps(selected_idx), selected_frac(selected_idx));
    end

    record = candidate_records(record_idx);
    cfg = apply_stage1_record(base_config, record);
    stage_res = quick_response(double(record.coeff_int) / ...
        2^record.frac_w, FS_STAGE1, F_PASS_LOW, F_PASS_HIGH, ...
        F_STOP_STAGE1, 2, NFFT_FINAL);
    h_total = build_multistage_ir(cfg);
    total_res = check_total_chain(h_total, FS_IN, FS_OUT, ...
        F_PASS_LOW, F_PASS_HIGH, 0.02, 73, EXPECTED_GAIN, NFFT_FINAL);

    pass_a = total_res.pass_abs_max_db <= 0.01 && ...
             total_res.stop_attn_db >= 75 && ...
             stage_res.stop_attn_db >= 76;
    pass_b = total_res.pass_abs_max_db <= 0.01 && ...
             total_res.stop_attn_db >= 75;
    pass_c = total_res.pass_abs_max_db <= 0.02 && ...
             total_res.stop_attn_db >= 73;

    if pass_a
        profile_name = 'A';
    elseif pass_b
        profile_name = 'B';
    elseif pass_c
        profile_name = 'C';
    else
        profile_name = 'FAIL';
    end

    selected_config{selected_idx} = cfg;
    selected_result{selected_idx} = total_res;
    row_profile{selected_idx} = profile_name;
    row_order(selected_idx) = record.order;
    row_taps(selected_idx) = record.taps;
    row_frac_w(selected_idx) = record.frac_w;
    row_coeff_w(selected_idx) = record.coeff_w;
    row_acc_w(selected_idx) = record.acc_w;
    row_mac_pairs(selected_idx) = record.mac_pair_count;
    row_history(selected_idx) = record.real_history_len;
    row_stage_stop(selected_idx) = stage_res.stop_attn_db;
    row_total_pass(selected_idx) = total_res.pass_abs_max_db;
    row_total_stop(selected_idx) = total_res.stop_attn_db;
    row_total_dc(selected_idx) = total_res.dc_gain;
    row_group_delay(selected_idx) = total_res.gd_mean;
    row_pass_a(selected_idx) = pass_a;
    row_pass_b(selected_idx) = pass_b;
    row_pass_c(selected_idx) = pass_c;

    coeff_name = sprintf('stage1_%03dtap_q%02d_coeff_int.txt', ...
                         record.taps, record.frac_w);
    writematrix(record.coeff_int(:), fullfile(coeff_dir, coeff_name), ...
                'Delimiter', 'tab');
end

selected_table = table(selected_name, row_profile, row_order, row_taps, ...
    row_frac_w, row_coeff_w, row_acc_w, row_mac_pairs, row_history, ...
    row_stage_stop, row_total_pass, row_total_stop, row_total_dc, ...
    row_group_delay, row_pass_a, row_pass_b, row_pass_c, ...
    'VariableNames', {'NAME', 'PROFILE', 'ORDER', 'TAPS', 'FRAC_W', ...
    'COEFF_W', 'ACC_W', 'MAC_PAIR_COUNT', 'REAL_HISTORY_LEN', ...
    'STAGE_STOP_ATTN_DB', 'TOTAL_PASS_ABS_DB', ...
    'TOTAL_STOP_ATTN_DB', 'TOTAL_DC_GAIN', 'GROUP_DELAY_SAMPLES', ...
    'PASS_A', 'PASS_B', 'PASS_C'});
writetable(selected_table, fullfile(script_dir, ...
           'stage1_strict_halfband_selected.csv'));
save(fullfile(script_dir, 'stage1_strict_halfband_selected.mat'), ...
     'selected_table', 'selected_config', 'selected_result', ...
     'baseline_res', '-v7.3');

colors = [0.16 0.34 0.56; 0.10 0.52 0.58; ...
          0.22 0.68 0.45; 0.25 0.13 0.47];
fig = figure('Color', 'w', 'Visible', 'off', ...
             'Units', 'pixels', 'Position', [80 80 1360 760]);

subplot(1,2,1);
plot(baseline_res.f/1000, baseline_res.H_db, ...
     'Color', [0.35 0.35 0.35], 'LineWidth', 1.0); hold on;
for selected_idx = 1:numel(selected_name)
    plot(selected_result{selected_idx}.f/1000, ...
         selected_result{selected_idx}.H_db, ...
         'Color', colors(selected_idx,:), 'LineWidth', 1.15);
end
yline(0.01, '--', 'Color', [0.83 0.84 0.10], 'LineWidth', 1.0);
yline(-0.01, '--', 'Color', [0.83 0.84 0.10], 'LineWidth', 1.0);
xlim([0 22]); ylim([-0.02 0.02]); grid on; box on;
xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
title('Stage 1 Pareto 候选：总链路通带');
legend([{'Phase 2 基线'}; selected_name; {'+0.01 dB'; '-0.01 dB'}], ...
       'Location', 'best');

subplot(1,2,2);
plot(baseline_res.f/1000, baseline_res.H_db, ...
     'Color', [0.35 0.35 0.35], 'LineWidth', 1.0); hold on;
for selected_idx = 1:numel(selected_name)
    plot(selected_result{selected_idx}.f/1000, ...
         selected_result{selected_idx}.H_db, ...
         'Color', colors(selected_idx,:), 'LineWidth', 1.15);
end
yline(-70, '--', 'Color', [0.83 0.84 0.10], 'LineWidth', 1.0);
yline(-75, ':', 'Color', [0.46 0.36 0.64], 'LineWidth', 1.0);
xlim([20 80]); ylim([-120 5]); grid on; box on;
xlabel('频率 / kHz'); ylabel('幅度 / dB');
title('Stage 1 Pareto 候选：总链路阻带入口');
legend([{'Phase 2 基线'}; selected_name; {'-70 dB'; '-75 dB'}], ...
       'Location', 'best');

print(fig, fullfile(script_dir, ...
      'stage1_strict_halfband_selected_response.png'), ...
      '-dpng', '-r180');
close(fig);

disp(selected_table);


function cfg = apply_stage1_record(base_config, record)
    cfg = base_config;
    coeff_int = record.coeff_int;
    center_idx = (numel(coeff_int) + 1) / 2;
    cfg(1).order_n = record.order;
    cfg(1).taps = record.taps;
    cfg(1).coeff_int = coeff_int;
    cfg(1).frac_w = record.frac_w;
    cfg(1).coeff_w_min = record.coeff_w;
    cfg(1).coeff_w_design = record.coeff_w;
    cfg(1).acc_w_min = record.acc_w - 1;
    cfg(1).acc_w_recommended = record.acc_w;
    cfg(1).nonzero_half = nnz(coeff_int(1:center_idx));
    cfg(1).dc_gain = double(sum(coeff_int)) / 2^record.frac_w;
    cfg(1).phase0_gain = double(sum(coeff_int(1:2:end))) / ...
                         2^record.frac_w;
    cfg(1).phase1_gain = double(sum(coeff_int(2:2:end))) / ...
                         2^record.frac_w;
end


function res = quick_response(h, Fs, f_pass_low, f_pass_high, ...
                              f_stop_begin, expected_gain, nfft)
    [H, f] = freqz(h, 1, nfft, Fs);
    H_db = 20*log10(abs(H/expected_gain) + 1e-15);
    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= Fs/2);
    res.pass_abs_max_db = max(abs(H_db(pass_idx)));
    res.stop_attn_db = -max(H_db(stop_idx));
end
