clc; clear; close all;

%=============================================================
% 文件名       : phase8_01_search_tail_architectures.m
% 脚本名       : phase8_01_search_tail_architectures
% 功能简述     : Phase 8 尾部 CIC/Halfband 联合架构筛选。
%                在保持前两级 FIR 和 128 倍总倍率不变的条件下，
%                比较 CIC16、CIC8+1 级 Halfband、CIC4+2 级
%                Halfband 的不同排列，并为每个候选重新设计
%                Stage3 折叠补偿 FIR。
%
%                本脚本只完成数学指标和结构成本初筛，不直接修改
%                板级 RTL。只有满足通带、阻带和线性相位约束，且
%                DSP/存储代理成本优于当前架构的候选才进入 RTL。
%
%                输出文件：
%                  results/phase8_tail_candidates.csv
%                  results/phase8_tail_pareto.csv
%                  results/phase8_tail_cic2_near_miss.csv
%                  results/phase8_tail_selected.md
%                  results/phase8_tail_pareto.mat
%                  figures/phase8_tail_architecture_pareto.png
%
% 当前默认配置：
%                  输入采样率      ：44.1kHz
%                  输出采样率      ：5.6448MHz
%                  总插值倍率      ：128
%                  尾部插值倍率    ：16
%                  CIC 倍率        ：4 / 8 / 16
%                  CIC 阶数        ：2 / 3 / 4
%                  Stage3 taps     ：11 / 15 / 19
%                  系数格式        ：Q14/16bit、Q15/18bit
%                  通带最大误差    ：<=0.01dB
%                  阻带衰减        ：>=72dB
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-18
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-18：新增 Phase 8 尾部架构联合筛选。
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

FS_IN = 44100;
FS_STAGE3_OUT = FS_IN*8;
FS_OUT = FS_IN*128;
TAIL_RATE = 16;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STAGE3_STOP = FS_IN*4-F_PASS_HIGH;
F_STOP_BEGIN = FS_IN-F_PASS_HIGH;
EXPECTED_GAIN = 128;
PASS_LIMIT_DB = 0.01;
STOP_LIMIT_DB = 72;
NFFT_SEARCH = 2^17;
NFFT_FINAL = 2^20;

TAP_LIST = [11 15 19];
FORMAT_LIST = [14 16; 15 18];
STOP_WEIGHT_LIST = [0 1e-5 1e-4 1e-3 1e-2 1e-1 1 10];

% H4 表示沿用全 2x 设计中的第 4 级 Halfband；C8 表示 8 倍 CIC。
architecture = struct( ...
    'name', {'CIC16', 'HB4_CIC8', 'CIC8_HB7', ...
             'HB4_HB5_CIC4', 'HB4_CIC4_HB7', 'CIC4_HB6_HB7'}, ...
    'sequence', {'C16', 'H4-C8', 'C8-H7', ...
                 'H4-H5-C4', 'H4-C4-H7', 'C4-H6-H7'}, ...
    'cic_rate', {16, 8, 8, 4, 4, 4}, ...
    'order_list', {[2 3 4], [2 3], [2 3], [2 3], [2 3], [2 3]});

h_pre2 = build_multistage_ir(best_config(1:2));
row = repmat(struct(), 0, 1);
store = repmat(struct(), 0, 1);
row_index = 0;

fprintf('Phase 8 尾部架构联合筛选开始。\n');
for arch_idx = 1:numel(architecture)
    one_arch = architecture(arch_idx);
    for cic_order = one_arch.order_list
        [h_tail, tail_rate, hb_nonzero_half] = build_tail_ir( ...
            one_arch.sequence, cic_order, best_config);
        if tail_rate ~= TAIL_RATE
            error('%s 的尾部倍率不是 16。', one_arch.name);
        end

        [tail_response, tail_frequency] = freqz( ...
            h_tail, 1, 16384, FS_OUT);
        tail_normalized = abs(tail_response)/abs(sum(h_tail));
        desired_fun = @(frequency_hz) 2 ./ max(interp1( ...
            tail_frequency, tail_normalized, frequency_hz, ...
            'pchip', 'extrap'), 1e-12);

        for tap_count = TAP_LIST
            for stop_weight = STOP_WEIGHT_LIST
                h_float = design_folded_stage3(tap_count, ...
                    FS_STAGE3_OUT, F_PASS_HIGH, F_STAGE3_STOP, ...
                    desired_fun, stop_weight);
                for format_idx = 1:size(FORMAT_LIST, 1)
                    frac_w = FORMAT_LIST(format_idx, 1);
                    coeff_w = FORMAT_LIST(format_idx, 2);
                    [coeff_int, h_stage3, fit_ok, required_w] = ...
                        quantize_folded_stage3( ...
                            h_float, frac_w, coeff_w);

                    h_pre3 = append_interp2_stage(h_pre2, h_stage3);
                    h_pre3_up = zeros(1, ...
                        TAIL_RATE*(numel(h_pre3)-1)+1);
                    h_pre3_up(1:TAIL_RATE:end) = h_pre3;
                    h_total = conv(h_pre3_up, h_tail);
                    metric = analyze_cic_response(h_total, ...
                        FS_IN, FS_OUT, F_PASS_LOW, F_PASS_HIGH, ...
                        F_STOP_BEGIN, EXPECTED_GAIN, NFFT_SEARCH);

                    row_index = row_index+1;
                    row(row_index).ARCH = string(one_arch.name); %#ok<SAGROW>
                    row(row_index).SEQUENCE = string(one_arch.sequence); %#ok<SAGROW>
                    row(row_index).CIC_RATE = one_arch.cic_rate; %#ok<SAGROW>
                    row(row_index).CIC_ORDER = cic_order; %#ok<SAGROW>
                    row(row_index).HB_COUNT = count(one_arch.sequence, 'H'); %#ok<SAGROW>
                    row(row_index).HB_NONZERO_HALF = hb_nonzero_half; %#ok<SAGROW>
                    row(row_index).STAGE3_TAPS = tap_count; %#ok<SAGROW>
                    row(row_index).FRAC_W = frac_w; %#ok<SAGROW>
                    row(row_index).COEFF_W = coeff_w; %#ok<SAGROW>
                    row(row_index).STOP_WEIGHT = stop_weight; %#ok<SAGROW>
                    row(row_index).REQUIRED_COEFF_W = required_w; %#ok<SAGROW>
                    row(row_index).COEFF_FIT = fit_ok; %#ok<SAGROW>
                    row(row_index).PASS_ABS_MAX_DB = metric.pass_abs_max_db; %#ok<SAGROW>
                    row(row_index).RIPPLE_PP_DB = metric.ripple_pp_db; %#ok<SAGROW>
                    row(row_index).STOP_ATTN_DB = metric.stop_attn_db; %#ok<SAGROW>
                    row(row_index).GD_RIPPLE_SAMPLE = metric.gd_pp; %#ok<SAGROW>
                    row(row_index).SYMMETRY_ERROR = metric.sym_err; %#ok<SAGROW>
                    row(row_index).BASE_FIR_DSP = 2; %#ok<SAGROW>
                    row(row_index).CIC_DSP = 2*cic_order; %#ok<SAGROW>
                    row(row_index).HB_DSP_DEDICATED = ...
                        row(row_index).HB_COUNT; %#ok<SAGROW>
                    row(row_index).TOTAL_DSP_LOWER_BOUND = ...
                        2+2*cic_order; %#ok<SAGROW>
                    row(row_index).TOTAL_DSP_SHARED_HB = ...
                        2+2*cic_order+(row(row_index).HB_COUNT > 0); %#ok<SAGROW>
                    row(row_index).TOTAL_DSP_DEDICATED = ...
                        2+2*cic_order+row(row_index).HB_COUNT; %#ok<SAGROW>
                    row(row_index).STAGE3_MAC_PROXY = ceil(tap_count/2); %#ok<SAGROW>
                    row(row_index).LOGIC_PROXY = ceil(tap_count/2)+ ...
                        hb_nonzero_half; %#ok<SAGROW>

                    store(row_index).coeff_int = coeff_int; %#ok<SAGROW>
                    store(row_index).h_stage3 = h_stage3; %#ok<SAGROW>
                    store(row_index).h_tail = h_tail; %#ok<SAGROW>
                    store(row_index).h_total = h_total; %#ok<SAGROW>
                end
            end
        end
    end
end

result_table = struct2table(row);
result_table.PASS = result_table.COEFF_FIT & ...
    result_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB & ...
    result_table.STOP_ATTN_DB >= STOP_LIMIT_DB & ...
    result_table.SYMMETRY_ERROR < 1e-10;
result_table.ORIGINAL_INDEX = (1:height(result_table)).';
writetable(result_table, fullfile(result_dir, ...
    'phase8_tail_candidates.csv'));

passing_table = result_table(result_table.PASS, :);
if isempty(passing_table)
    error('Phase 8 未找到满足数学指标的尾部候选。');
end

% 每种架构先选逻辑代理最小的候选，再计算精确频响。
selected_table = table();
arch_names = unique(passing_table.ARCH, 'stable');
for arch_idx = 1:numel(arch_names)
    one_table = passing_table(passing_table.ARCH == arch_names(arch_idx), :);
    one_table = sortrows(one_table, ...
        {'TOTAL_DSP_SHARED_HB', 'TOTAL_DSP_DEDICATED', ...
         'LOGIC_PROXY', 'PASS_ABS_MAX_DB', ...
         'STOP_ATTN_DB'}, ...
        {'ascend', 'ascend', 'ascend', 'ascend', 'descend'});
    selected_table = [selected_table; one_table(1, :)]; %#ok<AGROW>
end

for idx = 1:height(selected_table)
    original_index = selected_table.ORIGINAL_INDEX(idx);
    exact_metric = analyze_cic_response( ...
        store(original_index).h_total, FS_IN, FS_OUT, ...
        F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, ...
        EXPECTED_GAIN, NFFT_FINAL);
    selected_table.PASS_ABS_MAX_DB(idx) = exact_metric.pass_abs_max_db;
    selected_table.RIPPLE_PP_DB(idx) = exact_metric.ripple_pp_db;
    selected_table.STOP_ATTN_DB(idx) = exact_metric.stop_attn_db;
    selected_table.GD_RIPPLE_SAMPLE(idx) = exact_metric.gd_pp;
    selected_table.SYMMETRY_ERROR(idx) = exact_metric.sym_err;
end
selected_table.PASS = selected_table.COEFF_FIT & ...
    selected_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB & ...
    selected_table.STOP_ATTN_DB >= STOP_LIMIT_DB & ...
    selected_table.SYMMETRY_ERROR < 1e-10;
selected_table = sortrows(selected_table, ...
    {'TOTAL_DSP_SHARED_HB', 'TOTAL_DSP_DEDICATED', ...
     'LOGIC_PROXY', 'PASS_ABS_MAX_DB'}, ...
    {'ascend', 'ascend', 'ascend', 'ascend'});

% 记录最接近门槛的二阶 CIC 候选。它们只用于判断 7 DSP 路线
% 是否值得继续，绝不因满足 70dB 赛题下限而自动替换 72dB 基线。
near_source = result_table(result_table.CIC_ORDER == 2 & ...
    result_table.COEFF_FIT & ...
    result_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB & ...
    result_table.SYMMETRY_ERROR < 1e-10, :);
near_miss_table = table();
near_arch_names = unique(near_source.ARCH, 'stable');
for arch_idx = 1:numel(near_arch_names)
    one_table = near_source(near_source.ARCH == near_arch_names(arch_idx), :);
    one_table = sortrows(one_table, ...
        {'STOP_ATTN_DB', 'PASS_ABS_MAX_DB', 'LOGIC_PROXY'}, ...
        {'descend', 'ascend', 'ascend'});
    near_miss_table = [near_miss_table; one_table(1, :)]; %#ok<AGROW>
end
for idx = 1:height(near_miss_table)
    original_index = near_miss_table.ORIGINAL_INDEX(idx);
    exact_metric = analyze_cic_response( ...
        store(original_index).h_total, FS_IN, FS_OUT, ...
        F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, ...
        EXPECTED_GAIN, NFFT_FINAL);
    near_miss_table.PASS_ABS_MAX_DB(idx) = exact_metric.pass_abs_max_db;
    near_miss_table.RIPPLE_PP_DB(idx) = exact_metric.ripple_pp_db;
    near_miss_table.STOP_ATTN_DB(idx) = exact_metric.stop_attn_db;
    near_miss_table.GD_RIPPLE_SAMPLE(idx) = exact_metric.gd_pp;
    near_miss_table.SYMMETRY_ERROR(idx) = exact_metric.sym_err;
end
near_miss_table = sortrows(near_miss_table, ...
    {'STOP_ATTN_DB', 'TOTAL_DSP_SHARED_HB'}, {'descend', 'ascend'});

writetable(selected_table, fullfile(result_dir, ...
    'phase8_tail_pareto.csv'));
writetable(near_miss_table, fullfile(result_dir, ...
    'phase8_tail_cic2_near_miss.csv'));
save(fullfile(result_dir, 'phase8_tail_pareto.mat'), ...
    'selected_table', 'near_miss_table', 'store', 'architecture');
write_summary(fullfile(result_dir, 'phase8_tail_selected.md'), ...
    selected_table, near_miss_table);
plot_result(fullfile(figure_dir, ...
    'phase8_tail_architecture_pareto.png'), selected_table);

disp(selected_table(:, {'ARCH', 'SEQUENCE', 'CIC_ORDER', ...
    'STAGE3_TAPS', 'TOTAL_DSP_SHARED_HB', ...
    'TOTAL_DSP_DEDICATED', 'LOGIC_PROXY', ...
    'PASS_ABS_MAX_DB', 'STOP_ATTN_DB', 'PASS'}));
fprintf('\n二阶 CIC 最接近 72dB 门槛的候选：\n');
disp(near_miss_table(:, {'ARCH', 'SEQUENCE', 'CIC_ORDER', ...
    'STAGE3_TAPS', 'TOTAL_DSP_SHARED_HB', ...
    'TOTAL_DSP_DEDICATED', 'PASS_ABS_MAX_DB', 'STOP_ATTN_DB'}));


function [h_tail, rate_total, hb_nonzero_half] = ...
        build_tail_ir(sequence, cic_order, best_config)
    token_list = split(string(sequence), '-');
    h_tail = 1;
    rate_total = 1;
    hb_nonzero_half = 0;
    for token_idx = 1:numel(token_list)
        token = token_list(token_idx);
        if startsWith(token, 'H')
            stage_idx = str2double(extractAfter(token, 1));
            h_stage = double(best_config(stage_idx).coeff_int) / ...
                double(2^best_config(stage_idx).frac_w);
            h_tail = append_interp2_stage(h_tail, h_stage);
            rate_total = rate_total*2;
            hb_nonzero_half = hb_nonzero_half + ...
                best_config(stage_idx).nonzero_half;
        elseif startsWith(token, 'C')
            cic_rate = str2double(extractAfter(token, 1));
            h_cic = design_cic16_interpolator(cic_order, cic_rate, 1);
            h_up = zeros(1, cic_rate*(numel(h_tail)-1)+1);
            h_up(1:cic_rate:end) = h_tail;
            h_tail = conv(h_up, h_cic);
            rate_total = rate_total*cic_rate;
        else
            error('未知尾部运算：%s', token);
        end
    end
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
    coeff_int(center) = coeff_int(center) + ...
        (2*scale-sum(coeff_int));
    max_abs = max(abs(coeff_int));
    required_w = max(2, ceil(log2(double(max_abs)+1))+1);
    fit_ok = all(coeff_int <= 2^(coeff_w-1)-1) && ...
             all(coeff_int >= -2^(coeff_w-1));
    h_quantized = double(coeff_int)/double(scale);
end


function write_summary(filename, selected_table, near_miss_table)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '# Phase 8 尾部架构数学筛选结果\n\n');
    fprintf(fid, ['DSP 成本按三档表示：下界只计既有两颗 FIR DSP 和' ...
        'CIC 的 `2N` 颗宽位加减 DSP；共享估算假定全部新增 Halfband' ...
        '共用一颗串行 MAC；独立估算则每级 Halfband 各用一颗。' ...
        '共享估算仍需 RTL 调度与实现确认。\n\n']);
    fprintf(fid, ['| 架构 | 顺序 | CIC阶数 | Stage3 taps | DSP下界 | ' ...
        'DSP共享估算 | DSP独立估算 | 逻辑代理 | 通带误差/dB | ' ...
        '阻带/dB | 通过 |\n']);
    fprintf(fid, ['|---|---|---:|---:|---:|---:|---:|---:|---:|' ...
        '---:|---|\n']);
    for idx = 1:height(selected_table)
        fprintf(fid, ['| %s | `%s` | %d | %d | %d | %d | %d | %d | ' ...
            '%.8f | %.4f | %d |\n'], ...
            selected_table.ARCH(idx), selected_table.SEQUENCE(idx), ...
            selected_table.CIC_ORDER(idx), ...
            selected_table.STAGE3_TAPS(idx), ...
            selected_table.TOTAL_DSP_LOWER_BOUND(idx), ...
            selected_table.TOTAL_DSP_SHARED_HB(idx), ...
            selected_table.TOTAL_DSP_DEDICATED(idx), ...
            selected_table.LOGIC_PROXY(idx), ...
            selected_table.PASS_ABS_MAX_DB(idx), ...
            selected_table.STOP_ATTN_DB(idx), selected_table.PASS(idx));
    end
    fprintf(fid, '\n## 二阶 CIC 近门槛候选\n\n');
    fprintf(fid, ['以下候选通带与线性相位通过，但阻带未达到本阶段' ...
        '`72dB` 保守门槛，不能直接替换当前板测基线。\n\n']);
    fprintf(fid, ['| 架构 | 顺序 | DSP共享估算 | DSP独立估算 | ' ...
        '通带误差/dB | 阻带/dB | 距72dB/dB |\n']);
    fprintf(fid, '|---|---|---:|---:|---:|---:|---:|\n');
    for idx = 1:height(near_miss_table)
        fprintf(fid, '| %s | `%s` | %d | %d | %.8f | %.4f | %.4f |\n', ...
            near_miss_table.ARCH(idx), near_miss_table.SEQUENCE(idx), ...
            near_miss_table.TOTAL_DSP_SHARED_HB(idx), ...
            near_miss_table.TOTAL_DSP_DEDICATED(idx), ...
            near_miss_table.PASS_ABS_MAX_DB(idx), ...
            near_miss_table.STOP_ATTN_DB(idx), ...
            72-near_miss_table.STOP_ATTN_DB(idx));
    end
end


function plot_result(filename, selected_table)
    fig = figure('Color', 'w', 'Position', [100 100 1100 650]);
    ax = axes(fig);
    hold(ax, 'on');
    color_list = turbo(height(selected_table));
    for idx = 1:height(selected_table)
        scatter(ax, selected_table.TOTAL_DSP_SHARED_HB(idx), ...
            selected_table.LOGIC_PROXY(idx), 100, color_list(idx, :), ...
            'filled', 'MarkerEdgeColor', [0.15 0.15 0.15]);
        text(ax, selected_table.TOTAL_DSP_SHARED_HB(idx)+0.08, ...
            selected_table.LOGIC_PROXY(idx), selected_table.ARCH(idx), ...
            'FontSize', 10, 'Interpreter', 'none');
    end
    xlabel(ax, 'DSP 数量（Halfband 共享串行 MAC 估算）');
    ylabel(ax, 'FIR/Halfband 非零半系数代理');
    title(ax, 'Phase 8 尾部架构 Pareto 初筛');
    grid(ax, 'on');
    box(ax, 'on');
    ax.FontName = 'Microsoft YaHei';
    ax.FontSize = 12;
    exportgraphics(fig, filename, 'Resolution', 180);
    close(fig);
end
