%% 1）主流程：phase6_01_search_stage_data_wordlength
% 功能说明：执行参数搜索和 Pareto 筛选，在满足指标的前提下降低字长或资源开销。

clc; clear; close all;

%=============================================================
% 文件名       : phase6_01_search_stage_data_wordlength.m
% 脚本名       : phase6_01_search_stage_data_wordlength
% 功能简述     : Phase 6 级间数据字长第一轮 Pareto 搜索。
%                Stage 1 保持 24bit，Stage 2/3 和 Stage 4～7
%                按候选 Q 格式缩减数据位宽。每次缩位均使用与 RTL
%                一致的有符号舍入和饱和，并在最终输出处恢复到
%                24bit 标度后与全 24bit 基线比较。
%
%                本脚本检查：
%                  1. 七级系数的通带、阻带和线性相位；
%                  2. 相对 24bit 基线的增益误差；
%                  3. 字长量化增量 SNR；
%                  4. 正弦输出 SINAD 和 THD 相对基线的退化；
%                  5. 级间饱和和累加器溢出次数；
%                  6. 以各级历史长度估算的寄存器位成本。
%
%                输出文件：
%                  wordlength_results/
%                    phase6_wordlength_search_result.csv
%                    phase6_wordlength_search_summary.txt
%
% 当前默认配置：
%                  输入采样率：44.1kHz
%                  输出采样率：5.6448MHz
%                  输入输出位宽：24bit signed
%                  Stage 2 候选：24 / 22bit
%                  Stage 3 候选：24 / 22 / 20bit
%                  Stage 4～7候选：24 / 22 / 20 / 18bit
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 Phase 6 级间数据字长搜索。
%                2026-07-13：阻带指标改为由当前七级系数实时计算，
%                            删除旧基线硬编码数值。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
stable_dir = fullfile(repo_matlab_dir, 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
v2_dir = fullfile(repo_matlab_dir, 'alt_all2x_v2');
common_dir = fullfile(v2_dir, 'common');
result_dir = fullfile(script_dir, 'wordlength_results');

addpath(bittrue_dir);
addpath(common_dir);
if ~exist(result_dir, 'dir')
    mkdir(result_dir);
end

config_path = fullfile(v2_dir, 'stage1_strict_halfband_config.mat');
if ~exist(config_path, 'file')
    error('未找到严格半带配置：%s', config_path);
end
load(config_path, 'best_config');

% Phase 5 已把 Stage 3 从 Q14 等价改写为 Q15。
best_config(3).coeff_int = int64(best_config(3).coeff_int) * 2;
best_config(3).frac_w = best_config(3).frac_w + 1;
best_config(3).acc_w_recommended = 40;

FS_IN = 44100;
FS_OUT = FS_IN * 128;
DATA_W = 24;
INPUT_COUNT = 1024;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
RIPPLE_TARGET_DB = 0.05;
STOP_TARGET_DB = 70;
NFFT = 2^20;

h_total = build_multistage_ir(best_config);
coeff_metric = check_total_chain(h_total, FS_IN, FS_OUT, ...
    F_PASS_LOW, F_PASS_HIGH, RIPPLE_TARGET_DB, STOP_TARGET_DB, ...
    128, NFFT);
if ~coeff_metric.pass_all
    error('当前七级系数未通过频域或线性相位指标。');
end

test_name = {'sine_1k_m1dbfs', 'sine_15k_m6dbfs', ...
             'sine_20k_m6dbfs', 'random_m12dbfs'};
test_freq = [1000 15000 20000 0];
test_data = cell(size(test_name));
test_data{1} = make_sine(1000, -1, INPUT_COUNT, FS_IN, DATA_W);
test_data{2} = make_sine(15000, -6, INPUT_COUNT, FS_IN, DATA_W);
test_data{3} = make_sine(20000, -6, INPUT_COUNT, FS_IN, DATA_W);
rng(20260713, 'twister');
random_peak = round((2^(DATA_W-1)-1) * 10^(-12/20));
test_data{4} = int64(randi([-random_peak random_peak], 1, INPUT_COUNT));

profile_list = make_profile_list();
baseline_width = 24 * ones(1, 7);

baseline_output = cell(size(test_data));
baseline_metric = repmat(empty_metric(), size(test_data));
for test_idx = 1:numel(test_data)
    [baseline_output{test_idx}, baseline_stat] = ...
        simulate_wordlength_profile(test_data{test_idx}, best_config, ...
                                    baseline_width, DATA_W);
    baseline_metric(test_idx) = measure_output( ...
        baseline_output{test_idx}, baseline_output{test_idx}, ...
        test_freq(test_idx), FS_OUT);
    if baseline_stat.total_acc_overflow ~= 0 || ...
            baseline_stat.total_saturation ~= 0
        error('24bit 基线测试 %s 出现溢出或饱和。', test_name{test_idx});
    end
end

row_profile = cell(size(profile_list, 1), 1);
row_s2_w = zeros(size(profile_list, 1), 1);
row_s3_w = zeros(size(profile_list, 1), 1);
row_tail_w = zeros(size(profile_list, 1), 1);
row_bit_cost = zeros(size(profile_list, 1), 1);
row_gain_error = zeros(size(profile_list, 1), 1);
row_delta_snr = zeros(size(profile_list, 1), 1);
row_min_sinad = zeros(size(profile_list, 1), 1);
row_sinad_drop = zeros(size(profile_list, 1), 1);
row_worst_thd = zeros(size(profile_list, 1), 1);
row_overflow = zeros(size(profile_list, 1), 1);
row_saturation = zeros(size(profile_list, 1), 1);
row_pass = false(size(profile_list, 1), 1);

for profile_idx = 1:size(profile_list, 1)
    width_profile = profile_list(profile_idx, :);
    profile_name = sprintf('24-%d-%d-%d-%d-%d-%d', width_profile(2:end));

    max_gain_error = 0;
    min_delta_snr = inf;
    min_sinad = inf;
    max_sinad_drop = 0;
    worst_thd = -inf;
    total_overflow = 0;
    total_saturation = 0;

    for test_idx = 1:numel(test_data)
        [candidate_output, candidate_stat] = ...
            simulate_wordlength_profile(test_data{test_idx}, best_config, ...
                                        width_profile, DATA_W);
        one_metric = measure_output(candidate_output, ...
                                    baseline_output{test_idx}, ...
                                    test_freq(test_idx), FS_OUT);

        max_gain_error = max(max_gain_error, abs(one_metric.gain_error_db));
        min_delta_snr = min(min_delta_snr, one_metric.delta_snr_db);
        total_overflow = total_overflow + candidate_stat.total_acc_overflow;
        total_saturation = total_saturation + ...
                           candidate_stat.total_saturation;

        if test_freq(test_idx) > 0
            min_sinad = min(min_sinad, one_metric.sinad_db);
            max_sinad_drop = max(max_sinad_drop, ...
                baseline_metric(test_idx).sinad_db - one_metric.sinad_db);
            worst_thd = max(worst_thd, one_metric.thd_db);
        end
    end

    row_profile{profile_idx} = profile_name;
    row_s2_w(profile_idx) = width_profile(2);
    row_s3_w(profile_idx) = width_profile(3);
    row_tail_w(profile_idx) = width_profile(4);
    row_bit_cost(profile_idx) = history_bit_cost(width_profile);
    row_gain_error(profile_idx) = max_gain_error;
    row_delta_snr(profile_idx) = min_delta_snr;
    row_min_sinad(profile_idx) = min_sinad;
    row_sinad_drop(profile_idx) = max_sinad_drop;
    row_worst_thd(profile_idx) = worst_thd;
    row_overflow(profile_idx) = total_overflow;
    row_saturation(profile_idx) = total_saturation;

    row_pass(profile_idx) = max_gain_error <= 0.01 && ...
                            min_delta_snr >= 90 && ...
                            max_sinad_drop <= 0.5 && ...
                            total_overflow == 0 && ...
                            total_saturation == 0;

    fprintf(['%-20s cost=%4d gain=%8.5f dB deltaSNR=%7.2f dB ' ...
             'SINAD=%7.2f dB drop=%6.3f dB pass=%d\n'], ...
            profile_name, row_bit_cost(profile_idx), max_gain_error, ...
            min_delta_snr, min_sinad, max_sinad_drop, ...
            row_pass(profile_idx));
end

result_table = table(row_profile, row_s2_w, row_s3_w, row_tail_w, ...
    row_bit_cost, row_gain_error, row_delta_snr, row_min_sinad, ...
    row_sinad_drop, row_worst_thd, row_overflow, row_saturation, row_pass, ...
    'VariableNames', {'PROFILE', 'STAGE2_W', 'STAGE3_W', 'STAGE4_7_W', ...
    'HISTORY_BIT_COST', 'MAX_GAIN_ERROR_DB', 'MIN_DELTA_SNR_DB', ...
    'MIN_SINAD_DB', 'MAX_SINAD_DROP_DB', 'WORST_THD_DB', ...
    'ACC_OVERFLOW_COUNT', 'SATURATION_COUNT', 'PASS'});

result_table = sortrows(result_table, ...
    {'PASS', 'HISTORY_BIT_COST', 'MIN_DELTA_SNR_DB'}, ...
    {'descend', 'ascend', 'descend'});
writetable(result_table, fullfile(result_dir, ...
    'phase6_wordlength_search_result.csv'));

summary_path = fullfile(result_dir, ...
                        'phase6_wordlength_search_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Phase 6 stage data wordlength search\n');
fprintf(fid, '====================================\n');
fprintf(fid, 'Coefficient passband abs max = %.8f dB\n', ...
        coeff_metric.pass_abs_max_db);
fprintf(fid, 'Coefficient stopband attenuation = %.8f dB\n', ...
        coeff_metric.stop_attn_db);
fprintf(fid, 'Coefficient group-delay ripple = %.12g sample\n', ...
        coeff_metric.gd_pp);
fprintf(fid, ['Pass limits: |gain|<=0.01dB, delta SNR>=90dB, ' ...
              'SINAD drop<=0.5dB, overflow=0, saturation=0\n\n']);

for row_idx = 1:height(result_table)
    fprintf(fid, ['%-20s cost=%4d gain=%8.5f deltaSNR=%7.2f ' ...
                  'SINAD=%7.2f drop=%6.3f THD=%7.2f pass=%d\n'], ...
            result_table.PROFILE{row_idx}, ...
            result_table.HISTORY_BIT_COST(row_idx), ...
            result_table.MAX_GAIN_ERROR_DB(row_idx), ...
            result_table.MIN_DELTA_SNR_DB(row_idx), ...
            result_table.MIN_SINAD_DB(row_idx), ...
            result_table.MAX_SINAD_DROP_DB(row_idx), ...
            result_table.WORST_THD_DB(row_idx), ...
            result_table.PASS(row_idx));
end

pass_idx = find(result_table.PASS, 1, 'first');
if isempty(pass_idx)
    fprintf(fid, '\nNo reduced-width profile passed all limits.\n');
else
    fprintf(fid, '\nRecommended first RTL candidate = %s\n', ...
            result_table.PROFILE{pass_idx});
end
fclose(fid);

disp(result_table);
if isempty(pass_idx)
    fprintf('没有缩位候选通过全部门槛，RTL 保持 24bit。\n');
else
    fprintf('第一轮推荐 RTL 候选：%s\n', ...
            result_table.PROFILE{pass_idx});
end


% 2）局部函数模块：make_profile_list


% 功能说明：封装 make_profile_list 对应的局部计算，供主流程复用并保持代码层次清晰。
function profile_list = make_profile_list()
    stage2_list = [24 22];
    stage3_list = [24 22 20];
    tail_list = [24 22 20 18];
    profile_list = [];

    for stage2_w = stage2_list
        for stage3_w = stage3_list
            for tail_w = tail_list
                if stage3_w <= stage2_w && tail_w <= stage3_w
                    profile_list(end+1, :) = ...
                        [24 stage2_w stage3_w repmat(tail_w, 1, 4)];
                end
            end
        end
    end
end


% 3）局部函数模块：simulate_wordlength_profile


% 功能说明：封装 simulate_wordlength_profile 对应的局部计算，供主流程复用并保持代码层次清晰。
function [y_24, chain_stat] = simulate_wordlength_profile( ...
        x, stage_config, width_profile, final_data_w)
    y = int64(x(:).');
    current_w = final_data_w;
    total_overflow = 0;
    total_saturation = 0;

    for stage_idx = 1:numel(stage_config)
        target_w = width_profile(stage_idx);
        if target_w > current_w
            error('数据字长不允许在链路中重新增加。');
        end

        if target_w < current_w
            [y, boundary_stat] = round_shift_sat_signed( ...
                y, current_w-target_w, target_w);
            total_saturation = total_saturation + ...
                               boundary_stat.output_sat_count;
            current_w = target_w;
        end

        cfg = stage_config(stage_idx);
        [y, one_stat] = interp2_polyphase_bittrue( ...
            y, cfg.coeff_int, cfg.frac_w, current_w, ...
            cfg.acc_w_recommended);
        total_overflow = total_overflow + one_stat.acc_overflow_count;
        total_saturation = total_saturation + one_stat.output_sat_count;
    end

    y_24 = y * int64(2^(final_data_w-current_w));
    chain_stat.total_acc_overflow = total_overflow;
    chain_stat.total_saturation = total_saturation;
end


% 4）局部函数模块：measure_output


% 功能说明：封装 measure_output 对应的局部计算，供主流程复用并保持代码层次清晰。
function metric = measure_output(candidate, reference, tone_hz, Fs)
    candidate = double(candidate(:));
    reference = double(reference(:));
    compare_count = min(numel(candidate), numel(reference));
    candidate = candidate(1:compare_count);
    reference = reference(1:compare_count);

    trim_count = min(20000, floor(compare_count/4));
    keep_idx = (trim_count+1):(compare_count-trim_count);
    candidate = candidate(keep_idx);
    reference = reference(keep_idx);

    error_value = candidate - reference;
    reference_power = sum(reference.^2);
    error_power = sum(error_value.^2);
    if error_power == 0
        delta_snr_db = inf;
    else
        delta_snr_db = 10*log10(reference_power/error_power);
    end

    if reference_power == 0
        gain_error_db = 0;
    else
        gain_ratio = dot(candidate, reference) / reference_power;
        gain_error_db = 20*log10(max(abs(gain_ratio), realmin));
    end

    metric = empty_metric();
    metric.gain_error_db = gain_error_db;
    metric.delta_snr_db = delta_snr_db;

    if tone_hz > 0
        [metric.sinad_db, metric.thd_db] = ...
            measure_sinad_thd(candidate, tone_hz, Fs);
    end
end


% 5）局部函数模块：measure_sinad_thd


% 功能说明：封装 measure_sinad_thd 对应的局部计算，供主流程复用并保持代码层次清晰。
function [sinad_db, thd_db] = measure_sinad_thd(y, tone_hz, Fs)
    y = double(y(:));
    sample_index = (0:numel(y)-1).';
    harmonic_count = min(5, floor((Fs/2) / tone_hz));
    basis = ones(numel(y), 1);

    for harmonic_idx = 1:harmonic_count
        omega = 2*pi*harmonic_idx*tone_hz/Fs;
        basis = [basis sin(omega*sample_index) cos(omega*sample_index)]; %#ok<AGROW>
    end

    fit_coeff = basis \ y;
    fundamental = basis(:, 2:3) * fit_coeff(2:3);
    if harmonic_count >= 2
        harmonic = basis(:, 4:end) * fit_coeff(4:end);
    else
        harmonic = zeros(size(y));
    end
    all_fit = basis * fit_coeff;
    residual = y - all_fit;

    fundamental_power = mean(fundamental.^2);
    harmonic_power = mean(harmonic.^2);
    noise_power = mean(residual.^2);
    sinad_db = 10*log10(fundamental_power / ...
                        max(harmonic_power + noise_power, realmin));
    thd_db = 10*log10(max(harmonic_power, realmin) / ...
                      max(fundamental_power, realmin));
end


% 6）局部函数模块：history_bit_cost


% 功能说明：封装 history_bit_cost 对应的局部计算，供主流程复用并保持代码层次清晰。
function cost = history_bit_cost(width_profile)
    % Stage2/3 历史深度分别为 9/6，四个 canonical 级各 4 点。
    cost = 9*width_profile(2) + 6*width_profile(3) + ...
           4*sum(width_profile(4:7));
end


% 7）局部函数模块：empty_metric


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric = empty_metric()
    metric.gain_error_db = 0;
    metric.delta_snr_db = inf;
    metric.sinad_db = inf;
    metric.thd_db = -inf;
end


% 8）局部函数模块：make_sine


% 功能说明：封装 make_sine 对应的局部计算，供主流程复用并保持代码层次清晰。
function x = make_sine(freq_hz, dbfs, sample_count, Fs, data_w)
    amplitude = (2^(data_w-1)-1) * 10^(dbfs/20);
    n = 0:sample_count-1;
    x = int64(round(amplitude * sin(2*pi*freq_hz*n/Fs)));
end
