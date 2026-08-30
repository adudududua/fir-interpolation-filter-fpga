function stage_config = apply_canonical_halfband7(stage_config, first_stage)
%=============================================================
% 文件名       : apply_canonical_halfband7.m
% 函数名       : apply_canonical_halfband7
% 功能简述     : 从指定级开始，把 Stage 4～7 的系数替换为精确
%                7 tap canonical halfband 核，并更新位宽和增益信息。
%
%                精确系数：
%                  [-1 0 9 16 9 0 -1] / 16
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 V2 canonical halfband7 配置函数。
%=============================================================
% 1）主函数模块：apply_canonical_halfband7
% 功能说明：把规范半带滤波器应用到输入序列并保持与 RTL 相同的定点规则。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


    if first_stage < 4 || first_stage > 8
        error('first_stage 必须位于 4～8，8 表示不替换。');
    end

    if first_stage == 8
        return;
    end

    coeff_int = int64([-1 0 9 16 9 0 -1]);
    phase0 = coeff_int(1:2:end);
    phase1 = coeff_int(2:2:end);
    data_w = stage_config(1).data_w;
    x_max = 2^(data_w - 1) - 1;
    phase_abs_sum = max(sum(abs(double(phase0))), ...
                        sum(abs(double(phase1))));
    acc_w_min = ceil(log2(double(x_max)*phase_abs_sum + 1)) + 1;

    for stage_idx = first_stage:numel(stage_config)
        stage_config(stage_idx).order_n = 6;
        stage_config(stage_idx).taps = 7;
        stage_config(stage_idx).coeff_int = coeff_int;
        stage_config(stage_idx).coeff_w_design = 6;
        stage_config(stage_idx).coeff_w_min = 6;
        stage_config(stage_idx).frac_w = 4;
        stage_config(stage_idx).prune_thr = 0;
        stage_config(stage_idx).nonzero_half = 3;
        stage_config(stage_idx).acc_w_min = acc_w_min;
        stage_config(stage_idx).acc_w_recommended = acc_w_min + 1;
        stage_config(stage_idx).dc_gain = 2.0;
        stage_config(stage_idx).phase0_gain = 1.0;
        stage_config(stage_idx).phase1_gain = 1.0;
        stage_config(stage_idx).gain_mode = 'CANONICAL_HB7_Q4';
    end
end
