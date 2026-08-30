function config = nf_release_v2_config()
%=============================================================
% 文件名       : nf_release_v2_config.m
% 函数名       : nf_release_v2_config
% 功能简述     : 集中定义并返回正式配置、定点字长、滤波系数或验证门槛。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================
% 1）主函数模块：nf_release_v2_config
% 功能说明：集中定义并返回正式配置、定点字长、滤波系数或验证门槛。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


%NF_RELEASE_V2_CONFIG Auditable source of truth for the P4-D release-v2.

    config.schema = 'national-finals-release-config-v2';
    config.config_id = ...
        'NF-P4D-R2-479LUT-468FF-4DSP-2BRAM-2MMCM';
    config.part = 'xc7a35tfgg484-2';
    config.vivado = '2018.3 build 2405991';
    config.input_bits = 24;
    config.input_sample_rates_hz = [44100 48000];
    config.output_factors = [4 8 128];
    config.passband_hz = [10 20000];
    config.passband_limit_db = 0.05;
    config.stopband_attenuation_min_db = 70;

    config.stage1.coeff_int = int64([ ...
        0 -5 0 7 0 -12 0 19 0 -29 0 42 0 -59 0 80 0 -107 0 ...
        141 0 -182 0 233 0 -293 0 367 0 -455 0 562 0 -691 0 ...
        849 0 -1045 0 1296 0 -1629 0 2094 0 -2803 0 4044 0 ...
        -6876 0 20836 32768 20836 0 -6876 0 4044 0 -2803 0 ...
        2094 0 -1629 0 1296 0 -1045 0 849 0 -691 0 562 0 ...
        -455 0 367 0 -293 0 233 0 -182 0 141 0 -107 0 80 0 ...
        -59 0 42 0 -29 0 19 0 -12 0 7 0 -5 0]);
    config.stage1.frac_w = 15;
    config.stage1.input_w = 24;
    config.stage1.acc_w = 41;
    config.stage1.output_w = 24;

    config.stage2.coeff_int = int64([ ...
        -115 -203 534 1233 -1302 -4595 2116 19945 30298 19945 ...
        2116 -4595 -1302 1233 534 -203 -115]);
    config.stage2.frac_w = 15;
    config.stage2.input_w = 22;
    config.stage2.acc_w = 38;
    config.stage2.output_w = 22;

    config.stage3.coeff_int = nf_stage3_q15_coefficients();
    config.stage3.frac_w = 15;
    config.stage3.input_w = 20;
    config.stage3.acc_w = 38;
    config.stage3.output_w = 20;

    config.bridge1.shift_w = 2;
    config.bridge1.output_w = 22;
    config.bridge2.shift_w = 2;
    config.bridge2.output_w = 20;
    config.equalizer.equation = ...
        'x[n-1]+ASR3(2*x[n-1]-x[n]-x[n-2])';
    config.equalizer.input_w = 20;
    config.equalizer.output_w = 21;
    config.cic.structure = 'C2-Hold16-I2';
    config.cic.rate = 16;
    config.cic.order = 3;
    config.cic.input_w = 21;
    config.cic.first_integrator_w = 26;
    config.cic.final_integrator_w = 29;
    config.cic.normalization_shift = 8;
    config.cic.output_w = 20;
end
