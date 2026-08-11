% Evaluate the aggressive Stage1/Stage2/Stage3 = 24/20/20 candidate.
% Reports are written only below national_finals/_work.

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
nf_dir = fileparts(script_dir);
p3_rtl_dir = fullfile(nf_dir, 'p3_joint_stage3_equalizer', 'rtl');
work_dir = fullfile(nf_dir, '_work', 'wordlength_24_20_20');
if ~exist(work_dir, 'dir'); mkdir(work_dir); end
addpath(nf_dir);
addpath(script_dir);
addpath(p3_rtl_dir);

cfg = nf_release_v2_config();
fs_list = cfg.input_sample_rates_hz;
factor_list = cfg.output_factors;
node_list = {'4x'; '8x'; '128x'};
nfft = 2^18;
impulse_amplitude = int64(2^22);
% A single input sample produces the complete finite impulse response.
% Appending source-domain zeros here would append a long zero tail to the
% model output and make a whole-vector symmetry check use the wrong axis.
impulse = impulse_amplitude;

baseline_ir = nf_p3_build_bittrue_case(impulse);
candidate_ir = nf_p3_build_bittrue_case_24_20_20(impulse);
baseline_nodes = {baseline_ir.y4_24, baseline_ir.y8_24, ...
    baseline_ir.y128_24};
candidate_nodes = {candidate_ir.y4_24, candidate_ir.y8_24, ...
    candidate_ir.y128_24};

node = {};
fs_in_hz = [];
fs_out_hz = [];
pass_abs_max_db = [];
pass_ripple_pp_db = [];
stop_attenuation_db = [];
dc_gain_db = [];
mode_delta_from_4x_db = [];
symmetry_lsb = [];
phase_fit_residual_rad = [];
delta_snr_vs_baseline_db = [];
delta_peak_lsb_24 = [];
pass = [];

for fs_index = 1:numel(fs_list)
    first_dc = nan;
    row_base = numel(pass);
    for node_index = 1:3
        metric = analyze_node(double(candidate_nodes{node_index}), ...
            factor_list(node_index)*fs_list(fs_index), fs_list(fs_index), ...
            cfg.passband_hz(1), cfg.passband_hz(2), nfft, ...
            double(impulse_amplitude)*factor_list(node_index));
        [snr_db, peak_delta] = compare_vectors(candidate_nodes{node_index}, ...
            baseline_nodes{node_index});
        if node_index == 1; first_dc = metric.dc_gain_db; end
        node{end+1, 1} = node_list{node_index}; %#ok<SAGROW>
        fs_in_hz(end+1, 1) = fs_list(fs_index); %#ok<SAGROW>
        fs_out_hz(end+1, 1) = factor_list(node_index)*fs_list(fs_index); %#ok<SAGROW>
        pass_abs_max_db(end+1, 1) = metric.absolute_pass_abs_max_db; %#ok<SAGROW>
        pass_ripple_pp_db(end+1, 1) = metric.shape_ripple_pp_db; %#ok<SAGROW>
        stop_attenuation_db(end+1, 1) = metric.absolute_stop_attenuation_db; %#ok<SAGROW>
        dc_gain_db(end+1, 1) = metric.dc_gain_db; %#ok<SAGROW>
        mode_delta_from_4x_db(end+1, 1) = metric.dc_gain_db-first_dc; %#ok<SAGROW>
        symmetry_lsb(end+1, 1) = metric.symmetry_lsb; %#ok<SAGROW>
        phase_fit_residual_rad(end+1, 1) = metric.phase_fit_residual_rad; %#ok<SAGROW>
        delta_snr_vs_baseline_db(end+1, 1) = snr_db; %#ok<SAGROW>
        delta_peak_lsb_24(end+1, 1) = peak_delta; %#ok<SAGROW>
        pass(end+1, 1) = ...
            metric.absolute_pass_abs_max_db <= cfg.passband_limit_db && ...
            metric.absolute_stop_attenuation_db >= ...
                cfg.stopband_attenuation_min_db && ...
            metric.symmetry_lsb == 0 && ...
            metric.phase_fit_residual_rad < 1e-9; %#ok<SAGROW>
    end
    rows = row_base+(1:3);
    pass(rows) = pass(rows) & ...
        abs(mode_delta_from_4x_db(rows)) <= 0.01; %#ok<SAGROW>
end

frequency_table = table(node, fs_in_hz, fs_out_hz, ...
    pass_abs_max_db, pass_ripple_pp_db, stop_attenuation_db, dc_gain_db, ...
    mode_delta_from_4x_db, symmetry_lsb, phase_fit_residual_rad, ...
    delta_snr_vs_baseline_db, delta_peak_lsb_24, logical(pass), ...
    'VariableNames', {'NODE', 'FS_IN_HZ', 'FS_OUT_HZ', ...
    'ABSOLUTE_PASS_ABS_MAX_DB', 'SHAPE_RIPPLE_PP_DB', ...
    'ABSOLUTE_STOP_ATTENUATION_DB', 'DC_GAIN_DB', ...
    'MODE_DELTA_FROM_4X_DB', 'SYMMETRY_LSB', ...
    'PHASE_FIT_RESIDUAL_RAD', 'DELTA_SNR_VS_BASELINE_DB', ...
    'DELTA_PEAK_LSB_24', 'PASS'});
writetable(frequency_table, fullfile(work_dir, ...
    'stage123_24_20_20_frequency.csv'));

case_name = {'fullscale_positive'; 'fullscale_negative'; ...
    'random_seed307817'; 'tone_m1_44k1'; 'tone_m60_44k1'; ...
    'tone_m90_44k1'; 'tone_m1_48k'; 'tone_m60_48k'; 'tone_m90_48k'};
case_fs = [44100; 44100; 44100; 44100; 44100; 44100; ...
    48000; 48000; 48000];
case_input = cell(size(case_name));
case_input{1} = [int64(2^23-1) zeros(1, 255, 'int64')];
case_input{2} = [int64(-2^23) zeros(1, 255, 'int64')];
rng(307817, 'twister');
case_input{3} = int64(randi([-2^20, 2^20-1], 1, 2048));
case_input{4} = make_tone(997, -1, 2048, 44100);
case_input{5} = make_tone(997, -60, 2048, 44100);
case_input{6} = make_tone(997, -90, 2048, 44100);
case_input{7} = make_tone(997, -1, 2048, 48000);
case_input{8} = make_tone(997, -60, 2048, 48000);
case_input{9} = make_tone(997, -90, 2048, 48000);

snr_4x_db = zeros(size(case_name));
snr_8x_db = zeros(size(case_name));
snr_128x_db = zeros(size(case_name));
peak_4x_lsb24 = zeros(size(case_name));
peak_8x_lsb24 = zeros(size(case_name));
peak_128x_lsb24 = zeros(size(case_name));
candidate_acc_overflow = zeros(size(case_name));
candidate_saturation = zeros(size(case_name));
baseline_saturation = zeros(size(case_name));
case_pass = false(size(case_name));

for index = 1:numel(case_name)
    baseline = nf_p3_build_bittrue_case(case_input{index});
    candidate = nf_p3_build_bittrue_case_24_20_20(case_input{index});
    [snr_4x_db(index), peak_4x_lsb24(index)] = ...
        compare_vectors(candidate.y4_24, baseline.y4_24);
    [snr_8x_db(index), peak_8x_lsb24(index)] = ...
        compare_vectors(candidate.y8_24, baseline.y8_24);
    [snr_128x_db(index), peak_128x_lsb24(index)] = ...
        compare_vectors(candidate.y128_24, baseline.y128_24);
    candidate_acc_overflow(index) = count_acc_overflow(candidate.stat);
    candidate_saturation(index) = count_saturation(candidate.stat);
    baseline_saturation(index) = count_saturation(baseline.stat);

    if startsWith(case_name{index}, 'fullscale_')
        quality_floor = 75;
    elseif contains(case_name{index}, 'm90_')
        quality_floor = 12;
    elseif contains(case_name{index}, 'm60_')
        quality_floor = 42;
    else
        quality_floor = 75;
    end
    case_pass(index) = candidate_acc_overflow(index) == 0 && ...
        candidate_saturation(index) <= baseline_saturation(index) && ...
        min([snr_4x_db(index), snr_8x_db(index), ...
             snr_128x_db(index)]) >= quality_floor;
end

case_table = table(case_name, case_fs, snr_4x_db, snr_8x_db, ...
    snr_128x_db, peak_4x_lsb24, peak_8x_lsb24, peak_128x_lsb24, ...
    candidate_acc_overflow, candidate_saturation, baseline_saturation, ...
    case_pass, 'VariableNames', {'CASE_NAME', 'FS_IN_HZ', ...
    'SNR_4X_VS_BASELINE_DB', 'SNR_8X_VS_BASELINE_DB', ...
    'SNR_128X_VS_BASELINE_DB', 'PEAK_4X_DELTA_LSB24', ...
    'PEAK_8X_DELTA_LSB24', 'PEAK_128X_DELTA_LSB24', ...
    'CANDIDATE_ACC_OVERFLOW', 'CANDIDATE_SATURATION', ...
    'BASELINE_SATURATION', 'PASS'});
writetable(case_table, fullfile(work_dir, ...
    'stage123_24_20_20_directed.csv'));

fid = fopen(fullfile(work_dir, 'stage123_24_20_20_summary.txt'), 'w');
if fid < 0; error('Unable to create word-length summary.'); end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, 'Stage1/Stage2/Stage3 word-length candidate: 24/20/20\n');
fprintf(fid, 'Baseline quantization: 24 -(2)-> 22 -(2)-> 20\n');
fprintf(fid, 'Candidate quantization: 24 -(4)-> 20 -(0)-> 20\n');
fprintf(fid, 'FREQUENCY_PASS=%d (%d/6)\n', all(frequency_table.PASS), ...
    nnz(frequency_table.PASS));
fprintf(fid, 'DIRECTED_PASS=%d (%d/%d)\n', all(case_table.PASS), ...
    nnz(case_table.PASS), height(case_table));
fprintf(fid, 'OVERALL_PASS=%d\n', ...
    all(frequency_table.PASS) && all(case_table.PASS));

disp(frequency_table);
disp(case_table);
assert(all(frequency_table.PASS), ...
    '24/20/20 candidate failed the six-mode frequency gate.');
assert(all(case_table.PASS), ...
    '24/20/20 candidate failed the directed fixed-point gate.');
fprintf('STAGE123_24_20_20_PASS: frequency 6/6, directed %d/%d.\n', ...
    nnz(case_table.PASS), height(case_table));


function [snr_db, peak_delta] = compare_vectors(candidate, baseline)
    count = min(numel(candidate), numel(baseline));
    candidate = double(candidate(1:count));
    baseline = double(baseline(1:count));
    delta = candidate-baseline;
    energy = sum(baseline.^2);
    error_energy = sum(delta.^2);
    if error_energy == 0
        snr_db = inf;
    elseif energy == 0
        snr_db = -inf;
    else
        snr_db = 10*log10(energy/error_energy);
    end
    peak_delta = max(abs(delta));
end


function count = count_acc_overflow(stat)
    count = stat.stage1.acc_overflow_count + ...
        stat.stage2.acc_overflow_count + ...
        stat.stage3_flat.acc_overflow_count + ...
        stat.stage3_comp.acc_overflow_count;
end


function count = count_saturation(stat)
    count = stat.stage1.output_sat_count + ...
        stat.bridge1.output_sat_count + ...
        stat.stage2.output_sat_count + ...
        stat.bridge2.output_sat_count + ...
        stat.stage3_flat.output_sat_count + ...
        stat.stage3_comp.output_sat_count + ...
        stat.cic.output_sat_count;
end


function x = make_tone(frequency_hz, level_dbfs, sample_count, fs_in)
    amplitude = (2^23-1)*10^(level_dbfs/20);
    n = 0:sample_count-1;
    x = int64(round(amplitude*sin(2*pi*frequency_hz*n/fs_in)));
end


function metric = analyze_node(y, fs_out, fs_in, pass_low, pass_high, ...
        nfft, expected_dc_sum)
    y = y(:).';
    spectrum = fft(y, nfft);
    spectrum = spectrum(1:nfft/2+1);
    frequency = (0:nfft/2)*(fs_out/nfft);
    shape_db = 20*log10(abs(spectrum)/abs(sum(y))+1e-15);
    absolute_db = 20*log10(abs(spectrum)/expected_dc_sum+1e-15);
    pass_index = frequency >= pass_low & frequency <= pass_high;
    stop_index = frequency >= (fs_in-pass_high) & frequency <= fs_out/2;
    [worst_stop_db, local_index] = max(absolute_db(stop_index));
    stop_frequency = frequency(stop_index);
    worst_frequency = stop_frequency(local_index);

    bin_width = fs_out/nfft;
    refine_frequency = linspace(max(fs_in-pass_high, ...
        worst_frequency-bin_width), min(fs_out/2, ...
        worst_frequency+bin_width), 1001);
    sample_index = (0:numel(y)-1).';
    refine_response = y*exp(-1i*2*pi/fs_out* ...
        (sample_index*refine_frequency));
    refine_db = 20*log10(abs(refine_response)/expected_dc_sum+1e-15);
    [refined_worst_db, refined_index] = max(refine_db);
    if refined_worst_db > worst_stop_db
        worst_stop_db = refined_worst_db;
        worst_frequency = refine_frequency(refined_index);
    end

    phase_index = pass_index & abs(spectrum) > max(abs(spectrum))*1e-6;
    phase_value = unwrap(angle(spectrum(phase_index)));
    omega = 2*pi*frequency(phase_index)/fs_out;
    coefficient = polyfit(omega, phase_value, 1);

    metric.absolute_pass_abs_max_db = max(abs(absolute_db(pass_index)));
    metric.shape_ripple_pp_db = max(shape_db(pass_index))- ...
        min(shape_db(pass_index));
    metric.absolute_stop_attenuation_db = -worst_stop_db;
    metric.worst_stop_frequency_hz = worst_frequency;
    metric.dc_gain_db = 20*log10(abs(sum(y)/expected_dc_sum)+1e-15);
    % The CIC model deliberately retains all-zero drain frames so its
    % vector length matches the RTL streaming contract.  Linear-phase
    % symmetry applies to the finite nonzero impulse support, not to those
    % protocol-only tail frames.
    nonzero_index = find(y ~= 0);
    if isempty(nonzero_index)
        metric.symmetry_lsb = inf;
    else
        impulse_support = y(nonzero_index(1):nonzero_index(end));
        metric.symmetry_lsb = max(abs(impulse_support- ...
            fliplr(impulse_support)));
    end
    metric.group_delay_samples = -coefficient(1);
    metric.phase_fit_residual_rad = max(abs(phase_value- ...
        polyval(coefficient, omega)));
end
