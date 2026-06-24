clc; clear; close all;

%% ============================================================
% design_interp2_fir_common.m
%
% 作用：
% 1) 设计一个“公共 2倍插值 FIR”，用于挂在现有 4倍插值级后面
% 2) 同时支持：
%       - 176.4k -> 352.8k
%       - 192k   -> 384k
% 3) 导出后续 RTL 要用的系数文件
%
% 说明：
% - 这是 8倍插值系统中的“后级 2x FIR”
% - 前级 4x FIR 你已经做完并达标
% - 本脚本暂时只做“单独 2x 级”的设计与检查
%
% 设计策略：
% - 以更苛刻的 352.8k 输出模式作为设计基准
% - 为了给总链路留裕量，这一级目标设置得更严格：
%       通带 ±纹波 <= 0.01 dB
%       阻带衰减   >= 80 dB
%
% 后续流程：
% - 先把这一级设计出来
% - 再做 4x + 2x 的整体 8倍链路验证
%% ============================================================

%% 1) 基本参数
FRAC_W = 16;                 % Q16 定点量化

% -------- 2x 后级的最苛刻模式 --------
% 176.4k -> 352.8k 比 192k -> 384k 更苛刻
Fs_in_worst  = 176400;
Fs_out_worst = 352800;

% -------- 通带 / 阻带 --------
f_pass_low   = 10;
f_pass_high  = 20000;

% 对于 2倍插值：
% 新产生的镜像从 Fs_in - 20kHz 开始
% 最苛刻模式下：
%   176.4k - 20k = 156.4k
f_stop_begin = Fs_in_worst - 20000;

% -------- 这一级单独设计目标（留裕量）--------
ripple_pm_target_db = 0.01;   % 通带 ±纹波目标
stop_attn_target_db = 80;     % 阻带衰减目标

% dB -> 线性偏差
delta_p = (10^(ripple_pm_target_db/20) - 1) / (10^(ripple_pm_target_db/20) + 1);
delta_s = 10^(-stop_attn_target_db/20);

fprintf('====================================================\n');
fprintf('2倍后级公共 FIR 设计开始\n');
fprintf('最苛刻模式：Fs_in = %.1f Hz, Fs_out = %.1f Hz\n', Fs_in_worst, Fs_out_worst);
fprintf('通带：%.1f ~ %.1f Hz\n', f_pass_low, f_pass_high);
fprintf('阻带起始：%.1f Hz\n', f_stop_begin);
fprintf('通带 ±纹波目标：%.4f dB\n', ripple_pm_target_db);
fprintf('阻带衰减目标：%.1f dB\n', stop_attn_target_db);
fprintf('delta_p = %.10f\n', delta_p);
fprintf('delta_s = %.10f\n', delta_s);
fprintf('====================================================\n\n');

%% 2) 用 firpmord 先估计一个初始阶数
[n_est, fo, ao, w] = firpmord([f_pass_high f_stop_begin], [1 0], [delta_p delta_s], Fs_out_worst);

% 为了做奇数 tap 的线性相位 FIR：
% 阶数 n 要为偶数，这样 tap 数 = n+1 才是奇数
if mod(n_est, 2) ~= 0
    n_est = n_est + 1;
end

fprintf('firpmord 估计阶数 n_est = %d, 对应 tap 数 = %d\n\n', n_est, n_est+1);

%% 3) 搜索量化后也满足要求的公共 2x FIR
Nfft = 131072;

found = false;
best_n = -1;
best_b = [];

% 从估计阶数开始逐步搜索
for n = n_est : 2 : 200

    % 3.1 浮点等波纹设计
    b_float = firpm(n, fo, ao, w);

    % 3.2 Q16 量化
    coeff_int = round(b_float * 2^FRAC_W);
    b_q = coeff_int / 2^FRAC_W;

    % 3.3 检查两种模式
    ok_3528 = check_one_mode(b_q, 352800, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft);
    ok_3840 = check_one_mode(b_q, 384000, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft);

    fprintf('尝试阶数 n = %3d, tap = %3d | 352.8k: %d | 384k: %d\n', ...
        n, n+1, ok_3528.pass_all, ok_3840.pass_all);

    if ok_3528.pass_all && ok_3840.pass_all
        found = true;
        best_n = n;
        best_b = b_q;
        fprintf('\n找到满足两种模式的量化后 2x FIR：n = %d, tap = %d\n\n', best_n, best_n+1);
        break;
    end
end

if ~found
    error('在当前搜索范围内（n<=200）没有找到满足要求的 2x FIR，请继续扩大搜索范围。');
end

%% 4) 对最终结果做详细检查
fprintf('================ 最终 2x 公共 FIR 检查 ================\n');
fprintf('最终阶数 n = %d\n', best_n);
fprintf('最终 tap 数 = %d\n', best_n + 1);

sym_err = max(abs(best_b(:).' - fliplr(best_b(:).')));
fprintf('最大系数对称误差 = %.12g\n', sym_err);

res_3528 = check_one_mode_verbose(best_b, 352800, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft);
res_3840 = check_one_mode_verbose(best_b, 384000, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft);

%% 5) 导出系数文件
coeff_int_best = round(best_b * 2^FRAC_W);
coeff_int_best = coeff_int_best(:);   % 列向量

% 5.1 完整十进制文件（每行一个整数）
writematrix(coeff_int_best, 'interp2_coeff_decimal.txt', 'Delimiter', 'tab');

% 5.2 完整 Verilog 赋值文件（如果后面想做普通 FIR，也能直接用）
fid = fopen('interp2_coeff_for_verilog.txt', 'w');
fprintf(fid, '// =====================================================\n');
fprintf(fid, '// MATLAB 自动生成的 2x FIR 完整系数赋值语句\n');
fprintf(fid, '// 系数位宽: 18 bit\n');
fprintf(fid, '// 小数位宽: %d bit\n', FRAC_W);
fprintf(fid, '// 系数总数: %d\n', length(coeff_int_best));
fprintf(fid, '// =====================================================\n');

for k = 1:length(coeff_int_best)
    val = coeff_int_best(k);
    if val < 0
        fprintf(fid, '        coeff[%d] = -18''sd%d;\n', k-1, abs(val));
    else
        fprintf(fid, '        coeff[%d] = 18''sd%d;\n', k-1, val);
    end
end
fclose(fid);

% 5.3 导出半系数十进制文件（给对称优化 RTL 用）
half_taps = (length(coeff_int_best)-1)/2;
coeff_half_int = coeff_int_best(1:half_taps+1);

writematrix(coeff_half_int, 'interp2_coeff_half_decimal.txt', 'Delimiter', 'tab');

% 5.4 导出半系数 Verilog 赋值文件（推荐后续 RTL 使用）
fid = fopen('interp2_coeff_half_for_verilog.txt', 'w');
fprintf(fid, '// =====================================================\n');
fprintf(fid, '// MATLAB 自动生成的 2x FIR 半系数赋值语句（对称优化版）\n');
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
fprintf('1) interp2_coeff_decimal.txt\n');
fprintf('2) interp2_coeff_for_verilog.txt\n');
fprintf('3) interp2_coeff_half_decimal.txt\n');
fprintf('4) interp2_coeff_half_for_verilog.txt\n');

%% 6) 画最终频响图
Fs_list = [352800, 384000];

for i = 1:length(Fs_list)
    Fs_out = Fs_list(i);
    Fs_in  = Fs_out / 2;
    f_stop_begin_mode = Fs_in - 20000;

    [H, f] = freqz(best_b, 1, Nfft, Fs_out);
    H_db = 20*log10(abs(H) + 1e-15);

    [gd, fg] = grpdelay(best_b, 1, Nfft, Fs_out);

    figure('Color', 'w', 'Name', sprintf('2x FIR - Fsout=%.1f', Fs_out));

    subplot(2,1,1);
    plot(f, H_db, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('幅度 / dB');
    title(sprintf('2x 公共 FIR 频率响应（Fs_{out}=%.1f Hz）', Fs_out));
    xline(f_pass_low, '--r', '10 Hz');
    xline(f_pass_high, '--r', '20 kHz');
    xline(f_stop_begin_mode, '--m', sprintf('f_{stop}=%.1f Hz', f_stop_begin_mode));
    ylim([-160 5]);

    subplot(2,1,2);
    plot(fg, gd, 'LineWidth', 1.0); grid on;
    xlabel('频率 / Hz');
    ylabel('群延迟 / 样点');
    title('群延迟响应');
    xline(f_pass_low, '--r', '10 Hz');
    xline(f_pass_high, '--r', '20 kHz');
end

%% ============================================================
% 局部函数
%% ============================================================

function res = check_one_mode(b, Fs_out, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft)

    Fs_in = Fs_out / 2;
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

    Fs_in = Fs_out / 2;
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
        fprintf('结论：该模式满足 2x 级设计目标。\n');
    else
        fprintf('结论：该模式未完全满足 2x 级设计目标。\n');
    end

    res = [];
end