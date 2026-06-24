clc; clear; close all;

golden_out = readmatrix('golden_output_symm_v2_24bit.txt');
rtl_out    = readmatrix('rtl_output_symm_v2_24bit.txt');

golden_out = golden_out(:);
rtl_out    = rtl_out(:);

cmp_len = min(length(golden_out), length(rtl_out));

golden_cmp = golden_out(1:cmp_len);
rtl_cmp    = rtl_out(1:cmp_len);

err = rtl_cmp - golden_cmp;
max_abs_err = max(abs(err));

fprintf('黄金输出长度 = %d\n', length(golden_out));
fprintf('RTL输出长度  = %d\n', length(rtl_out));
fprintf('比较长度     = %d\n', cmp_len);
fprintf('最大绝对误差 = %d\n', max_abs_err);

if max_abs_err == 0
    fprintf('RTL 与 MATLAB 黄金输出完全一致。\n');
else
    fprintf('RTL 与 MATLAB 黄金输出存在差异。\n');
end

figure('Color', 'w');
plot(golden_cmp, 'b'); hold on;
plot(rtl_cmp, 'r--');
grid on;
xlabel('样点');
ylabel('幅值');
legend('MATLAB黄金输出', 'RTL输出');
title('最终版 155 tap 公共 FIR：MATLAB 与 RTL 对比');

figure('Color', 'w');
plot(err, 'k');
grid on;
xlabel('样点');
ylabel('误差');
title(sprintf('最终版误差曲线，最大绝对误差 = %d', max_abs_err));