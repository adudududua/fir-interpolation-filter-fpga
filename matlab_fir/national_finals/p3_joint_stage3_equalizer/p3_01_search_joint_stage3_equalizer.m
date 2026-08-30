%=============================================================
% 文件名       : p3_01_search_joint_stage3_equalizer.m
% 脚本名       : p3_01_search_joint_stage3_equalizer
% 功能简述     : 执行参数搜索和 Pareto 筛选，在满足指标的前提下降低字长或资源开销。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================

% P3 MATLAB-only gate: mode-specific Stage3/CIC compensation bank.
% The official 4x/8x modes retain the signed-off flat Stage3.  Only the
% 128x mode may select a second Q15/18-bit Stage3 bank and remove the
% external three-tap equalizer.  No RTL is changed by this script.

%% 1）主流程：p3_01_search_joint_stage3_equalizer
% 功能说明：执行参数搜索和 Pareto 筛选，在满足指标的前提下降低字长或资源开销。

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
nf_dir = fileparts(script_dir);
matlab_root = fileparts(nf_dir);
bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
result_dir = fullfile(script_dir, 'results');
figure_dir = fullfile(script_dir, 'figures');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
if ~exist(figure_dir, 'dir'); mkdir(figure_dir); end
addpath(nf_dir);
addpath(bittrue_dir);

CONFIG_ID = 'NF-P3-JOINT-STAGE3-EQ-MATLAB-R1';
FS_LIST = [44100 48000];
PASS_LOW_HZ = 10;
PASS_HIGH_HZ = 20000;
PASS_LIMIT_DB = 0.045;
STOP_LIMIT_DB = 71;
DC_LIMIT_DB = 0.01;
MODE_DELTA_LIMIT_DB = 0.01;
FRAC_W = 15;
COEFF_W = 18;
NFFT_SEARCH = 2^17;
NFFT_FINAL = 2^19;

cfg = nf_release_v2_config();
h1 = double(cfg.stage1.coeff_int(:).')/2^cfg.stage1.frac_w;
h2 = double(cfg.stage2.coeff_int(:).')/2^cfg.stage2.frac_w;
h3_flat = double(cfg.stage3.coeff_int(:).')/2^cfg.stage3.frac_w;
h4 = conv(upsample_ir(h1, 2), h2);
h8_flat = conv(upsample_ir(h4, 2), h3_flat);
h_cic = conv(conv(ones(1, 16), ones(1, 16)), ones(1, 16));
h_equalizer = [-1 10 -1]/8;
h128_baseline = conv(upsample_ir(conv(h8_flat, h_equalizer), 16), ...
    h_cic)/2^8;

candidate_source = {};
candidate_taps = [];
candidate_weight = [];
candidate_coeff = {};

% A mechanical convolution is useful only as a negative/control case: it
% does not reproduce the current intermediate Stage3 rounding boundary.
mechanical = conv(h3_flat, h_equalizer);
candidate_source{end+1, 1} = 'mechanical_convolution_q15';
candidate_taps(end+1, 1) = numel(mechanical);
candidate_weight(end+1, 1) = NaN;
candidate_coeff{end+1, 1} = mechanical;

% Prior Phase-7 result is a seed, not an accepted P3 result.  It is
% rechecked below against both sample-rate families and the new gates.
legacy_seed = double([561 137 -4234 -1555 20057 35604 ...
    20057 -1555 -4234 137 561])/2^FRAC_W;
candidate_source{end+1, 1} = 'legacy_phase7_seed';
candidate_taps(end+1, 1) = numel(legacy_seed);
candidate_weight(end+1, 1) = 0.01;
candidate_coeff{end+1, 1} = legacy_seed;
for gain_trim = [0.99975 0.9995 0.99945 0.9994 0.99935 ...
        0.9993 0.99925 0.9992 0.99915 0.9991 0.999 0.998]
    candidate_source{end+1, 1} = sprintf( ...
        'legacy_phase7_seed_trim_%g', gain_trim);
    candidate_taps(end+1, 1) = numel(legacy_seed);
    candidate_weight(end+1, 1) = gain_trim;
    candidate_coeff{end+1, 1} = legacy_seed*gain_trim;
end

tap_list = [11 13 15 17];
weight_list = [0 1e-6 1e-5 1e-4 1e-3 1e-2 1e-1 1 10];
for tap_count = tap_list
    for stop_weight = weight_list
        h_trial = design_joint_stage3(tap_count, stop_weight, h4, ...
            FS_LIST, PASS_HIGH_HZ);
        candidate_source{end+1, 1} = sprintf('joint_ls_t%d_w%g', ...
            tap_count, stop_weight);
        candidate_taps(end+1, 1) = numel(h_trial);
        candidate_weight(end+1, 1) = stop_weight;
        candidate_coeff{end+1, 1} = h_trial;
    end
end

row_source = {};
row_taps = [];
row_weight = [];
row_max_coeff = [];
row_required_w = [];
row_phase0_tasks = [];
row_phase1_tasks = [];
row_deadline_margin = [];
row_worst_pass = [];
row_worst_stop = [];
row_worst_dc = [];
row_mode_delta = [];
row_symmetry = [];
row_coeff_fit = [];
row_frequency_pass = [];
row_schedule_pass = [];
row_pass = [];
quantized_store = cell(size(candidate_coeff));
h128_store = cell(size(candidate_coeff));

base4_metrics = evaluate_all_fs(h4, 4, FS_LIST, PASS_LOW_HZ, ...
    PASS_HIGH_HZ, NFFT_SEARCH);
base8_metrics = evaluate_all_fs(h8_flat, 8, FS_LIST, PASS_LOW_HZ, ...
    PASS_HIGH_HZ, NFFT_SEARCH);

for index = 1:numel(candidate_coeff)
    coeff_int = int64(round(candidate_coeff{index}*2^FRAC_W));
    h_quantized = double(coeff_int)/2^FRAC_W;
    h8_comp = conv(upsample_ir(h4, 2), h_quantized);
    h128 = conv(upsample_ir(h8_comp, 16), h_cic)/2^8;
    metric128 = evaluate_all_fs(h128, 128, FS_LIST, PASS_LOW_HZ, ...
        PASS_HIGH_HZ, NFFT_SEARCH);
    all_metric = [base4_metrics base8_metrics metric128];
    all_pass_error = [all_metric.absolute_pass_abs_max_db];
    all_dc = [all_metric.dc_gain_db];
    stop128 = [metric128.absolute_stop_attenuation_db];
    delta = zeros(1, numel(FS_LIST));
    for fs_index = 1:numel(FS_LIST)
        delta(fs_index) = metric128(fs_index).dc_gain_db- ...
            base4_metrics(fs_index).dc_gain_db;
    end

    taps = numel(coeff_int);
    phase0_tasks = ceil(taps/2);
    phase1_tasks = floor(taps/2);
    % One event-to-job-start cycle, N MAC cycles, result capture and output.
    worst_latency = max(phase0_tasks, phase1_tasks)+3;
    deadline_margin = 16-worst_latency;
    max_coeff = max(abs(double(coeff_int)));
    required_w = signed_width(max_coeff);
    coeff_fit = required_w <= COEFF_W;
    frequency_pass = max(all_pass_error) <= PASS_LIMIT_DB && ...
        min(stop128) >= STOP_LIMIT_DB && ...
        max(abs(all_dc)) <= DC_LIMIT_DB && ...
        max(abs(delta)) <= MODE_DELTA_LIMIT_DB;
    schedule_pass = deadline_margin >= 4;

    row_source{end+1, 1} = candidate_source{index}; %#ok<SAGROW>
    row_taps(end+1, 1) = taps; %#ok<SAGROW>
    row_weight(end+1, 1) = candidate_weight(index); %#ok<SAGROW>
    row_max_coeff(end+1, 1) = max_coeff; %#ok<SAGROW>
    row_required_w(end+1, 1) = required_w; %#ok<SAGROW>
    row_phase0_tasks(end+1, 1) = phase0_tasks; %#ok<SAGROW>
    row_phase1_tasks(end+1, 1) = phase1_tasks; %#ok<SAGROW>
    row_deadline_margin(end+1, 1) = deadline_margin; %#ok<SAGROW>
    row_worst_pass(end+1, 1) = max(all_pass_error); %#ok<SAGROW>
    row_worst_stop(end+1, 1) = min(stop128); %#ok<SAGROW>
    row_worst_dc(end+1, 1) = max(abs(all_dc)); %#ok<SAGROW>
    row_mode_delta(end+1, 1) = max(abs(delta)); %#ok<SAGROW>
    row_symmetry(end+1, 1) = max(abs(h_quantized-fliplr(h_quantized))); %#ok<SAGROW>
    row_coeff_fit(end+1, 1) = coeff_fit; %#ok<SAGROW>
    row_frequency_pass(end+1, 1) = frequency_pass; %#ok<SAGROW>
    row_schedule_pass(end+1, 1) = schedule_pass; %#ok<SAGROW>
    row_pass(end+1, 1) = coeff_fit && frequency_pass && ...
        schedule_pass && row_symmetry(end) == 0; %#ok<SAGROW>
    quantized_store{index} = coeff_int;
    h128_store{index} = h128;
end

candidate_table = table(row_source, row_taps, row_weight, ...
    row_max_coeff, row_required_w, row_phase0_tasks, row_phase1_tasks, ...
    row_deadline_margin, row_worst_pass, row_worst_stop, row_worst_dc, ...
    row_mode_delta, row_symmetry, row_coeff_fit, row_frequency_pass, ...
    row_schedule_pass, row_pass, 'VariableNames', ...
    {'SOURCE', 'TAPS', 'STOP_WEIGHT', 'MAX_COEFF_INT', ...
     'REQUIRED_COEFF_W', 'PHASE0_MAC_TASKS', 'PHASE1_MAC_TASKS', ...
     'DEADLINE_MARGIN_AUDIO_CYCLES', 'WORST_ABS_PASS_DB', ...
     'WORST_128X_STOP_DB', 'WORST_ABS_DC_DB', ...
     'WORST_MODE_DELTA_DB', 'SYMMETRY_ERROR', 'COEFF_FIT', ...
     'FREQUENCY_PASS', 'SCHEDULE_PASS', 'PASS'});
candidate_table.COEFF_FIT = logical(candidate_table.COEFF_FIT);
candidate_table.FREQUENCY_PASS = logical(candidate_table.FREQUENCY_PASS);
candidate_table.SCHEDULE_PASS = logical(candidate_table.SCHEDULE_PASS);
candidate_table.PASS = logical(candidate_table.PASS);

passing_index = find(candidate_table.PASS);
candidate_table.BITTRUE_EVALUATED = false(height(candidate_table), 1);
candidate_table.BITTRUE_PASS = false(height(candidate_table), 1);
candidate_table.BITTRUE_MAX_STAGE3_SAT_DELTA = ...
    nan(height(candidate_table), 1);
candidate_table.BITTRUE_MAX_CIC_SAT_DELTA = ...
    nan(height(candidate_table), 1);
candidate_table.BITTRUE_MIN_SNR_DB = nan(height(candidate_table), 1);
candidate_table.BITTRUE_FAIL_CASES = repmat({''}, ...
    height(candidate_table), 1);
if isempty(passing_index)
    selected_index = 0;
    bittrue_table = table();
else
    passing_table = candidate_table(passing_index, :);
    passing_table.ORIGINAL_INDEX = passing_index;
    passing_table = sortrows(passing_table, ...
        {'TAPS', 'WORST_ABS_PASS_DB', 'WORST_128X_STOP_DB'}, ...
        {'ascend', 'ascend', 'descend'});
    selected_index = 0;
    bittrue_table = table();
    for passing_row = 1:height(passing_table)
        trial_index = passing_table.ORIGINAL_INDEX(passing_row);
        trial_bittrue = run_bittrue_gate(quantized_store{trial_index}, ...
            h128_store{trial_index}, cfg, FS_LIST, PASS_LOW_HZ, ...
            PASS_HIGH_HZ, NFFT_FINAL);
        candidate_table.BITTRUE_EVALUATED(trial_index) = true;
        candidate_table.BITTRUE_PASS(trial_index) = all(trial_bittrue.PASS);
        candidate_table.BITTRUE_MAX_STAGE3_SAT_DELTA(trial_index) = ...
            max(trial_bittrue.P3_STAGE3_SATURATION- ...
            trial_bittrue.BASELINE_STAGE3_SATURATION);
        candidate_table.BITTRUE_MAX_CIC_SAT_DELTA(trial_index) = ...
            max(trial_bittrue.P3_CIC_SATURATION_DELTA);
        finite_snr = trial_bittrue.SNR_VS_FLOAT_DB( ...
            isfinite(trial_bittrue.SNR_VS_FLOAT_DB));
        candidate_table.BITTRUE_MIN_SNR_DB(trial_index) = min(finite_snr);
        candidate_table.BITTRUE_FAIL_CASES{trial_index} = strjoin( ...
            trial_bittrue.CASE_NAME(~trial_bittrue.PASS), ';');
        if all(trial_bittrue.PASS)
            selected_index = trial_index;
            bittrue_table = trial_bittrue;
            break;
        end
    end
end

writetable(candidate_table, fullfile(result_dir, ...
    'p3_joint_stage3_equalizer_candidates.csv'));

if selected_index == 0
    write_no_go_summary(result_dir, CONFIG_ID);
    error(['P3 MATLAB gate: no candidate passed frequency, schedule, ' ...
        'and relative bit-true gates.']);
end

selected_coeff = quantized_store{selected_index};
selected_h128 = h128_store{selected_index};
selected_name = candidate_source{selected_index};

node_name = {};
fs_in_hz = [];
fs_out_hz = [];
shape_pass_abs_max_db = [];
shape_ripple_pp_db = [];
absolute_pass_abs_max_db = [];
absolute_stop_attenuation_db = [];
worst_stop_frequency_hz = [];
dc_gain_db = [];
mode_delta_from_4x_db = [];
symmetry_error = [];
group_delay_samples = [];
phase_fit_residual_rad = [];
pass = [];
for fs_index = 1:numel(FS_LIST)
    fs_in = FS_LIST(fs_index);
    node_ir = {h4, h8_flat, selected_h128};
    factor = [4 8 128];
    metric_one_fs = cell(1, 3);
    for node_index = 1:3
        metric = analyze_node(node_ir{node_index}, factor(node_index), ...
            fs_in, PASS_LOW_HZ, PASS_HIGH_HZ, NFFT_FINAL, true);
        metric_one_fs{node_index} = metric;
    end
    for node_index = 1:3
        metric = metric_one_fs{node_index};
        delta = metric.dc_gain_db-metric_one_fs{1}.dc_gain_db;
        node_name{end+1, 1} = sprintf('%dx', factor(node_index)); %#ok<SAGROW>
        fs_in_hz(end+1, 1) = fs_in; %#ok<SAGROW>
        fs_out_hz(end+1, 1) = factor(node_index)*fs_in; %#ok<SAGROW>
        shape_pass_abs_max_db(end+1, 1) = metric.shape_pass_abs_max_db; %#ok<SAGROW>
        shape_ripple_pp_db(end+1, 1) = metric.shape_ripple_pp_db; %#ok<SAGROW>
        absolute_pass_abs_max_db(end+1, 1) = metric.absolute_pass_abs_max_db; %#ok<SAGROW>
        absolute_stop_attenuation_db(end+1, 1) = metric.absolute_stop_attenuation_db; %#ok<SAGROW>
        worst_stop_frequency_hz(end+1, 1) = metric.worst_stop_frequency_hz; %#ok<SAGROW>
        dc_gain_db(end+1, 1) = metric.dc_gain_db; %#ok<SAGROW>
        mode_delta_from_4x_db(end+1, 1) = delta; %#ok<SAGROW>
        symmetry_error(end+1, 1) = metric.symmetry_error; %#ok<SAGROW>
        group_delay_samples(end+1, 1) = metric.group_delay_samples; %#ok<SAGROW>
        phase_fit_residual_rad(end+1, 1) = metric.phase_fit_residual_rad; %#ok<SAGROW>
        pass(end+1, 1) = metric.absolute_pass_abs_max_db <= PASS_LIMIT_DB && ...
            metric.absolute_stop_attenuation_db >= ...
                cfg.stopband_attenuation_min_db && ...
            abs(metric.dc_gain_db) <= DC_LIMIT_DB && ...
            abs(delta) <= MODE_DELTA_LIMIT_DB && ...
            metric.symmetry_error < 1e-12 && ...
            metric.phase_fit_residual_rad < 1e-9; %#ok<SAGROW>
    end
end

metric_table = table(node_name, fs_in_hz, fs_out_hz, ...
    shape_pass_abs_max_db, shape_ripple_pp_db, ...
    absolute_pass_abs_max_db, absolute_stop_attenuation_db, ...
    worst_stop_frequency_hz, dc_gain_db, mode_delta_from_4x_db, ...
    symmetry_error, group_delay_samples, phase_fit_residual_rad, pass, ...
    'VariableNames', {'NODE', 'FS_IN_HZ', 'FS_OUT_HZ', ...
    'SHAPE_PASS_ABS_MAX_DB', 'SHAPE_RIPPLE_PP_DB', ...
    'ABSOLUTE_PASS_ABS_MAX_DB', 'ABSOLUTE_STOP_ATTENUATION_DB', ...
    'WORST_STOP_FREQUENCY_HZ', 'DC_GAIN_DB', ...
    'MODE_DELTA_FROM_4X_DB', 'SYMMETRY_ERROR', ...
    'GROUP_DELAY_SAMPLES', 'PHASE_FIT_RESIDUAL_RAD', 'PASS'});
metric_table.PASS = logical(metric_table.PASS);
writetable(metric_table, fullfile(result_dir, ...
    'p3_joint_stage3_equalizer_six_mode_metrics.csv'));

coefficient_index = (0:numel(selected_coeff)-1).';
coefficient_integer = selected_coeff(:);
coefficient_q15 = double(coefficient_integer)/2^FRAC_W;
coefficient_table = table(coefficient_index, coefficient_integer, ...
    coefficient_q15, 'VariableNames', ...
    {'NATURAL_INDEX', 'COEFFICIENT_INTEGER', 'COEFFICIENT_Q15'});
writetable(coefficient_table, fullfile(result_dir, ...
    'p3_joint_stage3_equalizer_selected_coefficients.csv'));

writetable(bittrue_table, fullfile(result_dir, ...
    'p3_joint_stage3_equalizer_bittrue_metrics.csv'));

resource_table = build_resource_model(numel(selected_coeff));
writetable(resource_table, fullfile(result_dir, ...
    'p3_joint_stage3_equalizer_resource_model.csv'));

config_record.schema = 'national-finals-p3-matlab-config-v1';
config_record.config_id = CONFIG_ID;
config_record.parent_config_id = cfg.config_id;
config_record.mode_4x_8x_stage3 = 'P4-D flat Q15 bank';
config_record.mode_128x_stage3 = selected_name;
config_record.stage3_fraction_bits = FRAC_W;
config_record.stage3_coefficient_bits = COEFF_W;
config_record.stage3_coefficients_integer = double(selected_coeff);
config_record.external_equalizer_128x = false;
config_record.stage3_output_bits_128x = 21;
config_record.cic_input_bits = 21;
config_record.rtl_status = 'NOT_IMPLEMENTED_MATLAB_GATE_ONLY';
fid = fopen(fullfile(result_dir, ...
    'p3_joint_stage3_equalizer_config.json'), 'w');
if fid < 0; error('Unable to create P3 config JSON.'); end
cleanup_json = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(config_record, 'PrettyPrint', true));
clear cleanup_json;

write_summary_file(result_dir, CONFIG_ID, cfg, selected_name, ...
    selected_coeff, FRAC_W, COEFF_W, candidate_table, selected_index, ...
    metric_table, bittrue_table, resource_table);
plot_responses(figure_dir, h128_baseline, selected_h128, FS_LIST, ...
    PASS_HIGH_HZ);

disp(candidate_table(candidate_table.PASS, :));
disp(metric_table);
disp(bittrue_table);
disp(resource_table);
assert(all(metric_table.PASS), 'P3 six-mode frequency gate failed.');
assert(all(bittrue_table.PASS), 'P3 bit-true gate failed.');
assert(all(resource_table.PASS), 'P3 resource/deadline prediction gate failed.');
fprintf('P3_JOINT_STAGE3_EQUALIZER_MATLAB_GATE_PASS: %s, candidate=%s\n', ...
    CONFIG_ID, selected_name);


% 2）局部函数模块：upsample_ir


% 功能说明：按指定插值倍率展开冲激响应并构造当前级或完整链路的等效响应。
function h_up = upsample_ir(h, rate)
    h = h(:).';
    h_up = zeros(1, rate*(numel(h)-1)+1);
    h_up(1:rate:end) = h;
end


% 3）局部函数模块：design_joint_stage3


% 功能说明：封装 design_joint_stage3 对应的局部计算，供主流程复用并保持代码层次清晰。
function h = design_joint_stage3(tap_count, stop_weight, h4, ...
        fs_list, pass_high)
    half_order = (tap_count-1)/2;
    distance = 1:half_order;
    matrix = [];
    target = [];
    for fs_in = fs_list
        pass_frequency = linspace(0, pass_high, 1200).';
        pass_omega = 2*pi*pass_frequency/(8*fs_in);
        pass_matrix = [ones(size(pass_omega)), ...
            2*cos(pass_omega*distance)];
        h4_response = response_at(h4, pass_frequency, 4*fs_in);
        cic_norm = cic_normalized_magnitude(pass_frequency, ...
            8*fs_in, 16, 1, 3);
        desired = 128./(abs(h4_response).*16.*cic_norm);
        matrix = [matrix; pass_matrix]; %#ok<AGROW>
        target = [target; desired(:)]; %#ok<AGROW>

        stop_frequency = linspace(4*fs_in-pass_high, 4*fs_in, 700).';
        stop_omega = 2*pi*stop_frequency/(8*fs_in);
        stop_matrix = [ones(size(stop_omega)), ...
            2*cos(stop_omega*distance)];
        matrix = [matrix; sqrt(stop_weight)*stop_matrix]; %#ok<AGROW>
        target = [target; zeros(size(stop_frequency))]; %#ok<AGROW>
    end
    dc_target = mean(128./(abs(sum(h4))*16));
    dc_weight = 1e4;
    matrix = [matrix; dc_weight*[1 2*ones(1, half_order)]];
    target = [target; dc_weight*dc_target];
    ridge = 1e-10;
    matrix = [matrix; sqrt(ridge)*eye(half_order+1)];
    target = [target; zeros(half_order+1, 1)];
    column_scale = sqrt(sum(matrix.^2, 1));
    column_scale(column_scale < eps) = 1;
    coefficient = (matrix./column_scale)\target;
    coefficient = coefficient./column_scale.';
    h = zeros(1, tap_count);
    center = half_order+1;
    h(center) = coefficient(1);
    for distance_index = 1:half_order
        h(center-distance_index) = coefficient(distance_index+1);
        h(center+distance_index) = coefficient(distance_index+1);
    end
end


% 4）局部函数模块：cic_normalized_magnitude


% 功能说明：封装 cic_normalized_magnitude 对应的局部计算，供主流程复用并保持代码层次清晰。
function magnitude = cic_normalized_magnitude(frequency_hz, ...
        input_rate_hz, rate_change, diff_delay, cic_order)
    numerator = sin(pi*frequency_hz*diff_delay/input_rate_hz);
    denominator = rate_change*diff_delay* ...
        sin(pi*frequency_hz/(rate_change*input_rate_hz));
    ratio = ones(size(frequency_hz));
    nonzero = abs(frequency_hz) > 1e-15;
    ratio(nonzero) = numerator(nonzero)./denominator(nonzero);
    magnitude = abs(ratio).^cic_order;
end


% 5）局部函数模块：response_at


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function response = response_at(h, frequency_hz, sample_rate_hz)
    sample_index = (0:numel(h)-1).';
    response = h(:).'*exp(-1i*2*pi/sample_rate_hz* ...
        (sample_index*frequency_hz(:).'));
    response = response(:);
end


% 6）局部函数模块：signed_width


% 功能说明：封装 signed_width 对应的局部计算，供主流程复用并保持代码层次清晰。
function width = signed_width(max_abs_value)
    if max_abs_value == 0
        width = 1;
    else
        width = ceil(log2(max_abs_value+1))+1;
    end
end


% 7）局部函数模块：evaluate_all_fs


% 功能说明：封装 evaluate_all_fs 对应的局部计算，供主流程复用并保持代码层次清晰。
function metrics = evaluate_all_fs(h, factor, fs_list, pass_low, ...
        pass_high, nfft)
    metrics = repmat(analyze_node(h, factor, fs_list(1), ...
        pass_low, pass_high, nfft, false), 1, numel(fs_list));
    for index = 2:numel(fs_list)
        metrics(index) = analyze_node(h, factor, fs_list(index), ...
            pass_low, pass_high, nfft, false);
    end
end


% 8）局部函数模块：analyze_node


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric = analyze_node(h, factor, fs_in, pass_low, pass_high, ...
        nfft, refine_stop)
    h = double(h(:).');
    fs_out = factor*fs_in;
    spectrum = fft(h, nfft);
    spectrum = spectrum(1:nfft/2+1);
    frequency = (0:nfft/2)*(fs_out/nfft);
    shape_db = 20*log10(abs(spectrum)/abs(sum(h))+1e-15);
    absolute_db = 20*log10(abs(spectrum)/factor+1e-15);
    pass_index = frequency >= pass_low & frequency <= pass_high;
    stop_index = frequency >= (fs_in-pass_high) & frequency <= fs_out/2;
    [worst_stop_db, local_index] = max(absolute_db(stop_index));
    stop_frequency = frequency(stop_index);
    worst_frequency = stop_frequency(local_index);
    if refine_stop
        bin_width = fs_out/nfft;
        fine_frequency = linspace(max(fs_in-pass_high, ...
            worst_frequency-bin_width), min(fs_out/2, ...
            worst_frequency+bin_width), 1001);
        fine_response = response_at(h, fine_frequency, fs_out);
        fine_db = 20*log10(abs(fine_response)/factor+1e-15);
        [fine_worst, fine_index] = max(fine_db);
        if fine_worst > worst_stop_db
            worst_stop_db = fine_worst;
            worst_frequency = fine_frequency(fine_index);
        end
    end
    phase_index = pass_index & abs(spectrum) > max(abs(spectrum))*1e-6;
    phase_value = unwrap(angle(spectrum(phase_index)));
    omega = 2*pi*frequency(phase_index)/fs_out;
    fit = polyfit(omega, phase_value, 1);
    metric.shape_pass_abs_max_db = max(abs(shape_db(pass_index)));
    metric.shape_ripple_pp_db = max(shape_db(pass_index))- ...
        min(shape_db(pass_index));
    metric.absolute_pass_abs_max_db = max(abs(absolute_db(pass_index)));
    metric.absolute_stop_attenuation_db = -worst_stop_db;
    metric.worst_stop_frequency_hz = worst_frequency;
    metric.dc_gain_db = 20*log10(abs(sum(h))/factor+1e-15);
    metric.symmetry_error = max(abs(h-fliplr(h)));
    metric.group_delay_samples = -fit(1);
    metric.phase_fit_residual_rad = max(abs(phase_value-polyval(fit, omega)));
end


% 9）局部函数模块：run_bittrue_gate


% 功能说明：封装 run_bittrue_gate 对应的局部计算，供主流程复用并保持代码层次清晰。
function data = run_bittrue_gate(coeff_int, h128, cfg, fs_list, ...
        pass_low, pass_high, nfft)
    impulse = zeros(1, 256, 'int64');
    impulse(1) = int64(2^22);
    [impulse_output, impulse_stat] = simulate_candidate(impulse, ...
        coeff_int, cfg);
    frequency_rows = cell(numel(fs_list), 1);
    for fs_index = 1:numel(fs_list)
        metric = analyze_scaled_node(double(impulse_output)*16, ...
            128*fs_list(fs_index), fs_list(fs_index), pass_low, ...
            pass_high, nfft, double(impulse(1))*128);
        frequency_rows{fs_index} = metric;
    end

    names = {'impulse'; 'fullscale_positive'; 'fullscale_negative'; ...
        'random_seed307817'; 'tone_m1_44k1'; 'tone_m60_44k1'; ...
        'tone_m90_44k1'; 'tone_m1_48k'; 'tone_m60_48k'; 'tone_m90_48k'};
    sample_rates = [44100; 44100; 44100; 44100; 44100; 44100; ...
        44100; 48000; 48000; 48000];
    input_data = cell(size(names));
    input_data{1} = impulse;
    input_data{2} = [int64(2^23-1) zeros(1, 255, 'int64')];
    input_data{3} = [int64(-2^23) zeros(1, 255, 'int64')];
    rng(307817, 'twister');
    input_data{4} = int64(randi([-2^20, 2^20-1], 1, 2048));
    input_data{5} = make_tone(997, -1, 2048, 44100);
    input_data{6} = make_tone(997, -60, 2048, 44100);
    input_data{7} = make_tone(997, -90, 2048, 44100);
    input_data{8} = make_tone(997, -1, 2048, 48000);
    input_data{9} = make_tone(997, -60, 2048, 48000);
    input_data{10} = make_tone(997, -90, 2048, 48000);

    snr_db = nan(size(names));
    acc_overflow = zeros(size(names));
    saturation = zeros(size(names));
    inherited_front_saturation = zeros(size(names));
    p3_stage3_saturation = zeros(size(names));
    p3_cic_saturation = zeros(size(names));
    baseline_stage3_saturation = zeros(size(names));
    baseline_cic_saturation = zeros(size(names));
    p3_cic_saturation_delta = zeros(size(names));
    cic_i1_wrap = zeros(size(names));
    cic_i2_wrap = zeros(size(names));
    max_abs_output = zeros(size(names));
    pass = false(size(names));
    for index = 1:numel(names)
        [output, stat] = simulate_candidate(input_data{index}, ...
            coeff_int, cfg);
        [~, baseline_stat] = simulate_baseline(input_data{index}, cfg);
        if index ~= 1
            reference = floating_reference(input_data{index}, h128);
            count = min(numel(output), numel(reference));
            error_signal = double(output(1:count))*16-reference(1:count);
            snr_db(index) = 10*log10(sum(reference(1:count).^2)/ ...
                max(sum(error_signal.^2), realmin));
        end
        acc_overflow(index) = stat.acc_overflow;
        saturation(index) = stat.saturation;
        inherited_front_saturation(index) = stat.front_saturation;
        p3_stage3_saturation(index) = stat.stage3_saturation;
        p3_cic_saturation(index) = stat.cic_saturation;
        baseline_stage3_saturation(index) = ...
            baseline_stat.stage3_saturation;
        baseline_cic_saturation(index) = baseline_stat.cic_saturation;
        p3_cic_saturation_delta(index) = stat.cic_saturation- ...
            baseline_stat.cic_saturation;
        cic_i1_wrap(index) = stat.cic.first_integrator_wrap_count;
        cic_i2_wrap(index) = stat.cic.final_integrator_wrap_count;
        max_abs_output(index) = max(abs(double(output)));
        if index == 1
            pass(index) = all(cellfun(@(m) ...
                m.absolute_pass_abs_max_db <= 0.045 && ...
                m.absolute_stop_attenuation_db >= 71, frequency_rows));
        elseif index <= 3
            pass(index) = stat.acc_overflow == 0 && ...
                stat.stage3_saturation <= baseline_stat.stage3_saturation && ...
                stat.cic_saturation <= baseline_stat.cic_saturation;
        elseif index == 4
            pass(index) = stat.acc_overflow == 0 && ...
                stat.stage3_saturation <= baseline_stat.stage3_saturation && ...
                stat.cic_saturation <= baseline_stat.cic_saturation && ...
                snr_db(index) >= 90;
        elseif contains(names{index}, 'm1_')
            pass(index) = stat.acc_overflow == 0 && ...
                stat.stage3_saturation <= baseline_stat.stage3_saturation && ...
                stat.cic_saturation <= baseline_stat.cic_saturation && ...
                snr_db(index) >= 80;
        elseif contains(names{index}, 'm60_')
            pass(index) = stat.acc_overflow == 0 && ...
                stat.stage3_saturation <= baseline_stat.stage3_saturation && ...
                stat.cic_saturation <= baseline_stat.cic_saturation && ...
                snr_db(index) >= 45;
        else
            pass(index) = stat.acc_overflow == 0 && ...
                stat.stage3_saturation <= baseline_stat.stage3_saturation && ...
                stat.cic_saturation <= baseline_stat.cic_saturation && ...
                snr_db(index) >= 15;
        end
    end
    impulse_pass_44k1_db = repmat(frequency_rows{1}.absolute_pass_abs_max_db, ...
        numel(names), 1);
    impulse_stop_44k1_db = repmat(frequency_rows{1}.absolute_stop_attenuation_db, ...
        numel(names), 1);
    impulse_pass_48k_db = repmat(frequency_rows{2}.absolute_pass_abs_max_db, ...
        numel(names), 1);
    impulse_stop_48k_db = repmat(frequency_rows{2}.absolute_stop_attenuation_db, ...
        numel(names), 1);
    data = table(names, sample_rates, snr_db, acc_overflow, saturation, ...
        inherited_front_saturation, p3_stage3_saturation, ...
        p3_cic_saturation, baseline_stage3_saturation, ...
        baseline_cic_saturation, p3_cic_saturation_delta, ...
        cic_i1_wrap, cic_i2_wrap, max_abs_output, ...
        impulse_pass_44k1_db, impulse_stop_44k1_db, ...
        impulse_pass_48k_db, impulse_stop_48k_db, pass, ...
        'VariableNames', {'CASE_NAME', 'FS_IN_HZ', 'SNR_VS_FLOAT_DB', ...
        'ACC_OVERFLOW', 'TOTAL_SATURATION', ...
        'INHERITED_FRONT_SATURATION', 'P3_STAGE3_SATURATION', ...
        'P3_CIC_SATURATION', 'BASELINE_STAGE3_SATURATION', ...
        'BASELINE_CIC_SATURATION', 'P3_CIC_SATURATION_DELTA', ...
        'CIC_I1_WRAP', 'CIC_I2_WRAP', ...
        'MAX_ABS_OUTPUT', 'IMPULSE_128X_PASS_44K1_DB', ...
        'IMPULSE_128X_STOP_44K1_DB', 'IMPULSE_128X_PASS_48K_DB', ...
        'IMPULSE_128X_STOP_48K_DB', 'PASS'});
end


% 10）局部函数模块：simulate_candidate


% 功能说明：封装 simulate_candidate 对应的局部计算，供主流程复用并保持代码层次清晰。
function [y128, stat] = simulate_candidate(x, coeff_int, cfg)
    [stage1, s1] = interp2_polyphase_bittrue(x, ...
        cfg.stage1.coeff_int, cfg.stage1.frac_w, ...
        cfg.stage1.output_w, cfg.stage1.acc_w);
    [stage1_q22, b1] = round_shift_sat_signed(stage1, 2, 22);
    [stage2, s2] = interp2_polyphase_bittrue(stage1_q22, ...
        cfg.stage2.coeff_int, cfg.stage2.frac_w, ...
        cfg.stage2.output_w, cfg.stage2.acc_w);
    [stage2_q20, b2] = round_shift_sat_signed(stage2, 2, 20);
    % The joint bank keeps the signed-21 peak headroom already required by
    % the P4-D equalizer/CIC boundary.  Forcing this node back to signed-20
    % clips full-scale transients and is therefore intentionally rejected.
    [stage3, s3] = interp2_polyphase_bittrue(stage2_q20, ...
        coeff_int, 15, 21, 38);
    [y128, cic] = nf_cic_n3_hold2_bittrue(stage3, 21, 20);
    stat.acc_overflow = s1.acc_overflow_count+s2.acc_overflow_count+ ...
        s3.acc_overflow_count;
    stat.front_saturation = s1.output_sat_count+b1.output_sat_count+ ...
        s2.output_sat_count+b2.output_sat_count;
    stat.stage3_saturation = s3.output_sat_count;
    stat.cic_saturation = cic.output_sat_count;
    stat.saturation = stat.front_saturation+stat.stage3_saturation+ ...
        stat.cic_saturation;
    stat.cic = cic;
end


% 11）局部函数模块：simulate_baseline


% 功能说明：封装 simulate_baseline 对应的局部计算，供主流程复用并保持代码层次清晰。
function [y128, stat] = simulate_baseline(x, cfg)
    [stage1, s1] = interp2_polyphase_bittrue(x, ...
        cfg.stage1.coeff_int, cfg.stage1.frac_w, ...
        cfg.stage1.output_w, cfg.stage1.acc_w);
    [stage1_q22, b1] = round_shift_sat_signed(stage1, 2, 22);
    [stage2, s2] = interp2_polyphase_bittrue(stage1_q22, ...
        cfg.stage2.coeff_int, cfg.stage2.frac_w, ...
        cfg.stage2.output_w, cfg.stage2.acc_w);
    [stage2_q20, b2] = round_shift_sat_signed(stage2, 2, 20);
    [stage3, s3] = interp2_polyphase_bittrue(stage2_q20, ...
        cfg.stage3.coeff_int, cfg.stage3.frac_w, 20, cfg.stage3.acc_w);
    [equalized, eq] = nf_cic3_shiftadd_bittrue( ...
        [stage3 int64([0 0])], 20, 21);
    [y128, cic] = nf_cic_n3_hold2_bittrue(equalized, 21, 20);
    stat.acc_overflow = s1.acc_overflow_count+s2.acc_overflow_count+ ...
        s3.acc_overflow_count;
    stat.front_saturation = s1.output_sat_count+b1.output_sat_count+ ...
        s2.output_sat_count+b2.output_sat_count;
    stat.stage3_saturation = s3.output_sat_count;
    stat.equalizer_saturation = eq.output_sat_count;
    stat.cic_saturation = cic.output_sat_count;
end


% 12）局部函数模块：make_tone


% 功能说明：封装 make_tone 对应的局部计算，供主流程复用并保持代码层次清晰。
function x = make_tone(frequency_hz, level_dbfs, sample_count, fs_in)
    amplitude = (2^23-1)*10^(level_dbfs/20);
    n = 0:sample_count-1;
    x = int64(round(amplitude*sin(2*pi*frequency_hz*n/fs_in)));
end


% 13）局部函数模块：floating_reference


% 功能说明：封装 floating_reference 对应的局部计算，供主流程复用并保持代码层次清晰。
function reference = floating_reference(x, h128)
    x = double(x(:).');
    x_up = zeros(1, 128*(numel(x)-1)+1);
    x_up(1:128:end) = x;
    reference = conv(x_up, h128);
end


% 14）局部函数模块：analyze_scaled_node


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric = analyze_scaled_node(y, fs_out, fs_in, pass_low, ...
        pass_high, nfft, expected_dc_sum)
    spectrum = fft(double(y(:).'), nfft);
    spectrum = spectrum(1:nfft/2+1);
    frequency = (0:nfft/2)*(fs_out/nfft);
    absolute_db = 20*log10(abs(spectrum)/expected_dc_sum+1e-15);
    pass_index = frequency >= pass_low & frequency <= pass_high;
    stop_index = frequency >= (fs_in-pass_high) & frequency <= fs_out/2;
    metric.absolute_pass_abs_max_db = max(abs(absolute_db(pass_index)));
    metric.absolute_stop_attenuation_db = -max(absolute_db(stop_index));
end


% 15）局部函数模块：build_resource_model


% 功能说明：封装 build_resource_model 对应的局部计算，供主流程复用并保持代码层次清晰。
function table_out = build_resource_model(taps)
    item = {'remove_equalizer'; 'dual_bank_address_and_mode'; ...
        '18bit_coefficient_port'; 'signed21_stage3_output'; ...
        'scheduler_constants'; 'net_total'};
    lut_delta = [-46; 10; 4; 1; 2; -29];
    ff_delta = [-40; 5; 2; 1; 1; -31];
    evidence = {'P4-D routed hierarchy'; ...
        'conservative bank-bit/mode snapshot budget'; ...
        'RAMB18 parity lanes feed existing DSP B[17:0]'; ...
        'retains the existing equalizer-to-CIC signed-21 boundary'; ...
        sprintf('%d taps retain existing 4-bit counters', taps); ...
        'conservative pre-RTL estimate'};
    pass = [true; true; true; true; true; lut_delta(end) <= -20 && ...
        ff_delta(end) <= -20];
    table_out = table(item, lut_delta, ff_delta, evidence, pass, ...
        'VariableNames', {'ITEM', 'LUT_DELTA', 'FF_DELTA', ...
        'EVIDENCE_OR_ASSUMPTION', 'PASS'});
end


% 16）局部函数模块：write_no_go_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_no_go_summary(result_dir, config_id)
    fid = fopen(fullfile(result_dir, ...
        'p3_joint_stage3_equalizer_summary.txt'), 'w');
    if fid < 0; return; end
    fprintf(fid, 'CONFIG_ID=%s\nOVERALL_PASS=0\nREASON=no candidate passed\n', ...
        config_id);
    fclose(fid);
end


% 17）局部函数模块：write_summary_file


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_summary_file(result_dir, config_id, cfg, selected_name, ...
        selected_coeff, frac_w, coeff_w, candidate_table, ...
        selected_index, metric_table, bittrue_table, resource_table)
    filename = fullfile(result_dir, ...
        'p3_joint_stage3_equalizer_summary.txt');
    fid = fopen(filename, 'w');
    if fid < 0; error('Unable to create %s.', filename); end
    cleanup_summary = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'P3 joint Stage3/equalizer MATLAB-only acceptance\n');
    fprintf(fid, '================================================\n');
    fprintf(fid, 'CONFIG_ID=%s\n', config_id);
    fprintf(fid, 'PARENT_CONFIG_ID=%s\n', cfg.config_id);
    fprintf(fid, 'SELECTED=%s\n', selected_name);
    fprintf(fid, 'TAPS=%d Q%d/%dbit MAX_COEFF=%d\n', ...
        numel(selected_coeff), frac_w, coeff_w, ...
        max(abs(double(selected_coeff))));
    fprintf(fid, 'COEFFICIENTS='); fprintf(fid, '%d ', selected_coeff); fprintf(fid, '\n');
    fprintf(fid, 'SCHEDULE_MARGIN=%d audio cycles\n', ...
        candidate_table.DEADLINE_MARGIN_AUDIO_CYCLES(selected_index));
    fprintf(fid, 'FLOAT_SIX_MODE_PASS=%d\n', all(metric_table.PASS));
    fprintf(fid, 'BITTRUE_CASES_PASS=%d/%d\n', nnz(bittrue_table.PASS), ...
        height(bittrue_table));
    fprintf(fid, 'PREDICTED_NET_LUT=%d PREDICTED_NET_FF=%d\n', ...
        resource_table.LUT_DELTA(end), resource_table.FF_DELTA(end));
    fprintf(fid, 'RTL_STATUS=NOT_IMPLEMENTED_MATLAB_GATE_ONLY\n');
    fprintf(fid, 'OVERALL_PASS=%d\n', all(metric_table.PASS) && ...
        all(bittrue_table.PASS) && all(resource_table.PASS));
end


% 18）局部函数模块：plot_responses


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function plot_responses(figure_dir, h128_baseline, selected_h128, ...
        fs_list, pass_high_hz)
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Position', [80 80 1400 760]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    for fs_index = 1:numel(fs_list)
        fs_in = fs_list(fs_index);
        nexttile;
        hold on;
        [f1, db1] = response_db(h128_baseline, 128*fs_in, 128);
        [f2, db2] = response_db(selected_h128, 128*fs_in, 128);
        plot(f1/1e3, db1, 'LineWidth', 1.0);
        plot(f2/1e3, db2, 'LineWidth', 1.0);
        xline((fs_in-pass_high_hz)/1e3, ':k');
        yline(-71, '--r');
        xlim([0 500]); ylim([-120 1]); grid on;
        title(sprintf('Fs=%.1f kHz, 128x full response', fs_in/1e3));
        xlabel('Frequency / kHz'); ylabel('Absolute gain / dB');
        legend('P4-D Stage3 + 3-tap EQ', 'P3 joint Stage3', ...
            'first image edge', '-71 dB', 'Location', 'southwest');
        nexttile;
        index1 = f1 <= pass_high_hz;
        index2 = f2 <= pass_high_hz;
        plot(f1(index1)/1e3, db1(index1), 'LineWidth', 1.0);
        hold on;
        plot(f2(index2)/1e3, db2(index2), 'LineWidth', 1.0);
        yline(0.045, '--r'); yline(-0.045, '--r');
        xlim([0 pass_high_hz/1e3]); ylim([-0.05 0.05]); grid on;
        title(sprintf('Fs=%.1f kHz, passband', fs_in/1e3));
        xlabel('Frequency / kHz'); ylabel('Absolute gain / dB');
        legend('P4-D', 'P3', '+0.045 dB', '-0.045 dB', ...
            'Location', 'best');
    end
    exportgraphics(fig, fullfile(figure_dir, ...
        'p3_joint_stage3_equalizer_response.png'), 'Resolution', 180);
    close(fig);
end


% 19）局部函数模块：response_db


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function [frequency, response_db_value] = response_db(h, fs_out, gain)
    nfft = 2^18;
    spectrum = fft(h, nfft);
    spectrum = spectrum(1:nfft/2+1);
    frequency = (0:nfft/2)*(fs_out/nfft);
    response_db_value = 20*log10(abs(spectrum)/gain+1e-15);
end
