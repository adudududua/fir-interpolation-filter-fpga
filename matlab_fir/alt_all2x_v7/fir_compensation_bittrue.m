function [y, stat] = fir_compensation_bittrue( ...
        x, coeff_int, frac_w, data_w, acc_w)
%=============================================================
% 文件名       : fir_compensation_bittrue.m
% 函数名       : fir_compensation_bittrue
% 功能简述     : Phase 7 低速 CIC 补偿 FIR 的整数位真模型。
%                使用量化后的对称 FIR 系数完成卷积，并按 RTL 规则
%                执行就近舍入、算术右移和有符号饱和。
%
% 当前默认配置：
%                  输入输出位宽：20bit signed
%                  系数格式    ：Q12 / 14bit
%                  补偿位置    ：352.8kHz，CIC 之前
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增补偿 FIR 整数位真模型。
%=============================================================

    x = int64(x(:).');
    coeff_int = int64(coeff_int(:).');
    acc_double = conv(double(x), double(coeff_int));

    if max(abs(acc_double)) > flintmax
        error('补偿 FIR 累加结果超过 double 精确整数范围。');
    end

    acc = int64(acc_double);
    acc_max = 2^(acc_w-1)-1;
    acc_min = -2^(acc_w-1);
    acc_overflow = double(acc) > acc_max | double(acc) < acc_min;
    [y, round_stat] = round_shift_sat_signed(acc, frac_w, data_w);

    stat.acc_overflow_count = nnz(acc_overflow);
    stat.output_sat_count = round_stat.output_sat_count;
    stat.max_abs_acc = max(abs(double(acc)));
    stat.max_abs_output = max(abs(double(y)));
    stat.input_count = numel(x);
    stat.output_count = numel(y);
end
