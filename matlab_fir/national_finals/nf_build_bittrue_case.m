function result = nf_build_bittrue_case(x)
%=============================================================
% 函数名       : nf_build_bittrue_case
% 功能简述     : 全国赛平坦 4x/8x + 三抽头补偿 CIC16 的整数位真模型。
%=============================================================

    script_dir = fileparts(mfilename('fullpath'));
    matlab_root = fileparts(script_dir);
    bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
    v2_dir = fullfile(matlab_root, 'alt_all2x_v2');
    v7_dir = fullfile(matlab_root, 'alt_all2x_v7');
    addpath(bittrue_dir);
    addpath(v7_dir);

    reference = load(fullfile(v2_dir, ...
        'stage1_strict_halfband_config.mat'), 'best_config');
    stage_config = reference.best_config(1:3);
    stage3_coeff = nf_stage3_q15_coefficients();
    stage_config(3).coeff_int = stage3_coeff;
    stage_config(3).frac_w = 15;
    stage_config(3).acc_w_recommended = 38;

    x = int64(x(:).');
    [stage1, stat1] = interp2_polyphase_bittrue(x, ...
        stage_config(1).coeff_int, stage_config(1).frac_w, 24, ...
        stage_config(1).acc_w_recommended);
    [stage1_q22, bridge1_stat] = round_shift_sat_signed(stage1, 2, 22);
    [stage2, stat2] = interp2_polyphase_bittrue(stage1_q22, ...
        stage_config(2).coeff_int, stage_config(2).frac_w, 22, ...
        stage_config(2).acc_w_recommended);
    [stage2_q20, bridge2_stat] = round_shift_sat_signed(stage2, 2, 20);
    [stage3, stat3] = interp2_polyphase_bittrue(stage2_q20, ...
        stage_config(3).coeff_int, stage_config(3).frac_w, 20, 38);

    % RTL 补偿器在每个有效样点执行，并在有限输入序列后再送入
    % 两个 0，以完整排出三抽头冲激尾部。
    [equalized, equalizer_stat] = cic3_shiftadd_bittrue( ...
        [stage3 int64([0 0])], 20);

    prune_profile = zeros(1, 6);
    [cic_output, cic_stat, cic_trace] = cic_interp16_bittrue( ...
        equalized, 16, 3, 1, 20, 20, prune_profile);

    result.input = x;
    result.y4_internal = stage2;
    result.y8_internal = stage3;
    result.equalized_internal = equalized;
    result.y128_internal = cic_output;
    result.y4_24 = bitshift(stage2, 2);
    result.y8_24 = bitshift(stage3, 4);
    result.y128_24 = bitshift(cic_output, 4);
    result.stat.stage1 = stat1;
    result.stat.bridge1 = bridge1_stat;
    result.stat.stage2 = stat2;
    result.stat.bridge2 = bridge2_stat;
    result.stat.stage3 = stat3;
    result.stat.equalizer = equalizer_stat;
    result.stat.cic = cic_stat;
    result.trace.cic = cic_trace;
end


function [y, stat] = cic3_shiftadd_bittrue(x, data_w)
    x = int64(x(:).');
    out_max = int64(2^(data_w-1)-1);
    out_min = int64(-2^(data_w-1));
    y = zeros(size(x), 'int64');
    x_z1 = int64(0);
    x_z2 = int64(0);
    sat_count = 0;
    for idx = 1:numel(x)
        curvature = 2*x_z1-x(idx)-x_z2;
        % Verilog signed >>> 3 等价于向负无穷取整。
        correction = int64(floor(double(curvature)/8));
        value = x_z1+correction;
        if value > out_max
            value = out_max;
            sat_count = sat_count+1;
        elseif value < out_min
            value = out_min;
            sat_count = sat_count+1;
        end
        y(idx) = value;
        x_z2 = x_z1;
        x_z1 = x(idx);
    end
    stat.output_sat_count = sat_count;
    stat.input_count = numel(x);
    stat.output_count = numel(y);
    stat.max_abs_output = max(abs(double(y)));
end
