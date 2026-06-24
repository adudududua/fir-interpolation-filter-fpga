clc;
clear;

%% 1. 读取之前已经保存好的输入与系数
% =========================================================
x_int24 = readmatrix('input_24bit.txt');         % 原始 24 位输入整数
h_q     = readmatrix('fir_coeff_decimal.txt');   % Q16 定点 FIR 系数整数

L = 4;               % 4 倍插值
FRAC_W = 16;         % 系数小数位数

%% 2. 构造 RTL 对应的补零输入序列
%
% 注意：
% RTL 里 fir_core 接收到的是补零后的序列
%=========================================================
x_up_int = upsample(double(x_int24), L);

%% 3. 计算 FIR 全精度输出（对应 RTL 的 y_out_full）
%
% 卷积长度 = length(x_up_int) + length(h_q) - 1
%=========================================================
y_full_mat = conv(x_up_int, double(h_q));

%% 4. 按 RTL 的"舍入 + 饱和”规则生成 24 位输出
%=========================================================
round_bias_pos = 2^(FRAC_W-1);      % 32768
round_bias_neg = 2^(FRAC_W-1) - 1;  % 32767

y_round = zeros(size(y_full_mat));

pos_idx = (y_full_mat >= 0);
neg_idx = ~pos_idx;

% 正数：加 32768 后再除以 2^16 向下取整
y_round(pos_idx) = floor((y_full_mat(pos_idx) + round_bias_pos) / 2^FRAC_W);

% 负数：加 32767 后再除以 2^16 向下取整
y_round(neg_idx) = floor((y_full_mat(neg_idx) + round_bias_neg) / 2^FRAC_W);

% 24 位饱和范围
qmax =  2^23 - 1;
qmin = -2^23;

y_gold = y_round;
y_gold(y_gold > qmax) = qmax;
y_gold(y_gold < qmin) = qmin;

%% 5. 读取 RTL 输出
%=========================================================
rtl_out = readmatrix('rtl_output_symm_24bit.txt');

%% 6. 对齐长度并比较
%=========================================================
N = min(length(y_gold), length(rtl_out));

y_gold_cmp = y_gold(1:N);
rtl_out_cmp = rtl_out(1:N);

err = rtl_out_cmp - y_gold_cmp;

fprintf('黄金输出长度 = %d\n', length(y_gold));
fprintf('RTL输出长度  = %d\n', length(rtl_out));
fprintf('比较长度     = %d\n', N);
fprintf('最大绝对误差 = %d\n', max(abs(err)));

% 找第一个不一致的位置
idx_mismatch = find(err ~= 0, 1);

if isempty(idx_mismatch)
    disp('RTL 与 MATLAB 黄金输出完全一致。');
else
    fprintf('第一个不一致的位置 = %d\n', idx_mismatch);
    fprintf('MATLAB = %d, RTL = %d, err = %d\n', ...
        y_gold_cmp(idx_mismatch), rtl_out_cmp(idx_mismatch), err(idx_mismatch));
end

%% 7. 画图看看前 300 个点
%=========================================================
figure;
plot(y_gold_cmp(1:min(300,N)), 'b', 'LineWidth', 1.2); hold on;
plot(rtl_out_cmp(1:min(300,N)), '--r', 'LineWidth', 1.0);
grid on;
xlabel('样本点');
ylabel('幅值');
title('MATLAB 黄金输出 与 RTL 输出 对比');
legend('MATLAB', 'RTL');