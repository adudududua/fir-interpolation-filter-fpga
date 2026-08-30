%% 1）主流程：phase7_05_search_folded_stage3
% 功能说明：执行参数搜索和 Pareto 筛选，在满足指标的前提下降低字长或资源开销。

clc; clear; close all;

%=============================================================
% 文件名       : phase7_05_search_folded_stage3.m
% 脚本名       : phase7_05_search_folded_stage3
% 功能简述     : Phase 7 独立补偿 FIR 资源 No-Go 后的变通搜索。
%                将 CIC 通带逆下垂与原 Stage3 的 2x 镜像抑制合并
%                为一套线性相位 FIR 系数，使 Stage3 在完成
%                176.4kHz -> 352.8kHz 插值的同时补偿后续 CIC，
%                从而复用现有 Stage2/3 共享 DSP 调度器。
%
%                输出文件：
%                  folded_stage3_results/folded_stage3_candidates.csv
%                  folded_stage3_results/folded_stage3_pareto.mat
%                  folded_stage3_results/folded_stage3_summary.txt
%                  figures/folded_stage3_response.png
%
% 当前默认配置：
%                  CIC：R=16，M=1，N=3/4
%                  Stage3 taps：11/15/19/23/25/31
%                  系数格式：Q14/16bit，Q15/17bit
%                  通带最大绝对误差：<0.01dB
%                  阻带衰减：>70dB
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 Stage3 折叠补偿搜索。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
v2_dir = fullfile(repo_matlab_dir, 'alt_all2x_v2');
common_dir = fullfile(v2_dir, 'common');
result_dir = fullfile(script_dir, 'folded_stage3_results');
figure_dir = fullfile(script_dir, 'figures');
addpath(common_dir);
addpath(script_dir);
for one_dir = {result_dir, figure_dir}
    if ~exist(one_dir{1}, 'dir')
        mkdir(one_dir{1});
    end
end

load(fullfile(v2_dir, 'stage1_strict_halfband_config.mat'), ...
     'best_config');

FS_IN = 44100;
FS_STAGE3_OUT = FS_IN*8;
R_CIC = 16;
M_CIC = 1;
FS_OUT = FS_STAGE3_OUT*R_CIC;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STAGE3_STOP = FS_IN*4-F_PASS_HIGH;
F_STOP_BEGIN = FS_IN-F_PASS_HIGH;
EXPECTED_GAIN = 128;
PASS_LIMIT_DB = 0.01;
STOP_LIMIT_DB = 70;
NFFT_SEARCH = 2^18;
NFFT_FINAL = 2^20;

ORDER_LIST = [3 4];
TAP_LIST = [11 15 19 23 25 31];
FORMAT_LIST = [14 16; 15 17];
STOP_WEIGHT_LIST = [0 1e-6 1e-5 1e-4 1e-3 1e-2 1e-1 1 10];

h_pre2 = build_multistage_ir(best_config(1:2));

row_order = [];
row_taps = [];
row_frac = [];
row_coeff_w = [];
row_weight = [];
row_max_coeff = [];
row_required_w = [];
row_pass_abs = [];
row_ripple = [];
row_stop = [];
row_gd = [];
row_sym = [];
row_fit = [];
row_index = 0;

candidate_store = repmat(struct(), 0, 1);
fprintf('Phase 7 Stage3 折叠补偿搜索开始。\n');
for cic_order = ORDER_LIST
    h_cic = design_cic16_interpolator(cic_order, R_CIC, M_CIC);
    desired_fun = @(frequency_hz) 2 ./ cic_normalized_magnitude( ...
        frequency_hz, FS_STAGE3_OUT, R_CIC, M_CIC, cic_order);
    for tap_count = TAP_LIST
        for stop_weight = STOP_WEIGHT_LIST
            h_float = design_folded_stage3(tap_count, FS_STAGE3_OUT, ...
                F_PASS_HIGH, F_STAGE3_STOP, desired_fun, stop_weight);
            for format_idx = 1:size(FORMAT_LIST, 1)
                frac_w = FORMAT_LIST(format_idx, 1);
                coeff_w = FORMAT_LIST(format_idx, 2);
                [coeff_int, h_stage3, fit_ok, required_w] = ...
                    quantize_folded_stage3(h_float, frac_w, coeff_w);

                h_pre3 = append_interp2_stage(h_pre2, h_stage3);
                h_up = zeros(1, R_CIC*(numel(h_pre3)-1)+1);
                h_up(1:R_CIC:end) = h_pre3;
                h_total = conv(h_up, h_cic);
                metric = analyze_cic_response(h_total, FS_IN, FS_OUT, ...
                    F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, ...
                    EXPECTED_GAIN, NFFT_SEARCH);

                row_index = row_index+1;
                row_order(row_index, 1) = cic_order; %#ok<SAGROW>
                row_taps(row_index, 1) = tap_count; %#ok<SAGROW>
                row_frac(row_index, 1) = frac_w; %#ok<SAGROW>
                row_coeff_w(row_index, 1) = coeff_w; %#ok<SAGROW>
                row_weight(row_index, 1) = stop_weight; %#ok<SAGROW>
                row_max_coeff(row_index, 1) = max(abs(coeff_int)); %#ok<SAGROW>
                row_required_w(row_index, 1) = required_w; %#ok<SAGROW>
                row_pass_abs(row_index, 1) = metric.pass_abs_max_db; %#ok<SAGROW>
                row_ripple(row_index, 1) = metric.ripple_pp_db; %#ok<SAGROW>
                row_stop(row_index, 1) = metric.stop_attn_db; %#ok<SAGROW>
                row_gd(row_index, 1) = metric.gd_pp; %#ok<SAGROW>
                row_sym(row_index, 1) = metric.sym_err; %#ok<SAGROW>
                row_fit(row_index, 1) = fit_ok; %#ok<SAGROW>

                candidate_store(row_index).coeff_int = coeff_int; %#ok<SAGROW>
                candidate_store(row_index).h_stage3 = h_stage3; %#ok<SAGROW>
                candidate_store(row_index).h_cic = h_cic; %#ok<SAGROW>
                candidate_store(row_index).h_total = h_total; %#ok<SAGROW>
            end
        end
    end
end

result_table = table(row_order, row_taps, row_frac, row_coeff_w, ...
    row_weight, row_max_coeff, row_required_w, row_pass_abs, row_ripple, ...
    row_stop, row_gd, row_sym, row_fit, 'VariableNames', ...
    {'CIC_ORDER', 'STAGE3_TAPS', 'FRAC_W', 'COEFF_W', 'STOP_WEIGHT', ...
     'MAX_COEFF_INT', 'REQUIRED_COEFF_W', 'PASS_ABS_MAX_DB', ...
     'RIPPLE_PP_DB', 'STOP_ATTN_DB', 'GD_RIPPLE_SAMPLE', ...
     'SYMMETRY_ERROR', 'COEFF_FIT'});
result_table.PASS = result_table.COEFF_FIT & ...
    result_table.PASS_ABS_MAX_DB < PASS_LIMIT_DB & ...
    result_table.STOP_ATTN_DB > STOP_LIMIT_DB & ...
    result_table.SYMMETRY_ERROR < 1e-10;
result_table.RESOURCE_PROXY = 100*result_table.STAGE3_TAPS + ...
                              result_table.COEFF_W;
writetable(result_table, fullfile(result_dir, ...
    'folded_stage3_candidates.csv'));

pareto = repmat(struct(), 1, numel(ORDER_LIST));
pareto_rows = table();
for order_idx = 1:numel(ORDER_LIST)
    one_order = ORDER_LIST(order_idx);
    % Q15/17bit still fits the DSP48 coefficient input, while avoiding the
    % bit-true margin loss observed with the Q14/16bit folded candidate.
    order_table = result_table(result_table.PASS & ...
        result_table.CIC_ORDER == one_order & ...
        result_table.FRAC_W == 15, :);
    if isempty(order_table)
        error('N=%d 未找到通过的 Stage3 折叠补偿候选。', one_order);
    end
    order_table.ORIGINAL_INDEX = find(result_table.PASS & ...
        result_table.CIC_ORDER == one_order & ...
        result_table.FRAC_W == 15);
    order_table = sortrows(order_table, ...
        {'RESOURCE_PROXY', 'PASS_ABS_MAX_DB', 'STOP_ATTN_DB'}, ...
        {'ascend', 'ascend', 'descend'});
    selected_row = order_table(1, :);
    original_index = selected_row.ORIGINAL_INDEX;
    exact_metric = analyze_cic_response( ...
        candidate_store(original_index).h_total, FS_IN, FS_OUT, ...
        F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, NFFT_FINAL);

    pareto(order_idx).name = sprintf('folded_n%d', one_order);
    pareto(order_idx).row = selected_row;
    pareto(order_idx).coeff_int = ...
        candidate_store(original_index).coeff_int;
    pareto(order_idx).h_stage3 = ...
        candidate_store(original_index).h_stage3;
    pareto(order_idx).h_cic = candidate_store(original_index).h_cic;
    pareto(order_idx).h_total = candidate_store(original_index).h_total;
    pareto(order_idx).metric = exact_metric;
    pareto_rows = [pareto_rows; selected_row]; %#ok<AGROW>
end

save(fullfile(result_dir, 'folded_stage3_pareto.mat'), 'pareto');
writetable(pareto_rows, fullfile(result_dir, 'folded_stage3_pareto.csv'));
write_summary(fullfile(result_dir, 'folded_stage3_summary.txt'), pareto);
plot_pareto(fullfile(figure_dir, 'folded_stage3_response.png'), ...
    pareto, F_PASS_HIGH, F_STOP_BEGIN);

for idx = 1:numel(pareto)
    fprintf('%s: taps=%d Q%d/%dbit pass=%.8fdB stop=%.8fdB\n', ...
        pareto(idx).name, pareto(idx).row.STAGE3_TAPS, ...
        pareto(idx).row.FRAC_W, pareto(idx).row.COEFF_W, ...
        pareto(idx).metric.pass_abs_max_db, ...
        pareto(idx).metric.stop_attn_db);
end
formal_index = find(strcmp({pareto.name}, 'folded_n3'), 1);
if isempty(formal_index)
    error('缺少正式提交候选 folded_n3。');
end
formal = pareto(formal_index);
fprintf('\n================ Stage3 正式折叠补偿结论 ================\n');
fprintf('正式结构：%d taps 线性相位 FIR，Q%d，%d bit 系数\n', ...
    formal.row.STAGE3_TAPS, formal.row.FRAC_W, formal.row.COEFF_W);
fprintf('作用：同时完成第三级 2x 插值镜像抑制与 CIC16 通带补偿\n');
fprintf('完整 128x 通带最大偏差 = %.8f dB\n', ...
    formal.metric.pass_abs_max_db);
fprintf('完整 128x 通带峰峰纹波 = %.8f dB\n', ...
    formal.metric.ripple_pp_db);
fprintf('完整 128x 阻带衰减     = %.8f dB\n', ...
    formal.metric.stop_attn_db);
fprintf('整数系数：');
fprintf('%d ', formal.coeff_int);
fprintf('\n最终判定：PASS\n');
fprintf('CSV : %s\n', fullfile(result_dir, ...
    'folded_stage3_candidates.csv'));
fprintf('CSV2: %s\n', fullfile(result_dir, ...
    'folded_stage3_pareto.csv'));
fprintf('TXT : %s\n', fullfile(result_dir, ...
    'folded_stage3_summary.txt'));
fprintf('MAT : %s\n', fullfile(result_dir, ...
    'folded_stage3_pareto.mat'));
fprintf('PNG : %s\n', fullfile(figure_dir, ...
    'folded_stage3_response.png'));
fprintf('========================================================\n');
drawnow;


% 2）局部函数模块：append_interp2_stage


% 功能说明：封装 append_interp2_stage 对应的局部计算，供主流程复用并保持代码层次清晰。
function h_total = append_interp2_stage(h_previous, h_stage)
    h_up = zeros(1, 2*numel(h_previous)-1);
    h_up(1:2:end) = h_previous;
    h_total = conv(h_up, h_stage);
end


% 3）局部函数模块：cic_normalized_magnitude


% 功能说明：封装 cic_normalized_magnitude 对应的局部计算，供主流程复用并保持代码层次清晰。
function magnitude = cic_normalized_magnitude(frequency_hz, ...
        input_rate_hz, rate_change, diff_delay, cic_order)
    numerator = sin(pi*frequency_hz*diff_delay/input_rate_hz);
    denominator = rate_change*diff_delay * ...
        sin(pi*frequency_hz/(rate_change*input_rate_hz));
    ratio = ones(size(frequency_hz));
    nonzero = abs(frequency_hz) > 1e-15;
    ratio(nonzero) = numerator(nonzero)./denominator(nonzero);
    magnitude = abs(ratio).^cic_order;
end


% 4）局部函数模块：design_folded_stage3


% 功能说明：封装 design_folded_stage3 对应的局部计算，供主流程复用并保持代码层次清晰。
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


% 5）局部函数模块：anonymous_function_block


% 功能说明：封装 anonymous_function_block 对应的局部计算，供主流程复用并保持代码层次清晰。
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


% 6）局部函数模块：write_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_summary(filename, pareto)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Phase 7 Stage3 folded compensation search\n');
    fprintf(fid, '===========================================\n');
    fprintf(fid, 'Architecture: Stage1 -> Stage2 -> folded Stage3 -> CIC16\n');
    fprintf(fid, 'Limits: pass<0.01dB, stop>70dB, linear phase\n\n');
    for idx = 1:numel(pareto)
        fprintf(fid, ['%s taps=%d Q%d/%dbit weight=%.8g ' ...
            'pass=%.8fdB ripple=%.8fdB stop=%.8fdB gd=%.12g\n'], ...
            pareto(idx).name, pareto(idx).row.STAGE3_TAPS, ...
            pareto(idx).row.FRAC_W, pareto(idx).row.COEFF_W, ...
            pareto(idx).row.STOP_WEIGHT, ...
            pareto(idx).metric.pass_abs_max_db, ...
            pareto(idx).metric.ripple_pp_db, ...
            pareto(idx).metric.stop_attn_db, ...
            pareto(idx).metric.gd_pp);
        fprintf(fid, 'coeff_int = ');
        fprintf(fid, '%d ', pareto(idx).coeff_int);
        fprintf(fid, '\n\n');
    end
end


% 7）局部函数模块：plot_pareto


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function plot_pareto(filename, pareto, pass_edge, stop_begin)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_yellow = [0.82 0.88 0.05];
    line_color = {color_blue, color_purple};
    figure('Name', 'Stage3 - 11抽头折叠CIC补偿设计', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [80 60 1500 760]);
    tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    for idx = 1:numel(pareto)
        plot(pareto(idx).metric.f/1e3, pareto(idx).metric.H_db, ...
            'Color', line_color{idx}, 'LineWidth', 1.7); hold on;
    end
    yline(0.01, '--', 'Color', color_yellow);
    yline(-0.01, '--', 'Color', color_yellow);
    xline(pass_edge/1e3, '--', 'Color', color_green);
    xlim([0 22]); ylim([-0.025 0.025]);
    title('Stage3 折叠补偿通带'); xlabel('频率 / kHz');
    ylabel('相对幅度 / dB');
    legend(pareto.name, '+/-0.01 dB', '20 kHz', ...
        'Location', 'southwest'); style_axes(gca);
    nexttile;
    for idx = 1:numel(pareto)
        plot(pareto(idx).metric.f/1e3, pareto(idx).metric.H_db, ...
            'Color', line_color{idx}, 'LineWidth', 1.4); hold on;
    end
    yline(-70, '--', 'Color', color_yellow);
    xline(stop_begin/1e3, '--', 'Color', color_green);
    xlim([0 500]); ylim([-150 5]);
    title('Stage3 折叠补偿阻带'); xlabel('频率 / kHz');
    ylabel('幅度 / dB');
    legend(pareto.name, '-70 dB', '24.1 kHz', ...
        'Location', 'southwest'); style_axes(gca);
    sgtitle('Phase 7-E Stage3 折叠 CIC 补偿');
    exportgraphics(gcf, filename, 'Resolution', 180);
end


% 8）局部函数模块：style_axes


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function style_axes(ax)
    grid(ax, 'on'); box(ax, 'on');
    ax.FontName = 'Microsoft YaHei';
    ax.FontSize = 11;
    ax.LineWidth = 1.1;
    ax.XMinorTick = 'on'; ax.YMinorTick = 'on';
    ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';
end
