clc; clear; close all;

%=============================================================
% 文件名       : design_interp2_fir_common_wordlen_opt.m
% 脚本名       : design_interp2_fir_common_wordlen_opt
% 功能简述     : 2倍插值公共 FIR 的字长优化与稀疏系数裁剪搜索脚本。
%                本脚本在原 design_interp2_fir_common.m 的基础上，
%                增加 COEFF_W / FRAC_W 搜索与小系数裁剪搜索。
%
%                设计目标：
%                  1. 同一套 2x FIR 系数同时支持：
%                       176.4kHz -> 352.8kHz
%                       192kHz   -> 384kHz
%                  2. 量化后满足单级 2x 设计目标：
%                       通带：10Hz ~ 20kHz
%                       通带纹波：<= ±0.01dB
%                       阻带衰减：>= 80dB
%                       严格线性相位
%                  3. 在满足指标的前提下，搜索更小的系数字长，
%                     并尝试裁剪绝对值较小的系数，以减少有效乘加路径。
%
%                输出文件：
%                  interp2_wordlen_sparse_search_result.csv
%                  interp2_wordlen_opt_summary.txt
%                  interp2_coeff_decimal_wordlen_opt.txt
%                  interp2_coeff_for_verilog_wordlen_opt.txt
%                  interp2_coeff_half_decimal_wordlen_opt.txt
%                  interp2_coeff_half_for_verilog_wordlen_opt.txt
%                  interp2_wordlen_opt_response.png
%
% 当前默认配置：
%                  输入采样率    ：176.4kHz / 192kHz
%                  输出采样率    ：352.8kHz / 384kHz
%                  FRAC_W_LIST   ：[16 15 14 13 12]
%                  PRUNE_THR_LIST：[0 1 2 4 8 16]
%                  COEFF_W       ：FRAC_W + 2
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-06-23
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-06-23：新增 2x FIR 字长优化与稀疏裁剪搜索版本。
%=============================================================

%% 1) 设计目标参数
%=============================================================

% 字长优化候选参数
FRAC_W_LIST    = [16 15 14 13 12];
PRUNE_THR_LIST = [0 1 2 4 8 16];

% 2x 后级最苛刻模式：176.4kHz -> 352.8kHz
Fs_in_worst  = 176400;
Fs_out_worst = 352800;

f_pass_low   = 10;
f_pass_high  = 20000;
f_stop_begin = Fs_in_worst - f_pass_high;   % 176400 - 20000 = 156400 Hz

% 2x 单级设计目标，给总链路留裕量
ripple_pm_target_db = 0.01;
stop_attn_target_db = 80;

% dB 指标转换为 firpm 所需线性偏差
delta_p = (10^(ripple_pm_target_db/20) - 1) / ...
          (10^(ripple_pm_target_db/20) + 1);
delta_s = 10^(-stop_attn_target_db/20);

fprintf('====================================================\n');
fprintf('2x FIR 字长优化与稀疏裁剪搜索开始\n');
fprintf('最苛刻模式：Fs_in = %.1f Hz, Fs_out = %.1f Hz\n', Fs_in_worst, Fs_out_worst);
fprintf('通带：%.1f ~ %.1f Hz\n', f_pass_low, f_pass_high);
fprintf('阻带起始：%.1f Hz\n', f_stop_begin);
fprintf('通带 ±纹波目标：%.4f dB\n', ripple_pm_target_db);
fprintf('阻带衰减目标：%.1f dB\n', stop_attn_target_db);
fprintf('FRAC_W_LIST = [%s]\n', num2str(FRAC_W_LIST));
fprintf('PRUNE_THR_LIST = [%s]\n', num2str(PRUNE_THR_LIST));
fprintf('====================================================\n\n');

%% 2) 用 firpmord 估计初始阶数
%=============================================================

[n_est, fo, ao, w] = firpmord([f_pass_high f_stop_begin], ...
                              [1 0], ...
                              [delta_p delta_s], ...
                              Fs_out_worst);

% 奇数 tap 线性相位 FIR：阶数 n 取偶数，tap = n + 1 为奇数
if mod(n_est, 2) ~= 0
    n_est = n_est + 1;
end

fprintf('firpmord 估计阶数 n_est = %d，对应 tap 数 = %d\n\n', n_est, n_est + 1);

%% 3) 搜索满足指标的字长 / 裁剪组合
%=============================================================

Nfft = 131072;
N_MAX = 200;

found = false;

best_n            = -1;
best_b            = [];
best_coeff_int    = [];
best_frac_w       = -1;
best_coeff_w      = -1;
best_prune_thr    = -1;
best_nonzero_full = inf;
best_nonzero_half = inf;
best_res_3528     = [];
best_res_3840     = [];

% 结果表列：
% FRAC_W, COEFF_W, PRUNE_THR, ORDER_N, TAPS,
% RIPPLE_3528_DB, STOP_3528_DB, RIPPLE_3840_DB, STOP_3840_DB,
% NONZERO_FULL, NONZERO_HALF, PASS_ALL
result_table = [];

for frac_w_try = FRAC_W_LIST

    coeff_w_try = frac_w_try + 2;
    coeff_max   = 2^(coeff_w_try - 1) - 1;
    coeff_min   = -2^(coeff_w_try - 1);

    fprintf('\n=============== 开始搜索 FRAC_W=%d, COEFF_W=%d ===============\n', ...
            frac_w_try, coeff_w_try);

    for prune_thr = PRUNE_THR_LIST

        combo_found = false;

        for n = n_est : 2 : N_MAX

            % 3.1 浮点等波纹设计
            b_float = firpm(n, fo, ao, w);

            % 3.2 当前字长量化
            coeff_int = round(b_float * 2^frac_w_try);

            % 3.3 检查当前 COEFF_W 是否能表示该系数范围
            if max(coeff_int) > coeff_max || min(coeff_int) < coeff_min
                continue;
            end

            % 3.4 稀疏裁剪：小于等于阈值的量化系数置零
            coeff_int_pruned = coeff_int;
            coeff_int_pruned(abs(coeff_int_pruned) <= prune_thr) = 0;

            % 3.5 转换回浮点检查频响
            b_q = coeff_int_pruned / 2^frac_w_try;

            % 3.6 检查 352.8k 和 384k 两种输出模式
            ok_3528 = check_one_mode(b_q, ...
                                      352800, ...
                                      f_pass_low, ...
                                      f_pass_high, ...
                                      stop_attn_target_db, ...
                                      ripple_pm_target_db, ...
                                      Nfft);

            ok_3840 = check_one_mode(b_q, ...
                                      384000, ...
                                      f_pass_low, ...
                                      f_pass_high, ...
                                      stop_attn_target_db, ...
                                      ripple_pm_target_db, ...
                                      Nfft);

            pass_all = ok_3528.pass_all && ok_3840.pass_all;

            % 3.7 统计非零系数数量
            coeff_int_col = coeff_int_pruned(:);
            nonzero_full  = nnz(coeff_int_col);

            half_taps_try  = (length(coeff_int_col) - 1) / 2;
            coeff_half_try = coeff_int_col(1:half_taps_try + 1);
            nonzero_half   = nnz(coeff_half_try);

            result_table = [result_table; ...
                frac_w_try, coeff_w_try, prune_thr, n, n+1, ...
                ok_3528.ripple_pm_db, ok_3528.stop_attn_db, ...
                ok_3840.ripple_pm_db, ok_3840.stop_attn_db, ...
                nonzero_full, nonzero_half, pass_all];

            fprintf('FRAC=%2d COEFF=%2d prune=%2d n=%3d tap=%3d | nz_half=%3d | 352.8k=%d 384k=%d\n', ...
                    frac_w_try, coeff_w_try, prune_thr, n, n+1, ...
                    nonzero_half, ok_3528.pass_all, ok_3840.pass_all);

            if pass_all
                combo_found = true;

                % 选择策略：
                % 1. 优先更小 COEFF_W；
                % 2. 同 COEFF_W 下优先非零半系数更少；
                % 3. 再优先 tap 数更少；
                % 4. 再优先裁剪阈值更小，避免过度裁剪。
                update_best = false;

                if ~found
                    update_best = true;
                elseif coeff_w_try < best_coeff_w
                    update_best = true;
                elseif coeff_w_try == best_coeff_w && nonzero_half < best_nonzero_half
                    update_best = true;
                elseif coeff_w_try == best_coeff_w && nonzero_half == best_nonzero_half && n < best_n
                    update_best = true;
                elseif coeff_w_try == best_coeff_w && nonzero_half == best_nonzero_half && n == best_n && prune_thr < best_prune_thr
                    update_best = true;
                end

                if update_best
                    found = true;

                    best_n            = n;
                    best_b            = b_q;
                    best_coeff_int    = coeff_int_col;
                    best_frac_w       = frac_w_try;
                    best_coeff_w      = coeff_w_try;
                    best_prune_thr    = prune_thr;
                    best_nonzero_full = nonzero_full;
                    best_nonzero_half = nonzero_half;
                    best_res_3528     = ok_3528;
                    best_res_3840     = ok_3840;
                end

                % 当前 frac/prune 组合已经找到最小 n，换下一个组合
                break;
            end
        end

        if ~combo_found
            fprintf('FRAC=%2d COEFF=%2d prune=%2d 在 n<=%d 内未满足指标。\n', ...
                    frac_w_try, coeff_w_try, prune_thr, N_MAX);
        end
    end
end

if ~found
    error('未找到满足指标的 2x FIR 字长优化组合。请扩大 N_MAX 或减少裁剪阈值。');
end

%% 4) 打印最优结果并做详细检查
%=============================================================

fprintf('\n================ 2x 字长优化搜索完成 ================\n');
fprintf('最佳阶数 n             = %d\n', best_n);
fprintf('最佳 tap 数            = %d\n', best_n + 1);
fprintf('最佳 COEFF_W           = %d\n', best_coeff_w);
fprintf('最佳 FRAC_W            = %d\n', best_frac_w);
fprintf('最佳 prune_thr         = %d\n', best_prune_thr);
fprintf('非零完整系数个数       = %d / %d\n', best_nonzero_full, length(best_coeff_int));
fprintf('非零半系数个数         = %d / %d\n', best_nonzero_half, (length(best_coeff_int)+1)/2);

sym_err = max(abs(best_b(:).' - fliplr(best_b(:).')));
fprintf('最大系数对称误差       = %.12g\n', sym_err);

fprintf('\n================ 最佳 2x FIR 详细检查 ================\n');
res_3528 = check_one_mode_verbose(best_b, ...
                                  352800, ...
                                  f_pass_low, ...
                                  f_pass_high, ...
                                  stop_attn_target_db, ...
                                  ripple_pm_target_db, ...
                                  Nfft, ...
                                  '176.4k -> 352.8k');

res_3840 = check_one_mode_verbose(best_b, ...
                                  384000, ...
                                  f_pass_low, ...
                                  f_pass_high, ...
                                  stop_attn_target_db, ...
                                  ripple_pm_target_db, ...
                                  Nfft, ...
                                  '192k -> 384k');

%% 5) 导出搜索表与最优系数
%=============================================================

% 5.1 搜索结果 CSV
fid = fopen('interp2_wordlen_sparse_search_result.csv', 'w');
fprintf(fid, 'FRAC_W,COEFF_W,PRUNE_THR,ORDER_N,TAPS,RIPPLE_3528_DB,STOP_3528_DB,RIPPLE_3840_DB,STOP_3840_DB,NONZERO_FULL,NONZERO_HALF,PASS_ALL\n');
for i = 1:size(result_table, 1)
    fprintf(fid, '%d,%d,%d,%d,%d,%.8f,%.8f,%.8f,%.8f,%d,%d,%d\n', result_table(i,:));
end
fclose(fid);

% 5.2 完整十进制系数
writematrix(best_coeff_int, 'interp2_coeff_decimal_wordlen_opt.txt', 'Delimiter', 'tab');

% 5.3 完整 Verilog 赋值语句
export_full_coeff_for_verilog('interp2_coeff_for_verilog_wordlen_opt.txt', ...
                              best_coeff_int, ...
                              best_coeff_w, ...
                              best_frac_w, ...
                              best_n, ...
                              best_prune_thr, ...
                              '2x FIR word-length optimized full coefficients');

% 5.4 半系数十进制
half_taps       = (length(best_coeff_int) - 1) / 2;
coeff_half_int  = best_coeff_int(1:half_taps + 1);
writematrix(coeff_half_int, 'interp2_coeff_half_decimal_wordlen_opt.txt', 'Delimiter', 'tab');

% 5.5 半系数 Verilog 赋值语句
export_half_coeff_for_verilog('interp2_coeff_half_for_verilog_wordlen_opt.txt', ...
                              coeff_half_int, ...
                              best_coeff_w, ...
                              best_frac_w, ...
                              best_n, ...
                              best_prune_thr, ...
                              '2x FIR word-length optimized half coefficients');

% 5.6 摘要文件
fid = fopen('interp2_wordlen_opt_summary.txt', 'w');
fprintf(fid, '2x FIR word-length optimization summary\n');
fprintf(fid, '=======================================\n');
fprintf(fid, 'Best order n              = %d\n', best_n);
fprintf(fid, 'Best taps                 = %d\n', best_n + 1);
fprintf(fid, 'Best COEFF_W              = %d\n', best_coeff_w);
fprintf(fid, 'Best FRAC_W               = %d\n', best_frac_w);
fprintf(fid, 'Best prune threshold      = %d\n', best_prune_thr);
fprintf(fid, 'Nonzero full coefficients = %d / %d\n', best_nonzero_full, length(best_coeff_int));
fprintf(fid, 'Nonzero half coefficients = %d / %d\n', best_nonzero_half, length(coeff_half_int));
fprintf(fid, '\nMode 352.8k:\n');
fprintf(fid, 'Ripple_pm_db = %.8f\n', best_res_3528.ripple_pm_db);
fprintf(fid, 'Stop_attn_db = %.8f\n', best_res_3528.stop_attn_db);
fprintf(fid, '\nMode 384k:\n');
fprintf(fid, 'Ripple_pm_db = %.8f\n', best_res_3840.ripple_pm_db);
fprintf(fid, 'Stop_attn_db = %.8f\n', best_res_3840.stop_attn_db);
fclose(fid);

%% 6) 画最终频响图
%=============================================================

plot_two_mode_response(best_b, ...
                       352800, ...
                       384000, ...
                       f_pass_high, ...
                       'interp2_wordlen_opt_response.png');

fprintf('\n已导出文件：\n');
fprintf('1) interp2_wordlen_sparse_search_result.csv\n');
fprintf('2) interp2_wordlen_opt_summary.txt\n');
fprintf('3) interp2_coeff_decimal_wordlen_opt.txt\n');
fprintf('4) interp2_coeff_for_verilog_wordlen_opt.txt\n');
fprintf('5) interp2_coeff_half_decimal_wordlen_opt.txt\n');
fprintf('6) interp2_coeff_half_for_verilog_wordlen_opt.txt\n');
fprintf('7) interp2_wordlen_opt_response.png\n\n');

fprintf('RTL 建议参数：\n');
fprintf('    .COEFF_W(%d)\n', best_coeff_w);
fprintf('    .ACC_W  待结合 RTL 累加器扫描，一般可先尝试 48\n');
fprintf('    .FRAC_W (%d)\n', best_frac_w);


%% ============================================================
% 本地函数：检查单个输出采样率模式
% ============================================================
function res = check_one_mode(b, Fs_out, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft)

    Fs_in = Fs_out / 2;
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

    sym_err = max(abs(b(:).' - fliplr(b(:).')));
    pass_linear = (sym_err < 1e-10);

    pass_ripple = (ripple_pm_db <= ripple_pm_target_db);
    pass_stop   = (stop_attn_db >= stop_attn_target_db);

    res.ripple_pp_db = ripple_pp_db;
    res.ripple_pm_db = ripple_pm_db;
    res.stop_attn_db = stop_attn_db;
    res.pass_ripple  = pass_ripple;
    res.pass_stop    = pass_stop;
    res.pass_linear  = pass_linear;
    res.pass_all     = pass_ripple && pass_stop && pass_linear;
end


%% ============================================================
% 本地函数：详细打印单个模式检查结果
% ============================================================
function res = check_one_mode_verbose(b, Fs_out, f_pass_low, f_pass_high, stop_attn_target_db, ripple_pm_target_db, Nfft, mode_name)

    Fs_in = Fs_out / 2;
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
    idx_gd_pass = (f_gd >= f_pass_low) & (f_gd <= f_pass_high);
    gd_pass = gd(idx_gd_pass);
    gd_mean = mean(gd_pass);
    gd_pp   = max(gd_pass) - min(gd_pass);

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
        fprintf('结论：该模式满足 2x FIR 设计目标。\n');
    else
        fprintf('结论：该模式未完全满足 2x FIR 设计目标。\n');
    end

    res.ripple_pp_db = ripple_pp_db;
    res.ripple_pm_db = ripple_pm_db;
    res.stop_attn_db = stop_attn_db;
    res.gd_mean      = gd_mean;
    res.gd_pp        = gd_pp;
    res.pass_all     = pass_ripple && pass_stop && pass_linear;
end


%% ============================================================
% 本地函数：导出完整系数 Verilog 赋值语句
% ============================================================
function export_full_coeff_for_verilog(filename, coeff_int, coeff_w, frac_w, order_n, prune_thr, title_str)

    fid = fopen(filename, 'w');

    if fid == -1
        error('无法创建文件：%s', filename);
    end

    fprintf(fid, '// =====================================================\n');
    fprintf(fid, '// %s\n', title_str);
    fprintf(fid, '// 阶数 n   : %d\n', order_n);
    fprintf(fid, '// tap 数   : %d\n', order_n + 1);
    fprintf(fid, '// 系数位宽 : %d bit\n', coeff_w);
    fprintf(fid, '// 小数位宽 : %d bit\n', frac_w);
    fprintf(fid, '// 裁剪阈值 : %d\n', prune_thr);
    fprintf(fid, '// 系数总数 : %d\n', length(coeff_int));
    fprintf(fid, '// =====================================================\n');

    for k = 1:length(coeff_int)
        val = coeff_int(k);

        if val < 0
            fprintf(fid, '        coeff[%d] = -%d''sd%d;\n', k-1, coeff_w, abs(val));
        else
            fprintf(fid, '        coeff[%d] = %d''sd%d;\n', k-1, coeff_w, val);
        end
    end

    fclose(fid);
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
% 本地函数：绘制两个输出模式频响对比
% ============================================================
function plot_two_mode_response(b, Fs1, Fs2, f_pass_high, filename)

    Nfft_plot = 65536;

    [H1, f1] = freqz(b, 1, Nfft_plot, Fs1);
    [H2, f2] = freqz(b, 1, Nfft_plot, Fs2);

    mag1 = 20*log10(abs(H1) + eps);
    mag2 = 20*log10(abs(H2) + eps);

    figure;
    plot(f1/1000, mag1, 'LineWidth', 1.1);
    hold on;
    plot(f2/1000, mag2, 'LineWidth', 1.1);
    grid on;
    xlabel('Frequency (kHz)');
    ylabel('Magnitude (dB)');
    title('2x FIR Word-Length Optimized Frequency Response');
    legend(sprintf('Fs = %.1f kHz', Fs1/1000), sprintf('Fs = %.1f kHz', Fs2/1000), 'Location', 'best');
    xlim([0, max(Fs1, Fs2)/2000]);
    ylim([-120, 5]);

    xline(f_pass_high/1000, '--');

    saveas(gcf, filename);
end
