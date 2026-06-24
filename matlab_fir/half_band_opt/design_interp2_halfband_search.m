%=============================================================
% 文件名       : design_interp2_halfband_search.m
% 功能简述     : 后级 2x 插值 FIR 半带滤波器搜索脚本
%
% 目标：
%   在保持完整 4x / 8x / 128x 可切换系统结构不变的前提下，
%   尝试把后级普通 2x FIR 改成 halfband FIR。
%
% 设计约束：
%   输入数据       : 24 bit signed
%   后级 2x FIR   : COEFF_W = 14, FRAC_W = 12
%   通带           : 10 Hz ~ 20 kHz
%   通带纹波       : <= ±0.05 dB
%   阻带衰减       : >= 70 dB
%
% 验证模式：
%   1) 176.4 kHz -> 352.8 kHz
%   2) 192.0 kHz -> 384.0 kHz
%
% 注意：
%   这个脚本只做 MATLAB 搜索，不改 RTL。
%   只有当搜索结果满足指标后，才考虑生成 Verilog 系数并修改
%   fir_core_symm_interp2.v 或对应的 2x FIR 系数表。
%
% 作者         : kafeizizi
% 修改建议     : ChatGPT
% 日期         : 2026-06-24
%=============================================================

clear; clc; close all;

%%============================================================
% 1. 基本规格设置
%=============================================================

% 通带与指标
F_PASS_LOW  = 10;        % Hz
F_PASS_HIGH = 20e3;      % Hz
PASS_RIPPLE_LIMIT_PM_DB = 0.05;  % ±0.05 dB
STOP_ATT_LIMIT_DB       = 70;    % >=70 dB

% 两种后级 2x 模式
% Fs_in  -> Fs_out
MODE_NAME = { ...
    '176.4k_to_352.8k', ...
    '192k_to_384k' ...
};

FS_IN_LIST  = [176.4e3, 192e3];
FS_OUT_LIST = [352.8e3, 384e3];

% 定点量化设置：14bit Q12
COEFF_W = 14;
FRAC_W  = 12;
Q_SCALE = 2^FRAC_W;

% 14bit signed 范围
Q_MIN = -2^(COEFF_W-1);
Q_MAX =  2^(COEFF_W-1) - 1;

% halfband FIR tap 数搜索
% 注意：halfband FIR 需要奇数 tap 数，中心抽头位于正中间
NTAPS_LIST = [29 27 25 23 21 19 17 15 13 11 9 7];

% Kaiser beta 搜索范围
% beta 越大，阻带通常越好，但量化后不一定单调
BETA_LIST = 3.0 : 0.25 : 14.0;

% 频响 FFT 点数
NFFT = 262144;

fprintf('=============================================================\n');
fprintf('2x Halfband FIR 搜索开始\n');
fprintf('COEFF_W = %d, FRAC_W = %d, Q_SCALE = %d\n', COEFF_W, FRAC_W, Q_SCALE);
fprintf('通带：%.1f Hz ~ %.1f Hz\n', F_PASS_LOW, F_PASS_HIGH);
fprintf('通带 ±纹波目标：%.4f dB\n', PASS_RIPPLE_LIMIT_PM_DB);
fprintf('阻带衰减目标：%.1f dB\n', STOP_ATT_LIMIT_DB);
fprintf('NTAPS_LIST = ');
fprintf('%d ', NTAPS_LIST);
fprintf('\n');
fprintf('BETA_LIST = %.2f : %.2f : %.2f\n', BETA_LIST(1), BETA_LIST(2)-BETA_LIST(1), BETA_LIST(end));
fprintf('=============================================================\n\n');

%%============================================================
% 2. 搜索 halfband FIR
%=============================================================

result = struct([]);
result_idx = 0;

best_found = false;
best_score = inf;
best = struct();

for nt = 1:length(NTAPS_LIST)

    NTAPS = NTAPS_LIST(nt);

    % 中心点
    MID = (NTAPS - 1) / 2;

    for ib = 1:length(BETA_LIST)

        beta = BETA_LIST(ib);

        %-----------------------------------------------------
        % 2.1 设计浮点 halfband FIR
        %
        % 标准 halfband 低通的截止角频率为 pi/2。
        % 理想低通：
        %   h[n] = 0.5 * sinc(0.5*(n-M))
        %
        % 这里采用 DC gain = 1 的归一化形式。
        %-----------------------------------------------------
        h_float = design_halfband_kaiser(NTAPS, beta);

        %-----------------------------------------------------
        % 2.2 Q12 量化
        %
        % 量化后强制 halfband 的理论零系数保持为 0。
        % 最后调节中心抽头，使整数系数总和严格等于 Q_SCALE，
        % 也就是 DC gain = 1。
        %-----------------------------------------------------
        h_q_int = quantize_halfband_q(h_float, FRAC_W, COEFF_W);

        % 若量化溢出，直接跳过
        if any(h_q_int < Q_MIN) || any(h_q_int > Q_MAX)
            continue;
        end

        h_q = double(h_q_int) / Q_SCALE;

        % 统计非零系数
        nz_full = nnz(h_q_int);
        nz_half = nnz(h_q_int(1:MID+1));

        % halfband 理论零系数检查
        zero_err = check_halfband_zero_error(h_q_int);

        % 系数对称性检查
        sym_err = max(abs(h_q_int - fliplr(h_q_int)));

        %-----------------------------------------------------
        % 2.3 两种模式频响验证
        %-----------------------------------------------------
        pass_all = true;

        mode_eval = struct([]);

        for im = 1:length(FS_OUT_LIST)

            Fs_out = FS_OUT_LIST(im);

            % 对于 2x 插值，镜像阻带起始可取：
            %   f_stop = Fs_in - 20k = Fs_out/2 - 20k
            f_stop = Fs_out/2 - F_PASS_HIGH;

            eval_info = eval_fir_response( ...
                h_q, ...
                Fs_out, ...
                F_PASS_LOW, ...
                F_PASS_HIGH, ...
                f_stop, ...
                NFFT ...
            );

            mode_eval(im).Fs_out             = Fs_out;
            mode_eval(im).f_stop             = f_stop;
            mode_eval(im).pass_ripple_pp_db  = eval_info.pass_ripple_pp_db;
            mode_eval(im).pass_ripple_pm_db  = eval_info.pass_ripple_pm_db;
            mode_eval(im).stop_att_db        = eval_info.stop_att_db;
            mode_eval(im).pass_min_db        = eval_info.pass_min_db;
            mode_eval(im).pass_max_db        = eval_info.pass_max_db;
            mode_eval(im).ok                 = eval_info.ok;

            if ~eval_info.ok
                pass_all = false;
            end
        end

        %-----------------------------------------------------
        % 2.4 记录结果
        %-----------------------------------------------------
        result_idx = result_idx + 1;

        result(result_idx).NTAPS = NTAPS;
        result(result_idx).beta = beta;
        result(result_idx).nz_full = nz_full;
        result(result_idx).nz_half = nz_half;
        result(result_idx).zero_err = zero_err;
        result(result_idx).sym_err = sym_err;
        result(result_idx).pass_all = pass_all;
        result(result_idx).h_q_int = h_q_int;
        result(result_idx).h_q = h_q;
        result(result_idx).mode_eval = mode_eval;

        fprintf('NTAPS=%2d beta=%5.2f | nz_full=%2d/%2d nz_half=%2d/%2d | mode1=%d mode2=%d\n', ...
            NTAPS, beta, ...
            nz_full, NTAPS, nz_half, MID+1, ...
            mode_eval(1).ok, mode_eval(2).ok);

        %-----------------------------------------------------
        % 2.5 选择最佳结果
        %
        % 优先级：
        %   1) 必须两种模式都满足指标；
        %   2) 非零完整系数越少越好；
        %   3) tap 数越少越好；
        %   4) 阻带裕量越大越好。
        %-----------------------------------------------------
        if pass_all

            worst_stop_att = min([mode_eval.stop_att_db]);
            worst_ripple_pm = max([mode_eval.pass_ripple_pm_db]);

            score = nz_full * 100000 ...
                  + NTAPS   * 1000 ...
                  + worst_ripple_pm * 100 ...
                  - worst_stop_att;

            if (~best_found) || (score < best_score)
                best_found = true;
                best_score = score;

                best.NTAPS = NTAPS;
                best.beta = beta;
                best.nz_full = nz_full;
                best.nz_half = nz_half;
                best.zero_err = zero_err;
                best.sym_err = sym_err;
                best.h_q_int = h_q_int;
                best.h_q = h_q;
                best.mode_eval = mode_eval;
                best.worst_stop_att = worst_stop_att;
                best.worst_ripple_pm = worst_ripple_pm;
            end
        end
    end
end

%%============================================================
% 3. 输出搜索结果
%=============================================================

fprintf('\n=============================================================\n');

if ~best_found
    fprintf('没有找到满足指标的 halfband FIR。\n');
    fprintf('建议扩大 NTAPS_LIST 或调整 BETA_LIST 后重新搜索。\n');
    fprintf('=============================================================\n');
    return;
end

fprintf('最佳 halfband 结果：\n');
fprintf('  NTAPS      = %d\n', best.NTAPS);
fprintf('  beta       = %.4f\n', best.beta);
fprintf('  nz_full    = %d / %d\n', best.nz_full, best.NTAPS);
fprintf('  nz_half    = %d / %d\n', best.nz_half, (best.NTAPS+1)/2);
fprintf('  zero_err   = %d\n', best.zero_err);
fprintf('  sym_err    = %d\n', best.sym_err);
fprintf('  worst ripple ± = %.8f dB\n', best.worst_ripple_pm);
fprintf('  worst stop att = %.8f dB\n', best.worst_stop_att);

for im = 1:length(best.mode_eval)
    fprintf('\n模式：%s\n', MODE_NAME{im});
    fprintf('  Fs_out            = %.1f Hz\n', best.mode_eval(im).Fs_out);
    fprintf('  f_stop            = %.1f Hz\n', best.mode_eval(im).f_stop);
    fprintf('  通带峰峰纹波      = %.8f dB\n', best.mode_eval(im).pass_ripple_pp_db);
    fprintf('  通带 ±纹波        = %.8f dB\n', best.mode_eval(im).pass_ripple_pm_db);
    fprintf('  阻带衰减          = %.8f dB\n', best.mode_eval(im).stop_att_db);
    fprintf('  是否满足          = %d\n', best.mode_eval(im).ok);
end

fprintf('=============================================================\n');

%%============================================================
% 4. 保存 CSV 结果
%=============================================================

csv_file = 'interp2_halfband_search_result.csv';
fid = fopen(csv_file, 'w');

fprintf(fid, 'NTAPS,beta,nz_full,nz_half,zero_err,sym_err,pass_all,');
fprintf(fid, 'mode1_ripple_pm_db,mode1_stop_att_db,mode1_ok,');
fprintf(fid, 'mode2_ripple_pm_db,mode2_stop_att_db,mode2_ok\n');

for i = 1:length(result)
    fprintf(fid, '%d,%.4f,%d,%d,%d,%d,%d,', ...
        result(i).NTAPS, ...
        result(i).beta, ...
        result(i).nz_full, ...
        result(i).nz_half, ...
        result(i).zero_err, ...
        result(i).sym_err, ...
        result(i).pass_all);

    fprintf(fid, '%.10f,%.10f,%d,', ...
        result(i).mode_eval(1).pass_ripple_pm_db, ...
        result(i).mode_eval(1).stop_att_db, ...
        result(i).mode_eval(1).ok);

    fprintf(fid, '%.10f,%.10f,%d\n', ...
        result(i).mode_eval(2).pass_ripple_pm_db, ...
        result(i).mode_eval(2).stop_att_db, ...
        result(i).mode_eval(2).ok);
end

fclose(fid);

%%============================================================
% 5. 保存最佳系数
%=============================================================

% 完整整数系数
coeff_full_file = 'interp2_halfband_coeff_decimal.txt';
fid = fopen(coeff_full_file, 'w');
for i = 1:length(best.h_q_int)
    fprintf(fid, '%d\n', best.h_q_int(i));
end
fclose(fid);

% 半边整数系数：从左端到中心
coeff_half_file = 'interp2_halfband_coeff_half_decimal.txt';
fid = fopen(coeff_half_file, 'w');
MID = (best.NTAPS - 1) / 2;
for i = 1:MID+1
    fprintf(fid, '%d\n', best.h_q_int(i));
end
fclose(fid);

% Verilog 可读格式
coeff_verilog_file = 'interp2_halfband_coeff_half_for_verilog.txt';
fid = fopen(coeff_verilog_file, 'w');
fprintf(fid, '//=============================================================\n');
fprintf(fid, '// Halfband 2x FIR coefficient table\n');
fprintf(fid, '// NTAPS   = %d\n', best.NTAPS);
fprintf(fid, '// COEFF_W = %d\n', COEFF_W);
fprintf(fid, '// FRAC_W  = %d\n', FRAC_W);
fprintf(fid, '// beta    = %.4f\n', best.beta);
fprintf(fid, '// Note    = left side to center coefficients\n');
fprintf(fid, '//=============================================================\n\n');

for i = 1:MID+1
    fprintf(fid, "coeff_half[%2d] = %d'sd%d;\n", i-1, COEFF_W, best.h_q_int(i));
end
fclose(fid);

% summary
summary_file = 'interp2_halfband_summary.txt';
fid = fopen(summary_file, 'w');

fprintf(fid, '2x Halfband FIR Search Summary\n');
fprintf(fid, '========================================\n');
fprintf(fid, 'COEFF_W = %d\n', COEFF_W);
fprintf(fid, 'FRAC_W  = %d\n', FRAC_W);
fprintf(fid, 'Best NTAPS = %d\n', best.NTAPS);
fprintf(fid, 'Best beta  = %.4f\n', best.beta);
fprintf(fid, 'Full nonzero coeff = %d / %d\n', best.nz_full, best.NTAPS);
fprintf(fid, 'Half nonzero coeff = %d / %d\n', best.nz_half, (best.NTAPS+1)/2);
fprintf(fid, 'Zero coeff error = %d\n', best.zero_err);
fprintf(fid, 'Symmetry error = %d\n', best.sym_err);
fprintf(fid, 'Worst pass ripple ± = %.10f dB\n', best.worst_ripple_pm);
fprintf(fid, 'Worst stop attenuation = %.10f dB\n\n', best.worst_stop_att);

for im = 1:length(best.mode_eval)
    fprintf(fid, 'Mode: %s\n', MODE_NAME{im});
    fprintf(fid, '  Fs_out = %.1f Hz\n', best.mode_eval(im).Fs_out);
    fprintf(fid, '  f_stop = %.1f Hz\n', best.mode_eval(im).f_stop);
    fprintf(fid, '  pass ripple pp = %.10f dB\n', best.mode_eval(im).pass_ripple_pp_db);
    fprintf(fid, '  pass ripple pm = %.10f dB\n', best.mode_eval(im).pass_ripple_pm_db);
    fprintf(fid, '  stop attenuation = %.10f dB\n', best.mode_eval(im).stop_att_db);
    fprintf(fid, '  ok = %d\n\n', best.mode_eval(im).ok);
end

fclose(fid);

%%============================================================
% 6. 画最佳结果频响
%=============================================================

figure('Color', 'w');
hold on; grid on;

legend_text = cell(1, length(FS_OUT_LIST));

for im = 1:length(FS_OUT_LIST)
    Fs_out = FS_OUT_LIST(im);

    [f, mag_db] = get_response_fft(best.h_q, Fs_out, NFFT);

    plot(f/1000, mag_db, 'LineWidth', 1.2);
    legend_text{im} = MODE_NAME{im};
end

xlabel('Frequency (kHz)');
ylabel('Magnitude (dB)');
title(sprintf('Best 2x Halfband FIR Response: NTAPS=%d, beta=%.2f', best.NTAPS, best.beta));
legend(legend_text, 'Location', 'SouthWest');
ylim([-120, 5]);

xline(20, '--', '20 kHz');
xline((FS_OUT_LIST(1)/2 - 20e3)/1000, '--', '156.4 kHz');
xline((FS_OUT_LIST(2)/2 - 20e3)/1000, '--', '172 kHz');

saveas(gcf, 'interp2_halfband_response.png');

fprintf('\n已保存文件：\n');
fprintf('  %s\n', csv_file);
fprintf('  %s\n', summary_file);
fprintf('  %s\n', coeff_full_file);
fprintf('  %s\n', coeff_half_file);
fprintf('  %s\n', coeff_verilog_file);
fprintf('  interp2_halfband_response.png\n');

%%============================================================
% local functions
%=============================================================

function h = design_halfband_kaiser(NTAPS, beta)
    % 设计 DC gain = 1 的 halfband FIR
    %
    % 理想 halfband 低通截止角频率为 pi/2：
    %   h[n] = 0.5 * sinc(0.5*(n-M))
    %
    % 这里使用 Kaiser 窗，并强制理论零系数为 0。

    M = (NTAPS - 1) / 2;
    n = 0:NTAPS-1;
    k = n - M;

    h = 0.5 * local_sinc(0.5 * k);

    w = local_kaiser(NTAPS, beta);
    h = h .* w;

    % 强制 halfband 理论零系数
    for i = 1:NTAPS
        kk = i - 1 - M;
        if kk ~= 0 && mod(kk, 2) == 0
            h(i) = 0;
        end
    end

    % DC 归一化
    h = h / sum(h);
end

function q = quantize_halfband_q(h, FRAC_W, COEFF_W)
    Q_SCALE = 2^FRAC_W;
    NTAPS = length(h);
    M = (NTAPS - 1) / 2;

    q = round(h * Q_SCALE);

    % 强制 halfband 理论零系数为 0
    for i = 1:NTAPS
        kk = i - 1 - M;
        if kk ~= 0 && mod(kk, 2) == 0
            q(i) = 0;
        end
    end

    % 调节中心抽头，让 DC gain 严格等于 1
    center_idx = M + 1;
    q(center_idx) = q(center_idx) + (Q_SCALE - sum(q));

    % 限幅，理论上不会触发
    qmin = -2^(COEFF_W-1);
    qmax =  2^(COEFF_W-1) - 1;
    q(q < qmin) = qmin;
    q(q > qmax) = qmax;
end

function zero_err = check_halfband_zero_error(q)
    NTAPS = length(q);
    M = (NTAPS - 1) / 2;
    zero_err = 0;

    for i = 1:NTAPS
        kk = i - 1 - M;
        if kk ~= 0 && mod(kk, 2) == 0
            zero_err = max(zero_err, abs(q(i)));
        end
    end
end

function eval_info = eval_fir_response(h, Fs_out, f_pass_low, f_pass_high, f_stop, NFFT)
    [f, mag_db] = get_response_fft(h, Fs_out, NFFT);

    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop) & (f <= Fs_out/2);

    pass_mag = mag_db(pass_idx);
    stop_mag = mag_db(stop_idx);

    pass_min_db = min(pass_mag);
    pass_max_db = max(pass_mag);

    pass_ripple_pp_db = pass_max_db - pass_min_db;
    pass_ripple_pm_db = pass_ripple_pp_db / 2;

    stop_att_db = -max(stop_mag);

    ok = (pass_ripple_pm_db <= 0.05) && (stop_att_db >= 70);

    eval_info.pass_min_db = pass_min_db;
    eval_info.pass_max_db = pass_max_db;
    eval_info.pass_ripple_pp_db = pass_ripple_pp_db;
    eval_info.pass_ripple_pm_db = pass_ripple_pm_db;
    eval_info.stop_att_db = stop_att_db;
    eval_info.ok = ok;
end

function [f, mag_db] = get_response_fft(h, Fs_out, NFFT)
    H = fft(h, NFFT);
    H = H(1:NFFT/2+1);

    f = (0:NFFT/2) / NFFT * Fs_out;

    mag = abs(H);
    mag(mag < 1e-15) = 1e-15;
    mag_db = 20 * log10(mag);
end

function y = local_sinc(x)
    y = ones(size(x));
    idx = abs(x) > 1e-12;
    y(idx) = sin(pi*x(idx)) ./ (pi*x(idx));
end

function w = local_kaiser(N, beta)
    % 不依赖 Signal Processing Toolbox 的 Kaiser window
    n = 0:N-1;
    alpha = (N - 1) / 2;

    if alpha == 0
        w = 1;
        return;
    end

    t = (n - alpha) / alpha;
    w = besseli(0, beta * sqrt(1 - t.^2)) / besseli(0, beta);
end
