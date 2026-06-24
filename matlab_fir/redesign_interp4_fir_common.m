clc; clear; close all;

%% redesign_interp4_fir_common.m
%
% 作用：
% 1) 按“最苛刻模式” 44.1k -> 176.4k 重新设计一套 4 倍插值 FIR
% 2) 自动尝试更高 tap 数，直到满足赛题核心指标
% 3) 检查这套系数在：
%       - 176.4k 输出
%       - 192k 输出
%    两种模式下是否都满足指标
% 4) 导出新的定点系数文件，供 RTL 替换
%
% 赛题核心指标：
% - 通带：10 Hz ~ 20 kHz
% - 通带纹波：<= ±0.05 dB
% - 阻带衰减：>= 70 dB
% - 严格线性相位
%
% 设计策略：
% - 以最苛刻模式 Fs_out = 176400 Hz 作为设计基准
% - 通带上限固定 20kHz
% - 阻带起始取第一镜像开始位置：Fs_in - 20kHz = 24100 Hz
% - 使用 Parks-McClellan (firpm) 进行等波纹设计
% - 然后做 Q16 量化，再检查量化后性能

%% 1) 设计目标参数
% ---------------------------
FRAC_W = 16;               % Q16 定点量化
Fs_out_worst = 176400;     % 最苛刻输出采样率
Fs_in_worst  = Fs_out_worst / 4;

f_pass_low   = 10;         % 通带下限
f_pass_high  = 20000;      % 通带上限
f_stop_begin = Fs_in_worst - 20000;   % 第一镜像开始位置 = 24100 Hz

% 赛题要求
ripple_pm_target_db = 0.05;   % ±0.05 dB
stop_attn_target_db = 70;     % >= 70 dB

% 把 dB 指标换成 firpm 所需线性偏差
delta_p = (10^(ripple_pm_target_db/20) - 1) / (10^(ripple_pm_target_db/20) + 1);
delta_s = 10^(-stop_attn_target_db/20);

fprintf('最苛刻模式：Fs_in = %.1f Hz, Fs_out = %.1f Hz\n', Fs_in_worst, Fs_out_worst);
fprintf('通带：%.1f ~ %.1f Hz\n', f_pass_low, f_pass_high);
fprintf('阻带起始：%.1f Hz\n', f_stop_begin);
fprintf('delta_p = %.8f\n', delta_p);
fprintf('delta_s = %.8f\n\n', delta_s);

%% 2) 先估计一个初始阶数
% ---------------------------
[n_est, fo, ao, w] = firpmord([f_pass_high f_stop_begin], [1 0], [delta_p delta_s], Fs_out_worst);

% 为了做奇数长度线性相位 FIR，通常希望阶数为偶数（这样 tap 数为奇数）
if mod(n_est, 2) ~= 0
    n_est = n_est + 1;
end

fprintf('firpmord 估计阶数 n_est = %d，对应 tap 数 = %d\n\n', n_est, n_est + 1);

%% 3) 从估计值开始逐步增大阶数，直到量化后满足两种模式
% ---------------------------
Nfft = 131072;

found = false;
best_n = -1;
best_b = [];

% 从估计阶数开始，每次加 2，保持奇数 tap 数
for n = n_est : 2 : 400

    % 3.1 浮点等波纹设计
    b_float = firpm(n, fo, ao, w);

    % 3.2 Q16 量化后再检查
    coeff_int = round(b_float * 2^FRAC_W);
    b_q = coeff_int / 2^FRAC_W;

    % 3.3 检查两种模式
    ok_1764 = check_one_mode(b_q, 176400, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft);
    ok_1920 = check_one_mode(b_q, 192000, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft);

    fprintf('尝试阶数 n = %3d, tap = %3d | 176.4k: %d | 192k: %d\n', ...
        n, n+1, ok_1764.pass_all, ok_1920.pass_all);

    if ok_1764.pass_all && ok_1920.pass_all
        found = true;
        best_n = n;
        best_b = b_q;
        fprintf('\n找到满足两种模式的量化后 FIR：n = %d, tap = %d\n\n', best_n, best_n + 1);
        break;
    end
end

if ~found
    error('在当前搜索范围内（n<=400）没有找到满足指标的公共 FIR，请继续扩大搜索范围。');
end


%% 4) 对最终结果做详细检查并打印
% ---------------------------
fprintf('================ 最终公共 FIR 检查 ================\n');
fprintf('最终阶数 n = %d\n', best_n);
fprintf('最终 tap 数 = %d\n', best_n + 1);

sym_err = max(abs(best_b(:).' - fliplr(best_b(:).')));
fprintf('最大系数对称误差 = %.12g\n', sym_err);

res_1764 = check_one_mode_verbose(best_b, 176400, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft);
res_1920 = check_one_mode_verbose(best_b, 192000, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft);


%% 5) 导出新的系数文件
% ---------------------------
coeff_int_best = round(best_b * 2^FRAC_W);
coeff_int_best = coeff_int_best(:);   % 列向量

% 5.1 完整十进制文件（每行一个整数）
writematrix(coeff_int_best, 'fir_coeff_decimal_v2.txt', 'Delimiter', 'tab');

% 5.2 导出“半系数”十进制文件
% 对于 155 tap：
%   半系数数 = 78
half_taps = (length(coeff_int_best) - 1) / 2;   % 77
coeff_half_int = coeff_int_best(1:half_taps+1); % 取 1~78，对应 coeff_half[0:77]

writematrix(coeff_half_int, 'fir_coeff_half_decimal_v2.txt', 'Delimiter', 'tab');

% 5.3 导出 Verilog 半系数赋值语句
fid = fopen('fir_coeff_half_for_verilog_v2.txt', 'w');
fprintf(fid, '// =====================================================\n');
fprintf(fid, '// MATLAB 自动生成的对称优化 FIR 半系数赋值语句（公共双模式版）\n');
fprintf(fid, '// 系数位宽: 18 bit\n');
fprintf(fid, '// 小数位宽: %d bit\n', FRAC_W);
fprintf(fid, '// 半系数总数: %d\n', length(coeff_half_int));
fprintf(fid, '// =====================================================\n');

for k = 1:length(coeff_half_int)
    val = coeff_half_int(k);

    if val < 0
        fprintf(fid, '        coeff_half[%d] = -18''sd%d;\n', k-1, abs(val));
    else
        fprintf(fid, '        coeff_half[%d] = 18''sd%d;\n', k-1, val);
    end
end

fclose(fid);

fprintf('\n已生成文件：\n');
fprintf('1) fir_coeff_decimal_v2.txt\n');
fprintf('2) fir_coeff_half_decimal_v2.txt\n');
fprintf('3) fir_coeff_half_for_verilog_v2.txt\n');


%% 6) 画最终公共 FIR 的频响图
% ---------------------------
Fs_list = [176400, 192000];

for i = 1:length(Fs_list)
    Fs_out = Fs_list(i);
    Fs_in  = Fs_out / 4;
    f_stop_begin_mode = Fs_in - 20000;

    [H, f] = freqz(best_b, 1, Nfft, Fs_out);
    H_db = 20*log10(abs(H) + 1e-15);

    [gd, fg] = grpdelay(best_b, 1, Nfft, Fs_out);

    figure('Color', 'w', 'Name', sprintf('Final Common FIR - Fsout=%.1f', Fs_out));

    subplot(2,1,1);
    plot(f, H_db, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('幅度 / dB');
    title(sprintf('最终公共 FIR 频率响应（Fs_{out}=%.1f Hz）', Fs_out));
    xline(f_pass_low,   '--r', '10 Hz');
    xline(f_pass_high,  '--r', '20 kHz');
    xline(f_stop_begin_mode, '--m', sprintf('f_{stop}=%.1f Hz', f_stop_begin_mode));
    ylim([-160 5]);

    subplot(2,1,2);
    plot(fg, gd, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('群延迟 / 样点');
    title('群延迟响应');
    xline(f_pass_low,   '--r', '10 Hz');
    xline(f_pass_high,  '--r', '20 kHz');
end


%% 本脚本使用的局部函数

function res = check_one_mode(b, Fs_out, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft)

    Fs_in = Fs_out / 4;
    f_stop_begin = Fs_in - 20000;

    [H, f] = freqz(b, 1, Nfft, Fs_out);
    H_db = 20*log10(abs(H) + 1e-15);

    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= Fs_out/2);

    pass_db = H_db(pass_idx);
    stop_db = H_db(stop_idx);

    ripple_pm_db = max(abs(pass_db - mean(pass_db)));
    stop_attn_db = -max(stop_db);

    [gd, fg] = grpdelay(b, 1, Nfft, Fs_out);
    gd_idx = (fg >= f_pass_low) & (fg <= f_pass_high);
    gd_pp = max(gd(gd_idx)) - min(gd(gd_idx));

    sym_err = max(abs(b(:).' - fliplr(b(:).')));

    res.ripple_pm_db = ripple_pm_db;
    res.stop_attn_db = stop_attn_db;
    res.gd_pp = gd_pp;
    res.sym_err = sym_err;

    res.pass_ripple = (ripple_pm_db <= ripple_pm_target_db);
    res.pass_stop   = (stop_attn_db >= stop_attn_target_db);
    res.pass_linear = (sym_err < 1e-12) && (gd_pp < 1e-6);

    res.pass_all = res.pass_ripple && res.pass_stop && res.pass_linear;
end

function res = check_one_mode_verbose(b, Fs_out, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft)

    Fs_in = Fs_out / 4;
    f_stop_begin = Fs_in - 20000;

    [H, f] = freqz(b, 1, Nfft, Fs_out);
    H_db = 20*log10(abs(H) + 1e-15);

    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= Fs_out/2);

    pass_db = H_db(pass_idx);
    stop_db = H_db(stop_idx);

    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = max(abs(pass_db - mean(pass_db)));
    stop_attn_db = -max(stop_db);

    [gd, fg] = grpdelay(b, 1, Nfft, Fs_out);
    gd_idx = (fg >= f_pass_low) & (fg <= f_pass_high);
    gd_pass = gd(gd_idx);

    gd_mean = mean(gd_pass);
    gd_pp = max(gd_pass) - min(gd_pass);

    sym_err = max(abs(b(:).' - fliplr(b(:).')));

    pass_ripple = (ripple_pm_db <= ripple_pm_target_db);
    pass_stop   = (stop_attn_db >= stop_attn_target_db);
    pass_linear = (sym_err < 1e-12) && (gd_pp < 1e-6);

    fprintf('\n----------------------------------------------------\n');
    fprintf('模式：Fs_in = %.1f Hz, Fs_out = %.1f Hz\n', Fs_in, Fs_out);
    fprintf('通带峰峰纹波 = %.6f dB\n', ripple_pp_db);
    fprintf('通带 ±纹波   = %.6f dB\n', ripple_pm_db);
    fprintf('阻带起始频率 = %.1f Hz\n', f_stop_begin);
    fprintf('阻带衰减     = %.6f dB\n', stop_attn_db);
    fprintf('通带平均群延迟 = %.6f 个采样点\n', gd_mean);
    fprintf('通带群延迟波动 = %.12f 个采样点\n', gd_pp);
    fprintf('系数最大对称误差 = %.12g\n', sym_err);

    fprintf('通带纹波判定：%d\n', pass_ripple);
    fprintf('阻带衰减判定：%d\n', pass_stop);
    fprintf('线性相位判定：%d\n', pass_linear);

    if pass_ripple && pass_stop && pass_linear
        fprintf('结论：该模式满足赛题核心性能指标。\n');
    else
        fprintf('结论：该模式未完全满足赛题核心性能指标。\n');
    end

    res = [];
end