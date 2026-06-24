clc; clear; close all;

%% ============================================================
% gen_golden_output_interp8_ce.m
%
% 作用：
% 按照 RTL 的真实 8x 两级链路生成黄金输出：
%
%   原始输入
%      -> 4x补零
%      -> 4x FIR（Q16）
%      -> 舍入/截位/饱和到24位
%      -> 2x补零
%      -> 2x FIR（Q16）
%      -> 再次舍入/截位/饱和到24位
%
% 输出文件：
%   golden_output_interp8_ce_24bit.txt
%
% 说明：
% 这版脚本不再把 4x+2x 合并成一个总 FIR，
% 而是严格模拟 RTL 的“分级 + 中间量化”链路。
%% ============================================================

%% 1) 读取输入
x_in = readmatrix('input_24bit.txt');
x_in = x_in(:);

fprintf('输入样本数 = %d\n', length(x_in));

%% 2) 读取 4x / 2x 系数（Q16 整数）
coeff4_int = readmatrix('fir_coeff_decimal_v2.txt');
coeff2_int = readmatrix('interp2_coeff_decimal.txt');

coeff4_int = coeff4_int(:);
coeff2_int = coeff2_int(:);

fprintf('4x FIR 长度 = %d tap\n', length(coeff4_int));
fprintf('2x FIR 长度 = %d tap\n', length(coeff2_int));

FRAC_W = 16;
OUT_W  = 24;

%% ============================================================
% 局部函数：Q16 -> 24位（按 RTL 风格舍入/饱和）
%% ============================================================
q16_to_24 = @(din) local_q16_to_24(din, FRAC_W, OUT_W);

%% 3) 第一级：4x 插值
%
% 原始输入 -> 4倍补零 -> 4x FIR(Q16) -> 舍入到24位
x_up4 = zeros(length(x_in)*4, 1);
x_up4(1:4:end) = x_in;

fprintf('4倍补零后样本数 = %d\n', length(x_up4));

% 第一级 FIR 输出（Q16大位宽）
y4_full_q16 = filter(coeff4_int, 1, x_up4);

% 第一级输出量化成24位（模拟 RTL round_sat_q16_to24）
y4_24 = q16_to_24(y4_full_q16);

%% 4) 第二级：2x 插值
%
% 第一级24位输出 -> 2倍补零 -> 2x FIR(Q16) -> 再舍入到24位
x_up2 = zeros(length(y4_24)*2, 1);
x_up2(1:2:end) = y4_24;

fprintf('第二级 2倍补零后样本数 = %d\n', length(x_up2));

% 第二级 FIR 输出（Q16大位宽）
y8_full_q16 = filter(coeff2_int, 1, x_up2);

% 第二级输出量化成24位（最终黄金输出）
y8_24 = q16_to_24(y8_full_q16);

%% 5) 导出黄金输出
writematrix(y8_24, 'golden_output_interp8_ce_24bit.txt', 'Delimiter', 'tab');

fprintf('已生成文件：golden_output_interp8_ce_24bit.txt\n');
fprintf('黄金输出长度 = %d\n', length(y8_24));

%% 6) 简单画图
figure('Color', 'w');
plot(y8_24);
grid on;
xlabel('样点');
ylabel('幅值');
title('8x CE 链路黄金输出（分级+中间量化）');

%% ============================================================
% 局部函数定义
%% ============================================================
function dout = local_q16_to_24(din, FRAC_W, OUT_W)

    din = din(:);
    dout = zeros(size(din));

    round_bias = 2^(FRAC_W-1);
    max_val = 2^(OUT_W-1) - 1;
    min_val = -2^(OUT_W-1);

    for n = 1:length(din)
        val = din(n);

        % 与前面 4x 脚本保持一致的舍入方式
        if val >= 0
            val_shift = floor((val + round_bias) / 2^FRAC_W);
        else
            val_shift = ceil((val - round_bias) / 2^FRAC_W);
        end

        % 24位饱和
        if val_shift > max_val
            val_shift = max_val;
        elseif val_shift < min_val
            val_shift = min_val;
        end

        dout(n) = val_shift;
    end
end