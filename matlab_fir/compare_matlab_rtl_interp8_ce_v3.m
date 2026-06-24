clc; clear; close all;

%====================================================
% compare_matlab_rtl_interp8_ce_v3.m
%
% 作用：
% 1) 读取 MATLAB 黄金输出
% 2) 读取 RTL 文件输出
% 3) 自动做有限范围对齐搜索
% 4) 比较重叠段误差
%====================================================

% ---------- 1) 读文件 ----------
gold = readmatrix('golden_output_interp8_ce_24bit.txt');
rtl  = readmatrix('rtl_output_interp8_ce_24bit.txt');

gold = gold(:);
rtl  = rtl(:);

fprintf('黄金输出长度 = %d\n', length(gold));
fprintf('RTL输出长度  = %d\n', length(rtl));

% ---------- 2) 去掉空值 ----------
gold = gold(~isnan(gold));
rtl  = rtl(~isnan(rtl));

% ---------- 3) 自动搜索最佳对齐 ----------
max_search = min(2000, max(0, length(rtl)-1));  % 最多搜索前2000点偏移
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

% ---------- 4) 给出结论 ----------
if best_err == 0
    fprintf('RTL 与 MATLAB 黄金输出完全一致。\n');
else
    fprintf('RTL 与 MATLAB 黄金输出存在差异。\n');
end

% ---------- 5) 画误差图 ----------
err_seq = gold(1:best_len) - rtl(best_shift+1:best_shift+best_len);

figure('Color','w');
plot(err_seq, 'LineWidth', 1.0); grid on;
xlabel('样本点');
ylabel('误差');
title(sprintf('8x RTL 与 MATLAB 误差波形（shift=%d, maxerr=%d）', best_shift, best_err));