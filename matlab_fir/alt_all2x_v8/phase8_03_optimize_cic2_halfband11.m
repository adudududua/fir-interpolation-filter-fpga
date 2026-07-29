clc; clear; close all;

%=============================================================
% 文件名       : phase8_03_optimize_cic2_halfband11.m
% 脚本名       : phase8_03_optimize_cic2_halfband11
% 功能简述     : 在 7tap 联合优化未达到 72dB 后，搜索两级
%                11tap strict-halfband 的定点系数。
%
%                保持前两级 FIR、11tap Stage3 折叠补偿、
%                CIC4(N=2) 与总倍率不变，只改变两级 Halfband。
%                浮点原型由等波纹法生成，随后强制执行：
%                  1. 左右严格对称；
%                  2. 间隔零抽头；
%                  3. 中心抽头等于 1；
%                  4. 直流增益精确等于 2。
%
%                Stop/Go 门槛：
%                  通带最大绝对误差：<=0.01dB
%                  阻带衰减        ：>=72dB
%                  冲激响应对称误差：<1e-10
%
%                输出文件：
%                  results/phase8_cic2_hb11_candidates.csv
%                  results/phase8_cic2_hb11_selected.mat
%                  results/phase8_cic2_hb11_summary.md
%                  figures/phase8_cic2_hb11_response.png
%
% 当前默认配置：
%                  输入采样率      ：44.1kHz
%                  输出采样率      ：5.6448MHz
%                  Halfband taps   ：11
%                  Halfband 格式   ：Q8 / Q10 / Q12
%                  CIC             ：R=4，N=2，M=1
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-19
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-19：新增 11tap Halfband 系数搜索。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
v2_dir = fullfile(repo_matlab_dir, 'alt_all2x_v2');
v7_dir = fullfile(repo_matlab_dir, 'alt_all2x_v7');
common_dir = fullfile(v2_dir, 'common');
result_dir = fullfile(script_dir, 'results');
figure_dir = fullfile(script_dir, 'figures');
addpath(common_dir);
addpath(v7_dir);
for one_dir = {result_dir, figure_dir}
    if ~exist(one_dir{1}, 'dir')
        mkdir(one_dir{1});
    end
end

load(fullfile(v2_dir, 'stage1_strict_halfband_config.mat'), ...
     'best_config');
phase8_data = load(fullfile(result_dir, ...
    'phase8_cic2_hb_selected.mat'), 'selected');

FS_IN = 44100;
FS_PRE2 = FS_IN*4;
FS_STAGE3 = FS_IN*8;
FS_HB4 = FS_IN*16;
FS_HB5 = FS_IN*32;
FS_OUT = FS_IN*128;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_BEGIN = FS_IN-F_PASS_HIGH;
EXPECTED_GAIN = 128;
PASS_LIMIT_DB = 0.01;
STOP_LIMIT_DB = 72;
NFFT_SEARCH = 2^16;
NFFT_FINAL = 2^20;

FP_LIST = 0.10:0.02:0.44;
HB_FRAC_LIST = [8 10 12];

h_pre2 = build_multistage_ir(best_config(1:2));
h_stage3 = phase8_data.selected.h_stage3;
h_cic4 = design_cic16_interpolator(2, 4, 1);

prototype_coeff = zeros(numel(FP_LIST)*numel(HB_FRAC_LIST), 11);
prototype_fp = zeros(size(prototype_coeff, 1), 1);
prototype_frac = zeros(size(prototype_coeff, 1), 1);
prototype_index = 0;
for frac_w = HB_FRAC_LIST
    for pass_edge = FP_LIST
        h_float = 2*firpm(10, ...
            [0 pass_edge 1-pass_edge 1], [1 1 0 0]);
        coeff_int = quantize_strict_halfband11(h_float, frac_w);
        prototype_index = prototype_index+1;
        prototype_coeff(prototype_index, :) = double(coeff_int);
        prototype_fp(prototype_index) = pass_edge;
        prototype_frac(prototype_index) = frac_w;
    end
end

[unique_coeff, unique_index] = unique(prototype_coeff, 'rows', 'stable');
prototype_fp = prototype_fp(unique_index);
prototype_frac = prototype_frac(unique_index);
prototype_count = size(unique_coeff, 1);
fprintf('Phase 8 11tap Halfband 原型数量：%d。\n', prototype_count);

frequency = linspace(0, FS_OUT/2, NFFT_SEARCH).';
pass_index = frequency >= F_PASS_LOW & frequency <= F_PASS_HIGH;
stop_index = frequency >= F_STOP_BEGIN;
H_pre2 = response_at_frequency(h_pre2, frequency, FS_PRE2);
H_stage3 = response_at_frequency(h_stage3, frequency, FS_STAGE3);
H_cic4 = response_at_frequency(h_cic4, frequency, FS_OUT);
H_common = H_pre2.*H_stage3.*H_cic4;

H_hb4_bank = complex(zeros(NFFT_SEARCH, prototype_count));
H_hb5_bank = complex(zeros(NFFT_SEARCH, prototype_count));
for prototype_idx = 1:prototype_count
    h_one = unique_coeff(prototype_idx, :) / ...
        2^prototype_frac(prototype_idx);
    H_hb4_bank(:, prototype_idx) = response_at_frequency( ...
        h_one, frequency, FS_HB4);
    H_hb5_bank(:, prototype_idx) = response_at_frequency( ...
        h_one, frequency, FS_HB5);
end

candidate_count = prototype_count^2;
row_hb4 = zeros(candidate_count, 1);
row_hb5 = zeros(candidate_count, 1);
row_pass = zeros(candidate_count, 1);
row_stop = zeros(candidate_count, 1);
row_index = 0;
for hb4_idx = 1:prototype_count
    for hb5_idx = 1:prototype_count
        response_db = 20*log10(abs(H_common.* ...
            H_hb4_bank(:, hb4_idx).*H_hb5_bank(:, hb5_idx) / ...
            EXPECTED_GAIN)+1e-15);
        row_index = row_index+1;
        row_hb4(row_index) = hb4_idx;
        row_hb5(row_index) = hb5_idx;
        row_pass(row_index) = max(abs(response_db(pass_index)));
        row_stop(row_index) = -max(response_db(stop_index));
    end
end

candidate_table = table(row_hb4, row_hb5, row_pass, row_stop, ...
    'VariableNames', {'HB4_INDEX', 'HB5_INDEX', ...
     'PASS_ABS_MAX_DB', 'STOP_ATTN_DB'});
candidate_table.PASS = candidate_table.PASS_ABS_MAX_DB <= ...
    PASS_LIMIT_DB & candidate_table.STOP_ATTN_DB >= STOP_LIMIT_DB;
candidate_table = sortrows(candidate_table, ...
    {'PASS', 'STOP_ATTN_DB', 'PASS_ABS_MAX_DB'}, ...
    {'descend', 'descend', 'ascend'});
writetable(candidate_table, fullfile(result_dir, ...
    'phase8_cic2_hb11_candidates.csv'));

selected_row = candidate_table(1, :);
hb4_idx = selected_row.HB4_INDEX;
hb5_idx = selected_row.HB5_INDEX;
selected.h_hb4_int = int64(unique_coeff(hb4_idx, :));
selected.h_hb5_int = int64(unique_coeff(hb5_idx, :));
selected.h_hb4_frac_w = prototype_frac(hb4_idx);
selected.h_hb5_frac_w = prototype_frac(hb5_idx);
selected.h_hb4 = double(selected.h_hb4_int) / ...
    2^selected.h_hb4_frac_w;
selected.h_hb5 = double(selected.h_hb5_int) / ...
    2^selected.h_hb5_frac_w;
selected.h_stage3 = h_stage3;
selected.stage3_coeff_int = phase8_data.selected.stage3_coeff_int;
selected.stage3_frac_w = phase8_data.selected.row.STAGE3_FRAC_W;
selected.stage3_coeff_w = phase8_data.selected.row.STAGE3_COEFF_W;
selected.h_cic4 = h_cic4;
selected.hb4_prototype_pass_edge = prototype_fp(hb4_idx);
selected.hb5_prototype_pass_edge = prototype_fp(hb5_idx);

h_total = h_pre2;
h_total = append_interp2_stage(h_total, h_stage3);
h_total = append_interp2_stage(h_total, selected.h_hb4);
h_total = append_interp2_stage(h_total, selected.h_hb5);
h_up = zeros(1, 4*(numel(h_total)-1)+1);
h_up(1:4:end) = h_total;
h_total = conv(h_up, h_cic4);
selected.h_total = h_total;
selected.metric = analyze_cic_response(h_total, FS_IN, FS_OUT, ...
    F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, NFFT_FINAL);
selected.pass_exact = selected.metric.pass_abs_max_db <= PASS_LIMIT_DB && ...
    selected.metric.stop_attn_db >= STOP_LIMIT_DB && ...
    selected.metric.sym_err < 1e-10;
if selected.pass_exact
    selected.decision = "GO";
else
    selected.decision = "NO-GO";
end

save(fullfile(result_dir, 'phase8_cic2_hb11_selected.mat'), 'selected');
write_summary(fullfile(result_dir, 'phase8_cic2_hb11_summary.md'), ...
    phase8_data.selected, selected);
plot_response(fullfile(figure_dir, ...
    'phase8_cic2_hb11_response.png'), selected.metric, ...
    F_PASS_HIGH, F_STOP_BEGIN);

fprintf(['Phase 8 11tap Halfband：%s\n' ...
    'HB4 Q%d，HB5 Q%d，pass=%.8fdB，stop=%.8fdB，sym=%.3g\n'], ...
    selected.decision, selected.h_hb4_frac_w, ...
    selected.h_hb5_frac_w, selected.metric.pass_abs_max_db, ...
    selected.metric.stop_attn_db, selected.metric.sym_err);
fprintf('HB4 coeff = '); fprintf('%d ', selected.h_hb4_int); fprintf('\n');
fprintf('HB5 coeff = '); fprintf('%d ', selected.h_hb5_int); fprintf('\n');


function coeff_int = quantize_strict_halfband11(h_float, frac_w)
    scale = int64(2^frac_w);
    coeff_int = int64(round(h_float(:).'*double(scale)));
    center = 6;
    coeff_int = int64(round((double(coeff_int)+ ...
        fliplr(double(coeff_int)))/2));
    coeff_int([2 4 8 10]) = 0;
    coeff_int(center) = scale;
    delta = 2*scale-sum(coeff_int);
    if mod(delta, 2) ~= 0
        error('Halfband 直流增益修正量不是偶数。');
    end
    coeff_int([5 7]) = coeff_int([5 7])+delta/2;
    if sum(coeff_int) ~= 2*scale || ...
            max(abs(coeff_int-fliplr(coeff_int))) ~= 0
        error('Halfband 量化约束失败。');
    end
end


function H = response_at_frequency(h, frequency, sample_rate)
    omega = 2*pi*frequency(:)/sample_rate;
    sample_index = 0:numel(h)-1;
    H = exp(-1j*omega*sample_index)*h(:);
end


function h_total = append_interp2_stage(h_previous, h_stage)
    h_up = zeros(1, 2*numel(h_previous)-1);
    h_up(1:2:end) = h_previous;
    h_total = conv(h_up, h_stage);
end


function write_summary(filename, baseline, selected)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '# Phase 8 二阶 CIC + 11tap Halfband 搜索结果\n\n');
    fprintf(fid, '| 项目 | 7tap 基线 | 11tap 候选 |\n');
    fprintf(fid, '|---|---:|---:|\n');
    fprintf(fid, '| 通带最大绝对误差/dB | %.8f | %.8f |\n', ...
        baseline.metric.pass_abs_max_db, selected.metric.pass_abs_max_db);
    fprintf(fid, '| 阻带衰减/dB | %.8f | %.8f |\n', ...
        baseline.metric.stop_attn_db, selected.metric.stop_attn_db);
    fprintf(fid, '| 对称误差 | %.3g | %.3g |\n', ...
        baseline.metric.sym_err, selected.metric.sym_err);
    fprintf(fid, '| 数学门槛 | NO-GO | %s |\n', selected.decision);
    fprintf(fid, '\n## 定点系数\n\n');
    fprintf(fid, '- HB4 Q%d：`', selected.h_hb4_frac_w);
    fprintf(fid, '%d ', selected.h_hb4_int); fprintf(fid, '`\n');
    fprintf(fid, '- HB5 Q%d：`', selected.h_hb5_frac_w);
    fprintf(fid, '%d ', selected.h_hb5_int); fprintf(fid, '`\n');
    fprintf(fid, '- Stage3 Q%d/%dbit：`', selected.stage3_frac_w, ...
        selected.stage3_coeff_w);
    fprintf(fid, '%d ', selected.stage3_coeff_int); fprintf(fid, '`\n');
end


function plot_response(filename, metric, pass_edge, stop_edge)
    fig = figure('Color', 'w', 'Position', [100 100 1100 720]);
    color_main = [43 91 152]/255;
    color_pass = [42 161 152]/255;
    color_limit = [205 220 35]/255;
    subplot(2, 1, 1);
    plot(metric.f/1e3, metric.H_db, 'Color', color_main, ...
        'LineWidth', 1.5);
    hold on;
    xline(pass_edge/1e3, '--', 'Color', color_pass, 'LineWidth', 1.2);
    xline(stop_edge/1e3, '--', 'Color', [70 45 125]/255, ...
        'LineWidth', 1.2);
    yline(-72, '--', 'Color', color_limit, 'LineWidth', 1.2);
    xlim([0 80]); ylim([-120 5]);
    xlabel('频率 / kHz'); ylabel('幅度 / dB');
    title('二阶 CIC + 11tap Halfband：通带至阻带入口');
    grid on; box on;

    subplot(2, 1, 2);
    pass_index = metric.f >= 0 & metric.f <= 22000;
    plot(metric.f(pass_index)/1e3, metric.H_db(pass_index), ...
        'Color', [70 45 125]/255, 'LineWidth', 1.5);
    hold on;
    yline(0.01, '--', 'Color', color_limit, 'LineWidth', 1.2);
    yline(-0.01, '--', 'Color', color_limit, 'LineWidth', 1.2);
    xline(pass_edge/1e3, '--', 'Color', color_pass, 'LineWidth', 1.2);
    xlim([0 22]); ylim([-0.015 0.015]);
    xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    title('通带细节');
    grid on; box on;
    set(findall(fig, '-property', 'FontName'), 'FontName', ...
        'Microsoft YaHei');
    set(findall(fig, '-property', 'FontSize'), 'FontSize', 11);
    exportgraphics(fig, filename, 'Resolution', 180);
    close(fig);
end
