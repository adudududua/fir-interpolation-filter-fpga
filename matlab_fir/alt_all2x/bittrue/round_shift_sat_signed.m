function [y, stat] = round_shift_sat_signed(acc, shift_n, out_w)
%=============================================================
% 文件名       : round_shift_sat_signed.m
% 函数名       : round_shift_sat_signed
% 功能简述     : 对有符号 FIR 累加结果执行与 RTL 一致的就近舍入、
%                算术右移和饱和输出。
%
%                RTL 等价规则：
%                  正数：加 2^(shift_n-1) 后右移；
%                  负数：加 2^(shift_n-1)-1 后右移；
%                  最后饱和到 out_w 位有符号范围。
%
% 当前默认配置：
%                  输出位宽：24bit signed
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增 RTL 等价舍入与饱和函数。
%=============================================================

    acc = int64(acc);

    if shift_n > 0
        bias_pos = int64(2^(shift_n - 1));
        bias_neg = bias_pos - int64(1);
        acc_round = acc;
        idx_pos = (acc >= 0);
        acc_round(idx_pos) = acc(idx_pos) + bias_pos;
        acc_round(~idx_pos) = acc(~idx_pos) + bias_neg;
        shifted = idivide(acc_round, int64(2^shift_n), 'floor');
    elseif shift_n == 0
        shifted = acc;
    else
        shifted = bitshift(acc, -shift_n);
    end

    out_max = int64(2^(out_w - 1) - 1);
    out_min = int64(-2^(out_w - 1));
    sat_high = shifted > out_max;
    sat_low = shifted < out_min;

    y = shifted;
    y(sat_high) = out_max;
    y(sat_low) = out_min;

    stat.sat_high_count = nnz(sat_high);
    stat.sat_low_count = nnz(sat_low);
    stat.output_sat_count = stat.sat_high_count + stat.sat_low_count;
end
