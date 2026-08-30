%=============================================================
% 文件名       : nf_06_generate_release_v2_metadata.m
% 脚本名       : nf_06_generate_release_v2_metadata
% 功能简述     : 整理计算结果并导出后续 RTL、仿真或报告流程需要的技术文件。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================

% Generate deterministic, text-based release metadata from the source of truth.

%% 1）主流程：nf_06_generate_release_v2_metadata
% 功能说明：整理计算结果并导出后续 RTL、仿真或报告流程需要的技术文件。

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, 'release_v2');
if ~exist(output_dir, 'dir'); mkdir(output_dir); end
addpath(script_dir);

config = nf_release_v2_config();
write_json(fullfile(output_dir, 'p4d_release_v2_config.json'), config);

q = struct();
q.schema = 'national-finals-q-format-v2';
q.config_id = config.config_id;
q.input = struct('signed_bits', config.input_bits, ...
    'sample_rates_hz', config.input_sample_rates_hz);
q.stage1 = rmfield(config.stage1, 'coeff_int');
q.bridge1 = config.bridge1;
q.stage2 = rmfield(config.stage2, 'coeff_int');
q.bridge2 = config.bridge2;
q.stage3 = rmfield(config.stage3, 'coeff_int');
q.equalizer = config.equalizer;
q.cic = config.cic;
q.formal_outputs = struct('x4', 'stage2 signed-22 << 2', ...
    'x8', 'stage3 signed-20 << 4', ...
    'x128', 'CIC signed-20 << 4');
q.rounding = ['FIR Q15 uses bias 16383 plus signed carry before ASR15; ' ...
    'bridges and CIC use their declared signed round-shift helpers'];
write_json(fullfile(output_dir, 'q_format_and_scaling.json'), q);

stage = {};
tap_index = [];
coefficient_integer = [];
fraction_bits = [];
for stage_index = 1:3
    stage_name = sprintf('stage%d', stage_index);
    coefficient = config.(stage_name).coeff_int(:);
    row_count = numel(coefficient);
    stage = [stage; repmat({stage_name}, row_count, 1)]; %#ok<AGROW>
    tap_index = [tap_index; (0:row_count-1).']; %#ok<AGROW>
    coefficient_integer = [coefficient_integer; coefficient]; %#ok<AGROW>
    fraction_bits = [fraction_bits; ...
        repmat(config.(stage_name).frac_w, row_count, 1)]; %#ok<AGROW>
end
coefficient_table = table(stage, tap_index, coefficient_integer, ...
    fraction_bits, 'VariableNames', {'STAGE', 'TAP_INDEX', ...
    'COEFFICIENT_INTEGER', 'FRACTION_BITS'});
writetable(coefficient_table, fullfile(output_dir, 'coefficients.csv'));

fprintf('NF_RELEASE_V2_METADATA_PASS: config=%s coefficients=%d\n', ...
    config.config_id, height(coefficient_table));


% 2）局部函数模块：write_json


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_json(filename, value)
    text_value = jsonencode(value, 'PrettyPrint', true);
    fid = fopen(filename, 'w', 'n', 'UTF-8');
    if fid < 0; error('Unable to create %s.', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s\n', text_value);
end
