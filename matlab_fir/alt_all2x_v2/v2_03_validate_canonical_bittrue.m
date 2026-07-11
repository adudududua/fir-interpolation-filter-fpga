clc; clear; close all;

%=============================================================
% 文件名       : v2_03_validate_canonical_bittrue.m
% 脚本名       : v2_03_validate_canonical_bittrue
% 功能简述     : 对 canonical halfband7 五组尾级候选执行逐级 24bit
%                bit-true 验证，并导出脉冲、随机 PCM golden 向量。
%
%                输出文件：
%                  canonical_bittrue_results.csv
%                  canonical_bittrue_summary.txt
%                  golden/canonical_impulse_input_24bit.mem
%                  golden/<variant>_impulse_golden_24bit.mem
%                  golden/canonical_random_input_24bit.mem
%                  golden/<variant>_random_golden_24bit.mem
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 V2 canonical 候选 bit-true 验证。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
stable_dir = fullfile(script_dir, '..', 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
common_dir = fullfile(script_dir, 'common');

addpath(bittrue_dir);
addpath(common_dir);

config_path = fullfile(script_dir, 'canonical_variant_config.mat');
if ~exist(config_path, 'file')
    error('请先运行 v2_02_test_canonical_halfband7.m。');
end
load(config_path, 'variant_name', 'variant_config');

FS_IN = 44100;
DATA_W = 24;

rng(20260711, 'twister');
random_x = int64(randi([-2^20 2^20], 1, 128));

test_name = {'impulse', 'dc', 'sine_1k_m1dbfs', ...
             'sine_19k_m6dbfs', 'sine_20k_m6dbfs', 'random'};
test_data = cell(size(test_name));

test_data{1} = int64([2^22 zeros(1, 255)]);
test_data{2} = int64(ones(1, 512) * 2^20);
test_data{3} = make_sine(1000, -1, 1024, FS_IN, DATA_W);
test_data{4} = make_sine(19000, -6, 1024, FS_IN, DATA_W);
test_data{5} = make_sine(20000, -6, 1024, FS_IN, DATA_W);
test_data{6} = random_x;

golden_dir = fullfile(script_dir, 'golden');
if ~exist(golden_dir, 'dir')
    mkdir(golden_dir);
end
write_signed_hex_mem(fullfile(golden_dir, ...
    'canonical_impulse_input_24bit.mem'), test_data{1}, DATA_W);
write_signed_hex_mem(fullfile(golden_dir, ...
    'canonical_random_input_24bit.mem'), random_x, DATA_W);

row_variant = {};
row_test = {};
row_output_count = [];
row_overflow = [];
row_saturation = [];
row_output_peak = [];
row_pass = [];

summary_path = fullfile(script_dir, 'canonical_bittrue_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Canonical halfband7 bit-true validation\n');
fprintf(fid, '=======================================\n');

for variant_idx = 1:numel(variant_name)
    cfg = variant_config{variant_idx};
    fprintf(fid, '\n[%s]\n', variant_name{variant_idx});

    for test_idx = 1:numel(test_name)
        [y, stage_stat] = simulate_all2x_bittrue(test_data{test_idx}, cfg);
        overflow_count = sum([stage_stat.acc_overflow_count]);
        saturation_count = sum([stage_stat.output_sat_count]);
        output_peak = max(abs(double(y)));
        pass_case = (overflow_count == 0) && (saturation_count == 0);

        row_variant{end+1, 1} = variant_name{variant_idx};
        row_test{end+1, 1} = test_name{test_idx};
        row_output_count(end+1, 1) = numel(y);
        row_overflow(end+1, 1) = overflow_count;
        row_saturation(end+1, 1) = saturation_count;
        row_output_peak(end+1, 1) = output_peak;
        row_pass(end+1, 1) = pass_case;

        fprintf(fid, ['%-20s output=%7d peak=%9.0f overflow=%d ' ...
                      'sat=%d pass=%d\n'], ...
                test_name{test_idx}, numel(y), output_peak, ...
                overflow_count, saturation_count, pass_case);

        if strcmp(test_name{test_idx}, 'impulse') || ...
                strcmp(test_name{test_idx}, 'random')
            golden_path = fullfile(golden_dir, sprintf( ...
                '%s_%s_golden_24bit.mem', variant_name{variant_idx}, ...
                test_name{test_idx}));
            write_signed_hex_mem(golden_path, y, DATA_W);
        end
    end
end

fclose(fid);

result_table = table(row_variant, row_test, row_output_count, ...
                     row_overflow, row_saturation, row_output_peak, row_pass, ...
    'VariableNames', {'VARIANT', 'TEST', 'OUTPUT_COUNT', ...
                      'ACC_OVERFLOW_COUNT', 'OUTPUT_SAT_COUNT', ...
                      'OUTPUT_PEAK', 'PASS'});
writetable(result_table, ...
    fullfile(script_dir, 'canonical_bittrue_results.csv'));

if ~all(row_pass)
    error('至少一个 canonical halfband7 bit-true 常规测试未通过。');
end

fprintf('canonical halfband7 五组候选的常规 bit-true 测试全部通过。\n');


function x = make_sine(freq_hz, dbfs, sample_count, Fs, data_w)
    amplitude = (2^(data_w - 1) - 1) * 10^(dbfs/20);
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
