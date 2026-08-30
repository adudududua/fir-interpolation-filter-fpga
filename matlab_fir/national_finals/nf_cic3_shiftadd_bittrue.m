function [y, stat] = nf_cic3_shiftadd_bittrue(x, input_w, output_w)
%=============================================================
% 文件名       : nf_cic3_shiftadd_bittrue.m
% 函数名       : nf_cic3_shiftadd_bittrue
% 功能简述     : 建立三抽头移位加法 CIC 均衡器的逐位一致模型，并统计内部峰值与饱和次数。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================
% 1）主函数模块：nf_cic3_shiftadd_bittrue
% 功能说明：建立三抽头移位加法 CIC 均衡器的逐位一致模型，并统计内部峰值与饱和次数。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


%NF_CIC3_SHIFTADD_BITTRUE Bit-true model of the signed-off 3-tap equalizer.
%   The signed input is not pre-clipped.  The internal expression is kept
%   at input_w+3 bits and the output is saturated only at output_w.

    if output_w ~= input_w && output_w ~= input_w+1
        error('Equalizer output_w must be input_w or input_w+1.');
    end

    x = int64(x(:).');
    input_max = int64(2^(input_w-1)-1);
    input_min = int64(-2^(input_w-1));
    if any(x > input_max | x < input_min)
        error('Equalizer input is outside signed-%d before processing.', ...
            input_w);
    end

    output_max = int64(2^(output_w-1)-1);
    output_min = int64(-2^(output_w-1));
    y = zeros(size(x), 'int64');
    x_z1 = int64(0);
    x_z2 = int64(0);
    sat_high_count = 0;
    sat_low_count = 0;
    max_abs_unclipped = 0;

    for idx = 1:numel(x)
        curvature = 2*x_z1-x(idx)-x_z2;
        correction = idivide(curvature, int64(8), 'floor');
        value = x_z1+correction;
        max_abs_unclipped = max(max_abs_unclipped, abs(double(value)));
        if value > output_max
            value = output_max;
            sat_high_count = sat_high_count+1;
        elseif value < output_min
            value = output_min;
            sat_low_count = sat_low_count+1;
        end
        y(idx) = value;
        x_z2 = x_z1;
        x_z1 = x(idx);
    end

    stat.input_w = input_w;
    stat.output_w = output_w;
    stat.input_count = numel(x);
    stat.output_count = numel(y);
    stat.sat_high_count = sat_high_count;
    stat.sat_low_count = sat_low_count;
    stat.output_sat_count = sat_high_count+sat_low_count;
    stat.max_abs_input = max(abs(double(x)));
    stat.max_abs_unclipped = max_abs_unclipped;
    stat.max_abs_output = max(abs(double(y)));
    stat.exceeds_input_width_count = nnz(y > input_max | y < input_min);
end
