clc; clear; close all;

%=============================================================
% 文件名       : validate_all2x_bittrue.m
% 脚本名       : validate_all2x_bittrue
% 功能简述     : 全 2x 级联 128 倍插值链路的 24bit bit-true 验证脚本。
%                本脚本自动读取最新设计汇总与逐级整数系数，验证：
%                  1. 冲激下 polyphase 与直接插零模型完全一致；
%                  2. 直流及通带正弦的幅度保持；
%                  3. -60/-90/-110dBFS 小信号保留能力；
%                  4. 随机 PCM 的逐级溢出和饱和情况；
%                  5. 满量程直流与正负交替输入的边界行为；
%                  6. 每级理论 ACC_W、两相增益和实际最大累加值。
%
%                输出文件：
%                  all2x_bittrue_summary.txt
%                  all2x_bittrue_test_result.csv
%                  ../rtl_export/all2x_rtl_stage_config.csv
%
% 当前默认配置：
%                  输入采样率：44.1kHz
%                  输出采样率：5.6448MHz
%                  数据位宽  ：24bit signed
%                  级间量化  ：RTL 等价舍入并饱和
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增全 2x bit-true 综合测试脚本。
%=============================================================

%% 1）路径与配置
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
design_dir = fullfile(script_dir, '..');
rtl_export_dir = fullfile(design_dir, 'rtl_export');

if ~exist(rtl_export_dir, 'dir')
    mkdir(rtl_export_dir);
end

addpath(script_dir);

DATA_W = 24;
FS_IN = 44100;
FS_OUT = 5644800;
stage_config = load_all2x_stage_config(design_dir, DATA_W);

total_taps = stage_config(1).taps;
for stage_idx = 2:numel(stage_config)
    total_taps = 2 * (total_taps - 1) + stage_config(stage_idx).taps;
end

summary_path = fullfile(script_dir, 'all2x_bittrue_summary.txt');
result_csv_path = fullfile(script_dir, 'all2x_bittrue_test_result.csv');
config_csv_path = fullfile(rtl_export_dir, 'all2x_rtl_stage_config.csv');

export_stage_config(config_csv_path, stage_config);

fprintf('====================================================\n');
fprintf('全 2x 级联 128 倍插值 bit-true 验证开始\n');
fprintf('总等效冲激响应长度 = %d tap\n', total_taps);
fprintf('====================================================\n\n');

%% 2）构造测试集合
%=============================================================

test_case = make_case('impulse_2p22', 'impulse', ...
    [int64(2^22) zeros(1, 255, 'int64')], 0, 2^22, 0.05);
case_idx = 1;

case_idx = case_idx + 1;
test_case(case_idx) = make_case('dc_2p20', 'dc', ...
    repmat(int64(2^20), 1, 1024), 0, 2^20, 0.05);

case_idx = case_idx + 1;
test_case(case_idx) = make_sine_case('sine_1k_m1dbfs', 1000, -1, 4096, FS_IN, DATA_W, 0.05);

case_idx = case_idx + 1;
test_case(case_idx) = make_sine_case('sine_19k_m6dbfs', 19000, -6, 4096, FS_IN, DATA_W, 0.05);

case_idx = case_idx + 1;
test_case(case_idx) = make_sine_case('sine_20k_m6dbfs', 20000, -6, 4096, FS_IN, DATA_W, 0.05);

case_idx = case_idx + 1;
test_case(case_idx) = make_sine_case('sine_1k_m60dbfs', 1000, -60, 2048, FS_IN, DATA_W, 0.30);

case_idx = case_idx + 1;
test_case(case_idx) = make_sine_case('sine_1k_m90dbfs', 1000, -90, 2048, FS_IN, DATA_W, 1.00);

case_idx = case_idx + 1;
test_case(case_idx) = make_sine_case('sine_1k_m110dbfs', 1000, -110, 2048, FS_IN, DATA_W, 3.00);

rng(20260710, 'twister');
case_idx = case_idx + 1;
random_x = int64(randi([-2^20 2^20], 1, 1024));
test_case(case_idx) = make_case('random_pcm_21bit', 'random', random_x, 0, 0, 0);

case_idx = case_idx + 1;
test_case(case_idx) = make_case('fullscale_positive', 'limit', ...
    repmat(int64(2^23 - 1), 1, 1024), 0, 2^23 - 1, 0);

case_idx = case_idx + 1;
test_case(case_idx) = make_case('fullscale_negative', 'limit', ...
    repmat(int64(-2^23), 1, 1024), 0, 2^23, 0);

case_idx = case_idx + 1;
alternating_x = repmat([int64(2^23 - 1) int64(-2^23)], 1, 512);
test_case(case_idx) = make_case('fullscale_alternating', 'limit', ...
    alternating_x, 0, 2^23, 0);

%% 3）逐项运行 bit-true 验证
%=============================================================

test_result = struct([]);
stage_max_abs_acc = zeros(1, numel(stage_config));
stage_overflow_total = zeros(1, numel(stage_config));
stage_sat_total = zeros(1, numel(stage_config));

for idx = 1:numel(test_case)
    tc = test_case(idx);
    fprintf('运行测试：%s\n', tc.name);

    [y, stage_stat] = simulate_all2x_bittrue(tc.x, stage_config);

    overflow_count = 0;
    sat_count = 0;
    for stage_idx = 1:numel(stage_stat)
        overflow_count = overflow_count + stage_stat(stage_idx).acc_overflow_count;
        sat_count = sat_count + stage_stat(stage_idx).output_sat_count;
        stage_max_abs_acc(stage_idx) = max(stage_max_abs_acc(stage_idx), ...
            stage_stat(stage_idx).max_abs_acc);
        stage_overflow_total(stage_idx) = stage_overflow_total(stage_idx) + ...
            stage_stat(stage_idx).acc_overflow_count;
        stage_sat_total(stage_idx) = stage_sat_total(stage_idx) + ...
            stage_stat(stage_idx).output_sat_count;
    end

    metric = analyze_case(tc, y, FS_OUT, total_taps);
    direct_match = 1;
    direct_max_error = 0;

    if strcmp(tc.kind, 'impulse')
        y_direct = simulate_direct_insert_zero(tc.x, stage_config);
        direct_max_error = max(abs(double(y) - double(y_direct)));
        direct_match = (direct_max_error == 0);
    end

    pass_case = (overflow_count == 0) && direct_match;
    if ~strcmp(tc.kind, 'limit')
        pass_case = pass_case && (sat_count == 0);
    end

    if strcmp(tc.kind, 'dc') || strcmp(tc.kind, 'sine') || strcmp(tc.kind, 'small')
        pass_case = pass_case && isfinite(metric.gain_error_db) && ...
                    (abs(metric.gain_error_db) <= tc.gain_tolerance_db);
    end

    if strcmp(tc.kind, 'small')
        pass_case = pass_case && (nnz(y) > 0);
    end

    test_result(idx).name = tc.name;
    test_result(idx).kind = tc.kind;
    test_result(idx).input_peak = max(abs(double(tc.x)));
    test_result(idx).output_peak = max(abs(double(y)));
    test_result(idx).gain_error_db = metric.gain_error_db;
    test_result(idx).snr_db = metric.snr_db;
    test_result(idx).acc_overflow_count = overflow_count;
    test_result(idx).output_sat_count = sat_count;
    test_result(idx).zero_output_ratio = nnz(y == 0) / numel(y);
    test_result(idx).direct_max_error = direct_max_error;
    test_result(idx).pass_all = pass_case;

    fprintf(['  gain=%8.4f dB, SNR=%8.2f dB, overflow=%d, sat=%d, ' ...
             'pass=%d\n'], metric.gain_error_db, metric.snr_db, ...
             overflow_count, sat_count, pass_case);
end

%% 4）导出结果
%=============================================================

export_test_result(result_csv_path, test_result);

fid = fopen(summary_path, 'w');
fprintf(fid, 'All-2x 128x bit-true validation summary\n');
fprintf(fid, '=======================================\n');
fprintf(fid, 'Input sample rate       = %.1f Hz\n', FS_IN);
fprintf(fid, 'Output sample rate      = %.1f Hz\n', FS_OUT);
fprintf(fid, 'Data width              = %d bit signed\n', DATA_W);
fprintf(fid, 'Total equivalent taps   = %d\n\n', total_taps);

fprintf(fid, 'Stage configuration\n');
fprintf(fid, '-------------------\n');
for stage_idx = 1:numel(stage_config)
    cfg = stage_config(stage_idx);
    fprintf(fid, ['Stage %d: taps=%d, COEFF_W_DESIGN=%d, COEFF_W_MIN=%d, ' ...
                  'FRAC_W=%d, ACC_W_MIN=%d, ACC_W_REC=%d, ' ...
                  'dc=%.10f, phase0=%.10f, phase1=%.10f, ' ...
                  'max_abs_acc=%.0f, overflow=%d, sat=%d\n'], ...
                  stage_idx, cfg.taps, cfg.coeff_w_design, cfg.coeff_w_min, ...
                  cfg.frac_w, cfg.acc_w_min, cfg.acc_w_recommended, ...
                  cfg.dc_gain, cfg.phase0_gain, cfg.phase1_gain, ...
                  stage_max_abs_acc(stage_idx), stage_overflow_total(stage_idx), ...
                  stage_sat_total(stage_idx));
end

fprintf(fid, '\nTest result\n');
fprintf(fid, '-----------\n');
for idx = 1:numel(test_result)
    r = test_result(idx);
    fprintf(fid, ['%s: gain=%.6f dB, SNR=%.3f dB, input_peak=%.0f, ' ...
                  'output_peak=%.0f, overflow=%d, sat=%d, zero_ratio=%.8f, ' ...
                  'direct_error=%.0f, pass=%d\n'], ...
                  r.name, r.gain_error_db, r.snr_db, r.input_peak, ...
                  r.output_peak, r.acc_overflow_count, r.output_sat_count, ...
                  r.zero_output_ratio, r.direct_max_error, r.pass_all);
end

pass_all = all([test_result.pass_all]);
fprintf(fid, '\nPass all = %d\n', pass_all);
fclose(fid);

fprintf('\n================ bit-true 验证结果 ================\n');
fprintf('全部测试通过判定 = %d\n', pass_all);
fprintf('已导出：\n');
fprintf('1) %s\n', summary_path);
fprintf('2) %s\n', result_csv_path);
fprintf('3) %s\n', config_csv_path);

if ~pass_all
    error('bit-true 验证存在未通过项目，请检查汇总文件。');
end


%=============================================================
% 本地函数：构造通用测试项
% ============================================================
% 5）局部函数模块：make_case
% 功能说明：封装 make_case 对应的局部计算，供主流程复用并保持代码层次清晰。
function tc = make_case(name, kind, x, freq_hz, expected_amp, gain_tolerance_db)
    tc.name = name;
    tc.kind = kind;
    tc.x = int64(x(:).');
    tc.freq_hz = freq_hz;
    tc.expected_amp = expected_amp;
    tc.gain_tolerance_db = gain_tolerance_db;
end


%=============================================================
% 本地函数：构造正弦测试项
% ============================================================
% 6）局部函数模块：make_sine_case
% 功能说明：封装 make_sine_case 对应的局部计算，供主流程复用并保持代码层次清晰。
function tc = make_sine_case(name, freq_hz, dbfs, sample_count, Fs, data_w, tolerance_db)
    full_scale = 2^(data_w - 1) - 1;
    amplitude = round(full_scale * 10^(dbfs / 20));
    n = 0:sample_count-1;
    x = int64(round(amplitude * sin(2*pi*freq_hz*n/Fs)));

    if dbfs <= -60
        kind = 'small';
    else
        kind = 'sine';
    end

    tc = make_case(name, kind, x, freq_hz, amplitude, tolerance_db);
end


%=============================================================
% 本地函数：分析稳态幅度与拟合 SNR
% ============================================================
% 7）局部函数模块：analyze_case
% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric = analyze_case(tc, y, Fs_out, total_taps)
    metric.gain_error_db = NaN;
    metric.snr_db = NaN;

    steady_begin = total_taps + 1;
    steady_end = numel(y) - total_taps;
    if steady_end <= steady_begin
        steady_begin = floor(numel(y) * 0.35);
        steady_end = ceil(numel(y) * 0.65);
    end

    y_steady = double(y(steady_begin:steady_end));

    if strcmp(tc.kind, 'dc')
        measured = mean(y_steady);
        metric.gain_error_db = 20*log10(abs(measured) / tc.expected_amp + eps);
        residual = y_steady - measured;
        metric.snr_db = 10*log10(sum(measured.^2) / (sum(residual.^2) + eps));
    elseif strcmp(tc.kind, 'sine') || strcmp(tc.kind, 'small')
        n = (steady_begin-1:steady_end-1).';
        omega = 2*pi*tc.freq_hz/Fs_out;
        basis = [cos(omega*n) sin(omega*n) ones(numel(n), 1)];
        fit_coeff = basis \ y_steady(:);
        measured = hypot(fit_coeff(1), fit_coeff(2));
        fitted_ac = basis(:, 1:2) * fit_coeff(1:2);
        residual = y_steady(:) - basis * fit_coeff;
        metric.gain_error_db = 20*log10(measured / tc.expected_amp + eps);
        metric.snr_db = 10*log10(sum(fitted_ac.^2) / (sum(residual.^2) + eps));
    end
end


%=============================================================
% 本地函数：直接插零参考模型
% ============================================================
% 8）局部函数模块：simulate_direct_insert_zero
% 功能说明：封装 simulate_direct_insert_zero 对应的局部计算，供主流程复用并保持代码层次清晰。
function y = simulate_direct_insert_zero(x, stage_config)
    y = int64(x(:).');

    for stage_idx = 1:numel(stage_config)
        cfg = stage_config(stage_idx);
        x_up = zeros(1, 2*numel(y)-1, 'int64');
        x_up(1:2:end) = y;
        acc_double = conv(double(x_up), double(cfg.coeff_int));

        if max(abs(acc_double)) > flintmax
            error('直接插零参考模型超过 double 精确整数范围。');
        end

        y = round_shift_sat_signed(int64(acc_double), cfg.frac_w, cfg.data_w);
    end
end


%=============================================================
% 本地函数：导出 RTL 逐级配置
% ============================================================
% 9）局部函数模块：export_stage_config
% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function export_stage_config(filename, stage_config)
    fid = fopen(filename, 'w');
    fprintf(fid, ['STAGE,FS_IN,FS_OUT,TAPS,COEFF_W_DESIGN,COEFF_W_MIN,' ...
                  'FRAC_W,DATA_W,ACC_W_MIN,ACC_W_RECOMMENDED,GAIN_MODE,' ...
                  'NONZERO_HALF,DC_GAIN,PHASE0_GAIN,PHASE1_GAIN\n']);

    for idx = 1:numel(stage_config)
        cfg = stage_config(idx);
        fprintf(fid, ['%d,%.1f,%.1f,%d,%d,%d,%d,%d,%d,%d,%s,%d,' ...
                      '%.10f,%.10f,%.10f\n'], ...
                      cfg.stage_idx, cfg.Fs_in, cfg.Fs_out, cfg.taps, ...
                      cfg.coeff_w_design, cfg.coeff_w_min, cfg.frac_w, ...
                      cfg.data_w, cfg.acc_w_min, cfg.acc_w_recommended, ...
                      cfg.gain_mode, cfg.nonzero_half, cfg.dc_gain, ...
                      cfg.phase0_gain, cfg.phase1_gain);
    end

    fclose(fid);
end


%=============================================================
% 本地函数：导出测试结果 CSV
% ============================================================
% 10）局部函数模块：export_test_result
% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function export_test_result(filename, test_result)
    fid = fopen(filename, 'w');
    fprintf(fid, ['NAME,KIND,INPUT_PEAK,OUTPUT_PEAK,GAIN_ERROR_DB,SNR_DB,' ...
                  'ACC_OVERFLOW_COUNT,OUTPUT_SAT_COUNT,ZERO_OUTPUT_RATIO,' ...
                  'DIRECT_MAX_ERROR,PASS_ALL\n']);

    for idx = 1:numel(test_result)
        r = test_result(idx);
        fprintf(fid, '%s,%s,%.0f,%.0f,%.8f,%.8f,%d,%d,%.10f,%.0f,%d\n', ...
            r.name, r.kind, r.input_peak, r.output_peak, r.gain_error_db, ...
            r.snr_db, r.acc_overflow_count, r.output_sat_count, ...
            r.zero_output_ratio, r.direct_max_error, r.pass_all);
    end

    fclose(fid);
end
