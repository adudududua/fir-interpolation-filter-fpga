clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
vector_dir = fullfile(script_dir, 'vectors', 'daily');
result_dir = fullfile(script_dir, 'results');
if ~exist(vector_dir, 'dir'); mkdir(vector_dir); end
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
addpath(script_dir);

case_name = strings(3, 1);
input_count = zeros(3, 1);
y4_count = zeros(3, 1);
y8_count = zeros(3, 1);
y128_count = zeros(3, 1);
total_sat = zeros(3, 1);

impulse = zeros(1, 256, 'int64');
impulse(1) = int64(2^22);
[case_name(1), input_count(1), y4_count(1), y8_count(1), ...
    y128_count(1), total_sat(1)] = build_write_case( ...
    vector_dir, "impulse", impulse);

rng(294753618, 'twister');
random_limit = int64(2^20);
random_input = int64(randi( ...
    [-double(random_limit), double(random_limit-1)], 1, 1024));
[case_name(2), input_count(2), y4_count(2), y8_count(2), ...
    y128_count(2), total_sat(2)] = build_write_case( ...
    vector_dir, "random_seed01", random_input);

rng(804128, 'twister');
fullscale_limit = int64(2^23);
fullscale_input = int64(randi( ...
    [-double(fullscale_limit), double(fullscale_limit-1)], 1, 512));
[case_name(3), input_count(3), y4_count(3), y8_count(3), ...
    y128_count(3), total_sat(3)] = build_write_case( ...
    vector_dir, "random_fullscale", fullscale_input);

manifest = table(case_name, input_count, y4_count, y8_count, ...
    y128_count, total_sat, ...
    'VariableNames', {'CASE_NAME', 'INPUT_COUNT', 'Y4_COUNT', ...
    'Y8_COUNT', 'Y128_COUNT', 'TOTAL_OUTPUT_SAT'});
writetable(manifest, fullfile(result_dir, ...
    'route2_bittrue_manifest.csv'));
disp(manifest);
fprintf('Route 2B bit-true vectors generated: %s\n', vector_dir);


function [name_out, input_n, y4_n, y8_n, y128_n, sat_n] = ...
        build_write_case(vector_dir, case_name, input_data)
    result = route2_build_bittrue_case(input_data);
    write_signed_hex_mem(fullfile(vector_dir, ...
        case_name+'_input_24bit.mem'), result.input, 24);
    write_signed_hex_mem(fullfile(vector_dir, ...
        case_name+'_y4_golden_24bit.mem'), result.y4_24, 24);
    write_signed_hex_mem(fullfile(vector_dir, ...
        case_name+'_y8_golden_24bit.mem'), result.y8_24, 24);
    write_signed_hex_mem(fullfile(vector_dir, ...
        case_name+'_y128_golden_24bit.mem'), result.y128_24, 24);

    name_out = case_name;
    input_n = numel(result.input);
    y4_n = numel(result.y4_24);
    y8_n = numel(result.y8_24);
    y128_n = numel(result.y128_24);
    stat_names = {'stage1', 'bridge1', 'stage2', 'bridge2', ...
        'stage3', 'hb4', 'hb5', 'cic'};
    sat_n = 0;
    for idx = 1:numel(stat_names)
        one_stat = result.stat.(stat_names{idx});
        if isfield(one_stat, 'output_sat_count')
            sat_n = sat_n+one_stat.output_sat_count;
        end
    end
end


function write_signed_hex_mem(filename, data, data_w)
    digits = ceil(data_w/4);
    unsigned_data = mod(double(int64(data(:))), 2^data_w);
    fid = fopen(filename, 'w');
    if fid < 0; error('Cannot create %s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for idx = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], unsigned_data(idx));
    end
end
