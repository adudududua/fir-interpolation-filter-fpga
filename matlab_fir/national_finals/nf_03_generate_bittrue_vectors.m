%=============================================================
% 文件名       : nf_03_generate_bittrue_vectors.m
% 功能简述     : 生成全国赛完整 RTL 的冲激与固定随机 0 LSB golden。
%=============================================================

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
vector_dir = fullfile(script_dir, 'vectors', 'daily');
result_dir = fullfile(script_dir, 'results');
if ~exist(vector_dir, 'dir'); mkdir(vector_dir); end
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
addpath(script_dir);

impulse = zeros(1, 256, 'int64');
impulse(1) = int64(2^22);
impulse_result = nf_build_bittrue_case(impulse);
write_case(vector_dir, 'impulse', impulse_result);

rng(294753618, 'twister');
random_limit = int64(2^20);
random_input = int64(randi( ...
    [-double(random_limit), double(random_limit-1)], 1, 1024));
random_result = nf_build_bittrue_case(random_input);
write_case(vector_dir, 'random_seed01', random_result);

case_name = {'impulse'; 'random_seed01'};
input_count = [numel(impulse_result.input); numel(random_result.input)];
y4_count = [numel(impulse_result.y4_24); numel(random_result.y4_24)];
y8_count = [numel(impulse_result.y8_24); numel(random_result.y8_24)];
y128_count = [numel(impulse_result.y128_24); ...
    numel(random_result.y128_24)];
equalizer_sat = [impulse_result.stat.equalizer.output_sat_count; ...
    random_result.stat.equalizer.output_sat_count];
cic_sat = [impulse_result.stat.cic.output_sat_count; ...
    random_result.stat.cic.output_sat_count];
manifest = table(case_name, input_count, y4_count, y8_count, ...
    y128_count, equalizer_sat, cic_sat, ...
    'VariableNames', {'CASE_NAME', 'INPUT_COUNT', 'Y4_COUNT', ...
    'Y8_COUNT', 'Y128_COUNT', 'EQUALIZER_SAT', 'CIC_SAT'});
writetable(manifest, fullfile(result_dir, 'nf_bittrue_manifest.csv'));

summary_path = fullfile(result_dir, 'nf_bittrue_generation_summary.txt');
fid = fopen(summary_path, 'w');
if fid < 0; error('无法创建总结：%s', summary_path); end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'National finals bit-true vector generation\n');
fprintf(fid, '==========================================\n');
fprintf(fid, 'Stage3: flat 11-tap Q15 FIR\n');
fprintf(fid, 'Equalizer: [-1 10 -1]/8, arithmetic shift, 20 bit sat\n');
fprintf(fid, 'CIC: R=16 M=1 N=3, full precision, 20 bit output\n\n');
for idx = 1:height(manifest)
    fprintf(fid, ['%s input=%d y4=%d y8=%d y128=%d ' ...
        'eq_sat=%d cic_sat=%d\n'], ...
        manifest.CASE_NAME{idx}, manifest.INPUT_COUNT(idx), ...
        manifest.Y4_COUNT(idx), manifest.Y8_COUNT(idx), ...
        manifest.Y128_COUNT(idx), manifest.EQUALIZER_SAT(idx), ...
        manifest.CIC_SAT(idx));
end

disp(manifest);
fprintf('全国赛位真向量生成完成：%s\n', vector_dir);


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
    if fid < 0; error('无法创建向量：%s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for idx = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], unsigned_data(idx));
    end
end
