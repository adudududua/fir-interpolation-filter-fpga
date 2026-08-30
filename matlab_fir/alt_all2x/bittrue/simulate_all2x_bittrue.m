function [y, stage_stat] = simulate_all2x_bittrue(x, stage_config)
%=============================================================
% 文件名       : simulate_all2x_bittrue.m
% 函数名       : simulate_all2x_bittrue
% 功能简述     : 使用逐级 2 相整数模型仿真完整 7 级全 2x 插值链路。
%                每一级均使用独立整数系数、FRAC_W 和推荐 ACC_W，
%                级间数据固定饱和为 24bit signed。
%
% 当前默认配置：
%                  输入采样率：44.1kHz
%                  输出采样率：5.6448MHz
%                  插值结构  ：7 级 2x
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增完整全 2x bit-true 链路模型。
%=============================================================
% 1）主函数模块：simulate_all2x_bittrue
% 功能说明：按 RTL 舍入、饱和和流水规则建立逐位一致的定点行为模型。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


    y = int64(x(:).');
    stage_stat = [];

    for stage_idx = 1:numel(stage_config)
        cfg = stage_config(stage_idx);
        [y, one_stat] = interp2_polyphase_bittrue( ...
            y, cfg.coeff_int, cfg.frac_w, cfg.data_w, ...
            cfg.acc_w_recommended);

        one_stat.stage_idx = stage_idx;
        one_stat.acc_w = cfg.acc_w_recommended;
        one_stat.frac_w = cfg.frac_w;
        if stage_idx == 1
            stage_stat = one_stat;
        else
            stage_stat(stage_idx) = one_stat;
        end
    end
end
