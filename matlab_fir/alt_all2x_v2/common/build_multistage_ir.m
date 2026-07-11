function h_total = build_multistage_ir(stage_config)
%=============================================================
% 文件名       : build_multistage_ir.m
% 函数名       : build_multistage_ir
% 功能简述     : 根据逐级 2x 整数系数配置构造最终采样率下的
%                多级 128x 等效冲激响应。
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 V2 多级等效冲激响应构造函数。
%=============================================================

    if isempty(stage_config)
        error('stage_config 不能为空。');
    end

    h_total = double(stage_config(1).coeff_int) / ...
              2^stage_config(1).frac_w;
    h_total = h_total(:).';

    for stage_idx = 2:numel(stage_config)
        h_up = zeros(1, 2*numel(h_total) - 1);
        h_up(1:2:end) = h_total;

        h_stage = double(stage_config(stage_idx).coeff_int) / ...
                  2^stage_config(stage_idx).frac_w;
        h_total = conv(h_up, h_stage(:).');
    end
end
