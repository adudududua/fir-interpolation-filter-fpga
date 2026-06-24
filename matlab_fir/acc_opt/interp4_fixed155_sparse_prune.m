clc; clear; close all;

%=============================================================
% 文件名       : interp4_fixed155_sparse_prune.m
% 脚本名       : interp4_fixed155_sparse_prune
% 功能简述     : 4倍插值 FIR 固定阶数小系数稀疏裁剪优化脚本。
%                本脚本用于在不增加 4x FIR tap 数、不改变 4x FIR
%                基本字长的前提下，对 Q16 量化后的 155 tap 系数进行
%                小系数裁剪搜索。
%
%                与前一版 wordlen_opt 的区别：
%                  1. 不再降低 4x FIR 的 COEFF_W；
%                  2. 不再增加 4x FIR 的 tap 数；
%                  3. 固定 4x FIR 为 155 tap；
%                  4. 固定 COEFF_W = 18、FRAC_W = 16；
%                  5. 只搜索 PRUNE_THR，把绝对值较小的量化系数置零。
%
%                优化目的：
%                  在保持 44.1kHz -> 176.4kHz 与 48kHz -> 192kHz
%                  两种 4x 模式均满足指标的前提下，减少非零系数数量，
%                  从而让综合器优化掉部分常数乘法与加法路径。
%
%                输出文件：
%                  interp4_fixed155_sparse_result.csv
%                  interp4_fixed155_sparse_summary.txt
%                  interp4_fixed155_sparse_coeff_decimal.txt
%                  interp4_fixed155_sparse_coeff_half_decimal.txt
%                  interp4_fixed155_sparse_coeff_half_for_verilog.txt
%                  interp4_fixed155_sparse_response.png
%
% 当前默认配置：
%                  4x FIR tap 数：155
%                  阶数         ：154
%                  COEFF_W      ：18
%                  FRAC_W       ：16
%                  PRUNE_THR_LIST：[0 1 2 4 8 16 32 64 128 256]
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-06-24
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-06-24：新增 4x FIR 固定 155 tap 小系数稀疏裁剪脚本。
%=============================================================

%% 1) 基本设计参数
%=============================================================

% 固定 4x FIR 参数
N_ORDER = 154;              % 阶数，tap 数 = 155
NTAPS   = N_ORDER + 1;      % 155 tap
FRAC_W  = 16;               % Q16
COEFF_W = 18;               % 18 bit signed

% 裁剪阈值列表，单位是“量化后的整数系数值”
% 例如 PRUNE_THR = 4 表示 abs(coeff_int)<=4 的系数全部置零。
PRUNE_THR_LIST = [0 1 2 4 8 16 32 64 128 256];

% 两种 4x 输出模式
FS_OUT_LIST = [176400, 192000];
MODE_NAME   = {'44.1k -> 176.4k', '48k -> 192k'};

% 赛题指标
f_pass_low   = 10;
f_pass_high  = 20000;
ripple_pm_target_db = 0.05;
stop_attn_target_db = 70;

% 最苛刻模式用于 firpm 设计
Fs_out_worst = 176400;
Fs_in_worst  = Fs_out_worst / 4;
f_stop_begin_worst = Fs_in_worst - f_pass_high;

% firpm 权重
delta_p = (10^(ripple_pm_target_db/20) - 1) / ...
          (10^(ripple_pm_target_db/20) + 1);
delta_s = 10^(-stop_attn_target_db/20);

% 频响分析点数
Nfft = 131072;

fprintf('====================================================\n');
fprintf('4x FIR 固定 155 tap 小系数稀疏裁剪搜索开始\n');
fprintf('固定阶数 N_ORDER = %d，tap 数 = %d\n', N_ORDER, NTAPS);
fprintf('COEFF_W = %d, FRAC_W = %d\n', COEFF_W, FRAC_W);
fprintf('最苛刻模式 Fs_out = %.1f Hz, f_stop = %.1f Hz\n', ...
        Fs_out_worst, f_stop_begin_worst);
fprintf('通带：%.1f Hz ~ %.1f Hz\n', f_pass_low, f_pass_high);
fprintf('通带 ±纹波目标：%.4f dB\n', ripple_pm_target_db);
fprintf('阻带衰减目标：%.1f dB\n', stop_attn_target_db);
fprintf('PRUNE_THR_LIST = [%s]\n', num2str(PRUNE_THR_LIST));
fprintf('====================================================\n\n');

%% 2) 重新生成原始 155 tap 4x FIR，并做 Q16 量化
%=============================================================

% 使用最苛刻模式设计 155 tap 等波纹 FIR。
% 注意：这里固定 N_ORDER=154，不再自动增加 tap 数。
fo = [0, f_pass_high, f_stop_begin_worst, Fs_out_worst/2] / (Fs_out_worst/2);
ao = [1, 1, 0, 0];
w  = [1/delta_p, 1/delta_s];

b_float = firpm(N_ORDER, fo, ao, w);

% Q16 量化
coeff_int_base = round(b_float * 2^FRAC_W);
b_q_base       = coeff_int_base / 2^FRAC_W;

% 检查系数是否超出 18bit signed 范围
coeff_max =  2^(COEFF_W-1) - 1;
coeff_min = -2^(COEFF_W-1);

if max(coeff_int_base) > coeff_max || min(coeff_int_base) < coeff_min
    error('原始 4x 系数量化后超出 %d bit signed 表示范围。', COEFF_W);
end

fprintf('原始 155 tap Q16 系数范围：[%d, %d]\n', min(coeff_int_base), max(coeff_int_base));
fprintf('原始完整非零系数个数：%d / %d\n', nnz(coeff_int_base), NTAPS);

half_taps_base = (NTAPS - 1) / 2;
coeff_half_base = coeff_int_base(1:half_taps_base+1);
fprintf('原始半系数非零个数：%d / %d\n\n', nnz(coeff_half_base), length(coeff_half_base));

%% 3) 先检查未裁剪 baseline 是否满足两种模式
%=============================================================

fprintf('================ 未裁剪 baseline 检查 ================\n');

base_ok_all = true;
base_res = cell(1, length(FS_OUT_LIST));

for i = 1:length(FS_OUT_LIST)
    base_res{i} = check_one_mode_verbose(b_q_base, ...
                                         FS_OUT_LIST(i), ...
                                         f_pass_low, ...
                                         f_pass_high, ...
                                         stop_attn_target_db, ...
                                         ripple_pm_target_db, ...
                                         Nfft, ...
                                         MODE_NAME{i});
    base_ok_all = base_ok_all && base_res{i}.pass_all;
end

if ~base_ok_all
    warning('固定 155 tap 的 baseline 未同时满足两种模式指标。请确认当前 4x RTL 使用的是否正是这组系数。');
end

%% 4) 搜索可接受的最大裁剪阈值
%=============================================================

% 结果表列：
% PRUNE_THR, NONZERO_FULL, NONZERO_HALF,
% RIPPLE_1764_DB, STOP_1764_DB,
% RIPPLE_1920_DB, STOP_1920_DB,
% PASS_ALL
result_table = [];

best_found = false;
best_prune_thr = -1;
best_coeff_int = coeff_int_base(:);
best_b = b_q_base(:).';
best_nonzero_full = nnz(coeff_int_base);
best_nonzero_half = nnz(coeff_half_base);
best_res_1764 = [];
best_res_1920 = [];

fprintf('\n================ 开始裁剪搜索 ================\n');

for prune_thr = PRUNE_THR_LIST

    coeff_int_try = coeff_int_base(:).';
    coeff_int_try(abs(coeff_int_try) <= prune_thr) = 0;

    b_try = coeff_int_try / 2^FRAC_W;

    res_1764 = check_one_mode(b_try, ...
                              176400, ...
                              f_pass_low, ...
                              f_pass_high, ...
                              stop_attn_target_db, ...
                              ripple_pm_target_db, ...
                              Nfft);

    res_1920 = check_one_mode(b_try, ...
                              192000, ...
                              f_pass_low, ...
                              f_pass_high, ...
                              stop_attn_target_db, ...
                              ripple_pm_target_db, ...
                              Nfft);

    pass_all = res_1764.pass_all && res_1920.pass_all;

    coeff_half_try = coeff_int_try(1:half_taps_base+1);
    nonzero_full = nnz(coeff_int_try);
    nonzero_half = nnz(coeff_half_try);

    result_table = [result_table; ...
        prune_thr, nonzero_full, nonzero_half, ...
        res_1764.ripple_pm_db, res_1764.stop_attn_db, ...
        res_1920.ripple_pm_db, res_1920.stop_attn_db, ...
        pass_all];

    fprintf('prune_thr=%4d | nz_full=%3d/%3d | nz_half=%3d/%3d | 176.4k=%d | 192k=%d\n', ...
            prune_thr, ...
            nonzero_full, NTAPS, ...
            nonzero_half, length(coeff_half_base), ...
            res_1764.pass_all, res_1920.pass_all);

    % 选择策略：
    %   选择仍然满足两种模式指标的“最大裁剪阈值”；
    %   等价于尽可能多地裁掉小系数。
    if pass_all
        best_found = true;
        best_prune_thr = prune_thr;
        best_coeff_int = coeff_int_try(:);
        best_b = b_try(:).';
        best_nonzero_full = nonzero_full;
        best_nonzero_half = nonzero_half;
        best_res_1764 = res_1764;
        best_res_1920 = res_1920;
    end
end

if ~best_found
    error('没有找到满足指标的裁剪阈值。理论上 prune_thr=0 应该满足，请检查设计参数。');
end

%% 5) 打印最终最优裁剪结果
%=============================================================

fprintf('\n================ 4x 固定 155 tap 稀疏裁剪完成 ================\n');
fprintf('最佳 prune_thr           = %d\n', best_prune_thr);
fprintf('完整非零系数个数          = %d / %d\n', best_nonzero_full, NTAPS);
fprintf('完整裁剪系数个数          = %d / %d\n', NTAPS - best_nonzero_full, NTAPS);
fprintf('半系数非零个数            = %d / %d\n', best_nonzero_half, length(coeff_half_base));
fprintf('半系数裁剪个数            = %d / %d\n', length(coeff_half_base) - best_nonzero_half, length(coeff_half_base));

sym_err = max(abs(best_b(:).' - fliplr(best_b(:).')));
fprintf('最大系数对称误差          = %.12g\n', sym_err);

fprintf('\n================ 最佳裁剪版本详细检查 ================\n');

final_res_1764 = check_one_mode_verbose(best_b, ...
                                        176400, ...
                                        f_pass_low, ...
                                        f_pass_high, ...
                                        stop_attn_target_db, ...
                                        ripple_pm_target_db, ...
                                        Nfft, ...
                                        '44.1k -> 176.4k');

final_res_1920 = check_one_mode_verbose(best_b, ...
                                        192000, ...
                                        f_pass_low, ...
                                        f_pass_high, ...
                                        stop_attn_target_db, ...
                                        ripple_pm_target_db, ...
                                        Nfft, ...
                                        '48k -> 192k');

%% 6) 导出搜索结果与最优系数
%=============================================================

% 6.1 搜索结果表
fid = fopen('interp4_fixed155_sparse_result.csv', 'w');
fprintf(fid, 'PRUNE_THR,NONZERO_FULL,NONZERO_HALF,RIPPLE_1764_DB,STOP_1764_DB,RIPPLE_1920_DB,STOP_1920_DB,PASS_ALL\n');
for i = 1:size(result_table, 1)
    fprintf(fid, '%d,%d,%d,%.8f,%.8f,%.8f,%.8f,%d\n', result_table(i,:));
end
fclose(fid);

% 6.2 完整系数
writematrix(best_coeff_int, 'interp4_fixed155_sparse_coeff_decimal.txt', 'Delimiter', 'tab');

% 6.3 半系数
best_coeff_half = best_coeff_int(1:half_taps_base+1);
writematrix(best_coeff_half, 'interp4_fixed155_sparse_coeff_half_decimal.txt', 'Delimiter', 'tab');

% 6.4 Verilog 半系数赋值
export_half_coeff_for_verilog('interp4_fixed155_sparse_coeff_half_for_verilog.txt', ...
                              best_coeff_half, ...
                              COEFF_W, ...
                              FRAC_W, ...
                              N_ORDER, ...
                              best_prune_thr, ...
                              '4x FIR fixed-155-tap sparse-pruned half coefficients');

% 6.5 摘要
fid = fopen('interp4_fixed155_sparse_summary.txt', 'w');
fprintf(fid, '4x FIR fixed-155-tap sparse pruning summary\n');
fprintf(fid, '===========================================\n');
fprintf(fid, 'Order n                    = %d\n', N_ORDER);
fprintf(fid, 'Taps                       = %d\n', NTAPS);
fprintf(fid, 'COEFF_W                    = %d\n', COEFF_W);
fprintf(fid, 'FRAC_W                     = %d\n', FRAC_W);
fprintf(fid, 'Best prune threshold       = %d\n', best_prune_thr);
fprintf(fid, 'Nonzero full coefficients  = %d / %d\n', best_nonzero_full, NTAPS);
fprintf(fid, 'Pruned full coefficients   = %d / %d\n', NTAPS - best_nonzero_full, NTAPS);
fprintf(fid, 'Nonzero half coefficients  = %d / %d\n', best_nonzero_half, length(best_coeff_half));
fprintf(fid, 'Pruned half coefficients   = %d / %d\n', length(best_coeff_half) - best_nonzero_half, length(best_coeff_half));
fprintf(fid, '\nMode 176.4k:\n');
fprintf(fid, 'Ripple_pm_db = %.8f\n', final_res_1764.ripple_pm_db);
fprintf(fid, 'Stop_attn_db = %.8f\n', final_res_1764.stop_attn_db);
fprintf(fid, '\nMode 192k:\n');
fprintf(fid, 'Ripple_pm_db = %.8f\n', final_res_1920.ripple_pm_db);
fprintf(fid, 'Stop_attn_db = %.8f\n', final_res_1920.stop_attn_db);
fclose(fid);

%% 7) 绘制频响对比图
%=============================================================

plot_response_compare(b_q_base, ...
                      best_b, ...
                      176400, ...
                      192000, ...
                      f_pass_high, ...
                      'interp4_fixed155_sparse_response.png');

fprintf('\n已导出文件：\n');
fprintf('1) interp4_fixed155_sparse_result.csv\n');
fprintf('2) interp4_fixed155_sparse_summary.txt\n');
fprintf('3) interp4_fixed155_sparse_coeff_decimal.txt\n');
fprintf('4) interp4_fixed155_sparse_coeff_half_decimal.txt\n');
fprintf('5) interp4_fixed155_sparse_coeff_half_for_verilog.txt\n');
fprintf('6) interp4_fixed155_sparse_response.png\n\n');

fprintf('下一步 RTL 操作建议：\n');
fprintf('如果最佳 prune_thr > 0，并且裁剪后仍满足指标，\n');
fprintf('则可用 interp4_fixed155_sparse_coeff_half_for_verilog.txt\n');
fprintf('替换 fir_core_symm.v 中 4x FIR 的 coeff_half 初始化内容。\n');


%% ============================================================
% 本地函数：检查单个输出模式
% ============================================================
function res = check_one_mode(b, Fs_out, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft)

    Fs_in = Fs_out / 4;
    f_stop_begin = Fs_in - f_pass_high;

    [H, f] = freqz(b, 1, Nfft, Fs_out);
    mag_db = 20*log10(abs(H) + eps);

    idx_pass = (f >= f_pass_low) & (f <= f_pass_high);
    idx_stop = (f >= f_stop_begin) & (f <= Fs_out/2);

    pass_db = mag_db(idx_pass);
    stop_db = mag_db(idx_stop);

    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = ripple_pp_db / 2;
    stop_attn_db = -max(stop_db);

    [gd, f_gd] = grpdelay(b, 1, Nfft, Fs_out);
    idx_gd = (f_gd >= f_pass_low) & (f_gd <= f_pass_high);
    gd_pass = gd(idx_gd);
    gd_pp = max(gd_pass) - min(gd_pass);

    sym_err = max(abs(b(:).' - fliplr(b(:).')));

    pass_ripple = (ripple_pm_db <= ripple_pm_target_db);
    pass_stop   = (stop_attn_db >= stop_attn_target_db);
    pass_linear = (sym_err < 1e-10) && (gd_pp < 1e-6);

    res.ripple_pp_db = ripple_pp_db;
    res.ripple_pm_db = ripple_pm_db;
    res.stop_attn_db = stop_attn_db;
    res.gd_pp        = gd_pp;
    res.pass_ripple  = pass_ripple;
    res.pass_stop    = pass_stop;
    res.pass_linear  = pass_linear;
    res.pass_all     = pass_ripple && pass_stop && pass_linear;
end


%% ============================================================
% 本地函数：详细打印检查结果
% ============================================================
function res = check_one_mode_verbose(b, Fs_out, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft, mode_name)

    Fs_in = Fs_out / 4;
    f_stop_begin = Fs_in - f_pass_high;

    [H, f] = freqz(b, 1, Nfft, Fs_out);
    mag_db = 20*log10(abs(H) + eps);

    idx_pass = (f >= f_pass_low) & (f <= f_pass_high);
    idx_stop = (f >= f_stop_begin) & (f <= Fs_out/2);

    pass_db = mag_db(idx_pass);
    stop_db = mag_db(idx_stop);

    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = ripple_pp_db / 2;
    stop_attn_db = -max(stop_db);

    [gd, f_gd] = grpdelay(b, 1, Nfft, Fs_out);
    idx_gd = (f_gd >= f_pass_low) & (f_gd <= f_pass_high);
    gd_pass = gd(idx_gd);
    gd_mean = mean(gd_pass);
    gd_pp = max(gd_pass) - min(gd_pass);

    sym_err = max(abs(b(:).' - fliplr(b(:).')));

    pass_ripple = (ripple_pm_db <= ripple_pm_target_db);
    pass_stop   = (stop_attn_db >= stop_attn_target_db);
    pass_linear = (sym_err < 1e-10) && (gd_pp < 1e-6);

    fprintf('\n----------------------------------------------------\n');
    fprintf('模式：%s\n', mode_name);
    fprintf('Fs_in = %.1f Hz, Fs_out = %.1f Hz\n', Fs_in, Fs_out);
    fprintf('通带峰峰纹波 = %.8f dB\n', ripple_pp_db);
    fprintf('通带 ±纹波   = %.8f dB\n', ripple_pm_db);
    fprintf('阻带起始频率 = %.1f Hz\n', f_stop_begin);
    fprintf('阻带衰减     = %.8f dB\n', stop_attn_db);
    fprintf('通带平均群延迟 = %.8f 个采样点\n', gd_mean);
    fprintf('通带群延迟波动 = %.12f 个采样点\n', gd_pp);
    fprintf('系数最大对称误差 = %.12g\n', sym_err);
    fprintf('通带纹波判定：%d\n', pass_ripple);
    fprintf('阻带衰减判定：%d\n', pass_stop);
    fprintf('线性相位判定：%d\n', pass_linear);

    if pass_ripple && pass_stop && pass_linear
        fprintf('结论：该模式满足 4x FIR 设计目标。\n');
    else
        fprintf('结论：该模式未完全满足 4x FIR 设计目标。\n');
    end

    res.ripple_pp_db = ripple_pp_db;
    res.ripple_pm_db = ripple_pm_db;
    res.stop_attn_db = stop_attn_db;
    res.gd_mean      = gd_mean;
    res.gd_pp        = gd_pp;
    res.pass_all     = pass_ripple && pass_stop && pass_linear;
end


%% ============================================================
% 本地函数：导出半系数 Verilog 赋值语句
% ============================================================
function export_half_coeff_for_verilog(filename, coeff_half_int, coeff_w, frac_w, order_n, prune_thr, title_str)

    fid = fopen(filename, 'w');

    if fid == -1
        error('无法创建文件：%s', filename);
    end

    fprintf(fid, '// =====================================================\n');
    fprintf(fid, '// %s\n', title_str);
    fprintf(fid, '// 阶数 n     : %d\n', order_n);
    fprintf(fid, '// tap 数     : %d\n', order_n + 1);
    fprintf(fid, '// 系数位宽   : %d bit\n', coeff_w);
    fprintf(fid, '// 小数位宽   : %d bit\n', frac_w);
    fprintf(fid, '// 裁剪阈值   : %d\n', prune_thr);
    fprintf(fid, '// 半系数总数 : %d\n', length(coeff_half_int));
    fprintf(fid, '// =====================================================\n');

    for k = 1:length(coeff_half_int)
        val = coeff_half_int(k);

        if val < 0
            fprintf(fid, '        coeff_half[%d] = -%d''sd%d;\n', k-1, coeff_w, abs(val));
        else
            fprintf(fid, '        coeff_half[%d] = %d''sd%d;\n', k-1, coeff_w, val);
        end
    end

    fclose(fid);
end


%% ============================================================
% 本地函数：绘制 baseline 与 sparse 频响对比
% ============================================================
function plot_response_compare(b_base, b_sparse, Fs1, Fs2, f_pass_high, filename)

    Nfft_plot = 65536;

    [H1_base, f1] = freqz(b_base,   1, Nfft_plot, Fs1);
    [H1_sp,   ~ ] = freqz(b_sparse, 1, Nfft_plot, Fs1);

    [H2_base, f2] = freqz(b_base,   1, Nfft_plot, Fs2);
    [H2_sp,   ~ ] = freqz(b_sparse, 1, Nfft_plot, Fs2);

    figure('Color', 'w');

    subplot(2,1,1);
    plot(f1/1000, 20*log10(abs(H1_base)+eps), 'LineWidth', 1.0);
    hold on;
    plot(f1/1000, 20*log10(abs(H1_sp)+eps), '--', 'LineWidth', 1.0);
    grid on;
    xlabel('Frequency (kHz)');
    ylabel('Magnitude (dB)');
    title('4x FIR Fixed-155 Sparse Pruning Response, Fs=176.4kHz');
    legend('Baseline Q16', 'Sparse pruned', 'Location', 'best');
    xline(f_pass_high/1000, '--');
    ylim([-120, 5]);

    subplot(2,1,2);
    plot(f2/1000, 20*log10(abs(H2_base)+eps), 'LineWidth', 1.0);
    hold on;
    plot(f2/1000, 20*log10(abs(H2_sp)+eps), '--', 'LineWidth', 1.0);
    grid on;
    xlabel('Frequency (kHz)');
    ylabel('Magnitude (dB)');
    title('4x FIR Fixed-155 Sparse Pruning Response, Fs=192kHz');
    legend('Baseline Q16', 'Sparse pruned', 'Location', 'best');
    xline(f_pass_high/1000, '--');
    ylim([-120, 5]);

    saveas(gcf, filename);
end
