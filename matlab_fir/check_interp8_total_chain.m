clc; clear; close all;

%% ============================================================
% check_interp8_total_chain.m
%
% 作用：
% 1) 读取已经设计完成的 4x 公共 FIR 系数（155 tap）
% 2) 读取已经设计完成的 2x 公共 FIR 系数（约 11 tap）
% 3) 计算总链路：
%       4x + 2x = 8x
%    的整体冲激响应
% 4) 检查整体 8x 链路是否满足赛题核心指标
%
% 最终检查模式：
%   - 44.1k -> 352.8k
%   - 48k   -> 384k
%
% 赛题核心指标：
%   - 通带：10 Hz ~ 20 kHz
%   - 通带纹波：<= ±0.05 dB
%   - 阻带衰减：>= 70 dB
%   - 严格线性相位
%
% 说明：
% 这里先检查“线性级联后的总频响”。
% 对于你后续要实现的 RTL 两级级联结构，这是最关键的系统级验收。
%% ============================================================

%% 1) 读取 4x 与 2x 系数（Q16 定点整数）
coeff4_int = readmatrix('fir_coeff_decimal_v2.txt');
coeff2_int = readmatrix('interp2_coeff_decimal.txt');

coeff4_int = coeff4_int(:).';   % 转成行向量
coeff2_int = coeff2_int(:).';

FRAC_W = 16;

% 转成浮点系数，用于频响分析
b4 = coeff4_int / 2^FRAC_W;
b2 = coeff2_int / 2^FRAC_W;

fprintf('4x FIR 长度 = %d tap\n', length(b4));
fprintf('2x FIR 长度 = %d tap\n', length(b2));

%% 2) 构造总链路的冲激响应
%
% 注意：
% 不能直接用 upsample(b4,2)，因为那样会在最后多补一个 0，
% 使长度变成 310，而不是正确的 309。
%
% 对于长度为 N 的冲激响应，按 2 倍方式“在样点之间插零”，
% 正确长度应为：
%   2*(N-1) + 1
%
% 这样中心位置才能保持正确对称。

h4_up2 = zeros(1, 2*(length(b4)-1) + 1);
h4_up2(1:2:end) = b4;

% 总冲激响应 = 上采样后的 4x 冲激响应 与 2x FIR 卷积
h_total = conv(h4_up2, b2);

fprintf('上采样后的 4x 冲激响应长度 = %d tap\n', length(h4_up2));
fprintf('整体 8x 链路冲激响应长度 = %d tap\n', length(h_total));

%% 3) 先做一个基本一致性检查
sym_err = max(abs(h_total - fliplr(h_total)));
fprintf('整体冲激响应最大对称误差 = %.12g\n', sym_err);

if sym_err < 1e-12
    fprintf('结论：整体 8x 链路冲激响应严格对称。\n\n');
else
    fprintf('警告：整体冲激响应不完全对称，请检查级联逻辑。\n\n');
end

%% 4) 对两种最终输出模式分别检查
Fs_out_list = [352800, 384000];
Nfft = 131072;

result_cell = {};

for idx = 1:length(Fs_out_list)

    Fs_out = Fs_out_list(idx);   % 最终输出采样率
    Fs_in  = Fs_out / 8;         % 原始输入采样率（因为总倍率 8x）

    fprintf('====================================================\n');
    fprintf('正在检查整体 8x 模式：Fs_in = %.1f Hz, Fs_out = %.1f Hz\n', Fs_in, Fs_out);

    % ------------------------------------------------------
    % 4.1 计算整体频响
    % ------------------------------------------------------
    [H, f] = freqz(h_total, 1, Nfft, Fs_out);

    H_mag = abs(H);
    H_db  = 20 * log10(H_mag + 1e-15);

    % ------------------------------------------------------
    % 4.2 定义通带和阻带
    % ------------------------------------------------------
    f_pass_low  = 10;
    f_pass_high = 20000;

    % 对整体 8x 插值器来说，第一镜像仍然围绕原始 Fs_in 出现
    % 因此阻带起始仍取：
    %   Fs_in - 20kHz
    f_stop_begin = Fs_in - 20000;
    f_stop_end   = Fs_out / 2;

    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= f_stop_end);

    % ------------------------------------------------------
    % 4.3 通带纹波
    % ------------------------------------------------------
    pass_db = H_db(pass_idx);

    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = max(abs(pass_db - mean(pass_db)));

    fprintf('通带峰峰纹波 = %.6f dB\n', ripple_pp_db);
    fprintf('通带 ±纹波   = %.6f dB\n', ripple_pm_db);

    % ------------------------------------------------------
    % 4.4 阻带衰减
    % ------------------------------------------------------
    stop_db = H_db(stop_idx);
    stop_attn_db = -max(stop_db);

    fprintf('阻带起始频率 = %.1f Hz\n', f_stop_begin);
    fprintf('阻带衰减     = %.6f dB\n', stop_attn_db);

    % ------------------------------------------------------
    % 4.5 群延迟稳定性
    % ------------------------------------------------------
    [gd, fg] = grpdelay(h_total, 1, Nfft, Fs_out);

    gd_idx = (fg >= f_pass_low) & (fg <= f_pass_high);
    gd_pass = gd(gd_idx);

    gd_mean = mean(gd_pass);
    gd_pp   = max(gd_pass) - min(gd_pass);

    fprintf('通带内平均群延迟 = %.6f 个最终输出采样点\n', gd_mean);
    fprintf('通带内群延迟波动 = %.12f 个最终输出采样点\n', gd_pp);

    % ------------------------------------------------------
    % 4.6 按赛题要求判定
    % ------------------------------------------------------
    pass_ripple_ok = (ripple_pm_db <= 0.05);
    stop_attn_ok   = (stop_attn_db >= 70);
    linear_phase_ok = (sym_err < 1e-10) && (gd_pp < 1e-6);

    fprintf('\n指标判定：\n');
    fprintf('通带纹波 <= ±0.05 dB ：%d\n', pass_ripple_ok);
    fprintf('阻带衰减 >= 70 dB    ：%d\n', stop_attn_ok);
    fprintf('严格线性相位         ：%d\n', linear_phase_ok);

    if pass_ripple_ok && stop_attn_ok && linear_phase_ok
        fprintf('结论：整体 8x 模式满足赛题核心性能指标。\n');
    else
        fprintf('结论：整体 8x 模式未完全满足赛题核心性能指标。\n');
    end

    result_cell(end+1, :) = { ...
        Fs_in, Fs_out, ripple_pp_db, ripple_pm_db, stop_attn_db, ...
        gd_mean, gd_pp, pass_ripple_ok, stop_attn_ok, linear_phase_ok};

    % ------------------------------------------------------
    % 4.7 画图
    % ------------------------------------------------------
    figure('Name', sprintf('8x Total Chain - Fsout=%.1f Hz', Fs_out), 'Color', 'w');

    subplot(2,1,1);
    plot(f, H_db, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('幅度 / dB');
    title(sprintf('整体 8x 链路频率响应（Fs_{out}=%.1f Hz）', Fs_out));
    xline(f_pass_low,  '--r', '10 Hz');
    xline(f_pass_high, '--r', '20 kHz');
    xline(f_stop_begin,'--m', sprintf('f_{stop}=%.1f Hz', f_stop_begin));
    ylim([-160 5]);

    subplot(2,1,2);
    plot(fg, gd, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('群延迟 / 样点');
    title('整体 8x 链路群延迟响应');
    xline(f_pass_low,  '--r', '10 Hz');
    xline(f_pass_high, '--r', '20 kHz');
end

%% 5) 汇总打印
fprintf('\n\n===================== 整体 8x 汇总结果 =====================\n');
fprintf('   Fs_in      Fs_out      Ripple_pp      Ripple_±      StopAttn      GD_mean      GD_pp      Pass   Stop   Linear\n');

for i = 1:size(result_cell, 1)
    fprintf('%8.1f  %10.1f   %10.6f   %10.6f   %10.6f   %9.4f   %9.3e     %d      %d      %d\n', ...
        result_cell{i,1}, result_cell{i,2}, result_cell{i,3}, result_cell{i,4}, ...
        result_cell{i,5}, result_cell{i,6}, result_cell{i,7}, ...
        result_cell{i,8}, result_cell{i,9}, result_cell{i,10});
end

fprintf('============================================================\n');