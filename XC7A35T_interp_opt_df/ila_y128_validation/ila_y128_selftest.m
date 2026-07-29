%=============================================================
% 文件名       : ila_y128_selftest.m
% 脚本名       : ila_y128_selftest
% 功能简述     : 使用 MATLAB 黄金周期构造一份 Vivado 风格 Hex CSV，
%                回读后验证自动解析、相位对齐、逐点比较、误差直方图
%                和结果文件输出流程。该测试不代替真实 FPGA ILA 抓取。
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-20
% 版本         : V2018.3
% 开发工具     : MATLAB R2023a
% 修订记录     :
%                2026-07-20：新增 ILA CSV 验证流程自检。
%=============================================================

clc; close all;
script_dir = fileparts(mfilename('fullpath'));
capture_dir = fullfile(script_dir, 'captures');
if ~exist(capture_dir, 'dir'); mkdir(capture_dir); end
[steady_period, ~] = ila_y128_build_demo_golden(false);
capture_count = 4096;
start_offset = 12345;
source_data = [steady_period; steady_period];
source_data = source_data(start_offset+1:start_offset+capture_count);
selftest_csv = fullfile(capture_dir, 'ila_y128_selftest.csv');

fid = fopen(selftest_csv, 'w');
if fid < 0; error('无法创建自检 CSV：%s', selftest_csv); end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, ['Sample in Buffer,Sample in Window,TRIGGER,' ...
    'demo_audio_sync,ila_final128_sample_w[23:0]\n']);
for sample_idx = 1:capture_count
    unsigned_value = mod(double(source_data(sample_idx)), 2^24);
    fprintf(fid, '%d,%d,0,1,%06X\n', sample_idx-1, ...
        sample_idx-1, unsigned_value);
end
clear cleanup_obj;

result = ila_y128_compare(selftest_csv, 'selftest');
if ~result.pass
    error('ILA y128 验证流程自检失败。');
end
fprintf('ILA y128 验证流程自检通过：4096 点逐点 0 LSB。\n');
