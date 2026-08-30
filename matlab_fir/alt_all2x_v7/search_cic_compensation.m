%% 1）主流程：search_cic_compensation
% 功能说明：遍历 CIC 结构或补偿参数，筛选满足通带与阻带指标的候选方案。

clc; clear; close all;

%=============================================================
% 文件名       : search_cic_compensation.m
% 脚本名       : search_cic_compensation
% 功能简述     : Phase 7-B 低速 CIC 补偿 FIR 搜索。补偿器位于
%                Phase 6 Stage3 的 352.8kHz 输出与 16x CIC
%                之间，保持标准 CIC 插值数据流：
%                  compensation FIR -> low-rate comb ->
%                  upsample16 -> high-rate integrator。
%
%                搜索 N=3/4/5、15/21/31/41tap、Q12/Q14/Q16，
%                对每个量化候选构造完整 44.1kHz -> 5.6448MHz
%                等效冲激响应，统一检查通带、全阻带和线性相位。
%
%                输出文件：
%                  results/cic_compensation_candidates.csv
%                  results/cic_compensation_summary.txt
%                  results/cic_compensation_selected.mat
%                  results/cic_compensation_pareto.csv
%                  results/cic_compensation_pareto.mat
%                  results/cic_compensation_coefficients.txt
%                  figures/cic_compensation_response.png
%
% 当前默认配置：
%                  CIC：R=16，M=1，N=3/4/5
%                  taps：15 / 21 / 31 / 41
%                  系数：Q12 / Q14 / Q16
%                  通带最大绝对误差：<0.01dB
%                  阻带衰减：>70dB
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：按 Phase 7 修正版指导新增补偿搜索。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
v2_dir = fullfile(repo_matlab_dir, 'alt_all2x_v2');
common_dir = fullfile(v2_dir, 'common');
result_dir = fullfile(script_dir, 'results');
figure_dir = fullfile(script_dir, 'figures');

addpath(common_dir);
addpath(script_dir);
if ~exist(result_dir, 'dir')
    mkdir(result_dir);
end
if ~exist(figure_dir, 'dir')
    mkdir(figure_dir);
end

config_path = fullfile(v2_dir, 'stage1_strict_halfband_config.mat');
if ~exist(config_path, 'file')
    error('未找到 Phase 6 系数配置：%s', config_path);
end
load(config_path, 'best_config');
best_config(3).coeff_int = int64(best_config(3).coeff_int)*2;
best_config(3).frac_w = best_config(3).frac_w+1;
best_config(3).acc_w_recommended = 38;

FS_IN = 44100;
FS_CIC_IN = FS_IN*8;
R_CIC = 16;
M_CIC = 1;
FS_OUT = FS_CIC_IN*R_CIC;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_BEGIN = FS_IN-F_PASS_HIGH;
F_WIDE_STOP = FS_IN*4-F_PASS_HIGH;
EXPECTED_GAIN = 128;
PASS_LIMIT_DB = 0.01;
STOP_LIMIT_DB = 70;
NFFT_SEARCH = 2^18;
NFFT_FINAL = 2^21;

ORDER_LIST = [3 4 5];
TAP_LIST = [15 21 31 41];
FRAC_LIST = [12 14 16];
DESIGN_STOP_LIST = [F_STOP_BEGIN F_WIDE_STOP];
STOP_WEIGHT_LIST = [0 1e-6 1e-5 1e-4 1e-3 1e-2 1e-1 1 10];

h_pre3 = build_multistage_ir(best_config(1:3));
h_phase6 = build_multistage_ir(best_config);
phase6_metric = analyze_cic_response(h_phase6, FS_IN, FS_OUT, ...
    F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, 2^20);

row_arch = {};
row_order = [];
row_taps = [];
row_frac = [];
row_coeff_w = [];
row_design_stop = [];
row_stop_weight = [];
row_max_coeff = [];
row_required_w = [];
row_pass_abs = [];
row_ripple = [];
row_stop = [];
row_dc = [];
row_sym = [];
row_gd = [];
row_fit = [];

fprintf('Phase 7-B CIC 补偿 FIR 搜索开始。\n');
candidate_index = 0;
for cic_order = ORDER_LIST
    h_cic = design_cic16_interpolator(cic_order, R_CIC, M_CIC);
    for tap_count = TAP_LIST
        for design_stop = DESIGN_STOP_LIST
            for stop_weight = STOP_WEIGHT_LIST
                desired_fun = @(frequency_hz) 1 ./ ...
                    cic_normalized_magnitude(frequency_hz, ...
                    FS_CIC_IN, R_CIC, M_CIC, cic_order);
                h_float = design_symmetric_compensation(tap_count, ...
                    FS_CIC_IN, F_PASS_HIGH, design_stop, ...
                    desired_fun, stop_weight);

                for frac_w = FRAC_LIST
                    coeff_w = frac_w+2;
                    [coeff_int, h_quantized, fit_ok, required_w] = ...
                        quantize_compensation(h_float, frac_w, coeff_w);
                    metric = evaluate_candidate(h_pre3, h_quantized, ...
                        h_cic, R_CIC, FS_OUT, EXPECTED_GAIN, ...
                        F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, ...
                        NFFT_SEARCH);

                    candidate_index = candidate_index+1;
                    row_arch{candidate_index, 1} = 'standalone_lowrate'; %#ok<SAGROW>
                    row_order(candidate_index, 1) = cic_order; %#ok<SAGROW>
                    row_taps(candidate_index, 1) = tap_count; %#ok<SAGROW>
                    row_frac(candidate_index, 1) = frac_w; %#ok<SAGROW>
                    row_coeff_w(candidate_index, 1) = coeff_w; %#ok<SAGROW>
                    row_design_stop(candidate_index, 1) = design_stop; %#ok<SAGROW>
                    row_stop_weight(candidate_index, 1) = stop_weight; %#ok<SAGROW>
                    row_max_coeff(candidate_index, 1) = max(abs(coeff_int)); %#ok<SAGROW>
                    row_required_w(candidate_index, 1) = required_w; %#ok<SAGROW>
                    row_pass_abs(candidate_index, 1) = metric.pass_abs_max_db; %#ok<SAGROW>
                    row_ripple(candidate_index, 1) = metric.ripple_pp_db; %#ok<SAGROW>
                    row_stop(candidate_index, 1) = metric.stop_attn_db; %#ok<SAGROW>
                    row_dc(candidate_index, 1) = metric.dc_gain; %#ok<SAGROW>
                    row_sym(candidate_index, 1) = metric.sym_err; %#ok<SAGROW>
                    row_gd(candidate_index, 1) = metric.gd_samples; %#ok<SAGROW>
                    row_fit(candidate_index, 1) = fit_ok; %#ok<SAGROW>
                end
            end
        end
    end
end

result_table = table(row_arch, row_order, row_taps, row_frac, ...
    row_coeff_w, row_design_stop, row_stop_weight, row_max_coeff, ...
    row_required_w, row_pass_abs, row_ripple, row_stop, row_dc, ...
    row_sym, row_gd, row_fit, 'VariableNames', ...
    {'ARCHITECTURE', 'CIC_ORDER', 'COMP_TAPS', 'FRAC_W', ...
     'COEFF_W', 'DESIGN_STOP_HZ', 'STOP_WEIGHT', 'MAX_COEFF_INT', ...
     'REQUIRED_COEFF_W', 'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', ...
     'STOP_ATTN_DB', 'DC_GAIN', 'SYMMETRY_ERROR', ...
     'GROUP_DELAY_SAMPLES', 'COEFF_FIT'});
result_table.PASS = result_table.COEFF_FIT & ...
    result_table.PASS_ABS_MAX_DB < PASS_LIMIT_DB & ...
    result_table.STOP_ATTN_DB > STOP_LIMIT_DB & ...
    result_table.SYMMETRY_ERROR < 1e-10;

% 先按 CIC 阶数、补偿 taps 和系数字宽最小选择，综合再给最终资源结论。
result_table.RESOURCE_PROXY = 10000*result_table.CIC_ORDER + ...
    100*result_table.COMP_TAPS + result_table.COEFF_W;
writetable(result_table, fullfile(result_dir, ...
    'cic_compensation_candidates.csv'));

pass_table = result_table(result_table.PASS, :);
if ~isempty(pass_table)
    pass_table = sortrows(pass_table, ...
        {'RESOURCE_PROXY', 'PASS_ABS_MAX_DB', 'STOP_ATTN_DB'}, ...
        {'ascend', 'ascend', 'descend'});
    selected_row = pass_table(1, :);
    decision = 'GO_TO_BITTRUE';
else
    penalty = 1000*max(result_table.PASS_ABS_MAX_DB-PASS_LIMIT_DB, 0) + ...
              10*max(STOP_LIMIT_DB-result_table.STOP_ATTN_DB, 0);
    penalty(~result_table.COEFF_FIT) = inf;
    [~, selected_index] = min(penalty);
    selected_row = result_table(selected_index, :);
    decision = 'NO_GO_MATHEMATICAL';
end

[selected_coeff_int, selected_h_comp, selected_h_cic, ...
 selected_h_total] = rebuild_candidate(selected_row, h_pre3, ...
    FS_CIC_IN, R_CIC, M_CIC, FS_OUT, F_PASS_HIGH);
selected_metric = analyze_cic_response(selected_h_total, FS_IN, FS_OUT, ...
    F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, NFFT_FINAL);

selected.decision = decision;
selected.row = selected_row;
selected.coeff_int = selected_coeff_int;
selected.h_comp = selected_h_comp;
selected.h_cic = selected_h_cic;
selected.h_total = selected_h_total;
selected.metric = selected_metric;
save(fullfile(result_dir, 'cic_compensation_selected.mat'), 'selected');

% 同时固化资源优先 N=3 与阻带裕量优先 N=4，供 bit-true/综合比较。
robust_table = pass_table(pass_table.CIC_ORDER == 4 & ...
    pass_table.COMP_TAPS == 15 & pass_table.FRAC_W == 12 & ...
    pass_table.PASS_ABS_MAX_DB <= 0.006 & ...
    pass_table.STOP_ATTN_DB >= 75, :);
if isempty(robust_table)
    robust_row = selected_row;
else
    robust_table = sortrows(robust_table, ...
        {'PASS_ABS_MAX_DB', 'STOP_ATTN_DB'}, {'ascend', 'descend'});
    robust_row = robust_table(1, :);
end

pareto_table = [selected_row; robust_row];
pareto_table.CANDIDATE = {'aggressive_n3'; 'robust_n4'};
writetable(pareto_table, fullfile(result_dir, ...
    'cic_compensation_pareto.csv'));

pareto = repmat(struct(), 1, height(pareto_table));
for pareto_idx = 1:height(pareto_table)
    one_row = pareto_table(pareto_idx, :);
    [one_coeff_int, one_h_comp, one_h_cic, one_h_total] = ...
        rebuild_candidate(one_row, h_pre3, FS_CIC_IN, R_CIC, M_CIC, ...
        FS_OUT, F_PASS_HIGH);
    one_metric = analyze_cic_response(one_h_total, FS_IN, FS_OUT, ...
        F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, NFFT_FINAL);
    pareto(pareto_idx).name = pareto_table.CANDIDATE{pareto_idx};
    pareto(pareto_idx).row = one_row;
    pareto(pareto_idx).coeff_int = one_coeff_int;
    pareto(pareto_idx).h_comp = one_h_comp;
    pareto(pareto_idx).h_cic = one_h_cic;
    pareto(pareto_idx).h_total = one_h_total;
    pareto(pareto_idx).metric = one_metric;
end
save(fullfile(result_dir, 'cic_compensation_pareto.mat'), 'pareto');

write_summary(fullfile(result_dir, 'cic_compensation_summary.txt'), ...
    phase6_metric, result_table, selected_row, selected_metric, ...
    decision, PASS_LIMIT_DB, STOP_LIMIT_DB);
write_coefficients(fullfile(result_dir, ...
    'cic_compensation_coefficients.txt'), selected_row, ...
    selected_coeff_int, selected_h_comp);
plot_selected(fullfile(figure_dir, 'cic_compensation_response.png'), ...
    phase6_metric, selected_metric, selected_h_comp, selected_h_cic, ...
    selected_row, FS_CIC_IN, R_CIC, M_CIC, ...
    F_PASS_HIGH, F_STOP_BEGIN, PASS_LIMIT_DB, STOP_LIMIT_DB);

fprintf('\n================ Phase 7-B 搜索结论 ================\n');
fprintf('Decision     = %s\n', decision);
fprintf('CIC order    = %d\n', selected_row.CIC_ORDER);
fprintf('Comp taps    = %d\n', selected_row.COMP_TAPS);
fprintf('Coefficient  = Q%d / %dbit\n', ...
    selected_row.FRAC_W, selected_row.COEFF_W);
fprintf('Pass abs max = %.8f dB\n', selected_metric.pass_abs_max_db);
fprintf('Stop atten   = %.8f dB\n', selected_metric.stop_attn_db);
fprintf('GD ripple    = %.12g sample\n', selected_metric.gd_pp);
fprintf('Passing rows = %d / %d\n', sum(result_table.PASS), ...
    height(result_table));
fprintf('CSV summary  = %s\n', fullfile(result_dir, ...
    'cic_compensation_candidates.csv'));
fprintf('TXT summary  = %s\n', fullfile(result_dir, ...
    'cic_compensation_summary.txt'));
fprintf('TXT coeff    = %s\n', fullfile(result_dir, ...
    'cic_compensation_coefficients.txt'));
fprintf('PNG response = %s\n', fullfile(figure_dir, ...
    'cic_compensation_response.png'));
fprintf('====================================================\n');
drawnow;


% 2）局部函数模块：cic_normalized_magnitude


% 功能说明：封装 cic_normalized_magnitude 对应的局部计算，供主流程复用并保持代码层次清晰。
function magnitude = cic_normalized_magnitude(frequency_hz, ...
        input_rate_hz, rate_change, diff_delay, cic_order)
    frequency_hz = double(frequency_hz);
    numerator = sin(pi*frequency_hz*diff_delay/input_rate_hz);
    denominator = rate_change*diff_delay * ...
        sin(pi*frequency_hz/(rate_change*input_rate_hz));
    ratio = ones(size(frequency_hz));
    nonzero = abs(frequency_hz) > 1e-15;
    ratio(nonzero) = numerator(nonzero)./denominator(nonzero);
    magnitude = abs(ratio).^cic_order;
end


% 3）局部函数模块：design_symmetric_compensation


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function h = design_symmetric_compensation(tap_count, sample_rate, ...
        pass_edge, stop_edge, desired_fun, stop_weight)
    if mod(tap_count, 2) ~= 1
        error('补偿 FIR 必须使用奇数 tap。');
    end

    half_order = (tap_count-1)/2;
    distance = 1:half_order;
    pass_frequency = linspace(0, pass_edge, 1200).';
    stop_frequency = linspace(stop_edge, sample_rate/2, 1600).';
    pass_omega = 2*pi*pass_frequency/sample_rate;
    stop_omega = 2*pi*stop_frequency/sample_rate;
    pass_matrix = [ones(size(pass_omega)), ...
                   2*cos(pass_omega*distance)];
    stop_matrix = [ones(size(stop_omega)), ...
                   2*cos(stop_omega*distance)];
    dc_matrix = [1, 2*ones(1, half_order)];

    dc_weight = 1e4;
    matrix = [pass_matrix; ...
              sqrt(stop_weight)*stop_matrix; ...
              dc_weight*dc_matrix];
    target = [desired_fun(pass_frequency); ...
              zeros(size(stop_frequency)); ...
              dc_weight];
    % 使用列缩放后的增广最小二乘，避免正规方程平方化条件数。
    ridge_scale = 1e-10;
    augmented_matrix = [matrix; ...
                        sqrt(ridge_scale)*eye(half_order+1)];
    augmented_target = [target; zeros(half_order+1, 1)];
    column_scale = sqrt(sum(abs(augmented_matrix).^2, 1));
    column_scale(column_scale < eps) = 1;
    scaled_matrix = augmented_matrix./column_scale;
    scaled_coefficient = scaled_matrix\augmented_target;
    coefficient = scaled_coefficient./column_scale.';

    h = zeros(1, tap_count);
    center = half_order+1;
    h(center) = coefficient(1);
    for distance_idx = 1:half_order
        h(center-distance_idx) = coefficient(distance_idx+1);
        h(center+distance_idx) = coefficient(distance_idx+1);
    end
    h = h/sum(h);
end


% 4）局部函数模块：anonymous_function_block


% 功能说明：封装 anonymous_function_block 对应的局部计算，供主流程复用并保持代码层次清晰。
function [coeff_int, h_quantized, fit_ok, required_w] = ...
        quantize_compensation(h_float, frac_w, coeff_w)
    scale = 2^frac_w;
    coeff_int = int64(round(h_float*scale));
    center = (numel(coeff_int)+1)/2;
    coeff_int(center) = coeff_int(center) + ...
                        (int64(scale)-sum(coeff_int));
    max_abs = double(max(abs(coeff_int)));
    required_w = max(1, ceil(log2(max_abs+1))+1);
    fit_ok = all(double(coeff_int) >= -2^(coeff_w-1)) && ...
             all(double(coeff_int) <= 2^(coeff_w-1)-1);
    h_quantized = double(coeff_int)/scale;
end


% 5）局部函数模块：evaluate_candidate


% 功能说明：封装 evaluate_candidate 对应的局部计算，供主流程复用并保持代码层次清晰。
function metric = evaluate_candidate(h_pre3, h_comp, h_cic, ...
        rate_change, output_rate, expected_gain, pass_low, pass_high, ...
        stop_begin, nfft)
    h_low = conv(h_pre3, h_comp);
    h_low_up = zeros(1, rate_change*(numel(h_low)-1)+1);
    h_low_up(1:rate_change:end) = h_low;
    H = fft(h_low_up, nfft).*fft(h_cic, nfft);
    H = H(1:nfft/2+1)/expected_gain;
    frequency = (0:nfft/2).'*output_rate/nfft;
    response_db = 20*log10(abs(H(:))+1e-15);
    pass_index = frequency >= pass_low & frequency <= pass_high;
    stop_index = frequency >= stop_begin & frequency <= output_rate/2;
    pass_response = response_db(pass_index);
    stop_response = response_db(stop_index);
    metric.pass_abs_max_db = max(abs(pass_response));
    metric.ripple_pp_db = max(pass_response)-min(pass_response);
    metric.stop_attn_db = -max(stop_response);
    metric.dc_gain = sum(h_low)*sum(h_cic);
    metric.sym_err = max([max(abs(h_pre3-fliplr(h_pre3))), ...
                          max(abs(h_comp-fliplr(h_comp))), ...
                          max(abs(h_cic-fliplr(h_cic)))]);
    metric.gd_samples = ...
        (rate_change*(numel(h_low)-1)+numel(h_cic)-1)/2;
end


% 6）局部函数模块：rebuild_candidate


% 功能说明：封装 rebuild_candidate 对应的局部计算，供主流程复用并保持代码层次清晰。
function [coeff_int, h_comp, h_cic, h_total] = rebuild_candidate( ...
        selected_row, h_pre3, fs_cic_in, rate_change, diff_delay, ...
        fs_out, pass_edge)
    desired_fun = @(frequency_hz) 1 ./ cic_normalized_magnitude( ...
        frequency_hz, fs_cic_in, rate_change, diff_delay, ...
        selected_row.CIC_ORDER);
    h_float = design_symmetric_compensation(selected_row.COMP_TAPS, ...
        fs_cic_in, pass_edge, selected_row.DESIGN_STOP_HZ, ...
        desired_fun, selected_row.STOP_WEIGHT);
    [coeff_int, h_comp, fit_ok] = quantize_compensation( ...
        h_float, selected_row.FRAC_W, selected_row.COEFF_W);
    if ~fit_ok
        error('选中补偿 FIR 系数无法装入目标位宽。');
    end
    h_cic = design_cic16_interpolator(selected_row.CIC_ORDER, ...
        rate_change, diff_delay);
    h_low = conv(h_pre3, h_comp);
    h_low_up = zeros(1, rate_change*(numel(h_low)-1)+1);
    h_low_up(1:rate_change:end) = h_low;
    h_total = conv(h_low_up, h_cic);
    if abs(fs_out-fs_cic_in*rate_change) > 1e-9
        error('CIC 输出采样率配置不一致。');
    end
end


% 7）局部函数模块：write_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_summary(file_path, phase6_metric, result_table, ...
        selected_row, selected_metric, decision, pass_limit, stop_limit)
    fid = fopen(file_path, 'w');
    if fid < 0
        error('无法写入：%s', file_path);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Phase 7-B CIC compensation search\n');
    fprintf(fid, '==================================\n');
    fprintf(fid, 'Compensation location = 352.8kHz before CIC\n');
    fprintf(fid, 'Phase6 pass abs max = %.8f dB\n', ...
        phase6_metric.pass_abs_max_db);
    fprintf(fid, 'Phase6 stop attenuation = %.8f dB\n', ...
        phase6_metric.stop_attn_db);
    fprintf(fid, 'Limits: pass abs < %.5f dB, stop > %.2f dB\n\n', ...
        pass_limit, stop_limit);
    fprintf(fid, 'Total candidates = %d\n', height(result_table));
    fprintf(fid, 'Passing candidates = %d\n', sum(result_table.PASS));
    fprintf(fid, 'Decision = %s\n\n', decision);
    fprintf(fid, 'Selected CIC order = %d\n', selected_row.CIC_ORDER);
    fprintf(fid, 'Selected taps = %d\n', selected_row.COMP_TAPS);
    fprintf(fid, 'Selected format = Q%d / %dbit\n', ...
        selected_row.FRAC_W, selected_row.COEFF_W);
    fprintf(fid, 'Selected design stop = %.1f Hz\n', ...
        selected_row.DESIGN_STOP_HZ);
    fprintf(fid, 'Selected stop weight = %.8g\n', ...
        selected_row.STOP_WEIGHT);
    fprintf(fid, 'Final pass abs max = %.8f dB\n', ...
        selected_metric.pass_abs_max_db);
    fprintf(fid, 'Final ripple pp = %.8f dB\n', ...
        selected_metric.ripple_pp_db);
    fprintf(fid, 'Final stop attenuation = %.8f dB\n', ...
        selected_metric.stop_attn_db);
    fprintf(fid, 'Final DC gain = %.12f\n', selected_metric.dc_gain);
    fprintf(fid, 'Final symmetry error = %.12g\n', ...
        selected_metric.sym_err);
    fprintf(fid, 'Final group delay ripple = %.12g sample\n', ...
        selected_metric.gd_pp);
end


% 8）局部函数模块：write_coefficients


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_coefficients(file_path, selected_row, coeff_int, h_comp)
    fid = fopen(file_path, 'w');
    if fid < 0
        error('无法写入：%s', file_path);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'CIC order = %d\n', selected_row.CIC_ORDER);
    fprintf(fid, 'Compensation taps = %d\n', selected_row.COMP_TAPS);
    fprintf(fid, 'Fractional bits = %d\n', selected_row.FRAC_W);
    fprintf(fid, 'Coefficient width = %d\n', selected_row.COEFF_W);
    fprintf(fid, 'Integer coefficients:\n');
    fprintf(fid, '%d\n', coeff_int);
    fprintf(fid, 'Quantized coefficients:\n');
    fprintf(fid, '%.18g\n', h_comp);
end


% 9）局部函数模块：plot_selected


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function plot_selected(file_path, phase6_metric, selected_metric, ...
        h_comp, h_cic, selected_row, fs_cic_in, rate_change, ...
        diff_delay, pass_edge, stop_begin, pass_limit, stop_limit)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_yellow = [0.82 0.88 0.05];
    figure('Name', 'Phase 7-B - CIC补偿FIR设计', 'NumberTitle', 'off', ...
        'Color', 'w', 'Position', [80 60 1500 980]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    plot(phase6_metric.f/1e3, phase6_metric.H_db, ...
        'Color', color_blue, 'LineWidth', 1.6); hold on;
    plot(selected_metric.f/1e3, selected_metric.H_db, ...
        'Color', color_purple, 'LineWidth', 1.8);
    yline(pass_limit, '--', 'Color', color_yellow);
    yline(-pass_limit, '--', 'Color', color_yellow);
    xline(pass_edge/1e3, '--', 'Color', color_green);
    xlim([0 22]); ylim([-0.025 0.025]);
    title('补偿后通带'); xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    legend('Phase 6 FIR', 'Phase 7 FIR-CIC', '+/-0.01 dB', ...
        '20 kHz', 'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(selected_metric.f/1e3, selected_metric.H_db, ...
        'Color', color_blue, 'LineWidth', 1.4); hold on;
    xline(stop_begin/1e3, '--', 'Color', color_green);
    yline(-stop_limit, '--', 'Color', color_yellow);
    xlim([0 500]); ylim([-150 5]);
    title('首个镜像区'); xlabel('频率 / kHz'); ylabel('幅度 / dB');
    legend('Phase 7 响应', '24.1 kHz', '-70 dB', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(selected_metric.f/1e6, selected_metric.H_db, ...
        'Color', [0.05 0.50 0.58], 'LineWidth', 1.0); hold on;
    yline(-stop_limit, '--', 'Color', color_yellow);
    xlim([0 selected_metric.f(end)/1e6]); ylim([-170 5]);
    title('全频段响应'); xlabel('频率 / MHz'); ylabel('幅度 / dB');
    style_axes(gca);

    nexttile;
    frequency = linspace(0, pass_edge, 1200);
    cic_magnitude = cic_normalized_magnitude(frequency, ...
        fs_cic_in, rate_change, diff_delay, selected_row.CIC_ORDER);
    [H_comp, f_comp] = freqz(h_comp, 1, 4096, fs_cic_in);
    comp_index = f_comp <= pass_edge;
    plot(frequency/1e3, 20*log10(cic_magnitude+1e-15), ...
        'Color', color_blue, 'LineWidth', 1.8); hold on;
    plot(f_comp(comp_index)/1e3, ...
        20*log10(abs(H_comp(comp_index))+1e-15), ...
        'Color', color_green, 'LineWidth', 1.8);
    title(sprintf('N=%d CIC 与 %dtap Q%d 补偿', ...
        selected_row.CIC_ORDER, selected_row.COMP_TAPS, ...
        selected_row.FRAC_W));
    xlabel('频率 / kHz'); ylabel('幅度 / dB');
    legend('CIC 下垂', '补偿器增益', 'Location', 'best');
    style_axes(gca);

    sgtitle('Phase 7-B：低速补偿 FIR 后的 FIR-CIC 响应', ...
        'FontWeight', 'bold');
    exportgraphics(gcf, file_path, 'Resolution', 200);
end


% 10）局部函数模块：style_axes


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function style_axes(ax)
    grid(ax, 'on'); box(ax, 'on');
    ax.FontName = 'Microsoft YaHei';
    ax.FontSize = 11;
    ax.LineWidth = 1.1;
    ax.XMinorTick = 'off';
    ax.YMinorTick = 'off';
end
