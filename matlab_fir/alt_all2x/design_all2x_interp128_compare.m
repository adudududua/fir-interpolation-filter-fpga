clc; clear; close all;

%=============================================================
% 文件名       : design_all2x_interp128_compare.m
% 脚本名       : design_all2x_interp128_compare
% 功能简述     : 全 2x 级联 128 倍插值 FIR 的 MATLAB 设计与对比脚本。
%                本脚本用于探索一种替代结构：
%                     2x * 2x * 2x * 2x * 2x * 2x * 2x = 128x
%                与当前主工程中的 4x + 5 个 2x 结构进行资源和指标对比。
%
%                设计目标：
%                  1. 完成 44.1kHz -> 5.6448MHz 的 128 倍插值链路设计；
%                  2. 每一级均采用 2x 线性相位 FIR 插值滤波器；
%                  3. 每一级根据当前采样率单独设计，尽量放宽后级 FIR 的过渡带；
%                  4. 对每一级进行 COEFF_W / FRAC_W 搜索与小系数裁剪搜索；
%                  5. 构造完整 128x 总冲激响应并验证：
%                       通带：10Hz ~ 20kHz
%                       总通带纹波：<= ±0.05dB
%                       总阻带衰减：>= 70dB
%                       严格线性相位
%
%                输出文件：
%                  all2x_stage_search_result.csv
%                  all2x_interp128_summary.txt
%                  all2x_interp128_response.png
%                  stageXX_2x_coeff_decimal.txt
%                  stageXX_2x_coeff_half_decimal.txt
%                  stageXX_2x_coeff_half_for_verilog.txt
%
% 当前默认配置：
%                  输入采样率    ：44.1kHz
%                  输出采样率    ：5.6448MHz
%                  级联结构      ：7 级 2x
%                  FRAC_W_LIST   ：[16 15 14 13 12]
%                  PRUNE_THR_LIST：[0 1 2 4 8 16]
%                  COEFF_W       ：FRAC_W + 2
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增全 2x 级联 128 倍插值结构探索脚本。
%=============================================================

%% 1) 基本设计目标参数
%=============================================================

FS_IN_BASE = 44100;
NUM_STAGE  = 7;
L_STAGE    = 2;
FS_OUT_FINAL = FS_IN_BASE * L_STAGE^NUM_STAGE;

f_pass_low  = 10;
f_pass_high = 20000;
f_stop_base = FS_IN_BASE - f_pass_high;  % 44.1k - 20k = 24.1kHz

total_ripple_target_db = 0.05;
total_stop_target_db   = 70;

% 分级指标：
% Stage 1 是最靠近 20 kHz 的第一镜像抑制级，过渡带最窄。
% 如果只让 Stage 1 刚好达到 70 dB，它的过渡带残留会在后续 2x
% 上采样中镜像到更高频处，导致总链路阻带峰值不足 70 dB。
% 因此 Stage 1 也要留出额外裕量，后级过渡带更宽，可以继续加严。
stage_ripple_pm_target_db_list = [0.008 0.006 0.005 0.004 0.004 0.004 0.004];
stage_stop_attn_target_db_list = [76.0  80.0  82.0  84.0  84.0  84.0  84.0];

FRAC_W_LIST    = [16 15 14 13 12];
PRUNE_THR_LIST = [0 1 2 4 8 16];

N_MAX = 360;
Nfft_stage = 131072;
Nfft_total = 262144;

script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir)
    script_dir = pwd;
end

% Plot style close to the requested yellow-green-blue-purple palette.
color_yellow = [0.82 0.88 0.02];
color_green  = [0.35 0.73 0.28];
color_teal   = [0.08 0.63 0.50];
color_cyan   = [0.09 0.48 0.56];
color_blue   = [0.16 0.34 0.56];
color_purple = [0.25 0.13 0.47];
font_name = 'Microsoft YaHei';

fprintf('====================================================\n');
fprintf('全 2x 级联 128 倍插值 FIR 结构探索开始\n');
fprintf('输入采样率 Fs_in        = %.1f Hz\n', FS_IN_BASE);
fprintf('输出采样率 Fs_out       = %.1f Hz\n', FS_OUT_FINAL);
fprintf('级联结构                = %d 级 2x\n', NUM_STAGE);
fprintf('总通带目标              = %.1f Hz ~ %.1f Hz\n', f_pass_low, f_pass_high);
fprintf('总通带 ±纹波目标        = %.4f dB\n', total_ripple_target_db);
fprintf('总阻带衰减目标          = %.1f dB\n', total_stop_target_db);
fprintf('单级通带 ±纹波目标列表  = [%s] dB\n', num2str(stage_ripple_pm_target_db_list));
fprintf('单级阻带衰减目标列表    = [%s] dB\n', num2str(stage_stop_attn_target_db_list));
fprintf('FRAC_W_LIST             = [%s]\n', num2str(FRAC_W_LIST));
fprintf('PRUNE_THR_LIST          = [%s]\n', num2str(PRUNE_THR_LIST));
fprintf('====================================================\n\n');

%% 2) 逐级设计 7 个 2x FIR
%=============================================================

stage_result = struct([]);
stage_search_table = [];

for stage_idx = 1:NUM_STAGE
    Fs_in_stage  = FS_IN_BASE * L_STAGE^(stage_idx - 1);
    Fs_out_stage = Fs_in_stage * L_STAGE;

    if stage_idx == 1
        f_stop_begin = f_stop_base;
    else
        f_stop_begin = Fs_in_stage - f_stop_base;
    end

    stage_ripple_pm_target_db = stage_ripple_pm_target_db_list(stage_idx);
    stage_stop_attn_target_db = stage_stop_attn_target_db_list(stage_idx);

    fprintf('\n====================================================\n');
    fprintf('开始设计 Stage %d: %.1f Hz -> %.1f Hz\n', ...
            stage_idx, Fs_in_stage, Fs_out_stage);
    fprintf('阻带起始频率 = %.1f Hz\n', f_stop_begin);
    fprintf('本级通带 ±纹波目标 = %.4f dB\n', stage_ripple_pm_target_db);
    fprintf('本级阻带衰减目标   = %.1f dB\n', stage_stop_attn_target_db);

    [one_stage, one_table] = design_one_2x_stage( ...
        stage_idx, ...
        Fs_in_stage, ...
        Fs_out_stage, ...
        f_pass_low, ...
        f_pass_high, ...
        f_stop_begin, ...
        stage_ripple_pm_target_db, ...
        stage_stop_attn_target_db, ...
        FRAC_W_LIST, ...
        PRUNE_THR_LIST, ...
        N_MAX, ...
        Nfft_stage);

    stage_result(stage_idx).stage_idx        = stage_idx;
    stage_result(stage_idx).Fs_in            = Fs_in_stage;
    stage_result(stage_idx).Fs_out           = Fs_out_stage;
    stage_result(stage_idx).f_stop_begin     = f_stop_begin;
    stage_result(stage_idx).target_ripple_pm = stage_ripple_pm_target_db;
    stage_result(stage_idx).target_stop_attn = stage_stop_attn_target_db;
    stage_result(stage_idx).order_n          = one_stage.order_n;
    stage_result(stage_idx).taps             = one_stage.taps;
    stage_result(stage_idx).coeff_w          = one_stage.coeff_w;
    stage_result(stage_idx).frac_w           = one_stage.frac_w;
    stage_result(stage_idx).prune_thr        = one_stage.prune_thr;
    stage_result(stage_idx).coeff_int        = one_stage.coeff_int;
    stage_result(stage_idx).b                = one_stage.b;
    stage_result(stage_idx).nonzero_full     = one_stage.nonzero_full;
    stage_result(stage_idx).nonzero_half     = one_stage.nonzero_half;
    stage_result(stage_idx).pass_gain_db     = one_stage.res.pass_gain_db;
    stage_result(stage_idx).ripple_pm_db     = one_stage.res.ripple_pm_db;
    stage_result(stage_idx).stop_attn_db     = one_stage.res.stop_attn_db;
    stage_result(stage_idx).gd_mean          = one_stage.res.gd_mean;
    stage_result(stage_idx).gd_pp            = one_stage.res.gd_pp;
    stage_result(stage_idx).pass_all         = one_stage.res.pass_all;

    stage_search_table = [stage_search_table; one_table];

    export_stage_coefficients(script_dir, stage_result(stage_idx));
end

%% 3) 导出逐级搜索表
%=============================================================

stage_csv = fullfile(script_dir, 'all2x_stage_search_result.csv');
fid = fopen(stage_csv, 'w');
fprintf(fid, ['STAGE,FS_IN,FS_OUT,FRAC_W,COEFF_W,PRUNE_THR,ORDER_N,TAPS,' ...
              'PASS_GAIN_DB,RIPPLE_PM_DB,STOP_ATTN_DB,GD_MEAN,GD_PP,' ...
              'NONZERO_FULL,NONZERO_HALF,PASS_ALL\n']);
for i = 1:size(stage_search_table, 1)
    fprintf(fid, '%d,%.1f,%.1f,%d,%d,%d,%d,%d,%.8f,%.8f,%.8f,%.8f,%.12f,%d,%d,%d\n', ...
        stage_search_table(i, :));
end
fclose(fid);

%% 4) 构造完整 128x 总冲激响应
%=============================================================

h_total = stage_result(1).b(:).';

fprintf('\n逐级构造全 2x 的 128x 总链路：\n');
fprintf('Stage 1 : 2x -> 总冲激响应长度 = %d tap\n', length(h_total));

for stage_idx = 2:NUM_STAGE
    h_up = upsample(h_total, 2);
    h_up = h_up(1:end-1);
    h_total = conv(h_up, stage_result(stage_idx).b(:).');

    fprintf('Stage %d : 再接 1 个 2x -> 总冲激响应长度 = %d tap\n', ...
            stage_idx, length(h_total));
end

%% 5) 检查完整 128x 链路
%=============================================================

total_res = check_total_chain( ...
    h_total, ...
    FS_IN_BASE, ...
    FS_OUT_FINAL, ...
    f_pass_low, ...
    f_pass_high, ...
    total_ripple_target_db, ...
    total_stop_target_db, ...
    Nfft_total);

nonzero_half_total = 0;
for stage_idx = 1:NUM_STAGE
    nonzero_half_total = nonzero_half_total + stage_result(stage_idx).nonzero_half;
end

fprintf('\n================ 全 2x 结构总链路检查结果 ================\n');
fprintf('总冲激响应长度                 = %d tap\n', length(h_total));
fprintf('总冲激响应最大对称误差         = %.12g\n', total_res.sym_err);
fprintf('估算非零半系数总数             = %d\n', nonzero_half_total);
fprintf('总通带峰峰纹波                 = %.8f dB\n', total_res.ripple_pp_db);
fprintf('总通带 ±纹波                   = %.8f dB\n', total_res.ripple_pm_db);
fprintf('总通带平均增益                 = %.8f dB\n', total_res.pass_gain_db);
fprintf('总阻带起始频率                 = %.1f Hz\n', total_res.f_stop_begin);
fprintf('总阻带衰减                     = %.8f dB\n', total_res.stop_attn_db);
fprintf('总通带平均群延迟               = %.8f 个最终采样点\n', total_res.gd_mean);
fprintf('总通带群延迟波动               = %.12f 个最终采样点\n', total_res.gd_pp);
fprintf('总通带纹波判定                 = %d\n', total_res.pass_ripple);
fprintf('总通带增益判定                 = %d\n', total_res.pass_gain);
fprintf('总阻带衰减判定                 = %d\n', total_res.pass_stop);
fprintf('总线性相位判定                 = %d\n', total_res.pass_linear);
fprintf('总链路通过判定                 = %d\n', total_res.pass_all);

%% 6) 导出汇总文件与总频响图
%=============================================================

summary_path = fullfile(script_dir, 'all2x_interp128_summary.txt');
fid = fopen(summary_path, 'w');

fprintf(fid, 'All-2x 128x interpolation FIR summary\n');
fprintf(fid, '=====================================\n');
fprintf(fid, 'Input sample rate              = %.1f Hz\n', FS_IN_BASE);
fprintf(fid, 'Output sample rate             = %.1f Hz\n', FS_OUT_FINAL);
fprintf(fid, 'Number of 2x stages            = %d\n', NUM_STAGE);
fprintf(fid, 'Total impulse response taps    = %d\n', length(h_total));
fprintf(fid, 'Total nonzero half coefficients= %d\n', nonzero_half_total);
fprintf(fid, 'Total ripple_pm_db             = %.8f\n', total_res.ripple_pm_db);
fprintf(fid, 'Total ripple_pp_db             = %.8f\n', total_res.ripple_pp_db);
fprintf(fid, 'Total pass_gain_db             = %.8f\n', total_res.pass_gain_db);
fprintf(fid, 'Total stop_attn_db             = %.8f\n', total_res.stop_attn_db);
fprintf(fid, 'Total gd_mean                  = %.8f\n', total_res.gd_mean);
fprintf(fid, 'Total gd_pp                    = %.12f\n', total_res.gd_pp);
fprintf(fid, 'Total symmetry error           = %.12g\n', total_res.sym_err);
fprintf(fid, 'Pass ripple                    = %d\n', total_res.pass_ripple);
fprintf(fid, 'Pass gain                      = %d\n', total_res.pass_gain);
fprintf(fid, 'Pass stop                      = %d\n', total_res.pass_stop);
fprintf(fid, 'Pass linear phase              = %d\n', total_res.pass_linear);
fprintf(fid, 'Pass all                       = %d\n\n', total_res.pass_all);

if ~total_res.pass_stop
    fprintf(fid, ['Note: total stopband failed even though each stage may pass its own target.\n' ...
                  'This can happen because early-stage transition-band residue is mirrored\n' ...
                  'by later 2x upsampling stages. Tighten early-stage targets and rerun.\n\n']);
end

fprintf(fid, 'Stage detail\n');
fprintf(fid, '------------\n');
for stage_idx = 1:NUM_STAGE
    r = stage_result(stage_idx);
    fprintf(fid, ['Stage %d: Fs %.1f -> %.1f Hz, f_stop=%.1f Hz, order=%d, taps=%d, ' ...
                  'COEFF_W=%d, FRAC_W=%d, prune=%d, nz_half=%d, ' ...
                  'target_ripple=%.4f dB, target_stop=%.1f dB, ' ...
                  'gain=%.8f dB, ripple_pm=%.8f dB, stop=%.8f dB\n'], ...
                  r.stage_idx, r.Fs_in, r.Fs_out, r.f_stop_begin, r.order_n, r.taps, ...
                  r.coeff_w, r.frac_w, r.prune_thr, r.nonzero_half, ...
                  r.target_ripple_pm, r.target_stop_attn, ...
                  r.pass_gain_db, r.ripple_pm_db, r.stop_attn_db);
end
fclose(fid);

png_path = fullfile(script_dir, 'all2x_interp128_response.png');
plot_total_response(h_total, total_res, FS_IN_BASE, FS_OUT_FINAL, ...
                    f_pass_low, f_pass_high, total_stop_target_db, ...
                    Nfft_total, png_path, ...
                    color_yellow, color_green, color_teal, color_cyan, ...
                    color_blue, color_purple, font_name);

fprintf('\n已导出文件：\n');
fprintf('1) %s\n', stage_csv);
fprintf('2) %s\n', summary_path);
fprintf('3) %s\n', png_path);
fprintf('4) stageXX_2x_coeff_*.txt\n\n');


%% ============================================================
% 本地函数：设计单级 2x FIR
% ============================================================
function [best, result_table] = design_one_2x_stage(stage_idx, Fs_in, Fs_out, ...
                                                    f_pass_low, f_pass_high, ...
                                                    f_stop_begin, ...
                                                    ripple_pm_target_db, ...
                                                    stop_attn_target_db, ...
                                                    frac_w_list, prune_thr_list, ...
                                                    n_max, nfft)

    if f_stop_begin <= f_pass_high
        error('Stage %d 的过渡带不存在，请检查 Fs_in 与通带上限。', stage_idx);
    end

    delta_p = (10^(ripple_pm_target_db/20) - 1) / ...
              (10^(ripple_pm_target_db/20) + 1);
    delta_s = 10^(-stop_attn_target_db/20);

    [n_est, fo, ao, w] = firpmord([f_pass_high f_stop_begin], ...
                                  [1 0], ...
                                  [delta_p delta_s], ...
                                  Fs_out);

    if mod(n_est, 2) ~= 0
        n_est = n_est + 1;
    end

    n_max_stage = max(n_max, n_est + 80);

    fprintf('firpmord 估计阶数 n_est = %d，对应 tap 数 = %d\n', n_est, n_est + 1);

    found = false;
    result_table = [];

    best.order_n      = -1;
    best.taps         = -1;
    best.coeff_w      = -1;
    best.frac_w       = -1;
    best.prune_thr    = -1;
    best.coeff_int    = [];
    best.b            = [];
    best.nonzero_full = inf;
    best.nonzero_half = inf;
    best.res          = [];

    for frac_w_try = frac_w_list
        coeff_w_try = frac_w_try + 2;
        coeff_max =  2^(coeff_w_try - 1) - 1;
        coeff_min = -2^(coeff_w_try - 1);

        for prune_thr = prune_thr_list
            combo_found = false;

            for n = n_est : 2 : n_max_stage
                try
                    b_float = firpm(n, fo, ao, w);
                catch
                    continue;
                end

                coeff_int = round(b_float * 2^frac_w_try);

                if max(coeff_int) > coeff_max || min(coeff_int) < coeff_min
                    continue;
                end

                coeff_int_pruned = coeff_int;
                coeff_int_pruned(abs(coeff_int_pruned) <= prune_thr) = 0;

                b_q = coeff_int_pruned / 2^frac_w_try;

                res = check_one_stage(b_q, Fs_out, f_pass_low, f_pass_high, f_stop_begin, ...
                                      stop_attn_target_db, ripple_pm_target_db, nfft);

                coeff_int_col = coeff_int_pruned(:);
                nonzero_full = nnz(coeff_int_col);
                half_taps = (length(coeff_int_col) - 1) / 2;
                coeff_half = coeff_int_col(1:half_taps + 1);
                nonzero_half = nnz(coeff_half);

                pass_all = res.pass_all;

                result_table = [result_table; ...
                    stage_idx, Fs_in, Fs_out, frac_w_try, coeff_w_try, ...
                    prune_thr, n, n+1, res.pass_gain_db, res.ripple_pm_db, res.stop_attn_db, ...
                    res.gd_mean, res.gd_pp, nonzero_full, nonzero_half, pass_all];

                fprintf(['Stage=%d FRAC=%2d COEFF=%2d prune=%2d n=%3d tap=%3d | ' ...
                         'nz_half=%3d | gain=%.4f ripple=%.6f stop=%.3f pass=%d\n'], ...
                        stage_idx, frac_w_try, coeff_w_try, prune_thr, n, n+1, ...
                        nonzero_half, res.pass_gain_db, res.ripple_pm_db, res.stop_attn_db, pass_all);

                if pass_all
                    combo_found = true;

                    update_best = false;
                    if ~found
                        update_best = true;
                    elseif nonzero_half < best.nonzero_half
                        update_best = true;
                    elseif nonzero_half == best.nonzero_half && coeff_w_try < best.coeff_w
                        update_best = true;
                    elseif nonzero_half == best.nonzero_half && coeff_w_try == best.coeff_w && n < best.order_n
                        update_best = true;
                    elseif nonzero_half == best.nonzero_half && coeff_w_try == best.coeff_w && ...
                           n == best.order_n && prune_thr < best.prune_thr
                        update_best = true;
                    end

                    if update_best
                        found = true;
                        best.order_n      = n;
                        best.taps         = n + 1;
                        best.coeff_w      = coeff_w_try;
                        best.frac_w       = frac_w_try;
                        best.prune_thr    = prune_thr;
                        best.coeff_int    = coeff_int_col;
                        best.b            = b_q(:).';
                        best.nonzero_full = nonzero_full;
                        best.nonzero_half = nonzero_half;
                        best.res          = res;
                    end

                    break;
                end
            end

            if ~combo_found
                fprintf('Stage=%d FRAC=%2d COEFF=%2d prune=%2d 在 n<=%d 内未满足指标。\n', ...
                        stage_idx, frac_w_try, coeff_w_try, prune_thr, n_max_stage);
            end
        end
    end

    if ~found
        error('Stage %d 未找到满足指标的 2x FIR，请放宽字长或提高 N_MAX。', stage_idx);
    end

    fprintf(['Stage %d 最优结果：order=%d taps=%d COEFF_W=%d FRAC_W=%d ' ...
             'prune=%d nz_half=%d gain=%.8f dB ripple=%.8f dB stop=%.8f dB\n'], ...
             stage_idx, best.order_n, best.taps, best.coeff_w, best.frac_w, ...
             best.prune_thr, best.nonzero_half, ...
             best.res.pass_gain_db, best.res.ripple_pm_db, best.res.stop_attn_db);
end


%% ============================================================
% 本地函数：检查单级 2x FIR
% ============================================================
function res = check_one_stage(b, Fs_out, f_pass_low, f_pass_high, f_stop_begin, ...
                               stop_attn_target_db, ripple_pm_target_db, nfft)

    [H, f] = freqz(b, 1, nfft, Fs_out);
    mag_db = 20*log10(abs(H) + eps);

    idx_pass = (f >= f_pass_low) & (f <= f_pass_high);
    idx_stop = (f >= f_stop_begin) & (f <= Fs_out/2);

    pass_db = mag_db(idx_pass);
    stop_db = mag_db(idx_stop);

    pass_gain_db = mean(pass_db);
    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = ripple_pp_db / 2;
    stop_attn_db = -max(stop_db);

    [gd, f_gd] = grpdelay(b, 1, nfft, Fs_out);
    idx_gd_pass = (f_gd >= f_pass_low) & (f_gd <= f_pass_high);
    gd_pass = gd(idx_gd_pass);
    gd_mean = mean(gd_pass);
    gd_pp = max(gd_pass) - min(gd_pass);

    sym_err = max(abs(b(:).' - fliplr(b(:).')));

    pass_ripple = (ripple_pm_db <= ripple_pm_target_db);
    pass_gain   = (abs(pass_gain_db) <= max(0.02, 2*ripple_pm_target_db));
    pass_stop   = (stop_attn_db >= stop_attn_target_db);
    pass_linear = (sym_err < 1e-10) && (gd_pp < 1e-6);

    res.pass_gain_db = pass_gain_db;
    res.ripple_pp_db = ripple_pp_db;
    res.ripple_pm_db = ripple_pm_db;
    res.stop_attn_db = stop_attn_db;
    res.gd_mean      = gd_mean;
    res.gd_pp        = gd_pp;
    res.sym_err      = sym_err;
    res.pass_gain    = pass_gain;
    res.pass_ripple  = pass_ripple;
    res.pass_stop    = pass_stop;
    res.pass_linear  = pass_linear;
    res.pass_all     = pass_gain && pass_ripple && pass_stop && pass_linear;
end


%% ============================================================
% 本地函数：检查完整 128x 总链路
% ============================================================
function res = check_total_chain(h_total, Fs_in, Fs_out, ...
                                 f_pass_low, f_pass_high, ...
                                 ripple_target_db, stop_target_db, nfft)

    f_stop_begin = Fs_in - f_pass_high;

    [H, f] = freqz(h_total, 1, nfft, Fs_out);
    H_db = 20*log10(abs(H) + 1e-15);

    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= Fs_out/2);

    pass_db = H_db(pass_idx);
    stop_db = H_db(stop_idx);

    pass_gain_db = mean(pass_db);
    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = max(abs(pass_db - pass_gain_db));
    stop_attn_db = -max(stop_db);

    [gd, fg] = grpdelay(h_total, 1, nfft, Fs_out);
    gd_idx = (fg >= f_pass_low) & (fg <= f_pass_high);
    gd_pass = gd(gd_idx);
    gd_mean = mean(gd_pass);
    gd_pp = max(gd_pass) - min(gd_pass);

    sym_err = max(abs(h_total(:).' - fliplr(h_total(:).')));

    pass_ripple = (ripple_pm_db <= ripple_target_db);
    pass_gain   = (abs(pass_gain_db) <= ripple_target_db);
    pass_stop   = (stop_attn_db >= stop_target_db);
    pass_linear = (sym_err < 1e-10) && (gd_pp < 1e-6);

    res.f_stop_begin = f_stop_begin;
    res.pass_gain_db = pass_gain_db;
    res.ripple_pp_db = ripple_pp_db;
    res.ripple_pm_db = ripple_pm_db;
    res.stop_attn_db = stop_attn_db;
    res.gd_mean      = gd_mean;
    res.gd_pp        = gd_pp;
    res.sym_err      = sym_err;
    res.pass_gain    = pass_gain;
    res.pass_ripple  = pass_ripple;
    res.pass_stop    = pass_stop;
    res.pass_linear  = pass_linear;
    res.pass_all     = pass_gain && pass_ripple && pass_stop && pass_linear;
end


%% ============================================================
% 本地函数：导出单级系数
% ============================================================
function export_stage_coefficients(script_dir, stage)

    prefix = sprintf('stage%02d_2x', stage.stage_idx);

    coeff_decimal_path = fullfile(script_dir, [prefix '_coeff_decimal.txt']);
    coeff_half_path = fullfile(script_dir, [prefix '_coeff_half_decimal.txt']);
    coeff_half_verilog_path = fullfile(script_dir, [prefix '_coeff_half_for_verilog.txt']);

    coeff_int = stage.coeff_int(:);
    half_taps = (length(coeff_int) - 1) / 2;
    coeff_half_int = coeff_int(1:half_taps + 1);

    writematrix(coeff_int, coeff_decimal_path, 'Delimiter', 'tab');
    writematrix(coeff_half_int, coeff_half_path, 'Delimiter', 'tab');

    title_str = sprintf('All-2x Stage %d FIR half coefficients', stage.stage_idx);
    export_half_coeff_for_verilog(coeff_half_verilog_path, ...
                                  coeff_half_int, ...
                                  stage.coeff_w, ...
                                  stage.frac_w, ...
                                  stage.order_n, ...
                                  stage.prune_thr, ...
                                  title_str);
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
    fprintf(fid, '// 阶数 n       : %d\n', order_n);
    fprintf(fid, '// tap 数       : %d\n', order_n + 1);
    fprintf(fid, '// 系数位宽     : %d bit\n', coeff_w);
    fprintf(fid, '// 小数位宽     : %d bit\n', frac_w);
    fprintf(fid, '// 裁剪阈值     : %d\n', prune_thr);
    fprintf(fid, '// 半系数总数   : %d\n', length(coeff_half_int));
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
% 本地函数：绘制完整 128x 总响应
% ============================================================
function plot_total_response(h_total, total_res, Fs_in, Fs_out, ...
                             f_pass_low, f_pass_high, stop_target_db, ...
                             nfft, filename, ...
                             color_yellow, color_green, color_teal, color_cyan, ...
                             color_blue, color_purple, font_name)

    axis_font_size = 11;
    label_font_size = 13;
    title_font_size = 12;

    [H, f] = freqz(h_total, 1, nfft, Fs_out);
    H_db = 20*log10(abs(H) + 1e-15);

    [gd, fg] = grpdelay(h_total, 1, nfft, Fs_out);

    pass_idx_plot = (f >= f_pass_low) & (f <= f_pass_high);
    pass_mean_db = mean(H_db(pass_idx_plot));
    H_db_rel = H_db - pass_mean_db;

    gd_idx_plot = (fg >= f_pass_low) & (fg <= f_pass_high);
    gd_mean_plot = mean(gd(gd_idx_plot));
    gd_dev = gd - gd_mean_plot;
    gd_dev_pass = gd_dev(gd_idx_plot);

    fig = figure( ...
        'Color', 'w', ...
        'Name', 'All-2x 128x interpolation response', ...
        'Units', 'pixels', ...
        'Position', [80 80 1280 820]);

    set(fig, 'PaperPositionMode', 'auto');

    subplot(2,2,1);
    plot(f/1000, H_db_rel, 'Color', color_purple, 'LineWidth', 1.8); grid on; box on;
    xlabel('频率 / kHz', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', label_font_size);
    ylabel('相对幅度 / dB', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', label_font_size);
    title('全 2x 结构通带细节', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', title_font_size);
    xlim([0 22]);
    ylim([-0.08 0.08]);
    yline(0.05, '--', 'Color', color_yellow, 'LineWidth', 1.2);
    yline(-0.05, '--', 'Color', color_yellow, 'LineWidth', 1.2);
    xline(f_pass_high/1000, '--', 'Color', color_teal, 'LineWidth', 1.2);
    legend('通带响应', '+0.05 dB', '-0.05 dB', '20 kHz', ...
        'Location', 'southwest', 'Box', 'off', 'FontName', font_name, ...
        'FontWeight', 'bold', 'FontSize', 9);
    ax = gca;
    set(ax, 'FontName', font_name, 'FontSize', axis_font_size, 'FontWeight', 'bold', ...
        'LineWidth', 1.3, 'XColor', 'k', 'YColor', 'k', 'TickDir', 'in', ...
        'XMinorTick', 'on', 'YMinorTick', 'on', 'GridAlpha', 0.18);
    set_mid_minor_ticks(ax);

    subplot(2,2,2);
    plot(f/1000, H_db, 'Color', color_blue, 'LineWidth', 1.7); grid on; box on;
    xlabel('频率 / kHz', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', label_font_size);
    ylabel('幅度 / dB', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', label_font_size);
    title('通带到阻带入口', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', title_font_size);
    xlim([0 80]);
    ylim([-120 5]);
    xline(f_pass_high/1000, '--', 'Color', color_green, 'LineWidth', 1.2);
    xline(total_res.f_stop_begin/1000, '--', 'Color', color_purple, 'LineWidth', 1.2);
    yline(-stop_target_db, '--', 'Color', color_yellow, 'LineWidth', 1.2);
    legend('频率响应', '20 kHz', '阻带起点', '-70 dB', ...
        'Location', 'southwest', 'Box', 'off', 'FontName', font_name, ...
        'FontWeight', 'bold', 'FontSize', 9);
    ax = gca;
    set(ax, 'FontName', font_name, 'FontSize', axis_font_size, 'FontWeight', 'bold', ...
        'LineWidth', 1.3, 'XColor', 'k', 'YColor', 'k', 'TickDir', 'in', ...
        'XMinorTick', 'on', 'YMinorTick', 'on', 'GridAlpha', 0.18);
    set_mid_minor_ticks(ax);

    subplot(2,2,3);
    plot(f/1e6, H_db, 'Color', color_cyan, 'LineWidth', 1.6); grid on; box on;
    xlabel('频率 / MHz', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', label_font_size);
    ylabel('幅度 / dB', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', label_font_size);
    title('全频段响应', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', title_font_size);
    xlim([0 Fs_out/2/1e6]);
    ylim([-160 5]);
    yline(-stop_target_db, '--', 'Color', color_yellow, 'LineWidth', 1.2);
    ax = gca;
    set(ax, 'FontName', font_name, 'FontSize', axis_font_size, 'FontWeight', 'bold', ...
        'LineWidth', 1.3, 'XColor', 'k', 'YColor', 'k', 'TickDir', 'in', ...
        'XMinorTick', 'on', 'YMinorTick', 'on', 'GridAlpha', 0.18);
    set_mid_minor_ticks(ax);

    subplot(2,2,4);
    plot(fg(gd_idx_plot)/1000, gd_dev_pass, 'Color', color_purple, 'LineWidth', 1.7); grid on; box on;
    xlabel('频率 / kHz', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', label_font_size);
    ylabel('群延迟偏差 / 样点', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', label_font_size);
    title('通带群延迟平坦度', 'FontName', font_name, 'FontWeight', 'bold', 'FontSize', title_font_size);
    xlim([0 22]);
    ylim([-1e-9 1e-9]);
    yline(0, '-', 'Color', color_yellow, 'LineWidth', 1.1);
    xline(f_pass_high/1000, '--', 'Color', color_teal, 'LineWidth', 1.2);
    text(0.05, 0.90, sprintf('max |\\Delta\\tau| = %.2e samples', max(abs(gd_dev_pass))), ...
        'Units', 'normalized', 'FontName', font_name, 'FontWeight', 'bold', ...
        'FontSize', 9, 'Color', color_purple);
    ax = gca;
    set(ax, 'FontName', font_name, 'FontSize', axis_font_size, 'FontWeight', 'bold', ...
        'LineWidth', 1.3, 'XColor', 'k', 'YColor', 'k', 'TickDir', 'in', ...
        'XMinorTick', 'on', 'YMinorTick', 'on', 'GridAlpha', 0.18);
    set_mid_minor_ticks(ax);

    print(fig, filename, '-dpng', '-r200');
end


%% ============================================================
% 本地函数：设置每两个主刻度之间 1 个辅刻度
% ============================================================
function set_mid_minor_ticks(ax)
    try
        ax.XMinorTick = 'on';
        ax.YMinorTick = 'on';

        if isprop(ax.XAxis, 'MinorTickValues')
            ax.XAxis.MinorTickValues = midpoint_ticks(ax.XTick, ax.XLim);
        end

        if isprop(ax.YAxis, 'MinorTickValues')
            ax.YAxis.MinorTickValues = midpoint_ticks(ax.YTick, ax.YLim);
        end
    catch
        ax.XMinorTick = 'off';
        ax.YMinorTick = 'off';
    end
end


%% ============================================================
% 本地函数：计算主刻度中点
% ============================================================
function ticks_minor = midpoint_ticks(ticks_major, axis_lim)
    ticks_major = ticks_major(:).';
    ticks_major = ticks_major(ticks_major >= axis_lim(1) & ticks_major <= axis_lim(2));

    if numel(ticks_major) < 2
        ticks_minor = [];
        return;
    end

    ticks_minor = (ticks_major(1:end-1) + ticks_major(2:end)) / 2;
    ticks_minor = ticks_minor(ticks_minor > axis_lim(1) & ticks_minor < axis_lim(2));
end
