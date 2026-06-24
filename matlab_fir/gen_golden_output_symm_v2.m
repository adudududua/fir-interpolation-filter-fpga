clc; clear; close all;

%% ============================================================
% gen_golden_output_symm_v2.m
%
% 作用：
% 1) 读取 input_24bit.txt
% 2) 读取最终版 155 tap 系数 fir_coeff_decimal_v2.txt
% 3) 按 4 倍插值方式补零
% 4) 做 FIR 滤波
% 5) 生成最终版黄金输出文件：
%       golden_output_symm_v2_24bit.txt
%
% 说明：
% - 系数文件是 Q16 定点整数
% - FIR 输出先保持 Q16 形式
% - 再按 RTL 一样的方式舍入并缩放到 24 位
%% ============================================================

%% 1) 读取输入样本
x_in = readmatrix('input_24bit.txt');
x_in = x_in(:);   % 列向量

fprintf('输入样本数 = %d\n', length(x_in));

%% 2) 读取最终版 155 tap 系数（Q16 定点整数）
coeff_int = readmatrix('fir_coeff_decimal_v2.txt');
coeff_int = coeff_int(:);   % 列向量

fprintf('系数长度 = %d\n', length(coeff_int));

%% 3) 4 倍补零
L = 4;   % 4 倍插值
x_up = zeros(length(x_in) * L, 1);
x_up(1:L:end) = x_in;

fprintf('补零后样本数 = %d\n', length(x_up));

%% 4) FIR 滤波（保持 Q16 大位宽）
% coeff_int 是 Q16 整数系数，所以输出也是 Q16 格式
y_full_q16 = filter(coeff_int, 1, x_up);

%% 5) 按 RTL 方式做“舍入 + 右移 16 位 + 24 位饱和”
FRAC_W = 16;
OUT_W  = 24;

% 四舍五入偏置
round_bias = 2^(FRAC_W-1);

y_round = zeros(size(y_full_q16));

for n = 1:length(y_full_q16)
    val = y_full_q16(n);

    % 对正负数都采用与 RTL 一致的“加偏置后再算术右移”的思路
    if val >= 0
        val_shift = floor((val + round_bias) / 2^FRAC_W);
    else
        val_shift = ceil((val - round_bias) / 2^FRAC_W);
    end

    % 24 位有符号饱和
    max_val = 2^(OUT_W-1) - 1;
    min_val = -2^(OUT_W-1);

    if val_shift > max_val
        val_shift = max_val;
    elseif val_shift < min_val
        val_shift = min_val;
    end

    y_round(n) = val_shift;
end

%% 6) 去掉前导零段
% 对应 FIR 群延迟存在，输出前面会有过渡段
% 这里先不裁掉，保留完整输出，和 RTL 文件长度对齐更方便
golden_out = y_round;

%% 7) 导出黄金输出文件
writematrix(golden_out, 'golden_output_symm_v2_24bit.txt', 'Delimiter', 'tab');

fprintf('已生成文件：golden_output_symm_v2_24bit.txt\n');

%% 8) 简单画图
figure('Color', 'w');
plot(golden_out);
grid on;
xlabel('样点');
ylabel('幅值');
title('最终版 155 tap 公共 FIR 黄金输出');