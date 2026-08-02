% Generate independent P3 RTL vectors under ignored _work/.

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
p3_dir = fileparts(script_dir);
vector_profile = upper(strtrim(getenv('NF_P3_VECTOR_PROFILE')));
if isempty(vector_profile); vector_profile = 'RELEASE'; end
switch vector_profile
    case 'SMOKE'
        vector_dir = fullfile(p3_dir, '_work', 'rtl_vectors_smoke');
        seed_count = 1;
        random_input_count = 1024;
        include_fullscale = false;
    case 'RELEASE'
        vector_dir = fullfile(p3_dir, '_work', 'rtl_vectors');
        seed_count = 10;
        random_input_count = 4096;
        include_fullscale = true;
    otherwise
        error('Unknown NF_P3_VECTOR_PROFILE=%s (use SMOKE or RELEASE).', ...
            vector_profile);
end
vector_dir_override = strtrim(getenv('NF_P3_VECTOR_DIR'));
if ~isempty(vector_dir_override)
    vector_dir = vector_dir_override;
end
if ~exist(vector_dir, 'dir'); mkdir(vector_dir); end
addpath(script_dir);

seed_values = [294753618, 104729, 130363, 155921, 181081, ...
    206369, 231761, 257053, 282407, 307817];
case_names = [{'impulse'}, arrayfun(@(k) sprintf('random_seed%02d', k), ...
    1:seed_count, 'UniformOutput', false)];
if include_fullscale
    case_names = [case_names, {'fullscale_positive', 'fullscale_negative'}];
end
input_data = cell(size(case_names));
input_data{1} = zeros(1, 256, 'int64');
input_data{1}(1) = int64(2^22);

random_limit = int64(2^20);
for seed_index = 1:seed_count
    rng(seed_values(seed_index), 'twister');
    input_data{seed_index+1} = int64(randi( ...
        [-double(random_limit), double(random_limit-1)], ...
        1, random_input_count));
end
if include_fullscale
    input_data{seed_count+2} = zeros(1, 256, 'int64');
    input_data{seed_count+2}(1) = int64(2^23-1);
    input_data{seed_count+3} = zeros(1, 256, 'int64');
    input_data{seed_count+3}(1) = int64(-2^23);
end

config_id = cell(numel(case_names), 1);
input_count = zeros(numel(case_names), 1);
y4_count = zeros(numel(case_names), 1);
y8_count = zeros(numel(case_names), 1);
y128_count = zeros(numel(case_names), 1);
p3_stage3_sat = zeros(numel(case_names), 1);
p3_stage3_peak = zeros(numel(case_names), 1);
cic_sat = zeros(numel(case_names), 1);

for case_index = 1:numel(case_names)
    result = nf_p3_build_bittrue_case(input_data{case_index});
    write_case(vector_dir, case_names{case_index}, result);
    config_id{case_index} = result.config_id;
    input_count(case_index) = numel(result.input);
    y4_count(case_index) = numel(result.y4_24);
    y8_count(case_index) = numel(result.y8_24);
    y128_count(case_index) = numel(result.y128_24);
    p3_stage3_sat(case_index) = result.stat.stage3_comp.output_sat_count;
    p3_stage3_peak(case_index) = ...
        max(abs(double(result.p3_stage3_internal)));
    cic_sat(case_index) = result.stat.cic.output_sat_count;
    assert(p3_stage3_sat(case_index) == 0, ...
        'P3 Stage3 unexpectedly saturated in %s.', case_names{case_index});
    fprintf('Generated P3 RTL case %s (%d/%d)\n', ...
        case_names{case_index}, case_index, numel(case_names));
end

manifest = table(case_names(:), config_id, input_count, y4_count, ...
    y8_count, y128_count, p3_stage3_sat, p3_stage3_peak, cic_sat, ...
    'VariableNames', {'CASE_NAME', 'CONFIG_ID', 'INPUT_COUNT', ...
    'Y4_COUNT', 'Y8_COUNT', 'Y128_COUNT', 'P3_STAGE3_SAT', ...
    'P3_STAGE3_MAX_ABS', 'CIC_SAT'});
writetable(manifest, fullfile(vector_dir, 'p3_rtl_vector_manifest.csv'));
disp(manifest);
fprintf('P3_RTL_VECTORS_PASS: %s\n', vector_dir);


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
    for index = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], unsigned_data(index));
    end
end
