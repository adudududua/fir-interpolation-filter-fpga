% Generate the release-scale bit-true vectors used by the P4-D RTL gate.
% Outputs are reproducible working data and remain under ignored _work/.

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
vector_dir = fullfile(script_dir, '_work', 'release_vectors');
if ~exist(vector_dir, 'dir'); mkdir(vector_dir); end
addpath(script_dir);

seed_values = [294753618, 104729, 130363, 155921, 181081, ...
    206369, 231761, 257053, 282407, 307817];
random_limit = int64(2^20);
case_count = 13;
case_names = cell(case_count, 1);
config_ids = cell(case_count, 1);
seeds = nan(case_count, 1);
input_counts = zeros(case_count, 1);
y4_counts = zeros(case_count, 1);
y8_counts = zeros(case_count, 1);
y128_counts = zeros(case_count, 1);
equalizer_saturations = zeros(case_count, 1);
equalizer_max_abs = zeros(case_count, 1);
equalizer_exceeds_signed20 = zeros(case_count, 1);
cic_first_max_abs = zeros(case_count, 1);
cic_final_max_abs = zeros(case_count, 1);
cic_first_wraps = zeros(case_count, 1);
cic_final_wraps = zeros(case_count, 1);
cic_saturations = zeros(case_count, 1);

impulse = zeros(1, 256, 'int64');
impulse(1) = int64(2^22);
impulse_result = nf_build_bittrue_case(impulse);
write_case(vector_dir, 'impulse', impulse_result);
[case_names{1}, config_ids{1}, input_counts(1), y4_counts(1), ...
    y8_counts(1), y128_counts(1), equalizer_saturations(1), ...
    equalizer_max_abs(1), equalizer_exceeds_signed20(1), ...
    cic_first_max_abs(1), cic_final_max_abs(1), cic_first_wraps(1), ...
    cic_final_wraps(1), cic_saturations(1)] = ...
    describe_case('impulse', impulse_result);

for seed_index = 1:numel(seed_values)
    rng(seed_values(seed_index), 'twister');
    random_input = int64(randi( ...
        [-double(random_limit), double(random_limit-1)], 1, 4096));
    random_result = nf_build_bittrue_case(random_input);
    case_name = sprintf('random_seed%02d', seed_index);
    write_case(vector_dir, case_name, random_result);
    row = seed_index + 1;
    seeds(row) = seed_values(seed_index);
    [case_names{row}, config_ids{row}, input_counts(row), ...
        y4_counts(row), y8_counts(row), y128_counts(row), ...
        equalizer_saturations(row), equalizer_max_abs(row), ...
        equalizer_exceeds_signed20(row), cic_first_max_abs(row), ...
        cic_final_max_abs(row), cic_first_wraps(row), ...
        cic_final_wraps(row), cic_saturations(row)] = ...
        describe_case(case_name, random_result);
    fprintf('Generated %s (%d/10)\n', case_name, seed_index);
end

directed_names = {'fullscale_positive', 'fullscale_negative'};
directed_values = [int64(2^23-1), int64(-2^23)];
for directed_index = 1:2
    directed_input = zeros(1, 256, 'int64');
    directed_input(1) = directed_values(directed_index);
    directed_result = nf_build_bittrue_case(directed_input);
    row = 11+directed_index;
    write_case(vector_dir, directed_names{directed_index}, directed_result);
    [case_names{row}, config_ids{row}, input_counts(row), ...
        y4_counts(row), y8_counts(row), y128_counts(row), ...
        equalizer_saturations(row), equalizer_max_abs(row), ...
        equalizer_exceeds_signed20(row), cic_first_max_abs(row), ...
        cic_final_max_abs(row), cic_first_wraps(row), ...
        cic_final_wraps(row), cic_saturations(row)] = ...
        describe_case(directed_names{directed_index}, directed_result);
    assert(equalizer_saturations(row) == 0, ...
        '%s unexpectedly saturated the signed-21 equalizer.', ...
        directed_names{directed_index});
    assert(equalizer_exceeds_signed20(row) > 0, ...
        '%s did not exercise the signed-20/21 boundary.', ...
        directed_names{directed_index});
end

manifest = table(case_names, config_ids, seeds, input_counts, y4_counts, ...
    y8_counts, y128_counts, equalizer_saturations, equalizer_max_abs, ...
    equalizer_exceeds_signed20, cic_first_max_abs, cic_final_max_abs, ...
    cic_first_wraps, cic_final_wraps, cic_saturations, ...
    'VariableNames', {'CASE_NAME', 'CONFIG_ID', 'RNG_SEED', ...
    'INPUT_COUNT', 'Y4_COUNT', 'Y8_COUNT', 'Y128_COUNT', ...
    'EQUALIZER_SAT', 'EQUALIZER_MAX_ABS', ...
    'EQUALIZER_EXCEEDS_SIGNED20', 'CIC_I1_MAX_ABS', ...
    'CIC_I2_MAX_ABS', 'CIC_I1_WRAP', 'CIC_I2_WRAP', 'CIC_SAT'});
writetable(manifest, fullfile(vector_dir, 'release_vector_manifest.csv'));
disp(manifest);
fprintf('NF_RELEASE_VECTORS_PASS: %s\n', vector_dir);


function [name, config_id, input_count, y4_count, y8_count, y128_count, ...
        equalizer_sat, equalizer_peak, equalizer_exceeds20, ...
        cic_i1_peak, cic_i2_peak, cic_i1_wrap, cic_i2_wrap, ...
        cic_sat] = describe_case(name, result)
    config_id = result.config_id;
    input_count = numel(result.input);
    y4_count = numel(result.y4_24);
    y8_count = numel(result.y8_24);
    y128_count = numel(result.y128_24);
    equalizer_sat = result.stat.equalizer.output_sat_count;
    equalizer_peak = result.stat.equalizer.max_abs_output;
    equalizer_exceeds20 = ...
        result.stat.equalizer.exceeds_input_width_count;
    cic_i1_peak = result.stat.cic.first_integrator_max_abs;
    cic_i2_peak = result.stat.cic.final_integrator_max_abs;
    cic_i1_wrap = result.stat.cic.first_integrator_wrap_count;
    cic_i2_wrap = result.stat.cic.final_integrator_wrap_count;
    cic_sat = result.stat.cic.output_sat_count;
end


function write_case(vector_dir, case_name, result)
    write_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_input_24bit.mem']), result.input, 24);
    write_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y4_golden_24bit.mem']), result.y4_24, 24);
    write_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y8_golden_24bit.mem']), result.y8_24, 24);
    write_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y128_golden_24bit.mem']), result.y128_24, 24);
end


function write_signed_hex_mem(filename, data, data_w)
    digits = ceil(data_w/4);
    unsigned_data = mod(double(int64(data(:))), 2^data_w);
    fid = fopen(filename, 'w');
    if fid < 0; error('Unable to create vector: %s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for idx = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], unsigned_data(idx));
    end
end
