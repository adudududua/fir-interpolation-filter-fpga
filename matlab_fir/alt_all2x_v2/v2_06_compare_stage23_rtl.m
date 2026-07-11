clc; clear; close all;

%=============================================================
% 文件名       : v2_06_compare_stage23_rtl.m
% 脚本名       : v2_06_compare_stage23_rtl
% 功能简述     : 将 Phase 2 的 S3-only、S2～S3 true-polyphase
%                RTL 输出，与 Phase 1 的 stage4_7 MATLAB bit-true
%                golden 进行冲激响应和随机 PCM 的逐点 0 LSB 对拍。
%
%                输出文件：
%                  stage23_polyphase_rtl_results.csv
%                  stage23_polyphase_rtl_summary.txt
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 Phase 2 Stage 2/3 RTL 对拍。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
golden_dir = fullfile(script_dir, 'golden');
rtl_root = fullfile(tempdir, 'codex_vivado_fir_interpolation', ...
                    'all2x_v2_phase2_sim');

variant_name = {'poly_stage3', 'poly_stage2', 'lightbridge'};
rtl_stem = {'v2_poly_stage3_output.csv', ...
            'v2_poly_stage2_output.csv', ...
            'v2_lightbridge_output.csv'};
test_name = {'random', 'impulse'};

row_variant = {};
row_test = {};
row_shift = [];
row_max_error = [];
row_rms_error = [];
row_mismatch = [];
row_pass = [];

summary_path = fullfile(script_dir, ...
                        'stage23_polyphase_rtl_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Stage 2/3 true-polyphase RTL comparison\n');
fprintf(fid, '========================================\n');

for test_idx = 1:numel(test_name)
    test_id = test_name{test_idx};
    golden_mem = fullfile(golden_dir, ...
        sprintf('stage4_7_%s_golden_24bit.mem', test_id));
    golden_y = read_signed_hex_mem(golden_mem, 24);
    fprintf(fid, '\n[%s]\n', test_id);

    for variant_idx = 1:numel(variant_name)
        rtl_csv = fullfile(rtl_root, test_id, rtl_stem{variant_idx});
        if ~exist(rtl_csv, 'file')
            error('未找到 Phase 2 RTL 输出：%s', rtl_csv);
        end

        rtl_table = readtable(rtl_csv);
        rtl_y = double(rtl_table.y_out(:)).';
        result = compare_one(rtl_y, golden_y);

        row_variant{end+1, 1} = variant_name{variant_idx};
        row_test{end+1, 1} = test_id;
        row_shift(end+1, 1) = result.shift;
        row_max_error(end+1, 1) = result.max_abs_error;
        row_rms_error(end+1, 1) = result.rms_error;
        row_mismatch(end+1, 1) = result.mismatch;
        row_pass(end+1, 1) = result.pass;

        fprintf(fid, ['%-12s shift=%5d max=%4.0f LSB ' ...
                      'mismatch=%d pass=%d\n'], ...
                variant_name{variant_idx}, result.shift, ...
                result.max_abs_error, result.mismatch, result.pass);
        fprintf(['%-8s %-12s | shift=%5d | max=%4.0f LSB | ' ...
                 'mismatch=%d | pass=%d\n'], ...
                test_id, variant_name{variant_idx}, result.shift, ...
                result.max_abs_error, result.mismatch, result.pass);
    end
end

fclose(fid);

result_table = table(row_variant, row_test, row_shift, ...
                     row_max_error, row_rms_error, ...
                     row_mismatch, row_pass, ...
    'VariableNames', {'VARIANT', 'TEST', 'BEST_SHIFT', ...
                      'MAX_ABS_ERROR_LSB', 'RMS_ERROR_LSB', ...
                      'MISMATCH_COUNT', 'PASS'});
writetable(result_table, ...
    fullfile(script_dir, 'stage23_polyphase_rtl_results.csv'));

if ~all(row_pass)
    error('至少一组 Stage 2/3 true-polyphase RTL 对拍未达到 0 LSB。');
end

fprintf('Stage 2/3 true-polyphase 随机与冲激 RTL 对拍全部为 0 LSB。\n');


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
        error_seg = rtl_y(shift+1 : shift+numel(golden_y)) - golden_y;
        max_error = max(abs(error_seg));
        rms_error = sqrt(mean(error_seg.^2));
        if max_error < best_max_error || ...
                (max_error == best_max_error && rms_error < best_rms_error)
            best_shift = shift;
            best_max_error = max_error;
            best_rms_error = rms_error;
        end
    end

    error_value = rtl_y(best_shift+1 : ...
                        best_shift+numel(golden_y)) - golden_y;
    result.shift = best_shift;
    result.max_abs_error = max(abs(error_value));
    result.rms_error = sqrt(mean(error_value.^2));
    result.mismatch = nnz(error_value);
    result.pass = (result.max_abs_error == 0) && ...
                  (result.mismatch == 0);
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
