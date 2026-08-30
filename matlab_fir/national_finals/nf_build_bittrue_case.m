function result = nf_build_bittrue_case(x)
%=============================================================
% 文件名       : nf_build_bittrue_case.m
% 函数名       : nf_build_bittrue_case
% 功能简述     : 按 RTL 舍入、饱和和流水规则建立逐位一致的定点行为模型。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================
% 1）主函数模块：nf_build_bittrue_case
% 功能说明：按 RTL 舍入、饱和和流水规则建立逐位一致的定点行为模型。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


%=============================================================
% 函数名       : nf_build_bittrue_case
% 功能简述     : 全国赛平坦 4x/8x + 三抽头补偿 CIC16 的整数位真模型。
%=============================================================

    script_dir = fileparts(mfilename('fullpath'));
    matlab_root = fileparts(script_dir);
    bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
    v7_dir = fullfile(matlab_root, 'alt_all2x_v7');
    addpath(bittrue_dir);
    addpath(v7_dir);

    release = nf_release_v2_config();

    x = int64(x(:).');
    [stage1, stat1] = interp2_polyphase_bittrue(x, ...
        release.stage1.coeff_int, release.stage1.frac_w, ...
        release.stage1.input_w, release.stage1.acc_w);
    [stage1_q22, bridge1_stat] = round_shift_sat_signed(stage1, 2, 22);
    [stage2, stat2] = interp2_polyphase_bittrue(stage1_q22, ...
        release.stage2.coeff_int, release.stage2.frac_w, ...
        release.stage2.input_w, release.stage2.acc_w);
    [stage2_q20, bridge2_stat] = round_shift_sat_signed(stage2, 2, 20);
    [stage3, stat3] = interp2_polyphase_bittrue(stage2_q20, ...
        release.stage3.coeff_int, release.stage3.frac_w, ...
        release.stage3.input_w, release.stage3.acc_w);

    % RTL 补偿器在每个有效样点执行，并在有限输入序列后再送入
    % 两个 0，以完整排出三抽头冲激尾部。
    [equalized, equalizer_stat] = nf_cic3_shiftadd_bittrue( ...
        [stage3 int64([0 0])], 20, 21);

    [cic_output, cic_stat, cic_trace] = ...
        nf_cic_n3_hold2_bittrue(equalized, 21, 20);

    result.config_id = release.config_id;
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
