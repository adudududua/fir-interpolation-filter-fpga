function coeff = nf_stage3_q15_coefficients()
%=============================================================
% 文件名       : nf_stage3_q15_coefficients.m
% 函数名       : nf_stage3_q15_coefficients
% 功能简述     : 集中定义并返回正式配置、定点字长、滤波系数或验证门槛。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================
% 1）主函数模块：nf_stage3_q15_coefficients
% 功能说明：集中定义并返回正式配置、定点字长、滤波系数或验证门槛。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


%NF_STAGE3_Q15_COEFFICIENTS Authoritative national-finals Stage3 taps.
%   The natural-order 11-tap interpolator is stored as signed Q15.  Its
%   even and odd polyphase sums are both 32764/32768, so a constant input
%   retains unity amplitude after 2x interpolation.

    coeff = int64([404, -148, -3272, 522, 19250, 32016, ...
        19250, 522, -3272, -148, 404]);

    phase0_sum = sum(coeff(1:2:end));
    phase1_sum = sum(coeff(2:2:end));
    assert(phase0_sum == 32764 && phase1_sum == 32764, ...
        'National-finals Stage3 Q15 polyphase gain invariant failed.');
end
