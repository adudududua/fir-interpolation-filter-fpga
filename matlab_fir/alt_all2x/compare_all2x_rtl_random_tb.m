clc; clear; close all;

%=============================================================
% 文件名       : compare_all2x_rtl_random_tb.m
% 脚本名       : compare_all2x_rtl_random_tb
% 功能简述     : 读取全 2x RTL 随机 PCM 仿真输出，并与 MATLAB 导出的
%                24bit bit-true golden 向量进行逐点对拍。
%
%                输出文件：
%                  all2x_rtl_random_compare_summary.txt
%                  all2x_rtl_random_compare.png
%
% 当前默认配置：
%                  输入样点数：128 点
%                  golden 点数：22907 点
%                  通过条件  ：最大误差 0 LSB、不一致点数 0
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增随机 PCM RTL/golden 对拍脚本。
%=============================================================

%% 1）路径与数据读取
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
rtl_csv = fullfile(tempdir, 'codex_vivado_fir_interpolation', ...
                   'interp128_all2x_random_tb_output.csv');
golden_mem = fullfile(script_dir, 'rtl_export', ...
                      'all2x_random_golden_24bit.mem');

if ~exist(rtl_csv, 'file')
    error('未找到 RTL 随机仿真输出：%s', rtl_csv);
end

if ~exist(golden_mem, 'file')
    error('未找到 MATLAB golden 文件：%s', golden_mem);
end

rtl_tbl = readtable(rtl_csv);
rtl_y = double(rtl_tbl.y_out(:)).';
golden_y = read_signed_hex_mem(golden_mem, 24);

%% 2）搜索延迟并逐点比较
%=============================================================

search_max = min(numel(rtl_y) - numel(golden_y), 20000);
if search_max < 0
    error('RTL 输出长度短于 golden，无法完成对齐。');
end

best_shift = 0;
best_max_abs_error = inf;
best_rms_error = inf;

for shift = 0:search_max
    rtl_seg = rtl_y(shift+1 : shift+numel(golden_y));
    error_seg = rtl_seg - golden_y;
    max_abs_error = max(abs(error_seg));
    rms_error = sqrt(mean(error_seg.^2));

    if max_abs_error < best_max_abs_error || ...
       (max_abs_error == best_max_abs_error && rms_error < best_rms_error)
        best_shift = shift;
        best_max_abs_error = max_abs_error;
        best_rms_error = rms_error;
    end
end

rtl_aligned = rtl_y(best_shift+1 : best_shift+numel(golden_y));
error_value = rtl_aligned - golden_y;
max_abs_error = max(abs(error_value));
rms_error = sqrt(mean(error_value.^2));
num_mismatch = nnz(error_value);
pass_all = (max_abs_error == 0) && (num_mismatch == 0);

%% 3）导出结果
%=============================================================

summary_path = fullfile(script_dir, 'all2x_rtl_random_compare_summary.txt');
png_path = fullfile(script_dir, 'all2x_rtl_random_compare.png');

fid = fopen(summary_path, 'w');
fprintf(fid, 'All-2x RTL random PCM comparison summary\n');
fprintf(fid, '========================================\n');
fprintf(fid, 'RTL CSV samples       = %d\n', numel(rtl_y));
fprintf(fid, 'Golden samples        = %d\n', numel(golden_y));
fprintf(fid, 'Best shift            = %d\n', best_shift);
fprintf(fid, 'Max abs error LSB     = %.0f\n', max_abs_error);
fprintf(fid, 'RMS error LSB         = %.6f\n', rms_error);
fprintf(fid, 'Mismatch samples      = %d / %d\n', num_mismatch, numel(golden_y));
fprintf(fid, 'Pass all              = %d\n', pass_all);
fclose(fid);

fig = figure('Color', 'w', 'Visible', 'off', ...
             'Name', 'All-2x RTL random PCM compare', ...
             'Units', 'pixels', 'Position', [80 80 1280 720]);

subplot(2,1,1);
plot(golden_y, 'Color', [0.25 0.13 0.47], 'LineWidth', 1.1); hold on;
plot(rtl_aligned, '--', 'Color', [0.16 0.34 0.56], 'LineWidth', 0.9);
grid on; box on;
xlabel('输出样本序号');
ylabel('幅度 / LSB');
title(sprintf('随机 PCM 对齐结果，shift = %d', best_shift));
legend('MATLAB golden', 'RTL aligned', 'Location', 'best');

subplot(2,1,2);
plot(error_value, 'Color', [0.08 0.63 0.50], 'LineWidth', 1.0);
grid on; box on;
xlabel('输出样本序号');
ylabel('误差 / LSB');
title(sprintf('误差：max = %.0f LSB，mismatch = %d', ...
              max_abs_error, num_mismatch));

try
    print(fig, png_path, '-dpng', '-r160');
catch ME
    warning('随机对拍完成，但 PNG 导出失败：%s', ME.message);
end
close(fig);

fprintf('====================================================\n');
fprintf('全 2x RTL 随机 PCM 对拍结果\n');
fprintf('最佳延迟      = %d\n', best_shift);
fprintf('最大绝对误差  = %.0f LSB\n', max_abs_error);
fprintf('不一致样本数  = %d / %d\n', num_mismatch, numel(golden_y));
fprintf('全部通过判定  = %d\n', pass_all);
fprintf('====================================================\n');

if ~pass_all
    error('随机 PCM RTL 与 MATLAB golden 未完全一致。');
end


%=============================================================
% 本地函数：读取二进制补码十六进制 .mem
% ============================================================
% 4）局部函数模块：read_signed_hex_mem
% 功能说明：读取外部配置、RTL结果或数据文件，并转换为主流程使用的统一数据格式。
function data = read_signed_hex_mem(filename, data_w)
    fid = fopen(filename, 'r');
    raw = textscan(fid, '%s');
    fclose(fid);

    unsigned_value = hex2dec(raw{1});
    data = double(unsigned_value(:).');
    sign_threshold = 2^(data_w - 1);
    modulus = 2^data_w;
    data(data >= sign_threshold) = data(data >= sign_threshold) - modulus;
end
