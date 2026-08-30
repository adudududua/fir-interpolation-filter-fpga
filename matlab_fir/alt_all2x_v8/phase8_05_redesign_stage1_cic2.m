%% 1）主流程：phase8_05_redesign_stage1_cic2
% 功能说明：建立滤波器设计指标，搜索候选结构并评价幅频、相位和实现代价。

clc; clear; close all;

%=============================================================
% 文件名       : phase8_05_redesign_stage1_cic2.m
% 脚本名       : phase8_05_redesign_stage1_cic2
% 功能简述     : 面向二阶 CIC 尾级重新设计 Stage1 strict-halfband。
%                既有 Stage1 候选针对七级全 2x 链路设计，本脚本
%                在不改变 20kHz 有效通带的前提下，把等波纹原型的
%                设计通带边缘适当外移，使 24.1kHz 验收阻带入口
%                更深入原型阻带。
%
%                保持 strict-halfband 零抽头、对称性、两相整数和、
%                64 点历史 BRAM 上限以及单 DSP MAC 结构不变。
%
%                Stop/Go 门槛：
%                  通带最大绝对误差：<=0.01dB
%                  阻带衰减        ：>=72dB
%                  冲激响应对称误差：<1e-10
%                  Stage1 taps     ：<=129
%                  Stage1 MAC 对数 ：<=32
%
%                输出文件：
%                  results/phase8_cic2_stage1_redesign_candidates.csv
%                  results/phase8_cic2_stage1_redesign_selected.mat
%                  results/phase8_cic2_stage1_redesign_summary.md
%                  figures/phase8_cic2_stage1_redesign_response.png
%
% 当前默认配置：
%                  输入采样率      ：44.1kHz
%                  输出采样率      ：5.6448MHz
%                  Stage1 order    ：96:4:128
%                  原型通带边缘    ：20.0kHz:0.1kHz:21.4kHz
%                  Stage1 格式     ：Q15 / Q16
%                  CIC             ：R=4，N=2，M=1
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-19
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-19：新增二阶 CIC 专用 Stage1 搜索。
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
tail_data = load(fullfile(result_dir, ...
    'phase8_cic2_hb_selected.mat'), 'selected');

FS_IN = 44100;
FS_STAGE1 = FS_IN*2;
FS_STAGE2 = FS_IN*4;
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

ORDER_LIST = 96:4:128;
DESIGN_PASS_EDGE_LIST = 20000:100:21400;
FRAC_W_LIST = [15 16];

frequency = linspace(0, FS_OUT/2, NFFT_SEARCH).';
pass_index = frequency >= F_PASS_LOW & frequency <= F_PASS_HIGH;
stop_index = frequency >= F_STOP_BEGIN;

h_stage2 = double(best_config(2).coeff_int) / 2^best_config(2).frac_w;
h_stage3 = tail_data.selected.h_stage3;
h_hb4 = tail_data.selected.h_hb4;
h_hb5 = tail_data.selected.h_hb5;
h_cic4 = tail_data.selected.h_cic4;
H_tail = response_at_frequency(h_stage2, frequency, FS_STAGE2).* ...
    response_at_frequency(h_stage3, frequency, FS_STAGE3).* ...
    response_at_frequency(h_hb4, frequency, FS_HB4).* ...
    response_at_frequency(h_hb5, frequency, FS_HB5).* ...
    response_at_frequency(h_cic4, frequency, FS_OUT);

row = repmat(struct(), 0, 1);
store = repmat(struct(), 0, 1);
row_index = 0;
for order_n = ORDER_LIST
    for design_pass_edge = DESIGN_PASS_EDGE_LIST
        fp_norm = design_pass_edge/(FS_STAGE1/2);
        h_float = 2*firhalfband(order_n, fp_norm);
        for frac_w = FRAC_W_LIST
            coeff_int = quantize_strict_halfband(h_float, frac_w);
            h_stage1 = double(coeff_int)/2^frac_w;
            H_stage1 = response_at_frequency( ...
                h_stage1, frequency, FS_STAGE1);
            response_db = 20*log10(abs(H_stage1.*H_tail / ...
                EXPECTED_GAIN)+1e-15);

            row_index = row_index+1;
            row(row_index).ORDER = order_n; %#ok<SAGROW>
            row(row_index).TAPS = order_n+1; %#ok<SAGROW>
            row(row_index).DESIGN_PASS_EDGE_HZ = ...
                design_pass_edge; %#ok<SAGROW>
            row(row_index).FRAC_W = frac_w; %#ok<SAGROW>
            row(row_index).COEFF_W = ...
                required_signed_width(coeff_int); %#ok<SAGROW>
            row(row_index).MAC_PAIR_COUNT = order_n/4; %#ok<SAGROW>
            row(row_index).REAL_HISTORY_LEN = order_n/2; %#ok<SAGROW>
            row(row_index).PASS_ABS_MAX_DB = ...
                max(abs(response_db(pass_index))); %#ok<SAGROW>
            row(row_index).STOP_ATTN_DB = ...
                -max(response_db(stop_index)); %#ok<SAGROW>
            store(row_index).coeff_int = coeff_int; %#ok<SAGROW>
            store(row_index).h_stage1 = h_stage1; %#ok<SAGROW>
        end
    end
end

result_table = struct2table(row);
result_table.PASS = result_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB & ...
    result_table.STOP_ATTN_DB >= STOP_LIMIT_DB;
result_table.ORIGINAL_INDEX = (1:height(result_table)).';
result_table = sortrows(result_table, ...
    {'PASS', 'MAC_PAIR_COUNT', 'TAPS', 'COEFF_W', ...
     'STOP_ATTN_DB', 'PASS_ABS_MAX_DB'}, ...
    {'descend', 'ascend', 'ascend', 'ascend', 'descend', 'ascend'});
writetable(result_table, fullfile(result_dir, ...
    'phase8_cic2_stage1_redesign_candidates.csv'));

passing_table = result_table(result_table.PASS, :);
if isempty(passing_table)
    near_table = result_table(result_table.PASS_ABS_MAX_DB <= ...
        PASS_LIMIT_DB, :);
    if isempty(near_table)
        near_table = sortrows(result_table, ...
            {'PASS_ABS_MAX_DB', 'STOP_ATTN_DB', 'MAC_PAIR_COUNT'}, ...
            {'ascend', 'descend', 'ascend'});
    else
        near_table = sortrows(near_table, ...
            {'STOP_ATTN_DB', 'MAC_PAIR_COUNT'}, {'descend', 'ascend'});
    end
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
selected.h_stage2 = h_stage2;
selected.h_stage3 = h_stage3;
selected.stage3_coeff_int = tail_data.selected.stage3_coeff_int;
selected.h_hb4 = h_hb4;
selected.h_hb5 = h_hb5;
selected.h_cic4 = h_cic4;

h_total = selected.h_stage1;
h_total = append_interp2_stage(h_total, h_stage2);
h_total = append_interp2_stage(h_total, h_stage3);
h_total = append_interp2_stage(h_total, h_hb4);
h_total = append_interp2_stage(h_total, h_hb5);
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
    decision = "NO-GO";
end
selected.decision = decision;

save(fullfile(result_dir, ...
    'phase8_cic2_stage1_redesign_selected.mat'), 'selected');
write_summary(fullfile(result_dir, ...
    'phase8_cic2_stage1_redesign_summary.md'), ...
    tail_data.selected, selected);
plot_response(fullfile(figure_dir, ...
    'phase8_cic2_stage1_redesign_response.png'), selected.metric, ...
    F_PASS_HIGH, F_STOP_BEGIN);

fprintf(['Phase 8 二阶 CIC 专用 Stage1：%s\n' ...
    'Stage1=%dtap，MAC=%d，design_fp=%.1fHz，Q%d/%dbit，' ...
    'pass=%.8fdB，stop=%.8fdB，sym=%.3g\n'], ...
    selected.decision, selected.row.TAPS, selected.row.MAC_PAIR_COUNT, ...
    selected.row.DESIGN_PASS_EDGE_HZ, selected.row.FRAC_W, ...
    selected.row.COEFF_W, selected.metric.pass_abs_max_db, ...
    selected.metric.stop_attn_db, selected.metric.sym_err);


% 2）局部函数模块：quantize_strict_halfband


% 功能说明：执行与 RTL 一致的定点量化、舍入、移位和饱和处理。
function coeff_int = quantize_strict_halfband(h_float, frac_w)
    scale = int64(2^frac_w);
    coeff_int = int64(round(h_float(:).'*double(scale)));
    center = (numel(coeff_int)+1)/2;
    coeff_int = int64(round((double(coeff_int)+ ...
        fliplr(double(coeff_int)))/2));
    zero_idx = find(mod(1:numel(coeff_int), 2) == mod(center, 2));
    zero_idx(zero_idx == center) = [];
    coeff_int(zero_idx) = 0;
    coeff_int(center) = scale;

    filtered_idx = find(mod(1:numel(coeff_int), 2) ~= mod(center, 2));
    delta = scale-sum(coeff_int(filtered_idx));
    if mod(delta, 2) ~= 0
        error('Stage1 两相整数和修正量不是偶数。');
    end
    coeff_int([center-1 center+1]) = ...
        coeff_int([center-1 center+1])+delta/2;
    if sum(coeff_int(1:2:end)) ~= scale || ...
            sum(coeff_int(2:2:end)) ~= scale
        error('Stage1 两相整数和校正失败。');
    end
end


% 3）局部函数模块：required_signed_width


% 功能说明：封装 required_signed_width 对应的局部计算，供主流程复用并保持代码层次清晰。
function coeff_w = required_signed_width(coeff_int)
    coeff_w = 2;
    while max(coeff_int) > int64(2^(coeff_w-1)-1) || ...
            min(coeff_int) < int64(-2^(coeff_w-1))
        coeff_w = coeff_w+1;
    end
end


% 4）局部函数模块：response_at_frequency


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function H = response_at_frequency(h, frequency, sample_rate)
    omega = 2*pi*frequency(:)/sample_rate;
    sample_index = 0:numel(h)-1;
    H = exp(-1j*omega*sample_index)*h(:);
end


% 5）局部函数模块：append_interp2_stage


% 功能说明：封装 append_interp2_stage 对应的局部计算，供主流程复用并保持代码层次清晰。
function h_total = append_interp2_stage(h_previous, h_stage)
    h_up = zeros(1, 2*numel(h_previous)-1);
    h_up(1:2:end) = h_previous;
    h_total = conv(h_up, h_stage);
end


% 6）局部函数模块：write_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_summary(filename, baseline, selected)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '# Phase 8 二阶 CIC 专用 Stage1 搜索结果\n\n');
    fprintf(fid, '| 项目 | 原 105tap Stage1 | 专用候选 |\n');
    fprintf(fid, '|---|---:|---:|\n');
    fprintf(fid, '| Stage1 taps | 105 | %d |\n', selected.row.TAPS);
    fprintf(fid, '| Stage1 MAC 对数 | 26 | %d |\n', ...
        selected.row.MAC_PAIR_COUNT);
    fprintf(fid, '| 原型通带边缘/Hz | 20000 | %.1f |\n', ...
        selected.row.DESIGN_PASS_EDGE_HZ);
    fprintf(fid, '| 通带最大绝对误差/dB | %.8f | %.8f |\n', ...
        baseline.metric.pass_abs_max_db, selected.metric.pass_abs_max_db);
    fprintf(fid, '| 阻带衰减/dB | %.8f | %.8f |\n', ...
        baseline.metric.stop_attn_db, selected.metric.stop_attn_db);
    fprintf(fid, '| 对称误差 | %.3g | %.3g |\n', ...
        baseline.metric.sym_err, selected.metric.sym_err);
    fprintf(fid, '| 数学门槛 | NO-GO | %s |\n', selected.decision);
    fprintf(fid, '\n## Stage1 定点系数\n\n```text\n');
    fprintf(fid, '%d\n', selected.coeff_int);
    fprintf(fid, '```\n');
end


% 7）局部函数模块：plot_response


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
    title('二阶 CIC 专用 Stage1：通带至阻带入口');
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
