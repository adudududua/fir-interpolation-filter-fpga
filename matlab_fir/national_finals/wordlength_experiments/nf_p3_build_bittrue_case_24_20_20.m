function result = nf_p3_build_bittrue_case_24_20_20(x)
%=============================================================
% 文件名       : nf_p3_build_bittrue_case_24_20_20.m
% 函数名       : nf_p3_build_bittrue_case_24_20_20
% 功能简述     : 按 RTL 舍入、饱和和流水规则建立逐位一致的定点行为模型。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================
% 1）主函数模块：nf_p3_build_bittrue_case_24_20_20
% 功能说明：按 RTL 舍入、饱和和流水规则建立逐位一致的定点行为模型。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


% Bit-true candidate with Stage1/Stage2/Stage3 data widths 24/20/20.
%
% The first bridge moves the complete four-bit scale reduction in front of
% Stage2.  Stage2 therefore consumes and emits signed-20 data.  There is no
% second arithmetic quantizer: Stage2 feeds Stage3 at the same Q format.

    script_dir = fileparts(mfilename('fullpath'));
    nf_dir = fileparts(script_dir);
    matlab_root = fileparts(nf_dir);
    bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
    addpath(nf_dir);
    addpath(bittrue_dir);

    release = nf_release_218_config();

    x = int64(x(:).');
    [stage1, stat1] = interp2_polyphase_bittrue(x, ...
        release.stage1.coeff_int, release.stage1.frac_w, ...
        release.stage1.input_w, release.stage1.acc_w);
    [stage1_q20, bridge1_stat] = round_shift_sat_signed(stage1, 4, 20);
    [stage2, stat2] = interp2_polyphase_bittrue(stage1_q20, ...
        release.stage2.coeff_int, release.stage2.frac_w, 20, ...
        release.stage2.acc_w);

    % Stage2 already has the signed-20 Q format required by both Stage3
    % banks.  Keep a named identity bridge in the model so its statistics
    % and RTL correspondence remain explicit and auditable.
    [stage2_q20, bridge2_stat] = round_shift_sat_signed(stage2, 0, 20);

    [stage3_flat, stat3_flat] = interp2_polyphase_bittrue(stage2_q20, ...
        release.stage3.coeff_int, release.stage3.frac_w, ...
        release.stage3.output_w, ...
        release.stage3.acc_w);
    [stage3_comp, stat3_comp] = interp2_polyphase_bittrue(stage2_q20, ...
        release.stage3_comp.coeff_int, release.stage3_comp.frac_w, ...
        release.stage3_comp.output_w, release.stage3_comp.acc_w);
    [cic_output, cic_stat, cic_trace] = ...
        nf_cic_n3_hold2_bittrue([stage3_comp int64([0 0])], ...
        release.cic.input_w, release.cic.output_w);

    result.config_id = release.config_id;
    result.input = x;
    result.y4_internal = stage2;
    result.y8_internal = stage3_flat;
    result.p3_stage3_internal = stage3_comp;
    result.y128_internal = cic_output;
    result.y4_24 = bitshift(stage2, 4);
    result.y8_24 = bitshift(stage3_flat, 4);
    result.y128_24 = bitshift(cic_output, 4);
    result.stat.stage1 = stat1;
    result.stat.bridge1 = bridge1_stat;
    result.stat.stage2 = stat2;
    result.stat.bridge2 = bridge2_stat;
    result.stat.stage3_flat = stat3_flat;
    result.stat.stage3_comp = stat3_comp;
    result.stat.cic = cic_stat;
    result.trace.cic = cic_trace;
end
