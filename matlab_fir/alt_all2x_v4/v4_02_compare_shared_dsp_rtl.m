clc; clear;

%=============================================================
% 文件名       : v4_02_compare_shared_dsp_rtl.m
% 脚本名       : v4_02_compare_shared_dsp_rtl
% 功能简述     : V4 Stage 2/3 共享 DSP RTL 分级 bit-true 对拍。
%                Stage 2/3 输出与 V3 BRAM 参考链比较，最终 128x
%                输出与 MATLAB golden 按预期固定延迟直接比较，
%                不再自动搜索最佳延迟，避免掩盖漏样或相位错位。
%
%                输出文件：
%                  phase4_shared_dsp_rtl_results.csv
%                  phase4_shared_dsp_rtl_summary.txt
%
% 当前默认配置：
%                  测试类型：冲激、随机 PCM
%                  比较节点：Stage 2、Stage 3、完整 128x
%                  通过标准：最大误差 0 LSB，mismatch 数 0
%                  RTL 目录：%TEMP%/codex_fir_interpolation/phase5_q15_sim
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-12
% 版本         : V2018.3
% 开发工具     : MATLAB / Vivado
% 修订记录     :
%                2026-07-12：新增 V4 共享 DSP 分级 RTL 对拍。
%                2026-07-12：Phase 5 固定 Stage 2/3/完整链延迟。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
golden_dir = fullfile(fileparts(script_dir), 'alt_all2x_v2', 'golden');
rtl_dir = fullfile(getenv('TEMP'), 'codex_fir_interpolation', ...
                   'phase5_q15_sim');

row_name = {
    'stage2_impulse';
    'stage2_random';
    'stage3_impulse';
    'stage3_random';
    'full_impulse';
    'full_random'};
test_file = {
    'v4_stage2_impulse.csv';
    'v4_stage2_random.csv';
    'v4_stage3_impulse.csv';
    'v4_stage3_random.csv';
    'v4_full_impulse.csv';
    'v4_full_random.csv'};
ref_file = {
    'v3_stage2_impulse.csv';
    'v3_stage2_random.csv';
    'v3_stage3_impulse.csv';
    'v3_stage3_random.csv';
    'stage1_strict_impulse_golden_24bit.mem';
    'stage1_strict_random_golden_24bit.mem'};
ref_is_mem = [false; false; false; false; true; true];
expected_shift = [0; 0; 0; 0; 127; 127];

n_case = numel(row_name);
fixed_shift = zeros(n_case, 1);
test_count = zeros(n_case, 1);
ref_count = zeros(n_case, 1);
compare_count = zeros(n_case, 1);
max_error = zeros(n_case, 1);
rms_error = zeros(n_case, 1);
mismatch = zeros(n_case, 1);
pass = false(n_case, 1);

for case_idx = 1:n_case
    test_y = read_csv_stream(fullfile(rtl_dir, test_file{case_idx}));
    if ref_is_mem(case_idx)
        ref_y = read_signed_hex_mem(...
            fullfile(golden_dir, ref_file{case_idx}), 24);
        require_full_ref = true;
    else
        ref_y = read_csv_stream(fullfile(rtl_dir, ref_file{case_idx}));
        require_full_ref = false;
    end

    result = compare_one(test_y, ref_y, expected_shift(case_idx), ...
                         require_full_ref);
    fixed_shift(case_idx) = result.shift;
    test_count(case_idx) = numel(test_y);
    ref_count(case_idx) = numel(ref_y);
    compare_count(case_idx) = result.compare_count;
    max_error(case_idx) = result.max_abs_error;
    rms_error(case_idx) = result.rms_error;
    mismatch(case_idx) = result.mismatch;
    pass(case_idx) = result.pass;
end

result_table = table(row_name, fixed_shift, test_count, ref_count, ...
    compare_count, max_error, rms_error, mismatch, pass, ...
    'VariableNames', {'CASE_NAME', 'FIXED_SHIFT', 'TEST_COUNT', ...
    'REFERENCE_COUNT', 'COMPARE_COUNT', 'MAX_ABS_ERROR_LSB', ...
    'RMS_ERROR_LSB', 'MISMATCH_COUNT', 'PASS'});
writetable(result_table, fullfile(script_dir, ...
           'phase4_shared_dsp_rtl_results.csv'));

summary_path = fullfile(script_dir, ...
                        'phase4_shared_dsp_rtl_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'V4 Stage 2/3 shared DSP RTL comparison\n');
fprintf(fid, '=======================================\n');
for case_idx = 1:n_case
    fprintf(fid, ['%-16s shift=%4d compare=%6d max=%4.0f LSB ' ...
                  'mismatch=%6d pass=%d\n'], ...
            row_name{case_idx}, fixed_shift(case_idx), ...
            compare_count(case_idx), max_error(case_idx), ...
            mismatch(case_idx), pass(case_idx));
end
fprintf(fid, 'overall_pass=%d\n', all(pass));
fclose(fid);

disp(result_table);
if ~all(pass)
    error('V4 共享 DSP RTL 对拍存在非 0 LSB 项。');
end
fprintf('V4 Stage 2、Stage 3 与完整 128x 冲激/随机对拍全部为 0 LSB。\n');


function data = read_csv_stream(filename)
    if ~exist(filename, 'file')
        error('找不到 RTL 输出：%s', filename);
    end
    stream_table = readtable(filename);
    data = double(stream_table.y_out(:)).';
end


function result = compare_one(test_y, ref_y, expected_shift, require_full_ref)
    test_first = find(test_y ~= 0, 1, 'first');
    ref_first = find(ref_y ~= 0, 1, 'first');
    if isempty(test_first) || isempty(ref_first)
        error('测试流或参考流全零，拒绝产生伪通过结果。');
    end

    observed_shift = test_first - ref_first;
    if observed_shift ~= expected_shift
        error('固定延迟错误：预期 %d，实际首个非零样点偏移 %d。', ...
              expected_shift, observed_shift);
    end

    ref_start = max(1, 1-expected_shift);
    test_start = ref_start + expected_shift;
    count = min(numel(ref_y)-ref_start+1, ...
                numel(test_y)-test_start+1);
    if count <= 0
        error('固定延迟后没有可比较样点。');
    end
    if require_full_ref && count ~= numel(ref_y)
        error('完整链固定延迟后没有覆盖全部参考样点。');
    end
    if ~require_full_ref && count < min(numel(test_y), numel(ref_y))-64
        error('分级固定延迟后的覆盖长度不足。');
    end

    error_value = test_y(test_start:test_start+count-1) - ...
                  ref_y(ref_start:ref_start+count-1);
    result.shift = expected_shift;
    result.compare_count = count;
    result.max_abs_error = max(abs(error_value));
    result.rms_error = sqrt(mean(error_value.^2));
    result.mismatch = nnz(error_value);
    result.pass = result.max_abs_error == 0 && result.mismatch == 0;
end


function data = read_signed_hex_mem(filename, data_w)
    fid = fopen(filename, 'r');
    raw = textscan(fid, '%s');
    fclose(fid);
    unsigned_value = hex2dec(raw{1});
    data = double(unsigned_value(:).');
    sign_threshold = 2^(data_w - 1);
    modulus = 2^data_w;
    data(data >= sign_threshold) = data(data >= sign_threshold) - modulus;
end
