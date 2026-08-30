%% 1）主流程：v2_02_test_canonical_halfband7
% 功能说明：完成本文件对应的 MATLAB 建模、计算分析、结果验证或文件导出任务。

clc; clear; close all;

%=============================================================
% 文件名       : v2_02_test_canonical_halfband7.m
% 脚本名       : v2_02_test_canonical_halfband7
% 功能简述     : 按 Stage 7、Stage 6～7、Stage 5～7、Stage 4～7
%                的顺序，把尾级替换为精确 7 tap 半带核，并逐项
%                检查最终 128x 频率响应和工程验收门槛。
%
%                精确核：[-1 0 9 16 9 0 -1] / 16
%
%                输出文件：
%                  canonical_halfband_tail_results.csv
%                  canonical_halfband_tail_summary.txt
%                  canonical_halfband_tail_response.png
%                  canonical_variant_config.mat
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增尾级 canonical halfband7 逐级验证。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
stable_dir = fullfile(script_dir, '..', 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
common_dir = fullfile(script_dir, 'common');

addpath(bittrue_dir);
addpath(common_dir);

FS_IN = 44100;
FS_OUT = 5644800;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
RIPPLE_LIMIT_DB = 0.01;
STOP_LIMIT_DB = 75;
EXPECTED_GAIN = 128;
NFFT = 2^18;

baseline_config = load_all2x_stage_config(stable_dir, 24);

variant_name = {'baseline', 'stage7', 'stage6_7', 'stage5_7', 'stage4_7'};
first_stage_list = [8 7 6 5 4];
variant_config = cell(1, numel(variant_name));
variant_res = cell(1, numel(variant_name));

pass_abs_max_db = zeros(numel(variant_name), 1);
pass_ripple_pm_db = zeros(numel(variant_name), 1);
stop_attn_db = zeros(numel(variant_name), 1);
dc_gain = zeros(numel(variant_name), 1);
group_delay = zeros(numel(variant_name), 1);
nonzero_half_total = zeros(numel(variant_name), 1);
pass_all = false(numel(variant_name), 1);

for idx = 1:numel(variant_name)
    cfg = apply_canonical_halfband7(baseline_config, first_stage_list(idx));
    h_total = build_multistage_ir(cfg);
    res = check_total_chain(h_total, FS_IN, FS_OUT, ...
                            F_PASS_LOW, F_PASS_HIGH, ...
                            RIPPLE_LIMIT_DB, STOP_LIMIT_DB, ...
                            EXPECTED_GAIN, NFFT);

    variant_config{idx} = cfg;
    variant_res{idx} = res;
    pass_abs_max_db(idx) = res.pass_abs_max_db;
    pass_ripple_pm_db(idx) = res.ripple_pm_db;
    stop_attn_db(idx) = res.stop_attn_db;
    dc_gain(idx) = res.dc_gain;
    group_delay(idx) = res.gd_mean;
    nonzero_half_total(idx) = sum([cfg.nonzero_half]);
    pass_all(idx) = res.pass_all;

    fprintf(['%-10s | pass_abs=%10.8f dB | ripple=%10.8f dB | ' ...
             'stop=%10.8f dB | dc=%13.8f | pass=%d\n'], ...
            variant_name{idx}, pass_abs_max_db(idx), ...
            pass_ripple_pm_db(idx), stop_attn_db(idx), ...
            dc_gain(idx), pass_all(idx));
end

result_table = table(variant_name(:), first_stage_list(:), ...
                     pass_abs_max_db, pass_ripple_pm_db, ...
                     stop_attn_db, dc_gain, group_delay, ...
                     nonzero_half_total, pass_all, ...
    'VariableNames', {'VARIANT', 'FIRST_CANONICAL_STAGE', ...
                      'PASS_ABS_MAX_DB', 'PASS_RIPPLE_PM_DB', ...
                      'STOP_ATTN_DB', 'DC_GAIN', ...
                      'GROUP_DELAY_SAMPLES', 'NONZERO_HALF_TOTAL', ...
                      'PASS_ALL'});

writetable(result_table, ...
    fullfile(script_dir, 'canonical_halfband_tail_results.csv'));

save(fullfile(script_dir, 'canonical_variant_config.mat'), ...
     'variant_name', 'first_stage_list', 'variant_config', 'variant_res');

coeff_dir = fullfile(script_dir, 'candidates', 'stage4_7');
if ~exist(coeff_dir, 'dir')
    mkdir(coeff_dir);
end
writematrix([-1 0 9 16 9 0 -1].', ...
    fullfile(coeff_dir, 'canonical_halfband7_coeff_q4.txt'), ...
    'Delimiter', 'tab');

summary_path = fullfile(script_dir, 'canonical_halfband_tail_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Canonical halfband7 tail experiment\n');
fprintf(fid, '===================================\n');
fprintf(fid, 'Kernel = [-1 0 9 16 9 0 -1] / 16\n');
fprintf(fid, 'Acceptance: pass_abs<=%.3f dB, stop>=%.1f dB\n\n', ...
        RIPPLE_LIMIT_DB, STOP_LIMIT_DB);
for idx = 1:height(result_table)
    fprintf(fid, ['%-10s first_stage=%d pass_abs=%.8f dB ' ...
                  'ripple_pm=%.8f dB stop=%.8f dB dc=%.10f ' ...
                  'gd=%.3f nz_half=%d pass=%d\n'], ...
            result_table.VARIANT{idx}, ...
            result_table.FIRST_CANONICAL_STAGE(idx), ...
            result_table.PASS_ABS_MAX_DB(idx), ...
            result_table.PASS_RIPPLE_PM_DB(idx), ...
            result_table.STOP_ATTN_DB(idx), ...
            result_table.DC_GAIN(idx), ...
            result_table.GROUP_DELAY_SAMPLES(idx), ...
            result_table.NONZERO_HALF_TOTAL(idx), ...
            result_table.PASS_ALL(idx));
end
fclose(fid);

colors = [0.16 0.34 0.56; ...
          0.08 0.63 0.50; ...
          0.23 0.70 0.40; ...
          0.53 0.74 0.25; ...
          0.25 0.13 0.47];

fig = figure('Color', 'w', 'Visible', 'off', ...
             'Units', 'pixels', 'Position', [80 80 1360 760]);

subplot(1,2,1);
hold on;
for idx = 1:numel(variant_name)
    res = variant_res{idx};
    plot(res.f/1000, res.H_db, 'LineWidth', 1.2, ...
         'Color', colors(idx, :));
end
xlim([0 22]);
ylim([-0.012 0.012]);
grid on; box on;
xlabel('频率 / kHz');
ylabel('相对幅度 / dB');
title('canonical halfband7 尾级替换：通带');
legend(variant_name, 'Interpreter', 'none', 'Location', 'best');

subplot(1,2,2);
hold on;
for idx = 1:numel(variant_name)
    res = variant_res{idx};
    plot(res.f/1000, res.H_db, 'LineWidth', 1.1, ...
         'Color', colors(idx, :));
end
xlim([20 80]);
ylim([-120 5]);
yline(-75, '--', 'Color', [0.83 0.84 0.10], 'LineWidth', 1.1);
grid on; box on;
xlabel('频率 / kHz');
ylabel('幅度 / dB');
title('canonical halfband7 尾级替换：阻带入口');

print(fig, fullfile(script_dir, ...
      'canonical_halfband_tail_response.png'), '-dpng', '-r180');
close(fig);

if ~all(pass_all)
    error('至少一个 canonical halfband7 候选未通过频响门槛。');
end

fprintf('canonical halfband7 五组频响候选全部通过。\n');
