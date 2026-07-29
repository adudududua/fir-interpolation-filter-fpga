clc; clear; close all;

%=============================================================
% 文件名       : phase8_02_optimize_cic2_halfband.m
% 脚本名       : phase8_02_optimize_cic2_halfband
% 功能简述     : 7 DSP 研究候选的联合数学优化脚本。
%                固定前两级 FIR，采用两级 2x strict-halfband
%                与 4 倍、2 阶 CIC 组成 16 倍尾级，并联合搜索：
%                  1. 两级 7tap halfband 的非零系数；
%                  2. Stage3 折叠补偿 FIR 的抽头数与权重；
%                  3. Stage3 系数定点格式。
%
%                第一轮用既有 Stage3 系数快速扫描 halfband；
%                第二轮只对最优 halfband 组合重新设计 Stage3，
%                最后以 2^20 点频响和等效冲激响应复核。
%
%                Stop/Go 门槛：
%                  通带最大绝对误差：<=0.01dB
%                  阻带衰减        ：>=72dB
%                  冲激响应对称误差：<1e-10
%
%                输出文件：
%                  results/phase8_cic2_hb_coarse.csv
%                  results/phase8_cic2_hb_candidates.csv
%                  results/phase8_cic2_hb_selected.mat
%                  results/phase8_cic2_hb_summary.md
%                  figures/phase8_cic2_hb_response.png
%
% 当前默认配置：
%                  输入采样率      ：44.1kHz
%                  输出采样率      ：5.6448MHz
%                  Stage3 输出     ：352.8kHz
%                  Halfband 输出   ：705.6kHz / 1.4112MHz
%                  CIC             ：R=4，N=2，M=1
%                  Halfband 格式   ：Q8
%                  Stage3 taps     ：11 / 15
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-19
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-19：新增 7 DSP 候选联合系数优化。
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
phase8_data = load(fullfile(result_dir, 'phase8_tail_pareto.mat'), ...
    'near_miss_table', 'store');

FS_IN = 44100;
FS_PRE2 = FS_IN*4;
FS_STAGE3 = FS_IN*8;
FS_HB4 = FS_IN*16;
FS_HB5 = FS_IN*32;
FS_OUT = FS_IN*128;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STAGE3_STOP = FS_IN*4-F_PASS_HIGH;
F_STOP_BEGIN = FS_IN-F_PASS_HIGH;
EXPECTED_GAIN = 128;
PASS_LIMIT_DB = 0.01;
STOP_LIMIT_DB = 72;
NFFT_COARSE = 2^15;
NFFT_SEARCH = 2^17;
NFFT_FINAL = 2^20;

HB_FRAC_W = 8;
HB_A_INT_LIST = -32:-4;
TOP_PAIR_COUNT = 24;
TAP_LIST = [11 15];
FORMAT_LIST = [14 16; 15 18];
STOP_WEIGHT_LIST = [1e-4 1e-3 1e-2 1e-1 1 10];

baseline_row = phase8_data.near_miss_table( ...
    phase8_data.near_miss_table.ARCH == "HB4_HB5_CIC4", :);
if height(baseline_row) ~= 1
    error('未找到唯一的 HB4-HB5-CIC4 二阶基线。');
end
baseline_index = baseline_row.ORIGINAL_INDEX;
h_stage3_baseline = phase8_data.store(baseline_index).h_stage3;
h_pre2 = build_multistage_ir(best_config(1:2));
h_cic4 = design_cic16_interpolator(2, 4, 1);

frequency_coarse = linspace(0, FS_OUT/2, NFFT_COARSE).';
common_coarse = build_common_response(h_pre2, h_stage3_baseline, ...
    h_cic4, frequency_coarse, FS_PRE2, FS_STAGE3, FS_OUT);
pass_coarse = frequency_coarse >= F_PASS_LOW & ...
              frequency_coarse <= F_PASS_HIGH;
stop_coarse = frequency_coarse >= F_STOP_BEGIN;

coarse_count = numel(HB_A_INT_LIST)^2;
coarse_a4 = zeros(coarse_count, 1);
coarse_a5 = zeros(coarse_count, 1);
coarse_pass = zeros(coarse_count, 1);
coarse_stop = zeros(coarse_count, 1);
coarse_index = 0;

fprintf('Phase 8 二阶 CIC halfband 粗搜索开始，共 %d 组。\n', ...
    coarse_count);
H_hb4_bank = complex(zeros(NFFT_COARSE, numel(HB_A_INT_LIST)));
H_hb5_bank = complex(zeros(NFFT_COARSE, numel(HB_A_INT_LIST)));
for alpha_idx = 1:numel(HB_A_INT_LIST)
    h_one = build_halfband7(HB_A_INT_LIST(alpha_idx), HB_FRAC_W);
    H_hb4_bank(:, alpha_idx) = response_at_frequency( ...
        h_one, frequency_coarse, FS_HB4);
    H_hb5_bank(:, alpha_idx) = response_at_frequency( ...
        h_one, frequency_coarse, FS_HB5);
end
for a4_idx = 1:numel(HB_A_INT_LIST)
    a4_int = HB_A_INT_LIST(a4_idx);
    H_hb4 = H_hb4_bank(:, a4_idx);
    for a5_idx = 1:numel(HB_A_INT_LIST)
        a5_int = HB_A_INT_LIST(a5_idx);
        H_hb5 = H_hb5_bank(:, a5_idx);
        response_db = 20*log10(abs(common_coarse.*H_hb4.*H_hb5 / ...
            EXPECTED_GAIN)+1e-15);
        coarse_index = coarse_index+1;
        coarse_a4(coarse_index) = a4_int;
        coarse_a5(coarse_index) = a5_int;
        coarse_pass(coarse_index) = max(abs(response_db(pass_coarse)));
        coarse_stop(coarse_index) = -max(response_db(stop_coarse));
    end
end

coarse_table = table(coarse_a4, coarse_a5, coarse_pass, coarse_stop, ...
    'VariableNames', {'HB4_A_INT', 'HB5_A_INT', ...
     'PASS_ABS_MAX_DB', 'STOP_ATTN_DB'});
coarse_table.HB_FRAC_W = repmat(HB_FRAC_W, height(coarse_table), 1);
coarse_table.PASS = coarse_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB;
coarse_table = sortrows(coarse_table, ...
    {'PASS', 'STOP_ATTN_DB', 'PASS_ABS_MAX_DB'}, ...
    {'descend', 'descend', 'ascend'});
writetable(coarse_table, fullfile(result_dir, ...
    'phase8_cic2_hb_coarse.csv'));

top_table = coarse_table(coarse_table.PASS, :);
if isempty(top_table)
    error('粗搜索没有通带通过的 halfband 组合。');
end
top_table = top_table(1:min(TOP_PAIR_COUNT, height(top_table)), :);

frequency_search = linspace(0, FS_OUT/2, NFFT_SEARCH).';
pass_search = frequency_search >= F_PASS_LOW & ...
              frequency_search <= F_PASS_HIGH;
stop_search = frequency_search >= F_STOP_BEGIN;

candidate = repmat(struct(), 0, 1);
candidate_store = repmat(struct(), 0, 1);
candidate_index = 0;
for pair_idx = 1:height(top_table)
    a4_int = top_table.HB4_A_INT(pair_idx);
    a5_int = top_table.HB5_A_INT(pair_idx);
    h_hb4 = build_halfband7(a4_int, HB_FRAC_W);
    h_hb5 = build_halfband7(a5_int, HB_FRAC_W);

    tail_pass = tail_normalized_magnitude( ...
        h_hb4, h_hb5, h_cic4, ...
        linspace(0, F_PASS_HIGH, 2000).', ...
        FS_HB4, FS_HB5, FS_OUT);
    tail_frequency = linspace(0, F_PASS_HIGH, 2000).';
    desired_fun = @(frequency_hz) 2 ./ max(interp1( ...
        tail_frequency, tail_pass, frequency_hz, ...
        'pchip', 'extrap'), 1e-12);

    for tap_count = TAP_LIST
        for stop_weight = STOP_WEIGHT_LIST
            h_float = design_folded_stage3(tap_count, FS_STAGE3, ...
                F_PASS_HIGH, F_STAGE3_STOP, desired_fun, stop_weight);
            for format_idx = 1:size(FORMAT_LIST, 1)
                frac_w = FORMAT_LIST(format_idx, 1);
                coeff_w = FORMAT_LIST(format_idx, 2);
                [coeff_int, h_stage3, fit_ok, required_w] = ...
                    quantize_folded_stage3(h_float, frac_w, coeff_w);
                common_response = build_common_response( ...
                    h_pre2, h_stage3, h_cic4, frequency_search, ...
                    FS_PRE2, FS_STAGE3, FS_OUT);
                H_hb4 = response_at_frequency( ...
                    h_hb4, frequency_search, FS_HB4);
                H_hb5 = response_at_frequency( ...
                    h_hb5, frequency_search, FS_HB5);
                response_db = 20*log10(abs(common_response.*H_hb4.* ...
                    H_hb5/EXPECTED_GAIN)+1e-15);

                candidate_index = candidate_index+1;
                candidate(candidate_index).HB4_A_INT = a4_int; %#ok<SAGROW>
                candidate(candidate_index).HB5_A_INT = a5_int; %#ok<SAGROW>
                candidate(candidate_index).HB_FRAC_W = HB_FRAC_W; %#ok<SAGROW>
                candidate(candidate_index).STAGE3_TAPS = tap_count; %#ok<SAGROW>
                candidate(candidate_index).STAGE3_FRAC_W = frac_w; %#ok<SAGROW>
                candidate(candidate_index).STAGE3_COEFF_W = coeff_w; %#ok<SAGROW>
                candidate(candidate_index).STOP_WEIGHT = stop_weight; %#ok<SAGROW>
                candidate(candidate_index).REQUIRED_COEFF_W = required_w; %#ok<SAGROW>
                candidate(candidate_index).COEFF_FIT = fit_ok; %#ok<SAGROW>
                candidate(candidate_index).PASS_ABS_MAX_DB = ...
                    max(abs(response_db(pass_search))); %#ok<SAGROW>
                candidate(candidate_index).STOP_ATTN_DB = ...
                    -max(response_db(stop_search)); %#ok<SAGROW>

                candidate_store(candidate_index).h_hb4 = h_hb4; %#ok<SAGROW>
                candidate_store(candidate_index).h_hb5 = h_hb5; %#ok<SAGROW>
                candidate_store(candidate_index).h_stage3 = h_stage3; %#ok<SAGROW>
                candidate_store(candidate_index).stage3_coeff_int = ...
                    coeff_int; %#ok<SAGROW>
            end
        end
    end
end

candidate_table = struct2table(candidate);
candidate_table.PASS = candidate_table.COEFF_FIT & ...
    candidate_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB & ...
    candidate_table.STOP_ATTN_DB >= STOP_LIMIT_DB;
candidate_table.ORIGINAL_INDEX = (1:height(candidate_table)).';
candidate_table = sortrows(candidate_table, ...
    {'PASS', 'STAGE3_TAPS', 'STAGE3_COEFF_W', ...
     'STOP_ATTN_DB', 'PASS_ABS_MAX_DB'}, ...
    {'descend', 'ascend', 'ascend', 'descend', 'ascend'});
writetable(candidate_table, fullfile(result_dir, ...
    'phase8_cic2_hb_candidates.csv'));

passing_table = candidate_table(candidate_table.PASS, :);
if isempty(passing_table)
    selected_row = candidate_table(1, :);
    decision = "NO-GO";
else
    selected_row = passing_table(1, :);
    decision = "GO";
end

selected_index = selected_row.ORIGINAL_INDEX;
selected.h_hb4 = candidate_store(selected_index).h_hb4;
selected.h_hb5 = candidate_store(selected_index).h_hb5;
selected.h_stage3 = candidate_store(selected_index).h_stage3;
selected.stage3_coeff_int = ...
    candidate_store(selected_index).stage3_coeff_int;
selected.h_cic4 = h_cic4;
selected.row = selected_row;
selected.decision = decision;

h_total = h_pre2;
h_total = append_interp2_stage(h_total, selected.h_stage3);
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
if ~selected.pass_exact
    selected.decision = "NO-GO";
end

save(fullfile(result_dir, 'phase8_cic2_hb_selected.mat'), 'selected');
write_summary(fullfile(result_dir, 'phase8_cic2_hb_summary.md'), ...
    baseline_row, selected);
plot_response(fullfile(figure_dir, 'phase8_cic2_hb_response.png'), ...
    selected.metric, F_PASS_HIGH, F_STOP_BEGIN);

fprintf(['Phase 8 二阶 CIC 联合优化：%s\n' ...
    'HB4 a=%d/2^%d，HB5 a=%d/2^%d，Stage3=%dtap Q%d/%dbit\n' ...
    'pass=%.8fdB stop=%.8fdB symmetry=%.3g\n'], ...
    selected.decision, selected.row.HB4_A_INT, HB_FRAC_W, ...
    selected.row.HB5_A_INT, HB_FRAC_W, ...
    selected.row.STAGE3_TAPS, selected.row.STAGE3_FRAC_W, ...
    selected.row.STAGE3_COEFF_W, ...
    selected.metric.pass_abs_max_db, selected.metric.stop_attn_db, ...
    selected.metric.sym_err);


function h = build_halfband7(a_int, frac_w)
    scale = 2^frac_w;
    b_int = scale/2-a_int;
    h = double([a_int 0 b_int scale b_int 0 a_int])/scale;
end


function H = build_common_response(h_pre2, h_stage3, h_cic, ...
        frequency, fs_pre2, fs_stage3, fs_out)
    H_pre2 = response_at_frequency(h_pre2, frequency, fs_pre2);
    H_stage3 = response_at_frequency(h_stage3, frequency, fs_stage3);
    H_cic = response_at_frequency(h_cic, frequency, fs_out);
    H = H_pre2.*H_stage3.*H_cic;
end


function magnitude = tail_normalized_magnitude(h_hb4, h_hb5, h_cic, ...
        frequency, fs_hb4, fs_hb5, fs_out)
    H = response_at_frequency(h_hb4, frequency, fs_hb4).* ...
        response_at_frequency(h_hb5, frequency, fs_hb5).* ...
        response_at_frequency(h_cic, frequency, fs_out);
    magnitude = abs(H)/(sum(h_hb4)*sum(h_hb5)*sum(h_cic));
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


function h = design_folded_stage3(tap_count, sample_rate, pass_edge, ...
        stop_edge, desired_fun, stop_weight)
    half_order = (tap_count-1)/2;
    distance = 1:half_order;
    pass_frequency = linspace(0, pass_edge, 1600).';
    stop_frequency = linspace(stop_edge, sample_rate/2, 1000).';
    pass_omega = 2*pi*pass_frequency/sample_rate;
    stop_omega = 2*pi*stop_frequency/sample_rate;
    pass_matrix = [ones(size(pass_omega)), ...
                   2*cos(pass_omega*distance)];
    stop_matrix = [ones(size(stop_omega)), ...
                   2*cos(stop_omega*distance)];
    dc_matrix = [1 2*ones(1, half_order)];
    dc_weight = 1e4;
    matrix = [pass_matrix; sqrt(stop_weight)*stop_matrix; ...
              dc_weight*dc_matrix];
    target = [desired_fun(pass_frequency); zeros(size(stop_frequency)); ...
              2*dc_weight];
    ridge_scale = 1e-10;
    augmented_matrix = [matrix; ...
                        sqrt(ridge_scale)*eye(half_order+1)];
    augmented_target = [target; zeros(half_order+1, 1)];
    column_scale = sqrt(sum(abs(augmented_matrix).^2, 1));
    column_scale(column_scale < eps) = 1;
    coefficient = (augmented_matrix./column_scale)\augmented_target;
    coefficient = coefficient./column_scale.';

    h = zeros(1, tap_count);
    center = half_order+1;
    h(center) = coefficient(1);
    for idx = 1:half_order
        h(center-idx) = coefficient(idx+1);
        h(center+idx) = coefficient(idx+1);
    end
    h = h*(2/sum(h));
end


function [coeff_int, h_quantized, fit_ok, required_w] = ...
        quantize_folded_stage3(h_float, frac_w, coeff_w)
    scale = int64(2^frac_w);
    coeff_int = int64(round(h_float*double(scale)));
    center = (numel(coeff_int)+1)/2;
    coeff_int(center) = coeff_int(center)+(2*scale-sum(coeff_int));
    max_abs = max(abs(coeff_int));
    required_w = max(2, ceil(log2(double(max_abs)+1))+1);
    fit_ok = all(coeff_int <= 2^(coeff_w-1)-1) && ...
             all(coeff_int >= -2^(coeff_w-1));
    h_quantized = double(coeff_int)/double(scale);
end


function write_summary(filename, baseline_row, selected)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '# Phase 8 二阶 CIC 与 Halfband 联合优化结果\n\n');
    fprintf(fid, '| 项目 | 优化前 | 优化后 |\n');
    fprintf(fid, '|---|---:|---:|\n');
    fprintf(fid, '| Stage3 taps | %d | %d |\n', ...
        baseline_row.STAGE3_TAPS, selected.row.STAGE3_TAPS);
    fprintf(fid, '| 通带最大绝对误差/dB | %.8f | %.8f |\n', ...
        baseline_row.PASS_ABS_MAX_DB, selected.metric.pass_abs_max_db);
    fprintf(fid, '| 阻带衰减/dB | %.8f | %.8f |\n', ...
        baseline_row.STOP_ATTN_DB, selected.metric.stop_attn_db);
    fprintf(fid, '| 冲激对称误差 | %.3g | %.3g |\n', ...
        baseline_row.SYMMETRY_ERROR, selected.metric.sym_err);
    fprintf(fid, '\n## 量化系数\n\n');
    fprintf(fid, '- Halfband 4：`');
    fprintf(fid, '%d ', round(selected.h_hb4*2^selected.row.HB_FRAC_W));
    fprintf(fid, '`，Q%d。\n', selected.row.HB_FRAC_W);
    fprintf(fid, '- Halfband 5：`');
    fprintf(fid, '%d ', round(selected.h_hb5*2^selected.row.HB_FRAC_W));
    fprintf(fid, '`，Q%d。\n', selected.row.HB_FRAC_W);
    fprintf(fid, '- Stage3：`');
    fprintf(fid, '%d ', selected.stage3_coeff_int);
    fprintf(fid, '`，Q%d/%dbit。\n', selected.row.STAGE3_FRAC_W, ...
        selected.row.STAGE3_COEFF_W);
    fprintf(fid, '\n## Stop/Go\n\n');
    fprintf(fid, '**%s**：阻带门槛为 72dB。\n', selected.decision);
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
    title('二阶 CIC 联合优化：通带至阻带入口');
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
