function [y, stat] = interp2_polyphase_bittrue(x, coeff_int, frac_w, data_w, acc_w)
%=============================================================
% 文件名       : interp2_polyphase_bittrue.m
% 函数名       : interp2_polyphase_bittrue
% 功能简述     : 单级 2 倍插值 FIR 的 2 相 polyphase bit-true 模型。
%                本函数使用整数系数完成两相卷积，并在每一级末尾
%                按 RTL 规则舍入、右移及饱和到固定数据位宽。
%
%                两相关系：
%                  y[2n]   = sum(h[2k]   * x[n-k])
%                  y[2n+1] = sum(h[2k+1] * x[n-k])
%
% 当前默认配置：
%                  数据位宽：24bit signed
%                  系数增益：已包含 2 倍插值增益
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增单级 2 相 bit-true 插值模型。
%=============================================================
% 1）主函数模块：interp2_polyphase_bittrue
% 功能说明：模拟 2 倍多相 FIR 的偶相、奇相数据路径及定点量化过程。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


    x = int64(x(:).');
    coeff_int = int64(coeff_int(:).');

    if mod(numel(coeff_int), 2) == 0
        error('当前 polyphase 模型要求奇数 tap，实际为 %d tap。', numel(coeff_int));
    end

    phase0 = coeff_int(1:2:end);
    phase1 = coeff_int(2:2:end);

    acc0_double = conv(double(x), double(phase0));
    acc1_double = conv(double(x), double(phase1));

    if max(abs([acc0_double acc1_double])) > flintmax
        error('整数卷积超过 double 的精确整数范围，请改用分段 int64 MAC。');
    end

    out_len = 2 * numel(x) + numel(coeff_int) - 2;
    acc_full = zeros(1, out_len, 'int64');
    acc_full(1:2:end) = int64(acc0_double);
    acc_full(2:2:end) = int64(acc1_double);

    acc_max_limit = 2^(acc_w - 1) - 1;
    acc_min_limit = -2^(acc_w - 1);
    acc_overflow = (double(acc_full) > acc_max_limit) | ...
                   (double(acc_full) < acc_min_limit);

    [y, round_stat] = round_shift_sat_signed(acc_full, frac_w, data_w);

    stat.acc_overflow_count = nnz(acc_overflow);
    stat.output_sat_count = round_stat.output_sat_count;
    stat.max_abs_acc = max(abs(double(acc_full)));
    stat.max_abs_output = max(abs(double(y)));
    stat.zero_output_count = nnz(y == 0);
    stat.output_count = numel(y);
    stat.phase0_gain = double(sum(phase0)) / 2^frac_w;
    stat.phase1_gain = double(sum(phase1)) / 2^frac_w;
end
