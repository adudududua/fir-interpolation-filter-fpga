clc; clear; close all;

%% ============================================================
% compare_matlab_rtl_interp128_ce.m
%
% 作用：
% 1) 读取 128x MATLAB 黄金输出
% 2) 读取 128x RTL 文件输出
% 3) 自动搜索最佳对齐偏移
% 4) 比较重叠部分最大绝对误差
%% ============================================================

gold = readmatrix('golden_output_interp128_ce_24bit.txt');
rtl  = readmatrix('rtl_output_interp128_ce_24bit.txt');

gold = gold(~isnan(gold));
rtl  = rtl(~isnan(rtl));

gold = double(gold(:));
rtl  = double(rtl(:));

fprintf('黄金输出长度 = %d\n', length(gold));
fprintf('RTL输出长度  = %d\n', length(rtl));

%------------------------------------------------------------
% 搜索最佳对齐偏移
%
% 128x 链路级数更多，寄存器更多，所以搜索范围放大一些
%------------------------------------------------------------
max_search = min(5000, max(0, length(rtl)-1));

best_shift = 0;
best_err   = inf;
best_len   = 0;

for shift = 0:max_search
    L = min(length(gold), length(rtl)-shift);
    if L <= 0
        continue;
    end

    err = max(abs(gold(1:L) - rtl(shift+1:shift+L)));

    if err < best_err
        best_err   = err;
        best_shift = shift;
        best_len   = L;
    end
end

fprintf('最佳对齐偏移 = %d\n', best_shift);
fprintf('比较长度     = %d\n', best_len);
fprintf('最佳对齐下最大绝对误差 = %d\n', best_err);

if best_err == 0
    fprintf('RTL 与 MATLAB 黄金输出完全一致。\n');
else
    fprintf('RTL 与 MATLAB 黄金输出存在差异。\n');
end

%------------------------------------------------------------
% 误差波形
%------------------------------------------------------------
err_seq = gold(1:best_len) - rtl(best_shift+1:best_shift+best_len);

figure('Color','w');
plot(err_seq, 'LineWidth', 1.0); grid on;
xlabel('样本点');
ylabel('误差');
title(sprintf('128x RTL 与 MATLAB 误差波形（shift=%d, maxerr=%d）', best_shift, best_err));