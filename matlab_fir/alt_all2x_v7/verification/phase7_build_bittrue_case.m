function result = phase7_build_bittrue_case(x, CFG)
%=============================================================
% 文件名       : phase7_build_bittrue_case.m
% 函数名       : phase7_build_bittrue_case
% 功能简述     : 构造正式 Phase 7 N=3 完整链的整数位真结果。
%                依次执行 Stage1、24->22bit、Stage2、
%                22->20bit、折叠补偿 Stage3 和全精度 CIC16，
%                同时导出 RTL 可见的 4x/8x/128x 24bit 节点。
%
% 当前默认配置：
%                  Stage字长：24/22/20bit
%                  Stage3  ：11tap Q15 折叠补偿系数
%                  CIC     ：R=16，M=1，N=3，0bit剪枝
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-14
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-14：新增完整 Phase 7 位真用例函数。
%=============================================================

    verify_dir = fileparts(mfilename('fullpath'));
    v7_dir = fileparts(verify_dir);
    matlab_dir = fileparts(v7_dir);
    bittrue_dir = fullfile(matlab_dir, 'alt_all2x', 'bittrue');
    v2_dir = fullfile(matlab_dir, 'alt_all2x_v2');
    addpath(bittrue_dir);
    addpath(v7_dir);

    load(fullfile(v2_dir, 'stage1_strict_halfband_config.mat'), ...
        'best_config');
    load(fullfile(v7_dir, 'folded_stage3_results', ...
        'folded_stage3_pareto.mat'), 'pareto');

    selected_idx = find(strcmp({pareto.name}, 'folded_n3'), 1);
    if isempty(selected_idx)
        error('未找到正式 folded_n3 系数候选。');
    end
    selected = pareto(selected_idx);
    stage_config = best_config(1:3);
    stage_config(3).coeff_int = int64(selected.coeff_int);
    stage_config(3).frac_w = selected.row.FRAC_W;
    stage_config(3).acc_w_recommended = 38;

    x = int64(x(:).');
    [stage1, stat1] = interp2_polyphase_bittrue(x, ...
        stage_config(1).coeff_int, stage_config(1).frac_w, ...
        CFG.INPUT_W, stage_config(1).acc_w_recommended);
    [stage1_q22, bridge1_stat] = round_shift_sat_signed( ...
        stage1, CFG.INPUT_W-CFG.STAGE2_W, CFG.STAGE2_W);
    [stage2, stat2] = interp2_polyphase_bittrue(stage1_q22, ...
        stage_config(2).coeff_int, stage_config(2).frac_w, ...
        CFG.STAGE2_W, stage_config(2).acc_w_recommended);
    [stage2_q20, bridge2_stat] = round_shift_sat_signed( ...
        stage2, CFG.STAGE2_W-CFG.STAGE3_W, CFG.STAGE3_W);
    [stage3, stat3] = interp2_polyphase_bittrue(stage2_q20, ...
        stage_config(3).coeff_int, stage_config(3).frac_w, ...
        CFG.STAGE3_W, stage_config(3).acc_w_recommended);

    prune_profile = zeros(1, 2*CFG.CIC_N);
    [cic_output, cic_stat, cic_trace] = cic_interp16_bittrue( ...
        stage3, CFG.CIC_R, CFG.CIC_N, CFG.CIC_M, ...
        CFG.CIC_INPUT_W, CFG.CIC_INPUT_W, prune_profile);

    result.input = x;
    result.y4_internal = stage2;
    result.y8_internal = stage3;
    result.y128_internal = cic_output;
    result.y4_24 = bitshift(stage2, CFG.INPUT_W-CFG.STAGE2_W);
    result.y8_24 = bitshift(stage3, CFG.INPUT_W-CFG.STAGE3_W);
    result.y128_24 = bitshift(cic_output, CFG.TOP_OUTPUT_LEFT_SHIFT);
    result.h_total = selected.h_total;
    result.stage_config = stage_config;
    result.stat.stage1 = stat1;
    result.stat.bridge1 = bridge1_stat;
    result.stat.stage2 = stat2;
    result.stat.bridge2 = bridge2_stat;
    result.stat.stage3 = stat3;
    result.stat.cic = cic_stat;
    result.trace.cic = cic_trace;
end

