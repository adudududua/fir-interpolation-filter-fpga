function res = check_total_chain(h_total, Fs_in, Fs_out, ...
                                 f_pass_low, f_pass_high, ...
                                 ripple_target_db, stop_target_db, ...
                                 expected_gain, nfft)
%=============================================================
% 文件名       : check_total_chain.m
% 函数名       : check_total_chain
% 功能简述     : 检查 128x 等效 FIR 的通带、阻带、直流增益、
%                对称性和群延迟，并返回绘图所需频率响应。
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 V2 总链路统一验收函数。
%=============================================================

    f_stop_begin = Fs_in - f_pass_high;

    [H, f] = freqz(h_total, 1, nfft, Fs_out);
    H_norm = H / expected_gain;
    H_db = 20*log10(abs(H_norm) + 1e-15);

    pass_idx = (f >= f_pass_low) & (f <= f_pass_high);
    stop_idx = (f >= f_stop_begin) & (f <= Fs_out/2);

    pass_db = H_db(pass_idx);
    stop_db = H_db(stop_idx);

    pass_gain_db = mean(pass_db);
    ripple_pp_db = max(pass_db) - min(pass_db);
    ripple_pm_db = max(abs(pass_db - pass_gain_db));
    pass_abs_max_db = max(abs(pass_db));
    pass_abs_peak_db = max(pass_db);
    pass_abs_min_db = min(pass_db);
    stop_attn_db = -max(stop_db);
    dc_gain = sum(h_total);

    [gd, fg] = grpdelay(h_total, 1, nfft, Fs_out);
    gd_idx = (fg >= f_pass_low) & (fg <= f_pass_high);
    gd_pass = gd(gd_idx);
    gd_mean = mean(gd_pass);
    gd_pp = max(gd_pass) - min(gd_pass);

    sym_err = max(abs(h_total(:).' - fliplr(h_total(:).')));

    pass_ripple = pass_abs_max_db <= ripple_target_db;
    pass_gain = abs(pass_gain_db) <= ripple_target_db;
    pass_stop = stop_attn_db >= stop_target_db;
    pass_linear = (sym_err < 1e-10) && (gd_pp < 1e-6);

    res.f = f;
    res.H_db = H_db;
    res.f_stop_begin = f_stop_begin;
    res.expected_gain = expected_gain;
    res.dc_gain = dc_gain;
    res.pass_gain_db = pass_gain_db;
    res.ripple_pp_db = ripple_pp_db;
    res.ripple_pm_db = ripple_pm_db;
    res.pass_abs_max_db = pass_abs_max_db;
    res.pass_abs_peak_db = pass_abs_peak_db;
    res.pass_abs_min_db = pass_abs_min_db;
    res.stop_attn_db = stop_attn_db;
    res.gd_mean = gd_mean;
    res.gd_pp = gd_pp;
    res.sym_err = sym_err;
    res.pass_gain = pass_gain;
    res.pass_ripple = pass_ripple;
    res.pass_stop = pass_stop;
    res.pass_linear = pass_linear;
    res.pass_all = pass_ripple && pass_stop && pass_linear;
end
