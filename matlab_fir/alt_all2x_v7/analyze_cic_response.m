function metric = analyze_cic_response(h_total, Fs_in, Fs_out, ...
        f_pass_low, f_pass_high, f_stop_begin, expected_gain, nfft)
%=============================================================
% 文件名       : analyze_cic_response.m
% 函数名       : analyze_cic_response
% 功能简述     : 对 FIR-CIC 复合插值链的等效冲激响应进行统一
%                频域检查，返回通带、阻带、直流增益、对称性
%                和群延迟指标。
%
% 当前默认指标：
%                  通带：10Hz～20kHz
%                  阻带起点：24.1kHz
%                  通带最大绝对误差：< 0.01dB
%                  阻带衰减：> 70dB
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 FIR-CIC 统一频响检查函数。
%=============================================================

    if nargin < 8
        error('analyze_cic_response 输入参数不足。');
    end
    if abs(Fs_out/Fs_in-round(Fs_out/Fs_in)) > 1e-12
        error('Fs_out 必须是 Fs_in 的整数倍。');
    end

    [H, frequency] = freqz(h_total, 1, nfft, Fs_out);
    H_normalized = H/expected_gain;
    response_db = 20*log10(abs(H_normalized)+1e-15);

    pass_index = frequency >= f_pass_low & frequency <= f_pass_high;
    stop_index = frequency >= f_stop_begin & frequency <= Fs_out/2;
    pass_response = response_db(pass_index);
    stop_response = response_db(stop_index);

    metric.f = frequency;
    metric.H_db = response_db;
    metric.pass_gain_db = mean(pass_response);
    metric.pass_abs_max_db = max(abs(pass_response));
    metric.ripple_pp_db = max(pass_response)-min(pass_response);
    metric.stop_attn_db = -max(stop_response);
    metric.dc_gain = sum(h_total);
    metric.sym_err = max(abs(h_total(:).'-fliplr(h_total(:).')));

    [group_delay, gd_frequency] = grpdelay(h_total, 1, nfft, Fs_out);
    gd_index = gd_frequency >= f_pass_low & ...
               gd_frequency <= f_pass_high;
    gd_pass = group_delay(gd_index);
    metric.gd_mean = mean(gd_pass);
    metric.gd_pp = max(gd_pass)-min(gd_pass);
    metric.pass = metric.pass_abs_max_db < 0.01 && ...
                  metric.stop_attn_db > 70 && ...
                  metric.sym_err < 1e-10 && ...
                  metric.gd_pp < 1e-6;
end
