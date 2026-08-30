function [y, stat, trace] = nf_cic_n3_hold2_bittrue(x, input_w, output_w)
%=============================================================
% 文件名       : nf_cic_n3_hold2_bittrue.m
% 函数名       : nf_cic_n3_hold2_bittrue
% 功能简述     : 建立 C2—16点保持—I2 的严格等价 CIC 定点模型，并统计积分器回绕与输出饱和。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================
% 1）主函数模块：nf_cic_n3_hold2_bittrue
% 功能说明：建立 C2—16点保持—I2 的严格等价 CIC 定点模型，并统计积分器回绕与输出饱和。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


%NF_CIC_N3_HOLD2_BITTRUE Exact model of C2 -> Hold16 -> I2.
%   This is the signed-off N=3 interpolation identity.  The first and
%   second integrator widths are the proven input_w+5 and input_w+8 bits.

    rate = 16;
    first_integrator_w = input_w+5;
    final_integrator_w = input_w+8;
    normalization_shift = 8;

    x = int64(x(:).');
    input_max = int64(2^(input_w-1)-1);
    input_min = int64(-2^(input_w-1));
    if any(x > input_max | x < input_min)
        error('CIC input is outside signed-%d before processing.', input_w);
    end

    % Three low-rate zero samples retain the finite-vector length contract
    % of the reference C3/up16/I3 model.  The third produces only a zero
    % hold frame after the two comb histories have drained.
    low_data = [x zeros(1, 3, 'int64')];
    comb_max_abs = zeros(1, 2);
    for stage_idx = 1:2
        delayed = [int64(0) low_data(1:end-1)];
        low_data = low_data-delayed;
        comb_max_abs(stage_idx) = max(abs(double(low_data)));
    end
    if comb_max_abs(1) > 2^(input_w) || ...
            comb_max_abs(2) > 2^(input_w+1)
        error('CIC comb analytic width bound was violated.');
    end

    hold_data = repelem(low_data, rate);
    first_state = int64(0);
    final_state = int64(0);
    final_data = zeros(size(hold_data), 'int64');
    first_wrap_count = 0;
    final_wrap_count = 0;
    first_max_abs = 0;
    final_max_abs = 0;
    for idx = 1:numel(hold_data)
        [first_state, wrapped] = wrap_signed_local( ...
            first_state+hold_data(idx), first_integrator_w);
        first_wrap_count = first_wrap_count+wrapped;
        [final_state, wrapped] = wrap_signed_local( ...
            final_state+first_state, final_integrator_w);
        final_wrap_count = final_wrap_count+wrapped;
        final_data(idx) = final_state;
        first_max_abs = max(first_max_abs, abs(double(first_state)));
        final_max_abs = max(final_max_abs, abs(double(final_state)));
    end

    [y, output_stat] = round_shift_sat_signed( ...
        final_data, normalization_shift, output_w);

    stat.input_w = input_w;
    stat.output_w = output_w;
    stat.first_integrator_w = first_integrator_w;
    stat.final_integrator_w = final_integrator_w;
    stat.normalization_shift = normalization_shift;
    stat.input_count = numel(x);
    stat.output_count = numel(y);
    stat.comb_max_abs = comb_max_abs;
    stat.first_integrator_max_abs = first_max_abs;
    stat.final_integrator_max_abs = final_max_abs;
    stat.first_integrator_wrap_count = first_wrap_count;
    stat.final_integrator_wrap_count = final_wrap_count;
    stat.output_sat_count = output_stat.output_sat_count;
    stat.max_abs_output = max(abs(double(y)));

    trace.structure = 'C2-Hold16-I2';
    trace.integrator_widths = [first_integrator_w final_integrator_w];
    trace.comb_max_abs = comb_max_abs;
end


% 2）局部函数模块：wrap_signed_local


% 功能说明：按给定位宽执行二进制补码回绕，并返回是否发生溢出回绕的标志。
function [wrapped, did_wrap] = wrap_signed_local(value, word_w)
    half_range = 2^(word_w-1);
    modulus = 2^word_w;
    value_double = double(value);
    did_wrap = value_double >= half_range || value_double < -half_range;
    wrapped = int64(mod(value_double+half_range, modulus)-half_range);
end
