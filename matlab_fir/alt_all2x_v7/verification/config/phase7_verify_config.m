function CFG = phase7_verify_config(profile_name)
%=============================================================
% 文件名       : phase7_verify_config.m
% 函数名       : phase7_verify_config
% 功能简述     : Phase 7 FIR-CIC 补充验证的集中参数配置。
%                本配置锁定正式折叠补偿 N=3 候选，并统一管理
%                采样率、频响门槛、冲激长度、RTL 固定样点偏移、
%                多种子规模和板级实测结果。
%
% 当前默认配置：
%                  回归档位：daily
%                  随机规模：4 seed x 1024 input
%                  CIC     ：R=16，M=1，N=3，末级剪枝0bit
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-14
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-14：新增 Phase 7 补充验证集中配置。
%=============================================================
% 1）主函数模块：phase7_verify_config
% 功能说明：集中定义并返回正式配置、定点字长、滤波系数或验证门槛。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


    if nargin < 1 || isempty(profile_name)
        profile_name = 'daily';
    end

    CFG.FS_IN = 44100;
    CFG.FS_2X = 88200;
    CFG.FS_4X = 176400;
    CFG.FS_8X = 352800;
    CFG.FS_128X = 5644800;

    CFG.FPASS_LOW = 10;
    CFG.FPASS_HIGH = 20000;
    CFG.FSTOP = 24100;
    CFG.SPEC_PASS_DB = 0.05;
    CFG.RELEASE_PASS_DB = 0.01;
    CFG.SPEC_STOP_DB = 70;
    CFG.WARN_STOP_DB = 72;

    CFG.INPUT_W = 24;
    CFG.STAGE2_W = 22;
    CFG.STAGE3_W = 20;
    CFG.CIC_R = 16;
    CFG.CIC_M = 1;
    CFG.CIC_N = 3;
    CFG.CIC_INPUT_W = 20;
    CFG.CIC_FULL_W = 32;
    CFG.CIC_PRUNE_LSB = 0;
    CFG.CIC_OUTPUT_SHIFT = 8;
    CFG.TOP_OUTPUT_LEFT_SHIFT = 4;

    CFG.IR_LEN_4X = 225;
    CFG.IR_LEN_8X = 459;
    CFG.IR_LEN_128X = 7374;
    CFG.GROUP_DELAY_128X = (CFG.IR_LEN_128X-1)/2;
    CFG.GAIN_4X = 4;
    CFG.GAIN_8X = 8;
    CFG.GAIN_128X = 128;

    % 4x/8x 偏移来自已通过的前三级 RTL 回归。128x 偏移是
    % Stage3 的7个低速有效样点偏移映射到 CIC16 后的样点数。
    CFG.EXPECTED_SHIFT_4X = 3;
    CFG.EXPECTED_SHIFT_8X = 7;
    CFG.EXPECTED_SHIFT_128X = 7*CFG.CIC_R;

    CFG.IMPULSE_INPUT_COUNT = 256;
    CFG.DAILY_SEEDS = [294753618, 20260714, 44100, 5644800];
    CFG.NIGHTLY_SEEDS = [CFG.DAILY_SEEDS, 7, 17, 31, 127, 1024, 7374];
    CFG.NUM_INPUT_DAILY = 1024;
    CFG.NUM_INPUT_NIGHTLY = 4096;
    CFG.RANDOM_PEAK_BITS = 21;

    switch lower(profile_name)
        case 'daily'
            CFG.PROFILE = 'daily';
            CFG.SEEDS = CFG.DAILY_SEEDS;
            CFG.NUM_RANDOM_INPUT = CFG.NUM_INPUT_DAILY;
        case 'nightly'
            CFG.PROFILE = 'nightly';
            CFG.SEEDS = CFG.NIGHTLY_SEEDS;
            CFG.NUM_RANDOM_INPUT = CFG.NUM_INPUT_NIGHTLY;
        otherwise
            error('未知 Phase 7 验证档位：%s', profile_name);
    end

    CFG.BOARD_MODE = {'4x', '8x', '128x'};
    CFG.BOARD_THEORY_HZ = [176400, 352800, 5644800];
    CFG.BOARD_MEASURED_HZ = [176370, 352860, 5640000];
end

