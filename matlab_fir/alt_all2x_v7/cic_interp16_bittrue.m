function [y, stat, trace] = cic_interp16_bittrue( ...
        x, rate_change, cic_order, diff_delay, input_w, output_w, ...
        prune_lsb)
%=============================================================
% 文件名       : cic_interp16_bittrue.m
% 函数名       : cic_interp16_bittrue
% 功能简述     : 标准 CIC 插值器的整数位真模型。数据顺序严格为：
%                  低速 N 级 comb -> R 倍插零 ->
%                  高速 N 级 integrator。
%                各级使用有限位宽二进制补码模运算，并支持用累计
%                LSB 丢弃量描述 Hogenauer 剪枝候选。
%
%                prune_lsb 的前 N 项对应 comb，后 N 项对应
%                integrator；数值必须单调不减。全零表示全精度。
%
% 当前默认配置：
%                  R=16，M=1，N=3/4
%                  输入输出位宽：20bit signed
%                  全精度增长  ：N*log2(R*M)
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 CIC 插值整数位真模型。
%=============================================================

    if nargin < 7 || isempty(prune_lsb)
        prune_lsb = zeros(1, 2*cic_order);
    end
    if numel(prune_lsb) ~= 2*cic_order
        error('prune_lsb 必须包含 2*N 个元素。');
    end
    if any(diff(prune_lsb) < 0) || any(prune_lsb < 0) || ...
            any(mod(prune_lsb, 1) ~= 0)
        error('prune_lsb 必须是单调不减的非负整数。');
    end
    if diff_delay < 1 || mod(diff_delay, 1) ~= 0
        error('差分延迟 M 必须是正整数。');
    end

    growth_w = ceil(cic_order*log2(rate_change*diff_delay));
    full_w = input_w+growth_w;
    normalization_shift = round((cic_order-1)*log2(rate_change)) + ...
                          round(cic_order*log2(diff_delay));
    if prune_lsb(end) > normalization_shift
        error('最终剪枝位数超过 CIC 归一化右移量。');
    end

    x = int64(x(:).');
    low_data = [x zeros(1, cic_order*diff_delay, 'int64')];
    current_lsb = 0;
    wrap_count = 0;
    round_count = 0;
    stage_width = zeros(1, 2*cic_order);
    stage_max_abs = zeros(1, 2*cic_order);

    for stage_idx = 1:cic_order
        delayed = [zeros(1, diff_delay, 'int64'), ...
                   low_data(1:end-diff_delay)];
        difference = low_data-delayed;
        target_lsb = prune_lsb(stage_idx);
        [difference, one_round_count] = align_lsb( ...
            difference, target_lsb-current_lsb, ...
            full_w-target_lsb);
        round_count = round_count+one_round_count;
        [low_data, one_wrap_count] = wrap_signed( ...
            difference, full_w-target_lsb);
        wrap_count = wrap_count+one_wrap_count;
        current_lsb = target_lsb;
        stage_width(stage_idx) = full_w-current_lsb;
        stage_max_abs(stage_idx) = max(abs(double(low_data)));
    end

    high_data = zeros(1, rate_change*numel(low_data), 'int64');
    high_data(1:rate_change:end) = low_data;

    for stage_idx = 1:cic_order
        profile_idx = cic_order+stage_idx;
        target_lsb = prune_lsb(profile_idx);
        [integrator_input, one_round_count] = align_lsb( ...
            high_data, target_lsb-current_lsb, full_w-target_lsb);
        round_count = round_count+one_round_count;
        state = int64(0);
        integrator_output = zeros(size(integrator_input), 'int64');
        one_wrap_count = 0;
        for sample_idx = 1:numel(integrator_input)
            sum_value = state+integrator_input(sample_idx);
            [state, wrapped] = wrap_signed(sum_value, full_w-target_lsb);
            one_wrap_count = one_wrap_count+wrapped;
            integrator_output(sample_idx) = state;
        end
        wrap_count = wrap_count+one_wrap_count;
        high_data = integrator_output;
        current_lsb = target_lsb;
        stage_width(profile_idx) = full_w-current_lsb;
        stage_max_abs(profile_idx) = max(abs(double(high_data)));
    end

    output_shift = normalization_shift-current_lsb;
    [y, output_stat] = round_shift_sat_signed( ...
        high_data, output_shift, output_w);

    stat.full_width = full_w;
    stat.growth_width = growth_w;
    stat.normalization_shift = normalization_shift;
    stat.output_shift = output_shift;
    stat.modulo_wrap_count = wrap_count;
    stat.internal_round_count = round_count;
    stat.output_sat_count = output_stat.output_sat_count;
    stat.max_abs_output = max(abs(double(y)));
    stat.input_count = numel(x);
    stat.output_count = numel(y);

    trace.prune_lsb = prune_lsb;
    trace.stage_width = stage_width;
    trace.stage_max_abs = stage_max_abs;
end


function [aligned, changed_count] = align_lsb(data, shift_n, out_w)
    if shift_n < 0
        error('内部 LSB 对齐不允许恢复已丢弃的位。');
    end
    if shift_n == 0
        aligned = int64(data);
        changed_count = 0;
        return;
    end
    [aligned, stat] = round_shift_sat_signed(data, shift_n, out_w);
    if stat.output_sat_count ~= 0
        error('CIC 内部 LSB 对齐发生意外饱和。');
    end
    changed_count = nnz(bitand(abs(int64(data)), int64(2^shift_n-1)) ~= 0);
end


function [wrapped, wrap_count] = wrap_signed(value, word_w)
    if word_w < 2 || word_w > 52
        error('当前精确模运算仅支持 2～52bit。');
    end
    value_double = double(value);
    half_range = 2^(word_w-1);
    modulus = 2^word_w;
    wrap_mask = value_double >= half_range | value_double < -half_range;
    wrapped = int64(mod(value_double+half_range, modulus)-half_range);
    wrap_count = nnz(wrap_mask);
end
