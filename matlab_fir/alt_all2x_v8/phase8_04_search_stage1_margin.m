%% 1）主流程：phase8_04_search_stage1_margin
% 功能说明：执行参数搜索和 Pareto 筛选，在满足指标的前提下降低字长或资源开销。

clc; clear; close all;

%=============================================================
% 文件名       : phase8_04_search_stage1_margin.m
% 脚本名       : phase8_04_search_stage1_margin
% 功能简述     : 在尾级 7tap/11tap Halfband 均无法把二阶 CIC
%                候选提高到 72dB 后，从既有 Stage1 strict-halfband
%                定点候选库中搜索最小增量方案。
%
%                Stage2、Stage3、两级 7tap Halfband 与 CIC4(N=2)
%                全部保持不变，只替换 Stage1 系数。按 MAC 对数、
%                抽头数和系数字长排序，选择满足 72dB 的最小候选。
%
%                Stop/Go 门槛：
%                  通带最大绝对误差：<=0.01dB
%                  阻带衰减        ：>=72dB
%                  冲激响应对称误差：<1e-10
%                  Stage1 历史长度 ：<=64
%                  Stage1 MAC 对数 ：<=31
%
%                输出文件：
%                  results/phase8_cic2_stage1_candidates.csv
%                  results/phase8_cic2_stage1_selected.mat
%                  results/phase8_cic2_stage1_summary.md
%                  figures/phase8_cic2_stage1_response.png
%
% 当前默认配置：
%                  输入采样率      ：44.1kHz
%                  输出采样率      ：5.6448MHz
%                  Stage1 基线     ：105tap、26 对 MAC、Q15
%                  CIC             ：R=4，N=2，M=1
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-19
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-19：新增 Stage1 阻带余量搜索。
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

load(fullfile(v2_dir, 'stage1_strict_halfband_config.mat'), ...
     'best_config');
candidate_data = load(fullfile(v2_dir, ...
    'stage1_strict_halfband_candidates.mat'), 'candidate_records');
tail_data = load(fullfile(result_dir, ...
    'phase8_cic2_hb_selected.mat'), 'selected');

FS_IN = 44100;
FS_OUT = FS_IN*128;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_BEGIN = FS_IN-F_PASS_HIGH;
EXPECTED_GAIN = 128;
PASS_LIMIT_DB = 0.01;
STOP_LIMIT_DB = 72;
NFFT_SEARCH = 2^18;
NFFT_FINAL = 2^20;
MAX_HISTORY = 64;
MAX_MAC_PAIR = 31;

row = repmat(struct(), 0, 1);
store = repmat(struct(), 0, 1);
row_index = 0;
for candidate_idx = 1:numel(candidate_data.candidate_records)
    record = candidate_data.candidate_records(candidate_idx);
    if record.real_history_len > MAX_HISTORY || ...
            record.mac_pair_count > MAX_MAC_PAIR
        continue;
    end

    h_stage1 = double(record.coeff_int) / 2^record.frac_w;
    h_total = h_stage1;
    h_total = append_interp2_stage(h_total, ...
        double(best_config(2).coeff_int)/2^best_config(2).frac_w);
    h_total = append_interp2_stage(h_total, tail_data.selected.h_stage3);
    h_total = append_interp2_stage(h_total, tail_data.selected.h_hb4);
    h_total = append_interp2_stage(h_total, tail_data.selected.h_hb5);
    h_up = zeros(1, 4*(numel(h_total)-1)+1);
    h_up(1:4:end) = h_total;
    h_total = conv(h_up, tail_data.selected.h_cic4);
    metric = analyze_cic_response(h_total, FS_IN, FS_OUT, ...
        F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, ...
        EXPECTED_GAIN, NFFT_SEARCH);

    row_index = row_index+1;
    row(row_index).SOURCE_INDEX = candidate_idx; %#ok<SAGROW>
    row(row_index).TAPS = record.taps; %#ok<SAGROW>
    row(row_index).FRAC_W = record.frac_w; %#ok<SAGROW>
    row(row_index).COEFF_W = record.coeff_w; %#ok<SAGROW>
    row(row_index).ACC_W = record.acc_w; %#ok<SAGROW>
    row(row_index).MAC_PAIR_COUNT = record.mac_pair_count; %#ok<SAGROW>
    row(row_index).REAL_HISTORY_LEN = record.real_history_len; %#ok<SAGROW>
    row(row_index).PASS_ABS_MAX_DB = metric.pass_abs_max_db; %#ok<SAGROW>
    row(row_index).STOP_ATTN_DB = metric.stop_attn_db; %#ok<SAGROW>
    row(row_index).SYMMETRY_ERROR = metric.sym_err; %#ok<SAGROW>
    store(row_index).h_stage1 = h_stage1; %#ok<SAGROW>
    store(row_index).coeff_int = record.coeff_int; %#ok<SAGROW>
    store(row_index).h_total = h_total; %#ok<SAGROW>
end

result_table = struct2table(row);
result_table.PASS = result_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB & ...
    result_table.STOP_ATTN_DB >= STOP_LIMIT_DB & ...
    result_table.SYMMETRY_ERROR < 1e-10;
result_table.ORIGINAL_INDEX = (1:height(result_table)).';
result_table = sortrows(result_table, ...
    {'PASS', 'MAC_PAIR_COUNT', 'TAPS', 'COEFF_W', ...
     'STOP_ATTN_DB', 'PASS_ABS_MAX_DB'}, ...
    {'descend', 'ascend', 'ascend', 'ascend', 'descend', 'ascend'});
writetable(result_table, fullfile(result_dir, ...
    'phase8_cic2_stage1_candidates.csv'));

passing_table = result_table(result_table.PASS, :);
if isempty(passing_table)
    near_table = result_table(result_table.PASS_ABS_MAX_DB <= ...
        PASS_LIMIT_DB, :);
    near_table = sortrows(near_table, ...
        {'STOP_ATTN_DB', 'MAC_PAIR_COUNT', 'TAPS'}, ...
        {'descend', 'ascend', 'ascend'});
    selected_row = near_table(1, :);
    decision = "NO-GO";
else
    selected_row = passing_table(1, :);
    decision = "GO";
end
selected_index = selected_row.ORIGINAL_INDEX;
selected.row = selected_row;
selected.coeff_int = store(selected_index).coeff_int;
selected.h_stage1 = store(selected_index).h_stage1;
selected.h_stage2 = double(best_config(2).coeff_int) / ...
    2^best_config(2).frac_w;
selected.h_stage3 = tail_data.selected.h_stage3;
selected.stage3_coeff_int = tail_data.selected.stage3_coeff_int;
selected.h_hb4 = tail_data.selected.h_hb4;
selected.h_hb5 = tail_data.selected.h_hb5;
selected.h_cic4 = tail_data.selected.h_cic4;
selected.h_total = store(selected_index).h_total;
selected.metric = analyze_cic_response(selected.h_total, FS_IN, FS_OUT, ...
    F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, NFFT_FINAL);
selected.pass_exact = selected.metric.pass_abs_max_db <= PASS_LIMIT_DB && ...
    selected.metric.stop_attn_db >= STOP_LIMIT_DB && ...
    selected.metric.sym_err < 1e-10;
if ~selected.pass_exact
    decision = "NO-GO";
end
selected.decision = decision;

save(fullfile(result_dir, 'phase8_cic2_stage1_selected.mat'), 'selected');
write_summary(fullfile(result_dir, ...
    'phase8_cic2_stage1_summary.md'), best_config(1), ...
    tail_data.selected, selected);
plot_response(fullfile(figure_dir, ...
    'phase8_cic2_stage1_response.png'), selected.metric, ...
    F_PASS_HIGH, F_STOP_BEGIN);

fprintf(['Phase 8 Stage1 余量搜索：%s\n' ...
    'Stage1=%dtap，MAC=%d，Q%d/%dbit，pass=%.8fdB，' ...
    'stop=%.8fdB，sym=%.3g\n'], ...
    selected.decision, selected.row.TAPS, selected.row.MAC_PAIR_COUNT, ...
    selected.row.FRAC_W, selected.row.COEFF_W, ...
    selected.metric.pass_abs_max_db, selected.metric.stop_attn_db, ...
    selected.metric.sym_err);


% 2）局部函数模块：append_interp2_stage


% 功能说明：封装 append_interp2_stage 对应的局部计算，供主流程复用并保持代码层次清晰。
function h_total = append_interp2_stage(h_previous, h_stage)
    h_up = zeros(1, 2*numel(h_previous)-1);
    h_up(1:2:end) = h_previous;
    h_total = conv(h_up, h_stage);
end


% 3）局部函数模块：write_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_summary(filename, baseline_stage1, baseline_tail, selected)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '# Phase 8 二阶 CIC 的 Stage1 余量搜索结果\n\n');
    fprintf(fid, '| 项目 | 105tap + 二阶 CIC | 最佳近邻候选 |\n');
    fprintf(fid, '|---|---:|---:|\n');
    fprintf(fid, '| Stage1 taps | %d | %d |\n', ...
        baseline_stage1.taps, selected.row.TAPS);
    fprintf(fid, '| Stage1 MAC 对数 | %d | %d |\n', ...
        (baseline_stage1.taps-1)/4, selected.row.MAC_PAIR_COUNT);
    fprintf(fid, '| Stage1 历史长度 | %d | %d |\n', ...
        (baseline_stage1.taps-1)/2, selected.row.REAL_HISTORY_LEN);
    fprintf(fid, '| 通带最大绝对误差/dB | %.8f | %.8f |\n', ...
        baseline_tail.metric.pass_abs_max_db, ...
        selected.metric.pass_abs_max_db);
    fprintf(fid, '| 阻带衰减/dB | %.8f | %.8f |\n', ...
        baseline_tail.metric.stop_attn_db, selected.metric.stop_attn_db);
    fprintf(fid, '| 数学门槛 | NO-GO | %s |\n', selected.decision);
    fprintf(fid, '\n## Stage1 定点系数\n\n```text\n');
    fprintf(fid, '%d\n', selected.coeff_int);
    fprintf(fid, '```\n');
end


% 4）局部函数模块：plot_response


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
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
    title('二阶 CIC + Stage1 余量优化：通带至阻带入口');
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
