%% 1）主流程：v2_04_compare_canonical_rtl
% 功能说明：在相同输入下对齐 MATLAB 黄金模型与 RTL 输出，执行逐样本 bit-true 判定。

clc; clear; close all;

%=============================================================
% 文件名       : v2_04_compare_canonical_rtl.m
% 脚本名       : v2_04_compare_canonical_rtl
% 功能简述     : 对 V2 canonical halfband7 四组 RTL 候选执行
%                冲激响应和随机 PCM 的 MATLAB bit-true 逐点对拍。
%                先依据首个非零样本估计固定延迟，再在邻域精确搜索。
%
%                输出文件：
%                  canonical_rtl_compare_results.csv
%                  canonical_rtl_compare_summary.txt
%
% 当前默认配置：
%                  对拍数据位宽：24bit signed
%                  通过条件    ：最大误差 0 LSB，不一致样本数 0
%                  RTL 临时目录：系统 temp/codex_vivado_fir_interpolation
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 V2 四候选冲激与随机 RTL 对拍。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
golden_dir = fullfile(script_dir, 'golden');
rtl_root = fullfile(tempdir, 'codex_vivado_fir_interpolation', ...
                    'all2x_v2_sim');

variant_name = {'stage7', 'stage6_7', 'stage5_7', 'stage4_7'};
test_name = {'random', 'impulse'};

row_variant = {};
row_test = {};
row_rtl_count = [];
row_golden_count = [];
row_shift = [];
row_max_error = [];
row_rms_error = [];
row_mismatch = [];
row_pass = [];

summary_path = fullfile(script_dir, ...
                        'canonical_rtl_compare_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Canonical halfband7 RTL comparison\n');
fprintf(fid, '==================================\n');

for test_idx = 1:numel(test_name)
    test_id = test_name{test_idx};
    fprintf(fid, '\n[%s]\n', test_id);

    for variant_idx = 1:numel(variant_name)
        variant_id = variant_name{variant_idx};
        rtl_csv = fullfile(rtl_root, test_id, ...
            sprintf('v2_%s_output.csv', variant_id));
        golden_mem = fullfile(golden_dir, ...
            sprintf('%s_%s_golden_24bit.mem', variant_id, test_id));

        if ~exist(rtl_csv, 'file')
            error('未找到 RTL 输出：%s', rtl_csv);
        end
        if ~exist(golden_mem, 'file')
            error('未找到 MATLAB golden：%s', golden_mem);
        end

        rtl_table = readtable(rtl_csv);
        rtl_y = double(rtl_table.y_out(:)).';
        golden_y = read_signed_hex_mem(golden_mem, 24);
        result = compare_one(rtl_y, golden_y);

        row_variant{end+1, 1} = variant_id;
        row_test{end+1, 1} = test_id;
        row_rtl_count(end+1, 1) = numel(rtl_y);
        row_golden_count(end+1, 1) = numel(golden_y);
        row_shift(end+1, 1) = result.shift;
        row_max_error(end+1, 1) = result.max_abs_error;
        row_rms_error(end+1, 1) = result.rms_error;
        row_mismatch(end+1, 1) = result.mismatch;
        row_pass(end+1, 1) = result.pass;

        fprintf(fid, ['%-10s rtl=%6d golden=%6d shift=%5d ' ...
                      'max=%4.0f LSB mismatch=%d pass=%d\n'], ...
                variant_id, numel(rtl_y), numel(golden_y), ...
                result.shift, result.max_abs_error, ...
                result.mismatch, result.pass);
        fprintf(['%-8s %-10s | shift=%5d | max=%4.0f LSB | ' ...
                 'mismatch=%d | pass=%d\n'], ...
                test_id, variant_id, result.shift, ...
                result.max_abs_error, result.mismatch, result.pass);
    end
end

fclose(fid);

result_table = table(row_variant, row_test, row_rtl_count, ...
                     row_golden_count, row_shift, row_max_error, ...
                     row_rms_error, row_mismatch, row_pass, ...
    'VariableNames', {'VARIANT', 'TEST', 'RTL_COUNT', 'GOLDEN_COUNT', ...
                      'BEST_SHIFT', 'MAX_ABS_ERROR_LSB', 'RMS_ERROR_LSB', ...
                      'MISMATCH_COUNT', 'PASS'});
writetable(result_table, ...
    fullfile(script_dir, 'canonical_rtl_compare_results.csv'));

if ~all(row_pass)
    error('至少一组 V2 canonical RTL 对拍未达到 0 LSB。');
end

fprintf('V2 canonical 四候选的冲激与随机 RTL 对拍全部为 0 LSB。\n');


% 2）局部函数模块：compare_one


% 功能说明：对齐参考数据与待测数据，计算逐样本误差并形成一致性判定。
function result = compare_one(rtl_y, golden_y)
    rtl_first = find(rtl_y ~= 0, 1, 'first');
    golden_first = find(golden_y ~= 0, 1, 'first');

    if isempty(rtl_first) || isempty(golden_first)
        error('RTL 或 golden 全零，无法进行有效对拍。');
    end

    shift_estimate = rtl_first - golden_first;
    shift_min = max(0, shift_estimate - 256);
    shift_max = min(numel(rtl_y) - numel(golden_y), ...
                    shift_estimate + 256);

    if shift_max < shift_min
        error('RTL 输出长度不足，无法覆盖完整 golden。');
    end

    best_shift = shift_min;
    best_max_error = inf;
    best_rms_error = inf;

    for shift = shift_min:shift_max
        rtl_seg = rtl_y(shift+1 : shift+numel(golden_y));
        error_seg = rtl_seg - golden_y;
        max_error = max(abs(error_seg));
        rms_error = sqrt(mean(error_seg.^2));

        if max_error < best_max_error || ...
                (max_error == best_max_error && rms_error < best_rms_error)
            best_shift = shift;
            best_max_error = max_error;
            best_rms_error = rms_error;
        end
    end

    rtl_aligned = rtl_y(best_shift+1 : best_shift+numel(golden_y));
    error_value = rtl_aligned - golden_y;

    result.shift = best_shift;
    result.max_abs_error = max(abs(error_value));
    result.rms_error = sqrt(mean(error_value.^2));
    result.mismatch = nnz(error_value);
    result.pass = (result.max_abs_error == 0) && ...
                  (result.mismatch == 0);
end


% 3）局部函数模块：read_signed_hex_mem


% 功能说明：读取外部配置、RTL结果或数据文件，并转换为主流程使用的统一数据格式。
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
