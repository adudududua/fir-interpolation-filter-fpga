clc; clear; close all;

%% ============================================================
%  check_interp128_chain_common.m
%
%  作用：
%  1) 读取已经设计好的 4x 公共 FIR（155 tap）系数
%  2) 读取已经设计好的 2x 公共 FIR（11 tap）系数
%  3) 构造总 128x 级联系统：
%         4x + 2x + 2x + 2x + 2x + 2x
%  4) 检查两种最终模式：
%         44.1k  -> 5.6448M
%         48k    -> 6.144M
%  5) 输出总链路的：
%         - 通带纹波
%         - 阻带衰减
%         - 线性相位
%         - 群延迟
%
%  说明：
%  - 这里做的是“总系统指标验证”
%  - 不是检查某一级单独 FIR，而是检查整条 128x 链路
%% ============================================================

%% 1) 基本参数
FRAC_W = 16;                     % 系数小数位数（Q16）
f_pass_low  = 10;                % 通带下限
f_pass_high = 20000;             % 通带上限

ripple_target_db = 0.05;         % 通带 ±0.05 dB
stop_target_db   = 70;           % 阻带衰减 >= 70 dB

Nfft = 262144;                   % 频响分析点数，够细一些

%% 2) 读取 4x / 2x 系数
% ------------------------------------------------------------
% 4x 公共 FIR：
%   fir_coeff_decimal_v2.txt
%
% 2x 公共 FIR：
%   interp2_coeff_decimal.txt
%
% 注意：
% 如果你的文件名有变化，就在这里改。
% ------------------------------------------------------------
coeff4_int = readmatrix('fir_coeff_decimal_v2.txt');
coeff2_int = readmatrix('interp2_coeff_decimal.txt');

coeff4_int = coeff4_int(~isnan(coeff4_int));
coeff2_int = coeff2_int(~isnan(coeff2_int));

b4 = coeff4_int(:).' / 2^FRAC_W;   % 4x FIR，转成行向量
b2 = coeff2_int(:).' / 2^FRAC_W;   % 2x FIR，转成行向量

fprintf('4x FIR 长度 = %d tap\n', length(b4));
fprintf('2x FIR 长度 = %d tap\n', length(b2));

%% 3) 构造总 128x 链路冲激响应
% ------------------------------------------------------------
% 当前已有：
%   第1级：4x
%
% 为了到 128x，还需要 5 个 2x 级：
%   4 * 2^5 = 128
%
% 构造方法：
%   如果已有总冲激响应 h_prev（对应当前输出采样率），
%   再串联一个 2x 插值器 b2，则新的总冲激响应为：
%
%       h_new = conv( upsample(h_prev, 2), b2 )
%
% ------------------------------------------------------------
h_total = b4;

fprintf('\n逐级构造 128x 总链路：\n');
fprintf('Stage 1 : 4x   -> 长度 = %d tap\n', length(h_total));

for stage = 1:5
    % 先把已有总冲激响应提升到下一层采样率
    h_up = upsample(h_total, 2);

    % 注意：
    % MATLAB 的 upsample(h,2) 会在序列末尾多补 1 个 0，
    % 这会破坏严格对称性判断。
    % 对插值链路的等效冲激响应来说，这个末尾 0 应该去掉。
    h_up = h_up(1:end-1);

    % 再与 2x FIR 卷积
    h_total = conv(h_up, b2);

    fprintf('Stage %d : 再接 1 个 2x -> 总长度 = %d tap\n', stage+1, length(h_total));
end

%% 4) 先检查总冲激响应是否严格对称
sym_err = max(abs(h_total - fliplr(h_total)));
fprintf('\n总 128x 链路冲激响应长度 = %d tap\n', length(h_total));
fprintf('总冲激响应最大对称误差   = %.12g\n', sym_err);

if sym_err < 1e-12
    fprintf('结论：总 128x 链路冲激响应严格对称。\n');
else
    fprintf('警告：总 128x 链路冲激响应不完全对称，请检查级联逻辑。\n');
end

%% 5) 检查两种最终模式
% ------------------------------------------------------------
% 模式 A：
%   44.1k -> 5.6448M
%
% 模式 B：
%   48k   -> 6.144M
%
% 对总插值系统来说：
%   第一镜像位置仍然与原始输入采样率 Fs_in 有关
%
% 所以总系统阻带起始仍取：
%   f_stop_begin = Fs_in - 20k
% ------------------------------------------------------------
modes = [
    44100, 5644800;
    48000, 6144000
];

result_table = zeros(size(modes,1), 8);

for i = 1:size(modes,1)
    Fs_in  = modes(i,1);
    Fs_out = modes(i,2);

    f_stop_begin = Fs_in - 20000;

    fprintf('\n====================================================\n');
    fprintf('正在检查整体 128x 模式：Fs_in = %.1f Hz, Fs_out = %.1f Hz\n', Fs_in, Fs_out);

    [H, f] = freqz(h_total, 1, Nfft, Fs_out);
    H_db = 20*log10(abs(H) + 1e-15);

    % 通带 / 阻带索引
    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= Fs_out/2);

    pass_db = H_db(pass_idx);
    stop_db = H_db(stop_idx);

    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = max(abs(pass_db - mean(pass_db)));
    stop_attn_db = -max(stop_db);

    % 群延迟检查
    [gd, fg] = grpdelay(h_total, 1, Nfft, Fs_out);
    gd_idx = (fg >= f_pass_low) & (fg <= f_pass_high);
    gd_pass = gd(gd_idx);

    gd_mean = mean(gd_pass);
    gd_pp   = max(gd_pass) - min(gd_pass);

    pass_ripple = (ripple_pm_db <= ripple_target_db);
    pass_stop   = (stop_attn_db >= stop_target_db);
    pass_linear = (sym_err < 1e-12) && (gd_pp < 1e-6);

    fprintf('通带峰峰纹波 = %.6f dB\n', ripple_pp_db);
    fprintf('通带 ±纹波   = %.6f dB\n', ripple_pm_db);
    fprintf('阻带起始频率 = %.1f Hz\n', f_stop_begin);
    fprintf('阻带衰减     = %.6f dB\n', stop_attn_db);
    fprintf('通带平均群延迟 = %.6f 个最终输出采样点\n', gd_mean);
    fprintf('通带群延迟波动 = %.12f 个最终输出采样点\n', gd_pp);

    fprintf('\n指标判定：\n');
    fprintf('通带纹波 <= ±0.05 dB ：%d\n', pass_ripple);
    fprintf('阻带衰减 >= 70 dB    ：%d\n', pass_stop);
    fprintf('严格线性相位         ：%d\n', pass_linear);

    if pass_ripple && pass_stop && pass_linear
        fprintf('结论：整体 128x 模式满足赛题核心性能指标。\n');
    else
        fprintf('结论：整体 128x 模式未完全满足赛题核心性能指标。\n');
    end

    result_table(i,:) = [Fs_in, Fs_out, ripple_pp_db, ripple_pm_db, ...
                         stop_attn_db, gd_mean, pass_ripple, pass_stop];
end

%% 6) 打印汇总表
fprintf('\n\n===================== 整体 128x 汇总结果 =====================\n');
fprintf('   Fs_in        Fs_out        Ripple_pp      Ripple_±      StopAttn       GD_mean      Pass   Stop\n');

for i = 1:size(result_table,1)
    fprintf('%8.1f   %12.1f   %10.6f   %10.6f   %10.6f   %10.4f      %d      %d\n', ...
        result_table(i,1), result_table(i,2), result_table(i,3), result_table(i,4), ...
        result_table(i,5), result_table(i,6), result_table(i,7), result_table(i,8));
end
fprintf('==============================================================\n');

%% 7) 画两种最终模式下的总频响
for i = 1:size(modes,1)
    Fs_in  = modes(i,1);
    Fs_out = modes(i,2);
    f_stop_begin = Fs_in - 20000;

    [H, f] = freqz(h_total, 1, Nfft, Fs_out);
    H_db = 20*log10(abs(H) + 1e-15);

    [gd, fg] = grpdelay(h_total, 1, Nfft, Fs_out);

    figure('Color', 'w', 'Name', sprintf('128x total chain - Fsout=%.1f', Fs_out));

    subplot(2,1,1);
    plot(f, H_db, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('幅度 / dB');
    title(sprintf('整体 128x 链路频率响应（Fs_{out}=%.1f Hz）', Fs_out));
    xline(f_pass_low, '--r', '10 Hz');
    xline(f_pass_high, '--r', '20 kHz');
    xline(f_stop_begin, '--m', sprintf('f_{stop}=%.1f Hz', f_stop_begin));
    ylim([-160 5]);

    subplot(2,1,2);
    plot(fg, gd, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('群延迟 / 样点');
    title('整体 128x 链路群延迟');
    xline(f_pass_low, '--r', '10 Hz');
    xline(f_pass_high, '--r', '20 kHz');
end