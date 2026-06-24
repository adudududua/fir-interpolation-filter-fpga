clc; clear; close all;

%%  check_final_specs.m
%
%  作用：
%  1) 读取最终量化后的 FIR 系数
%  2) 在给定输出采样率下检查：
%     - 通带纹波
%     - 阻带衰减
%     - 线性相位（系数对称性 + 群延迟稳定性）
%  3) 输出是否满足赛题核心指标
%
%  说明：
%  - 当前你的设计是 4 倍插值，因此：
%       Fs_out = 4 * Fs_in
%  - 对于 48k 输入，对应输出 192k
%  - 对于 44.1k 输入，对应输出 176.4k
%
%  赛题核心指标：
%  - 通带：10 Hz ~ 20 kHz
%  - 通带纹波：<= ±0.05 dB
%  - 阻带衰减：>= 70 dB
%  - 相位响应：严格线性相位
%
%  注意：
%  阻带起始频率赛题截图里没有单独给出，因此这里采用
%  “补零插值后第一镜像开始位置” 作为阻带起始点：
%
%      f_stop_begin = Fs_in - 20kHz
%
%  这是插值滤波器中非常常见且合理的验收方式：
%  - 对 48k -> 192k：f_stop_begin = 48k - 20k = 28k
%  - 对 44.1k -> 176.4k：f_stop_begin = 44.1k - 20k = 24.1k

%% 1) 读取量化后的 FIR 系数
% ---------------------------
% 这里默认你之前 MATLAB 导出的系数文件名是 fir_coeff_decimal.txt
% 文件内容应为“每行一个量化后整数系数”
coeff_int = readmatrix('fir_coeff_decimal.txt');

% 如果读出来是列向量，就转成行向量，便于后续处理
coeff_int = coeff_int(:).';

% 当前系数采用 Q16 定点格式
FRAC_W = 16;

% 转成浮点系数，便于频响分析
b = coeff_int / 2^FRAC_W;

% FIR 长度
N = length(b);

fprintf('量化后 FIR 系数长度 = %d\n', N);

%% 2) 检查系数对称性
% ---------------------------
% 对于严格线性相位的奇数长度 FIR，应满足：
%   b(k) = b(N+1-k)
sym_err = max(abs(b - fliplr(b)));

fprintf('最大系数对称误差 = %.12g\n', sym_err);

if sym_err < 1e-12
    fprintf('结论：系数严格对称，可判定为线性相位 FIR。\n\n');
else
    fprintf('警告：系数不完全对称，需检查导出或量化过程。\n\n');
end

%% 3) 定义待检查的两种输出采样率
% ---------------------------
Fs_out_list = [192000, 176400];

% FFT 点数取大一些，频率分辨率更高
Nfft = 131072;

% 用于保存结果，便于最后汇总打印
result_cell = {};


%% 4) 对每种输出采样率分别做指标检查
% ---------------------------
for idx = 1:length(Fs_out_list)

    Fs_out = Fs_out_list(idx);   % 输出采样率
    Fs_in  = Fs_out / 4;         % 4 倍插值下的输入采样率

    fprintf('====================================================\n');
    fprintf('正在检查模式：Fs_in = %.1f Hz, Fs_out = %.1f Hz\n', Fs_in, Fs_out);

    % ------------------------------------------------------
    % 4.1 计算频响
    % ------------------------------------------------------
    [H, f] = freqz(b, 1, Nfft, Fs_out);

    % 幅度（线性值）
    H_mag = abs(H);

    % 幅度（dB）
    H_db = 20 * log10(H_mag + 1e-15);

    % ------------------------------------------------------
    % 4.2 定义通带与阻带
    % ------------------------------------------------------
    % 通带：10 Hz ~ 20 kHz
    f_pass_low  = 10;
    f_pass_high = 20000;

    % 阻带起始：插值后第一镜像开始位置
    % 镜像中心位于 Fs_in，原始基带最高到 20kHz，
    % 因此第一镜像从 Fs_in - 20kHz 开始出现
    f_stop_begin = Fs_in - 20000;

    % 只分析到奈奎斯特频率
    f_stop_end = Fs_out / 2;

    % 构造索引
    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= f_stop_end);

    % ------------------------------------------------------
    % 4.3 计算通带纹波
    % ------------------------------------------------------
    % 通带纹波的定义有多种。
    % 这里给出两种常见结果：
    %
    % (1) 通带峰峰值 ripple_pp_db
    %     = max(H_db) - min(H_db)
    %
    % (2) 相对通带平均值的 ±纹波 ripple_pm_db
    %     = max(|H_db - mean(H_db)|)
    %
    pass_db = H_db(pass_idx);

    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = max(abs(pass_db - mean(pass_db)));

    fprintf('通带峰峰纹波 = %.6f dB\n', ripple_pp_db);
    fprintf('通带 ±纹波   = %.6f dB\n', ripple_pm_db);

    % ------------------------------------------------------
    % 4.4 计算阻带衰减
    % ------------------------------------------------------
    % 阻带衰减取阻带内“最大泄漏峰值”的相反数
    %
    % 例如阻带最高点是 -82 dB，则衰减为 82 dB
    stop_db = H_db(stop_idx);
    stop_attn_db = -max(stop_db);

    fprintf('阻带起始频率 = %.1f Hz\n', f_stop_begin);
    fprintf('阻带衰减     = %.6f dB\n', stop_attn_db);

    % ------------------------------------------------------
    % 4.5 检查群延迟稳定性（线性相位的另一种数值证据）
    % ------------------------------------------------------
    % 对称 FIR 理论群延迟应为：
    %   (N - 1) / 2
    [gd, fg] = grpdelay(b, 1, Nfft, Fs_out);

    % 只在通带内检查群延迟波动
    gd_idx = (fg >= f_pass_low) & (fg <= f_pass_high);
    gd_pass = gd(gd_idx);

    gd_mean = mean(gd_pass);
    gd_pp   = max(gd_pass) - min(gd_pass);

    fprintf('通带内平均群延迟 = %.6f 个采样点\n', gd_mean);
    fprintf('通带内群延迟波动 = %.12f 个采样点\n', gd_pp);

    % ------------------------------------------------------
    % 4.6 按赛题要求进行判定
    % ------------------------------------------------------
    pass_ripple_ok = (ripple_pm_db <= 0.05);
    stop_attn_ok   = (stop_attn_db >= 70);
    linear_phase_ok = (sym_err < 1e-12) && (gd_pp < 1e-6);

    fprintf('\n指标判定：\n');
    fprintf('通带纹波 <= ±0.05 dB ：%d\n', pass_ripple_ok);
    fprintf('阻带衰减 >= 70 dB    ：%d\n', stop_attn_ok);
    fprintf('严格线性相位         ：%d\n', linear_phase_ok);

    if pass_ripple_ok && stop_attn_ok && linear_phase_ok
        fprintf('结论：该模式满足赛题核心性能指标。\n');
    else
        fprintf('结论：该模式未完全满足赛题核心性能指标。\n');
    end

    % ------------------------------------------------------
    % 4.7 保存结果，便于最后汇总
    % ------------------------------------------------------
    result_cell(end+1, :) = { ...
        Fs_in, Fs_out, ripple_pp_db, ripple_pm_db, stop_attn_db, ...
        gd_mean, gd_pp, pass_ripple_ok, stop_attn_ok, linear_phase_ok};

    % ------------------------------------------------------
    % 4.8 画图，便于写报告
    % ------------------------------------------------------
    figure('Name', sprintf('Spec Check - Fsout=%.1f Hz', Fs_out), 'Color', 'w');

    subplot(2,1,1);
    plot(f, H_db, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('幅度 / dB');
    title(sprintf('量化后 FIR 频率响应（Fs_{out}=%.1f Hz）', Fs_out));
    xline(f_pass_low,  '--r', '10 Hz');
    xline(f_pass_high, '--r', '20 kHz');
    xline(f_stop_begin,'--m', sprintf('f_{stop}=%.1f Hz', f_stop_begin));
    ylim([-160 5]);

    subplot(2,1,2);
    plot(fg, gd, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('群延迟 / 样点');
    title('群延迟响应');
    xline(f_pass_low,  '--r', '10 Hz');
    xline(f_pass_high, '--r', '20 kHz');
end

%% 5) 汇总打印
% ---------------------------
fprintf('\n\n===================== 汇总结果 =====================\n');
fprintf('   Fs_in      Fs_out      Ripple_pp      Ripple_±      StopAttn      GD_mean      GD_pp      Pass   Stop   Linear\n');

for i = 1:size(result_cell, 1)
    fprintf('%8.1f  %10.1f   %10.6f   %10.6f   %10.6f   %9.4f   %9.3e     %d      %d      %d\n', ...
        result_cell{i,1}, result_cell{i,2}, result_cell{i,3}, result_cell{i,4}, ...
        result_cell{i,5}, result_cell{i,6}, result_cell{i,7}, ...
        result_cell{i,8}, result_cell{i,9}, result_cell{i,10});
end

fprintf('====================================================\n');