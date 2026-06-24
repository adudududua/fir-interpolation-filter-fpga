clc; clear; close all;

%% ============================================================
% gen_golden_output_interp128_ce_24bit.m
%
% 作用：
% 1) 读取 input_24bit.txt
% 2) 读取 4x / 2x 已量化系数
% 3) 按 RTL 的“逐级插值 + 每级 Q16->24bit 舍入饱和”方式，
%    构造 128x 的 MATLAB 黄金输出
% 4) 导出 golden_output_interp128_ce_24bit.txt
%
% 说明：
% - 这里不是用总冲激响应 h_total 直接卷积
% - 而是严格按 RTL 的级联结构逐级计算
% - 每一级后都执行与 Verilog round_sat_q16_to24 一致的舍入饱和
%% ============================================================

FRAC_W = 16;

%% 1) 读取输入与系数
x0 = readmatrix('input_24bit.txt');
x0 = x0(~isnan(x0));
x0 = x0(:);   % 列向量，24bit整数输入

coeff4_int = readmatrix('fir_coeff_decimal_v2.txt');
coeff2_int = readmatrix('interp2_coeff_decimal.txt');

coeff4_int = coeff4_int(~isnan(coeff4_int));
coeff2_int = coeff2_int(~isnan(coeff2_int));

coeff4_int = coeff4_int(:);   % 列向量
coeff2_int = coeff2_int(:);   % 列向量

fprintf('输入样本数 = %d\n', length(x0));
fprintf('4x FIR tap = %d\n', length(coeff4_int));
fprintf('2x FIR tap = %d\n', length(coeff2_int));

%% 2) 定义“一级插值 + FIR + Q16转24bit”的函数
stage_interp = @(xin_int, coeff_int, L) stage_interp_quantized(xin_int, coeff_int, L);

%% 3) 逐级构造 128x 黄金输出
% Stage1: 4x
y4  = stage_interp(x0,  coeff4_int, 4);
fprintf('Stage1 (4x)   输出长度 = %d\n', length(y4));

% Stage2~Stage6: 五个 2x
y8   = stage_interp(y4,   coeff2_int, 2);
fprintf('Stage2 (8x)   输出长度 = %d\n', length(y8));

y16  = stage_interp(y8,   coeff2_int, 2);
fprintf('Stage3 (16x)  输出长度 = %d\n', length(y16));

y32  = stage_interp(y16,  coeff2_int, 2);
fprintf('Stage4 (32x)  输出长度 = %d\n', length(y32));

y64  = stage_interp(y32,  coeff2_int, 2);
fprintf('Stage5 (64x)  输出长度 = %d\n', length(y64));

y128 = stage_interp(y64,  coeff2_int, 2);
fprintf('Stage6 (128x) 输出长度 = %d\n', length(y128));

%% 4) 写出黄金输出
writematrix(y128, 'golden_output_interp128_ce_24bit.txt', 'Delimiter', 'tab');

fprintf('\n已生成文件：golden_output_interp128_ce_24bit.txt\n');

%% ============================================================
% 局部函数：一级插值 + FIR + 舍入饱和
%% ============================================================
function y_int = stage_interp_quantized(x_int, coeff_int, L)

    FRAC_W = 16;

    %--------------------------------------------------------
    % 1) 补零插值
    %
    % 采用与 RTL 对应的“流式”思路：
    %   每个输入样本扩展为 L 个输出时刻
    %   第1个位置放真实输入，后面 L-1 个位置补零
    %--------------------------------------------------------
    N = length(x_int);
    x_up = zeros(N*L, 1);

    for n = 1:N
        x_up((n-1)*L + 1) = x_int(n);
    end

    %--------------------------------------------------------
    % 2) 用“已量化整数系数”做 FIR
    %
    % coeff_int 是 Q16 整数
    % x_up      是 24bit 整数
    %
    % 所以 filter 后得到的是“Q16域下的全精度结果”
    %--------------------------------------------------------
    y_full_q16 = filter(double(coeff_int(:).'), 1, double(x_up));

    %--------------------------------------------------------
    % 3) Q16 -> 24bit，严格仿照 Verilog 的 round_sat_q16_to24
    %--------------------------------------------------------
    y_int = round_sat_q16_to24_matlab(y_full_q16, FRAC_W);
end

function y24 = round_sat_q16_to24_matlab(din_full, FRAC_W)

    OUT_MAX =  2^(24-1) - 1;   %  8388607
    OUT_MIN = -2^(24-1);       % -8388608

    din_full = double(din_full(:));
    y24 = zeros(size(din_full));

    for k = 1:length(din_full)
        x = din_full(k);

        % 与 Verilog 一致：
        % 正数加 2^(FRAC_W-1)
        % 负数加 2^(FRAC_W-1)-1
        if x >= 0
            xr = x + 2^(FRAC_W-1);
        else
            xr = x + (2^(FRAC_W-1) - 1);
        end

        % 算术右移 FRAC_W 位
        xs = floor(xr / 2^FRAC_W);

        % 饱和到 24bit
        if xs > OUT_MAX
            xs = OUT_MAX;
        elseif xs < OUT_MIN
            xs = OUT_MIN;
        end

        y24(k) = xs;
    end

    y24 = int32(y24);
end