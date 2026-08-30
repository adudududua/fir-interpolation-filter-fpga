%=============================================================
% 文件名       : nf_05_validate_release_v2_model.m
% 脚本名       : nf_05_validate_release_v2_model
% 功能简述     : 运行规定工况的自动验证，汇总误差并给出通过或失败结论。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================

% Validate the P0 release-v2 20->21-bit equalizer/CIC boundary.

%% 1）主流程：nf_05_validate_release_v2_model
% 功能说明：运行规定工况的自动验证，汇总误差并给出通过或失败结论。

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(script_dir);
addpath(script_dir);
addpath(fullfile(matlab_root, 'alt_all2x', 'bittrue'));
addpath(fullfile(matlab_root, 'alt_all2x_v7'));

input_min = int64(-2^19);
input_max = int64(2^19-1);
directed = [input_min input_max input_min input_max input_min 0 0];
[wide, wide_stat] = nf_cic3_shiftadd_bittrue(directed, 20, 21);
[legacy, legacy_stat] = nf_cic3_shiftadd_bittrue(directed, 20, 20);

assert(wide_stat.output_sat_count == 0, ...
    'The signed-21 equalizer unexpectedly saturated.');
assert(wide_stat.max_abs_output > 2^19, ...
    'Directed sequence did not cross the signed-20 boundary.');
assert(wide_stat.max_abs_output <= 2^20, ...
    'Directed sequence exceeded the proven signed-21 bound.');
assert(legacy_stat.output_sat_count > 0, ...
    'Legacy signed-20 model did not fail the directed negative test.');
assert(any(wide ~= legacy), ...
    'Legacy and release-v2 models unexpectedly matched at the boundary.');

rng(240821, 'twister');
cic_input = int64(randi([-2^20, 2^20-1], 1, 512));
[hold_output, hold_stat] = nf_cic_n3_hold2_bittrue(cic_input, 21, 20);
[reference_output, reference_stat] = cic_interp16_bittrue( ...
    cic_input, 16, 3, 1, 21, 20, zeros(1, 6));
assert(isequal(hold_output, reference_output), ...
    'C2/Hold16/I2 is not bit-true with the C3/up16/I3 reference.');
assert(hold_stat.first_integrator_w == 26 && ...
    hold_stat.final_integrator_w == 29, ...
    'Release-v2 CIC state widths are not 26/29 bits.');

vector_dir = fullfile(script_dir, 'vectors', 'daily');
case_names = {'impulse', 'random_seed01'};
case_pass = false(size(case_names));
for case_idx = 1:numel(case_names)
    case_name = case_names{case_idx};
    input_data = read_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_input_24bit.mem']), 24);
    result = nf_build_bittrue_case(input_data);
    expected4 = read_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y4_golden_24bit.mem']), 24);
    expected8 = read_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y8_golden_24bit.mem']), 24);
    expected128 = read_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y128_golden_24bit.mem']), 24);
    assert(isequal(result.y4_24(:), expected4(:)), ...
        '%s 4x changed after the 21-bit model fix.', case_name);
    assert(isequal(result.y8_24(:), expected8(:)), ...
        '%s 8x changed after the 21-bit model fix.', case_name);
    assert(isequal(result.y128_24(:), expected128(:)), ...
        '%s 128x changed after the 21-bit model fix.', case_name);
    case_pass(case_idx) = true;
end

result_path = fullfile(script_dir, 'results', ...
    'p0_release_v2_model_validation.txt');
fid = fopen(result_path, 'w');
if fid < 0; error('Unable to create %s.', result_path); end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'P0 release-v2 model validation\n');
fprintf(fid, '==============================\n');
release = nf_release_v2_config();
fprintf(fid, 'CONFIG_ID=%s\n', release.config_id);
fprintf(fid, 'DIRECTED_WIDE_MAX_ABS=%d\n', ...
    int64(wide_stat.max_abs_output));
fprintf(fid, 'DIRECTED_WIDE_SAT=%d\n', wide_stat.output_sat_count);
fprintf(fid, 'DIRECTED_LEGACY20_SAT=%d\n', ...
    legacy_stat.output_sat_count);
fprintf(fid, 'DIRECTED_OLD_MODEL_MISMATCH=%d\n', any(wide ~= legacy));
fprintf(fid, 'CIC_HOLD_REFERENCE_SAMPLES=%d\n', numel(hold_output));
fprintf(fid, 'CIC_HOLD_REFERENCE_0LSB=%d\n', ...
    isequal(hold_output, reference_output));
fprintf(fid, 'CIC_STATE_WIDTHS=%d/%d\n', ...
    hold_stat.first_integrator_w, hold_stat.final_integrator_w);
fprintf(fid, 'LOW_AMPLITUDE_DAILY_0LSB=%d/%d\n', ...
    nnz(case_pass), numel(case_pass));
fprintf(fid, 'REFERENCE_CIC_OUTPUT_SAT=%d\n', ...
    reference_stat.output_sat_count);
fprintf(fid, 'OVERALL_PASS=1\n');

fprintf(['P0 RELEASE-V2 MODEL PASS: max_abs=%d, legacy_sat=%d, ' ...
    'CIC samples=%d, daily=%d/%d.\n'], ...
    int64(wide_stat.max_abs_output), legacy_stat.output_sat_count, ...
    numel(hold_output), nnz(case_pass), numel(case_pass));


% 2）局部函数模块：read_signed_hex_mem


% 功能说明：读取外部配置、RTL结果或数据文件，并转换为主流程使用的统一数据格式。
function data = read_signed_hex_mem(filename, data_w)
    text_value = strtrim(fileread(filename));
    if isempty(text_value)
        data = zeros(0, 1, 'int64');
        return;
    end
    tokens = regexp(text_value, '\s+', 'split');
    unsigned_value = hex2dec(tokens);
    signed_value = unsigned_value;
    negative = unsigned_value >= 2^(data_w-1);
    signed_value(negative) = signed_value(negative)-2^data_w;
    data = int64(signed_value(:));
end
