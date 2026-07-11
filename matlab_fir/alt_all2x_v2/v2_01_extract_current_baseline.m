clc; clear; close all;

%=============================================================
% 文件名       : v2_01_extract_current_baseline.m
% 脚本名       : v2_01_extract_current_baseline
% 功能简述     : 从 alt_all2x 稳定目录读取当前七级配置，重新计算
%                总链路指标并保存 V2 实验使用的基线配置。
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 V2 稳定基线提取脚本。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
stable_dir = fullfile(script_dir, '..', 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
common_dir = fullfile(script_dir, 'common');

addpath(bittrue_dir);
addpath(common_dir);

FS_IN = 44100;
FS_OUT = 5644800;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
RIPPLE_LIMIT_DB = 0.05;
STOP_LIMIT_DB = 70;
EXPECTED_GAIN = 128;
NFFT = 2^18;

stage_config = load_all2x_stage_config(stable_dir, 24);
h_total = build_multistage_ir(stage_config);
res = check_total_chain(h_total, FS_IN, FS_OUT, ...
                        F_PASS_LOW, F_PASS_HIGH, ...
                        RIPPLE_LIMIT_DB, STOP_LIMIT_DB, ...
                        EXPECTED_GAIN, NFFT);

save(fullfile(script_dir, 'baseline_stage_config.mat'), ...
     'stage_config', 'h_total', 'res');

summary_path = fullfile(script_dir, 'baseline_manifest.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'All-2x V2 stable baseline manifest\n');
fprintf(fid, '=================================\n');
fprintf(fid, 'Git commit            = 8418c7f\n');
fprintf(fid, 'Git tag               = regional-final-all2x-baseline\n');
fprintf(fid, 'Equivalent taps       = %d\n', numel(h_total));
fprintf(fid, 'Pass abs max dB       = %.8f\n', res.pass_abs_max_db);
fprintf(fid, 'Pass ripple pm dB     = %.8f\n', res.ripple_pm_db);
fprintf(fid, 'Stop attenuation dB   = %.8f\n', res.stop_attn_db);
fprintf(fid, 'DC gain               = %.10f\n', res.dc_gain);
fprintf(fid, 'Group delay samples   = %.8f\n', res.gd_mean);
fprintf(fid, 'Group delay pp        = %.12f\n', res.gd_pp);
fprintf(fid, 'Pass all              = %d\n', res.pass_all);
fclose(fid);

fprintf('V2 基线提取完成：\n');
fprintf('  通带最大绝对误差 = %.8f dB\n', res.pass_abs_max_db);
fprintf('  阻带衰减         = %.8f dB\n', res.stop_attn_db);
fprintf('  总链路通过       = %d\n', res.pass_all);

if ~res.pass_all
    error('稳定基线重新计算未通过，停止 V2 实验。');
end
