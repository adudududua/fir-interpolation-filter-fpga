function h_cic = design_cic16_interpolator(cic_order, rate_change, diff_delay)
%=============================================================
% 文件名       : design_cic16_interpolator.m
% 函数名       : design_cic16_interpolator
% 功能简述     : 构造标准 CIC 插值器在高采样率端的等效 FIR
%                冲激响应。RTL 对应结构为：
%                  低速 comb -> R 倍插零 -> 高速 integrator。
%
%                原始等效响应由 N 个长度 R*M 的矩形脉冲
%                卷积得到。本函数把直流增益归一化为 R，
%                与一个 R 倍插值滤波器的系统增益约定一致。
%
% 当前默认配置：
%                  插值倍率：R = 16
%                  差分延迟：M = 1
%                  CIC 阶数：N = 3 / 4 / 5
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增标准 CIC 插值等效响应函数。
%=============================================================
% 1）主函数模块：design_cic16_interpolator
% 功能说明：建立滤波器设计指标，搜索候选结构并评价幅频、相位和实现代价。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


    if cic_order < 1 || fix(cic_order) ~= cic_order
        error('cic_order 必须为正整数。');
    end
    if rate_change < 2 || fix(rate_change) ~= rate_change
        error('rate_change 必须为不小于 2 的整数。');
    end
    if diff_delay < 1 || fix(diff_delay) ~= diff_delay
        error('diff_delay 必须为正整数。');
    end

    one_section = ones(1, rate_change*diff_delay);
    h_cic = 1;
    for section_idx = 1:cic_order
        h_cic = conv(h_cic, one_section);
    end

    h_cic = h_cic * (rate_change/sum(h_cic));
end
