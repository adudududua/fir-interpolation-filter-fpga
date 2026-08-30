clc; clear; close all;

%=============================================================
% 文件名       : compare_all2x_rtl_impulse_tb.m
% 脚本名       : compare_all2x_rtl_impulse_tb
% 功能简述     : 全 2x 结构 RTL 脉冲响应基础仿真的 MATLAB golden 对拍脚本。
%                本脚本读取 tb_interp128_all2x_top_ce.v 生成的
%                interp128_all2x_tb_output.csv，并用 MATLAB 固定点模型
%                复现同一组 7 级 2x 插值滤波链路。
%
%                固定点模型与 RTL 保持一致：
%                  1. 每一级先 2 倍插零；
%                  2. 使用 stageXX_2x_coeff_decimal.txt 中的整数系数；
%                  3. FIR 累加后按对应 FRAC_W 做四舍五入；
%                  4. 每一级输出均饱和到 24bit signed；
%                  5. 最后自动搜索 RTL 输出相对 golden 的最佳延迟。
%
%                输出文件：
%                  all2x_rtl_impulse_compare_summary.txt
%                  all2x_rtl_impulse_compare.png
%
% 当前默认配置：
%                  输入激励    ：单点脉冲，幅度 1000000
%                  插值结构    ：7 级 2x
%                  RTL CSV 文件：系统临时 Vivado 工作目录
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增全 2x RTL 脉冲响应 golden 对拍脚本。
%                2026-07-10：改为自动读取最新逐级 FRAC_W，并优先从
%                            专用 Vivado 临时目录读取 RTL 输出。
%=============================================================

%% 1）路径与参数
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir)
    script_dir = pwd;
end

repo_dir = fullfile(script_dir, '..', '..');
bittrue_dir = fullfile(script_dir, 'bittrue');
addpath(bittrue_dir);

stage_config = load_all2x_stage_config(script_dir, 24);
NUM_STAGE = numel(stage_config);

rtl_csv_temp = fullfile(tempdir, 'codex_vivado_fir_interpolation', ...
                        'interp128_all2x_tb_output.csv');
rtl_csv_legacy = fullfile(repo_dir, 'interp128_all2x_tb_output.csv');

if exist(rtl_csv_temp, 'file')
    rtl_csv = rtl_csv_temp;
else
    rtl_csv = rtl_csv_legacy;
end
IMPULSE_AMP = 1000000;
OUT_W = 24;

summary_path = fullfile(script_dir, 'all2x_rtl_impulse_compare_summary.txt');
png_path = fullfile(script_dir, 'all2x_rtl_impulse_compare.png');

fprintf('====================================================\n');
fprintf('全 2x RTL 脉冲响应 golden 对拍开始\n');
fprintf('RTL CSV: %s\n', rtl_csv);
fprintf('====================================================\n\n');

if ~exist(rtl_csv, 'file')
    error('未找到 RTL 仿真输出 CSV：%s。请先运行 tb_interp128_all2x_top_ce。', rtl_csv);
end

%% 2）读取 RTL 输出
%=============================================================

rtl_tbl = readtable(rtl_csv);
rtl_y = double(rtl_tbl.y_out(:)).';

fprintf('RTL 输出样本数 = %d\n', length(rtl_y));
fprintf('RTL 非零样本数 = %d\n', nnz(rtl_y));

%% 3）生成 MATLAB 固定点 golden
%=============================================================

golden_y = IMPULSE_AMP;

for stage_idx = 1:NUM_STAGE
    coeff_path = fullfile(script_dir, sprintf('stage%02d_2x_coeff_decimal.txt', stage_idx));
    coeff_int = readmatrix(coeff_path);
    coeff_int = coeff_int(~isnan(coeff_int));
    coeff_int = double(coeff_int(:).');

    x_up = zeros(1, 2*length(golden_y) - 1);
    x_up(1:2:end) = golden_y;

    acc_full = conv(x_up, coeff_int);
    golden_y = round_sat_to_int(acc_full, stage_config(stage_idx).frac_w, OUT_W);

    fprintf('Stage %d golden 长度 = %d，非零样本数 = %d\n', ...
            stage_idx, length(golden_y), nnz(golden_y));
end

fprintf('\nGolden 输出样本数 = %d\n', length(golden_y));
fprintf('Golden 非零样本数 = %d\n', nnz(golden_y));

%% 4）自动搜索最佳延迟并对齐
%=============================================================

search_max = min(length(rtl_y) - length(golden_y), 20000);
if search_max < 0
    error('RTL 输出长度短于 golden，无法完成对齐。');
end

best_shift = 0;
best_max_abs_err = inf;
best_rms_err = inf;

for shift = 0:search_max
    rtl_seg = rtl_y(shift + 1 : shift + length(golden_y));
    err = rtl_seg - golden_y;
    max_abs_err = max(abs(err));
    rms_err = sqrt(mean(err.^2));

    if (max_abs_err < best_max_abs_err) || ...
       (max_abs_err == best_max_abs_err && rms_err < best_rms_err)
        best_shift = shift;
        best_max_abs_err = max_abs_err;
        best_rms_err = rms_err;
    end
end

rtl_aligned = rtl_y(best_shift + 1 : best_shift + length(golden_y));
err = rtl_aligned - golden_y;

max_abs_err = max(abs(err));
rms_err = sqrt(mean(err.^2));
num_mismatch = nnz(err);

fprintf('\n================ 对拍结果 ================\n');
fprintf('最佳 RTL 延迟 shift       = %d 个最终输出样本\n', best_shift);
fprintf('最大绝对误差              = %.0f LSB\n', max_abs_err);
fprintf('RMS 误差                  = %.6f LSB\n', rms_err);
fprintf('不一致样本数              = %d / %d\n', num_mismatch, length(golden_y));

if max_abs_err == 0
    pass_all = 1;
    fprintf('结论：RTL 与 MATLAB fixed-point golden 完全一致。\n');
else
    pass_all = 0;
    fprintf('结论：RTL 与 MATLAB fixed-point golden 尚未完全一致，请检查延迟、相位或舍入模型。\n');
end

%% 5）导出 summary 与对比图
%=============================================================

fid = fopen(summary_path, 'w');
fprintf(fid, 'All-2x RTL impulse comparison summary\n');
fprintf(fid, '=====================================\n');
fprintf(fid, 'RTL CSV samples       = %d\n', length(rtl_y));
fprintf(fid, 'Golden samples        = %d\n', length(golden_y));
fprintf(fid, 'Best shift            = %d\n', best_shift);
fprintf(fid, 'Max abs error LSB     = %.0f\n', max_abs_err);
fprintf(fid, 'RMS error LSB         = %.6f\n', rms_err);
fprintf(fid, 'Mismatch samples      = %d / %d\n', num_mismatch, length(golden_y));
fprintf(fid, 'Pass all              = %d\n', pass_all);
fclose(fid);

fig = figure('Color', 'w', ...
             'Visible', 'off', ...
             'Name', 'All-2x RTL impulse compare', ...
             'Units', 'pixels', ...
             'Position', [80 80 1280 720]);

subplot(2,1,1);
plot(golden_y, 'Color', [0.25 0.13 0.47], 'LineWidth', 1.3); hold on;
plot(rtl_aligned, '--', 'Color', [0.16 0.34 0.56], 'LineWidth', 1.0);
grid on; box on;
xlabel('输出样本序号');
ylabel('幅度 / LSB');
title(sprintf('全 2x 脉冲响应对齐结果，shift = %d', best_shift));
legend('MATLAB golden', 'RTL aligned', 'Location', 'best');

subplot(2,1,2);
plot(err, 'Color', [0.08 0.63 0.50], 'LineWidth', 1.0);
grid on; box on;
xlabel('输出样本序号');
ylabel('误差 / LSB');
title(sprintf('误差曲线：max = %.0f LSB, rms = %.6f LSB', max_abs_err, rms_err));

try
    print(fig, png_path, '-dpng', '-r160');
catch ME
    warning('对拍已完成，但 PNG 导出失败：%s', ME.message);
end

close(fig);

fprintf('\n已导出：\n');
fprintf('1) %s\n', summary_path);
fprintf('2) %s\n\n', png_path);


%=============================================================
% 本地函数：RTL 等价四舍五入 + 24bit 饱和
% ============================================================
% 6）局部函数模块：round_sat_to_int
% 功能说明：执行与 RTL 一致的定点量化、舍入、移位和饱和处理。
function y = round_sat_to_int(x_full, frac_w, out_w)

    scale = 2^frac_w;
    bias_pos = 2^(frac_w - 1);
    bias_neg = bias_pos - 1;

    x_round = x_full;
    idx_pos = (x_full >= 0);
    x_round(idx_pos) = x_full(idx_pos) + bias_pos;
    x_round(~idx_pos) = x_full(~idx_pos) + bias_neg;

    y = floor(x_round / scale);

    out_max =  2^(out_w - 1) - 1;
    out_min = -2^(out_w - 1);

    y(y > out_max) = out_max;
    y(y < out_min) = out_min;
end

