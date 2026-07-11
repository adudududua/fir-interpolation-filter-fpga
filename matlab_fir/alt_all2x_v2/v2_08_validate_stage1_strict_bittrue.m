clc; clear; close all;

%=============================================================
% 文件名       : v2_08_validate_stage1_strict_bittrue.m
% 脚本名       : v2_08_validate_stage1_strict_bittrue
% 功能简述     : 对 Stage 1 严格半带最优候选执行七级 24bit
%                bit-true 验证，区分常规无削顶测试与满幅饱和测试，
%                并导出后续 RTL 对拍使用的脉冲和随机 PCM golden。
%
%                输出文件：
%                  stage1_strict_bittrue_results.csv
%                  stage1_strict_bittrue_summary.txt
%                  golden/stage1_strict_*_24bit.mem
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 Stage 1 严格半带 bit-true 验证。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
stable_dir = fullfile(script_dir, '..', 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
addpath(bittrue_dir);

config_path = fullfile(script_dir, ...
                       'stage1_strict_halfband_config.mat');
if ~exist(config_path, 'file')
    error('请先运行 v2_07_design_stage1_strict_halfband.m。');
end
load(config_path, 'best_config');

FS_IN = 44100;
DATA_W = 24;
rng(20260711, 'twister');

test_name = {'impulse', 'dc', 'sine_1k_m1dbfs', ...
             'sine_19k_m6dbfs', 'sine_20k_m6dbfs', ...
             'random', 'alternate_fullscale', 'random_fullscale'};
test_class = {'regular', 'regular', 'regular', 'regular', ...
              'regular', 'regular', 'stress', 'stress'};
test_data = cell(size(test_name));

test_data{1} = int64([2^22 zeros(1, 255)]);
test_data{2} = int64(ones(1, 512) * 2^20);
test_data{3} = make_sine(1000, -1, 1024, FS_IN, DATA_W);
test_data{4} = make_sine(19000, -6, 1024, FS_IN, DATA_W);
test_data{5} = make_sine(20000, -6, 1024, FS_IN, DATA_W);
test_data{6} = int64(randi([-2^20 2^20], 1, 128));
test_data{7} = int64(repmat([2^(DATA_W-1)-1 -2^(DATA_W-1)], 1, 256));
test_data{8} = int64(randi([-2^(DATA_W-1) 2^(DATA_W-1)-1], 1, 256));

golden_dir = fullfile(script_dir, 'golden');
if ~exist(golden_dir, 'dir')
    mkdir(golden_dir);
end
write_signed_hex_mem(fullfile(golden_dir, ...
    'stage1_strict_impulse_input_24bit.mem'), test_data{1}, DATA_W);
write_signed_hex_mem(fullfile(golden_dir, ...
    'stage1_strict_random_input_24bit.mem'), test_data{6}, DATA_W);

row_test = {};
row_class = {};
row_output_count = [];
row_acc_overflow = [];
row_output_sat = [];
row_output_peak = [];
row_functional_pass = [];
row_no_clipping_pass = [];

summary_path = fullfile(script_dir, ...
                        'stage1_strict_bittrue_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Stage 1 strict halfband bit-true validation\n');
fprintf(fid, '===========================================\n');

for test_idx = 1:numel(test_name)
    [y, stage_stat] = simulate_all2x_bittrue(test_data{test_idx}, ...
                                             best_config);
    overflow_count = sum([stage_stat.acc_overflow_count]);
    saturation_count = sum([stage_stat.output_sat_count]);
    output_peak = max(abs(double(y)));
    functional_pass = (overflow_count == 0);
    no_clipping_pass = (saturation_count == 0);

    row_test{end+1, 1} = test_name{test_idx};
    row_class{end+1, 1} = test_class{test_idx};
    row_output_count(end+1, 1) = numel(y);
    row_acc_overflow(end+1, 1) = overflow_count;
    row_output_sat(end+1, 1) = saturation_count;
    row_output_peak(end+1, 1) = output_peak;
    row_functional_pass(end+1, 1) = functional_pass;
    row_no_clipping_pass(end+1, 1) = no_clipping_pass;

    fprintf(fid, ['%-20s class=%-7s output=%7d peak=%9.0f ' ...
                  'overflow=%d sat=%d functional=%d no_clip=%d\n'], ...
            test_name{test_idx}, test_class{test_idx}, numel(y), ...
            output_peak, overflow_count, saturation_count, ...
            functional_pass, no_clipping_pass);

    if strcmp(test_name{test_idx}, 'impulse') || ...
            strcmp(test_name{test_idx}, 'random')
        write_signed_hex_mem(fullfile(golden_dir, sprintf( ...
            'stage1_strict_%s_golden_24bit.mem', ...
            test_name{test_idx})), y, DATA_W);
    end
end
fclose(fid);

result_table = table(row_test, row_class, row_output_count, ...
                     row_acc_overflow, row_output_sat, row_output_peak, ...
                     row_functional_pass, row_no_clipping_pass, ...
    'VariableNames', {'TEST', 'CLASS', 'OUTPUT_COUNT', ...
                      'ACC_OVERFLOW_COUNT', 'OUTPUT_SAT_COUNT', ...
                      'OUTPUT_PEAK', 'FUNCTIONAL_PASS', ...
                      'NO_CLIPPING_PASS'});
writetable(result_table, ...
    fullfile(script_dir, 'stage1_strict_bittrue_results.csv'));

regular_idx = strcmp(row_class, 'regular');
if ~all(row_functional_pass) || ...
        ~all(row_no_clipping_pass(regular_idx))
    error('Stage 1 严格半带 bit-true 验证未通过。');
end

fprintf('Stage 1 严格半带 bit-true 验证通过。\n');


function x = make_sine(freq_hz, dbfs, sample_count, Fs, data_w)
    amplitude = (2^(data_w-1)-1) * 10^(dbfs/20);
    n = 0:sample_count-1;
    x = int64(round(amplitude * sin(2*pi*freq_hz*n/Fs)));
end


function write_signed_hex_mem(filename, data, data_w)
    digits = ceil(data_w / 4);
    unsigned_data = mod(double(int64(data(:))), 2^data_w);
    fid = fopen(filename, 'w');
    for idx = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], unsigned_data(idx));
    end
    fclose(fid);
end

