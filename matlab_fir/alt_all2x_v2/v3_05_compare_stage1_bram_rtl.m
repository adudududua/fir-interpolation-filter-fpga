clc; clear;

%=============================================================
% 文件名       : v3_05_compare_stage1_bram_rtl.m
% 脚本名       : v3_05_compare_stage1_bram_rtl
% 功能简述     : 将 V3 strict Stage 1 BRAM 完整七级输出与 MATLAB
%                128x bit-true golden 进行固定延迟搜索和逐点对拍。
%
%                输出文件：
%                  stage1_strict_bram_rtl_results.csv
%                  stage1_strict_bram_rtl_summary.txt
%
% 当前默认配置：
%                  测试类型：冲激、随机 PCM
%                  判定标准：最大误差 0 LSB，不一致点数 0
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB / Vivado
% 修订记录     :
%                2026-07-11：新增 V3 Stage 1 BRAM 完整链路对拍。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
workspace_dir = fileparts(fileparts(script_dir));
golden_dir = fullfile(script_dir, 'golden');
rtl_dir = fullfile(workspace_dir, '.codex_xvlog_check', 'all2x_v3');

test_name = {'impulse'; 'random'};
rtl_name = {'v3_strict_bram_impulse_output.csv'; ...
            'v3_strict_bram_random_output.csv'};
golden_name = {'stage1_strict_impulse_golden_24bit.mem'; ...
               'stage1_strict_random_golden_24bit.mem'};

row_test = cell(numel(test_name), 1);
row_shift = zeros(numel(test_name), 1);
row_max_error = zeros(numel(test_name), 1);
row_rms_error = zeros(numel(test_name), 1);
row_mismatch = zeros(numel(test_name), 1);
row_rtl_count = zeros(numel(test_name), 1);
row_golden_count = zeros(numel(test_name), 1);
row_pass = false(numel(test_name), 1);

summary_path = fullfile(script_dir, ...
                        'stage1_strict_bram_rtl_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'V3 Stage 1 strict-halfband BRAM RTL comparison\n');
fprintf(fid, '==========================================\n');

for test_idx = 1:numel(test_name)
    rtl_path = fullfile(rtl_dir, rtl_name{test_idx});
    golden_path = fullfile(golden_dir, golden_name{test_idx});
    if ~exist(rtl_path, 'file')
        error('找不到 RTL 输出：%s', rtl_path);
    end

    rtl_table = readtable(rtl_path);
    rtl_y = double(rtl_table.y_out(:)).';
    golden_y = read_signed_hex_mem(golden_path, 24);
    result = compare_one(rtl_y, golden_y);

    row_test{test_idx} = test_name{test_idx};
    row_shift(test_idx) = result.shift;
    row_max_error(test_idx) = result.max_abs_error;
    row_rms_error(test_idx) = result.rms_error;
    row_mismatch(test_idx) = result.mismatch;
    row_rtl_count(test_idx) = numel(rtl_y);
    row_golden_count(test_idx) = numel(golden_y);
    row_pass(test_idx) = result.pass;

    fprintf(fid, ['%-8s shift=%5d rtl=%6d golden=%6d ' ...
                  'max=%4.0f LSB mismatch=%d pass=%d\n'], ...
            test_name{test_idx}, result.shift, numel(rtl_y), ...
            numel(golden_y), result.max_abs_error, ...
            result.mismatch, result.pass);
end
fclose(fid);

result_table = table(row_test, row_shift, row_rtl_count, ...
    row_golden_count, row_max_error, row_rms_error, row_mismatch, ...
    row_pass, 'VariableNames', {'TEST', 'FIXED_SHIFT', 'RTL_COUNT', ...
    'GOLDEN_COUNT', 'MAX_ABS_ERROR_LSB', 'RMS_ERROR_LSB', ...
    'MISMATCH_COUNT', 'PASS'});
writetable(result_table, fullfile(script_dir, ...
           'stage1_strict_bram_rtl_results.csv'));

disp(result_table);
if ~all(row_pass)
    error('V3 Stage 1 BRAM 完整链路 RTL 对拍未达到 0 LSB。');
end
fprintf('V3 Stage 1 BRAM 冲激与随机 PCM 对拍均为 0 LSB。\n');


function result = compare_one(rtl_y, golden_y)
    rtl_first = find(rtl_y ~= 0, 1, 'first');
    golden_first = find(golden_y ~= 0, 1, 'first');
    if isempty(rtl_first) || isempty(golden_first)
        error('RTL 或 golden 全零，无法进行有效对拍。');
    end

    shift_estimate = rtl_first - golden_first;
    shift_min = max(0, shift_estimate - 512);
    shift_max = min(numel(rtl_y) - numel(golden_y), ...
                    shift_estimate + 512);
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
