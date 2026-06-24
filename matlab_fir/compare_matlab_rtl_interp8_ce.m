clc; clear; close all;

%% ============================================================
% compare_matlab_rtl_interp8_ce.m
%
% 作用：
% 1) 读取 MATLAB 黄金输出
% 2) 读取 RTL 8x CE 仿真输出
% 3) 自动搜索最佳对齐位置
% 4) 输出最大绝对误差
%% ============================================================

golden_out = readmatrix('golden_output_interp8_ce_24bit.txt');
rtl_out    = readmatrix('rtl_output_interp8_ce_24bit.txt');

golden_out = golden_out(:);
rtl_out    = rtl_out(:);

fprintf('黄金输出长度 = %d\n', length(golden_out));
fprintf('RTL输出长度  = %d\n', length(rtl_out));

% ------------------------------------------------------------
% 在 RTL 输出中搜索黄金序列的最佳起点
% 因为 RTL 文件里包含：
% - 前导零
% - 有效输出
% - 多跑出来的尾部零
%
% 所以需要自动找一个 offset，使两者误差最小
% ------------------------------------------------------------
max_search = min(2000, length(rtl_out) - length(golden_out));

best_offset = -1;
best_max_err = inf;

for offset = 0:max_search
    rtl_seg = rtl_out(offset+1 : offset+length(golden_out));
    err = rtl_seg - golden_out;
    max_err = max(abs(err));

    if max_err < best_max_err
        best_max_err = max_err;
        best_offset = offset;
    end
end

fprintf('最佳对齐偏移 = %d\n', best_offset);
fprintf('最佳对齐下最大绝对误差 = %d\n', best_max_err);

rtl_best = rtl_out(best_offset+1 : best_offset+length(golden_out));
err_best = rtl_best - golden_out;

if best_max_err == 0
    fprintf('RTL 与 MATLAB 黄金输出完全一致。\n');
else
    fprintf('RTL 与 MATLAB 黄金输出存在差异。\n');
end

%% 画图
figure('Color', 'w');
plot(golden_out, 'b'); hold on;
plot(rtl_best, 'r--');
grid on;
xlabel('样点');
ylabel('幅值');
legend('MATLAB黄金输出', 'RTL对齐输出');
title(sprintf('8x CE 输出对比（offset=%d）', best_offset));

figure('Color', 'w');
plot(err_best, 'k');
grid on;
xlabel('样点');
ylabel('误差');
title(sprintf('8x CE 误差曲线，最大绝对误差 = %d', best_max_err));