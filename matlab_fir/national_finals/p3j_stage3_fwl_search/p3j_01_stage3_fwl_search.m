% P3-J P5 MATLAB gate: constrained signed-20 and 9-tap Stage3 search.
% The 4x/8x flat bank is frozen. Only the compensated 128x bank is searched.

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
nf_dir = fileparts(script_dir);
matlab_root = fileparts(nf_dir);
bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
result_dir = fullfile(script_dir, 'results');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
addpath(nf_dir);
addpath(bittrue_dir);

CONFIG_ID = 'NF-P3J-P5-STAGE3-FWL-SEARCH-R1';
FS_LIST = [44100 48000];
PASS_LOW_HZ = 10;
PASS_HIGH_HZ = 20000;
PASS_GATE_DB = 0.02;
STOP_GATE_DB = 71;
FRAC_W = 15;
COEFF_W = 18;
SIGNED20_MAX = 2^19-1;
SIGNED20_MIN = -2^19;
NFFT_FINAL = 2^19;

cfg = nf_release_v2_config();
h1 = double(cfg.stage1.coeff_int(:).')/2^cfg.stage1.frac_w;
h2 = double(cfg.stage2.coeff_int(:).')/2^cfg.stage2.frac_w;
h4 = conv(upsample_ir(h1, 2), h2);
h_cic = conv(conv(ones(1, 16), ones(1, 16)), ones(1, 16))/2^8;
baseline_independent = int64([561 137 -4232 -1554 20046 35584]);
baseline_coeff = expand_symmetric(baseline_independent);

fprintf('Building fixed P3-J Stage2 search vectors...\n');
[case_names, case_inputs] = make_fixed_inputs();
stage2_cases = cell(size(case_inputs));
for case_index = 1:numel(case_inputs)
    stage2_cases{case_index} = build_stage2(case_inputs{case_index}, cfg);
end
search_names = {'impulse', 'fullscale_positive', ...
    'fullscale_negative', 'strong_44k1_minus1dbfs'};
search_case_index = find(ismember(case_names, search_names));
peak_basis_search = [];
for index = search_case_index(:).'
    peak_basis_search = [peak_basis_search, ... %#ok<AGROW>
        build_stage3_acc_basis(stage2_cases{index}, 11)];
end

fprintf('Building dual-family coarse frequency banks...\n');
bank11 = make_frequency_bank(h4, h_cic, FS_LIST, PASS_LOW_HZ, ...
    PASS_HIGH_HZ, 11);
bank9 = make_frequency_bank(h4, h_cic, FS_LIST, PASS_LOW_HZ, ...
    PASS_HIGH_HZ, 9);

%% P5-A20: six-integer constrained 11-tap search.
rng(803021, 'twister');
candidate11 = baseline_independent;
sigma_sets = [12 12 20 20 30; 30 30 50 50 80; ...
    80 80 120 120 180; 180 180 250 250 350];
group_count = 20000;
for sigma_index = 1:size(sigma_sets, 1)
    first_five = double(baseline_independent(1:5)) + round( ...
        randn(group_count, 5).*sigma_sets(sigma_index, :));
    dc_sum = double(sum(baseline_coeff)) + randi([-120 120], ...
        group_count, 1);
    center = dc_sum-2*sum(first_five, 2);
    candidate11 = [candidate11; int64([first_five center])]; %#ok<AGROW>
end
candidate11 = unique(candidate11, 'rows', 'stable');
candidate11 = candidate11(max(abs(double(candidate11)), [], 2) < 2^(COEFF_W-1), :);

[pass11, stop11] = coarse_screen(candidate11, bank11, 250);
frequency_keep11 = pass11 <= PASS_GATE_DB+0.002 & ...
    stop11 >= STOP_GATE_DB-0.2;
candidate11_gate = candidate11(frequency_keep11, :);
pass11_gate = pass11(frequency_keep11);
stop11_gate = stop11(frequency_keep11);
peak11_gate = bittrue_peak(candidate11_gate, peak_basis_search, 100);

% Refine around the lowest-peak frequency-qualified regions twice.
for refinement = 1:2
    [~, order] = sortrows([peak11_gate, pass11_gate, -stop11_gate], ...
        [1 2 3]);
    seed_count = min(24, numel(order));
    if seed_count == 0; break; end
    seeds = candidate11_gate(order(1:seed_count), :);
    local_count_per_seed = 2500;
    local = zeros(seed_count*local_count_per_seed, 6, 'int64');
    write_index = 1;
    for seed_index = 1:seed_count
        if refinement == 1
            sigma = [12 12 20 20 28];
        else
            sigma = [4 4 7 7 10];
        end
        first_five = double(seeds(seed_index, 1:5)) + round( ...
            randn(local_count_per_seed, 5).*sigma);
        dc_sum = double(sum(expand_symmetric(seeds(seed_index, :)))) + ...
            randi([-24 24], local_count_per_seed, 1);
        center = dc_sum-2*sum(first_five, 2);
        rows = int64([first_five center]);
        local(write_index:write_index+local_count_per_seed-1, :) = rows;
        write_index = write_index+local_count_per_seed;
    end
    local = unique(local, 'rows', 'stable');
    local = local(max(abs(double(local)), [], 2) < 2^(COEFF_W-1), :);
    [local_pass, local_stop] = coarse_screen(local, bank11, 250);
    local_keep = local_pass <= PASS_GATE_DB+0.002 & ...
        local_stop >= STOP_GATE_DB-0.2;
    local = local(local_keep, :);
    local_pass = local_pass(local_keep);
    local_stop = local_stop(local_keep);
    local_peak = bittrue_peak(local, peak_basis_search, 100);
    candidate11_gate = [candidate11_gate; local]; %#ok<AGROW>
    pass11_gate = [pass11_gate; local_pass]; %#ok<AGROW>
    stop11_gate = [stop11_gate; local_stop]; %#ok<AGROW>
    peak11_gate = [peak11_gate; local_peak]; %#ok<AGROW>
    [candidate11_gate, unique_index] = unique(candidate11_gate, ...
        'rows', 'stable');
    pass11_gate = pass11_gate(unique_index);
    stop11_gate = stop11_gate(unique_index);
    peak11_gate = peak11_gate(unique_index);
end

precise_pass11 = nan(size(pass11_gate));
precise_stop11 = nan(size(stop11_gate));
safe_index = find(peak11_gate <= SIGNED20_MAX);
if ~isempty(safe_index)
    [~, safe_order] = sortrows([pass11_gate(safe_index), ...
        -stop11_gate(safe_index), peak11_gate(safe_index)], [1 2 3]);
    precise_index = safe_index(safe_order(1:min(200, numel(safe_order))));
    for row = precise_index(:).'
        h = double(expand_symmetric(candidate11_gate(row, :)))/2^FRAC_W;
        h128 = build_h128(h4, h, h_cic);
        [precise_pass11(row), precise_stop11(row)] = precise_gate( ...
            h128, FS_LIST, PASS_LOW_HZ, PASS_HIGH_HZ, NFFT_FINAL);
    end
end
signed20_pass = peak11_gate <= SIGNED20_MAX & ...
    precise_pass11 <= PASS_GATE_DB & precise_stop11 >= STOP_GATE_DB;

% Always retain a compact ranked audit table, including the baseline.
baseline_row = find(all(candidate11_gate == baseline_independent, 2), 1);
rank_score11 = pass11_gate/PASS_GATE_DB + ...
    max(0, STOP_GATE_DB-stop11_gate) + ...
    max(0, peak11_gate-SIGNED20_MAX)/4096;
[~, rank11] = sort(rank_score11, 'ascend');
keep11 = unique([baseline_row; find(signed20_pass); rank11(1:min(1000, numel(rank11)))], ...
    'stable');
table11 = build_candidate_table(candidate11_gate(keep11, :), ...
    pass11_gate(keep11), stop11_gate(keep11), peak11_gate(keep11), ...
    precise_pass11(keep11), precise_stop11(keep11), ...
    signed20_pass(keep11), 11);
writetable(table11, fullfile(result_dir, ...
    'p3j_p5_signed20_candidates.csv'));

selected11 = int64([]);
coverage_table = table();
if any(signed20_pass)
    passing_rows = find(signed20_pass);
    [~, best_order] = sortrows([precise_pass11(passing_rows), ...
        -precise_stop11(passing_rows), peak11_gate(passing_rows)], [1 2 3]);
    selected_row = passing_rows(best_order(1));
    selected11 = candidate11_gate(selected_row, :);
    coverage_table = full_coverage(selected11, case_names, stage2_cases, ...
        SIGNED20_MIN, SIGNED20_MAX);
    writetable(coverage_table, fullfile(result_dir, ...
        'p3j_p5_signed20_fixed_vector_coverage.csv'));
    if ~all(coverage_table.SIGNED20_SAFE)
        selected11 = int64([]);
    end
end

%% P5-A9: MATLAB-only 9-tap prefilter search.
weight_list = [1e-5 1e-4 1e-3 1e-2 1e-1 1 10 100];
seed9 = zeros(numel(weight_list), 5, 'int64');
for weight_index = 1:numel(weight_list)
    h = design_joint_stage3(9, weight_list(weight_index), h4, ...
        FS_LIST, PASS_HIGH_HZ);
    seed9(weight_index, :) = int64(round(h(1:5)*2^FRAC_W));
end
candidate9 = seed9;
for seed_index = 1:size(seed9, 1)
    local_count = 5000;
    first_four = double(seed9(seed_index, 1:4)) + round( ...
        randn(local_count, 4).*[40 60 90 140]);
    dc_sum = double(sum(expand_symmetric(seed9(seed_index, :)))) + ...
        randi([-120 120], local_count, 1);
    center = dc_sum-2*sum(first_four, 2);
    candidate9 = [candidate9; int64([first_four center])]; %#ok<AGROW>
end
candidate9 = unique(candidate9, 'rows', 'stable');
candidate9 = candidate9(max(abs(double(candidate9)), [], 2) < 2^(COEFF_W-1), :);
[pass9, stop9] = coarse_screen(candidate9, bank9, 250);
precise_pass9 = nan(size(pass9));
precise_stop9 = nan(size(stop9));
coarse_gate9 = find(pass9 <= PASS_GATE_DB+0.003 & ...
    stop9 >= STOP_GATE_DB-0.3);
if ~isempty(coarse_gate9)
    [~, order9] = sortrows([pass9(coarse_gate9), -stop9(coarse_gate9)], [1 2]);
    precise_index9 = coarse_gate9(order9(1:min(300, numel(order9))));
    for row = precise_index9(:).'
        h = double(expand_symmetric(candidate9(row, :)))/2^FRAC_W;
        h128 = build_h128(h4, h, h_cic);
        [precise_pass9(row), precise_stop9(row)] = precise_gate( ...
            h128, FS_LIST, PASS_LOW_HZ, PASS_HIGH_HZ, NFFT_FINAL);
    end
end
pass_gate9 = precise_pass9 <= PASS_GATE_DB & precise_stop9 >= STOP_GATE_DB;
rank_score9 = pass9/PASS_GATE_DB + max(0, STOP_GATE_DB-stop9);
[~, rank9] = sort(rank_score9, 'ascend');
keep9 = unique([find(pass_gate9); rank9(1:min(1000, numel(rank9)))], 'stable');
table9 = build_candidate_table(candidate9(keep9, :), pass9(keep9), ...
    stop9(keep9), nan(numel(keep9), 1), precise_pass9(keep9), ...
    precise_stop9(keep9), pass_gate9(keep9), 9);
writetable(table9, fullfile(result_dir, 'p3j_p5_9tap_candidates.csv'));

%% Summary and hard conclusion.
baseline_peak = bittrue_peak(baseline_independent, peak_basis_search, 1);
fid = fopen(fullfile(result_dir, 'p3j_p5_stage3_fwl_summary.txt'), 'w');
if fid < 0; error('Unable to create P5 summary.'); end
cleanup_summary = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'P3-J P5 Stage3 finite-word-length search\n');
fprintf(fid, 'CONFIG_ID=%s\n', CONFIG_ID);
fprintf(fid, 'BASELINE_COEFFICIENTS='); fprintf(fid, '%d ', baseline_coeff); fprintf(fid, '\n');
fprintf(fid, 'BASELINE_SEARCH_VECTOR_PEAK=%d\n', baseline_peak);
fprintf(fid, 'SIGNED20_LIMIT=[%d,%d]\n', SIGNED20_MIN, SIGNED20_MAX);
fprintf(fid, 'SIGNED20_RANDOM_AND_LOCAL_CANDIDATES=%d\n', size(candidate11, 1));
fprintf(fid, 'SIGNED20_FREQUENCY_QUALIFIED=%d\n', size(candidate11_gate, 1));
fprintf(fid, 'SIGNED20_PRECISE_AND_PEAK_PASS=%d\n', nnz(signed20_pass));
fprintf(fid, 'SIGNED20_FULL_COVERAGE_PASS=%d\n', ~isempty(selected11));
if ~isempty(selected11)
    fprintf(fid, 'SIGNED20_SELECTED_INDEPENDENT='); fprintf(fid, '%d ', selected11); fprintf(fid, '\n');
    fprintf(fid, 'SIGNED20_SELECTED_FULL='); fprintf(fid, '%d ', expand_symmetric(selected11)); fprintf(fid, '\n');
end
fprintf(fid, 'NINE_TAP_CANDIDATES=%d\n', size(candidate9, 1));
fprintf(fid, 'NINE_TAP_PRECISE_PASS=%d\n', nnz(pass_gate9));
fprintf(fid, 'SIGNED20_MATLAB_GO=%d\n', ~isempty(selected11));
fprintf(fid, 'NINE_TAP_MATLAB_GO=%d\n', any(pass_gate9));
fprintf(fid, 'RTL_STATUS=NOT_CHANGED_BY_THIS_SCRIPT\n');
clear cleanup_summary;

fprintf(['P3J_P5_SEARCH_DONE: signed20_go=%d, 9tap_go=%d, ' ...
    'baseline_peak=%d\n'], ~isempty(selected11), any(pass_gate9), baseline_peak);


function h_up = upsample_ir(h, rate)
    h = h(:).';
    h_up = zeros(1, rate*(numel(h)-1)+1);
    h_up(1:rate:end) = h;
end


function full = expand_symmetric(independent)
    full = [independent, independent(:, end-1:-1:1)];
end


function [names, inputs] = make_fixed_inputs()
    seed_values = [294753618, 104729, 130363, 155921, 181081, ...
        206369, 231761, 257053, 282407, 307817];
    names = [{'impulse'}, arrayfun(@(k) sprintf('random_seed%02d', k), ...
        1:numel(seed_values), 'UniformOutput', false), ...
        {'fullscale_positive', 'fullscale_negative', ...
         'strong_44k1_minus1dbfs'}];
    inputs = cell(size(names));
    inputs{1} = zeros(1, 256, 'int64');
    inputs{1}(1) = int64(2^22);
    for index = 1:numel(seed_values)
        rng(seed_values(index), 'twister');
        inputs{index+1} = int64(randi([-2^20, 2^20-1], 1, 4096));
    end
    inputs{end-2} = zeros(1, 256, 'int64');
    inputs{end-2}(1) = int64(2^23-1);
    inputs{end-1} = zeros(1, 256, 'int64');
    inputs{end-1}(1) = int64(-2^23);
    amplitude = (2^23-1)*10^(-1/20);
    n = 0:2047;
    inputs{end} = int64(round(amplitude*sin(2*pi*997*n/44100)));
end


function stage2_q20 = build_stage2(x, cfg)
    [stage1, ~] = interp2_polyphase_bittrue(x, ...
        cfg.stage1.coeff_int, cfg.stage1.frac_w, ...
        cfg.stage1.input_w, cfg.stage1.acc_w);
    [stage1_q22, ~] = round_shift_sat_signed(stage1, 2, 22);
    [stage2, ~] = interp2_polyphase_bittrue(stage1_q22, ...
        cfg.stage2.coeff_int, cfg.stage2.frac_w, ...
        cfg.stage2.input_w, cfg.stage2.acc_w);
    [stage2_q20, ~] = round_shift_sat_signed(stage2, 2, 20);
end


function basis = build_stage3_acc_basis(x, taps)
    independent_count = (taps+1)/2;
    output_count = 2*numel(x)+taps-2;
    basis = zeros(independent_count, output_count);
    for index = 1:independent_count
        independent = zeros(1, independent_count, 'int64');
        independent(index) = 1;
        coeff = expand_symmetric(independent);
        phase0 = coeff(1:2:end);
        phase1 = coeff(2:2:end);
        acc = zeros(1, output_count);
        acc(1:2:end) = conv(double(x), double(phase0));
        acc(2:2:end) = conv(double(x), double(phase1));
        basis(index, :) = acc;
    end
end


function peak = bittrue_peak(candidate, basis, batch_size)
    if isempty(candidate)
        peak = zeros(0, 1);
        return;
    end
    peak = zeros(size(candidate, 1), 1);
    for first = 1:batch_size:size(candidate, 1)
        last = min(size(candidate, 1), first+batch_size-1);
        acc = double(candidate(first:last, :))*basis;
        rounded = floor((acc+16383+(acc >= 0))/2^15);
        peak(first:last) = max(abs(rounded), [], 2);
    end
end


function bank = make_frequency_bank(h4, h_cic, fs_list, ...
        pass_low, pass_high, taps)
    half = (taps-1)/2;
    distances = half:-1:1;
    pass_basis = [];
    pass_prefactor = [];
    stop_basis = [];
    stop_prefactor = [];
    for fs_in = fs_list
        pass_frequency = linspace(pass_low, pass_high, 900);
        stop_frequency = linspace(fs_in-pass_high, 64*fs_in, 12000);
        pass_basis = [pass_basis, symmetric_basis(pass_frequency, ... %#ok<AGROW>
            8*fs_in, distances)];
        stop_basis = [stop_basis, symmetric_basis(stop_frequency, ... %#ok<AGROW>
            8*fs_in, distances)];
        pass_prefactor = [pass_prefactor, response_prefactor(h4, ... %#ok<AGROW>
            h_cic, pass_frequency, fs_in)];
        stop_prefactor = [stop_prefactor, response_prefactor(h4, ... %#ok<AGROW>
            h_cic, stop_frequency, fs_in)];
    end
    bank.pass_basis = pass_basis;
    bank.pass_prefactor = pass_prefactor;
    bank.stop_basis = stop_basis;
    bank.stop_prefactor = stop_prefactor;
end


function basis = symmetric_basis(frequency, stage_rate, distances)
    omega = 2*pi*frequency(:).'/stage_rate;
    basis = [2*cos(distances(:)*omega); ones(1, numel(omega))];
end


function prefactor = response_prefactor(h4, h_cic, frequency, fs_in)
    h4_response = response_at(h4, frequency, 4*fs_in);
    cic_response = response_at(h_cic, frequency, 128*fs_in);
    prefactor = abs(h4_response(:).').*abs(cic_response(:).')/(2^15*128);
end


function [worst_pass, worst_stop] = coarse_screen(candidate, bank, batch_size)
    worst_pass = zeros(size(candidate, 1), 1);
    worst_stop = zeros(size(candidate, 1), 1);
    for first = 1:batch_size:size(candidate, 1)
        last = min(size(candidate, 1), first+batch_size-1);
        coeff = double(candidate(first:last, :));
        pass_gain = abs(coeff*bank.pass_basis).*bank.pass_prefactor;
        stop_gain = abs(coeff*bank.stop_basis).*bank.stop_prefactor;
        pass_db = 20*log10(pass_gain+1e-15);
        stop_db = 20*log10(stop_gain+1e-15);
        worst_pass(first:last) = max(abs(pass_db), [], 2);
        worst_stop(first:last) = -max(stop_db, [], 2);
    end
end


function h128 = build_h128(h4, h3, h_cic)
    h8 = conv(upsample_ir(h4, 2), h3);
    h128 = conv(upsample_ir(h8, 16), h_cic);
end


function [worst_pass, worst_stop] = precise_gate(h, fs_list, ...
        pass_low, pass_high, nfft)
    worst_pass = 0;
    worst_stop = inf;
    for fs_in = fs_list
        metric = analyze_node(h, 128, fs_in, pass_low, pass_high, nfft);
        worst_pass = max(worst_pass, metric.pass_abs_db);
        worst_stop = min(worst_stop, metric.stop_db);
    end
end


function metric = analyze_node(h, factor, fs_in, pass_low, pass_high, nfft)
    fs_out = factor*fs_in;
    spectrum = fft(double(h(:).'), nfft);
    spectrum = spectrum(1:nfft/2+1);
    frequency = (0:nfft/2)*(fs_out/nfft);
    absolute_db = 20*log10(abs(spectrum)/factor+1e-15);
    pass_index = frequency >= pass_low & frequency <= pass_high;
    stop_index = frequency >= (fs_in-pass_high) & frequency <= fs_out/2;
    [worst_stop_db, local_index] = max(absolute_db(stop_index));
    stop_frequency = frequency(stop_index);
    worst_frequency = stop_frequency(local_index);
    bin_width = fs_out/nfft;
    fine_frequency = linspace(max(fs_in-pass_high, worst_frequency-bin_width), ...
        min(fs_out/2, worst_frequency+bin_width), 2001);
    fine_response = response_at(h, fine_frequency, fs_out);
    fine_db = 20*log10(abs(fine_response)/factor+1e-15);
    worst_stop_db = max(worst_stop_db, max(fine_db));
    metric.pass_abs_db = max(abs(absolute_db(pass_index)));
    metric.stop_db = -worst_stop_db;
end


function response = response_at(h, frequency, sample_rate)
    sample_index = (0:numel(h)-1).';
    response = h(:).'*exp(-1i*2*pi/sample_rate* ...
        (sample_index*frequency(:).'));
    response = response(:).';
end


function h = design_joint_stage3(tap_count, stop_weight, h4, ...
        fs_list, pass_high)
    half_order = (tap_count-1)/2;
    distance = 1:half_order;
    matrix = [];
    target = [];
    for fs_in = fs_list
        pass_frequency = linspace(0, pass_high, 1200).';
        pass_omega = 2*pi*pass_frequency/(8*fs_in);
        pass_matrix = [ones(size(pass_omega)), 2*cos(pass_omega*distance)];
        h4_response = response_at(h4, pass_frequency, 4*fs_in).';
        cic_norm = cic_normalized_magnitude(pass_frequency, 8*fs_in, 16, 1, 3);
        desired = 128./(abs(h4_response).*16.*cic_norm);
        matrix = [matrix; pass_matrix]; %#ok<AGROW>
        target = [target; desired(:)]; %#ok<AGROW>
        stop_frequency = linspace(4*fs_in-pass_high, 4*fs_in, 700).';
        stop_omega = 2*pi*stop_frequency/(8*fs_in);
        stop_matrix = [ones(size(stop_omega)), 2*cos(stop_omega*distance)];
        matrix = [matrix; sqrt(stop_weight)*stop_matrix]; %#ok<AGROW>
        target = [target; zeros(size(stop_frequency))]; %#ok<AGROW>
    end
    dc_target = mean(128./(abs(sum(h4))*16));
    matrix = [matrix; 1e4*[1 2*ones(1, half_order)]];
    target = [target; 1e4*dc_target];
    matrix = [matrix; 1e-5*eye(half_order+1)];
    target = [target; zeros(half_order+1, 1)];
    scale = sqrt(sum(matrix.^2, 1));
    scale(scale < eps) = 1;
    coefficient = (matrix./scale)\target;
    coefficient = coefficient./scale.';
    h = zeros(1, tap_count);
    center = half_order+1;
    h(center) = coefficient(1);
    for index = 1:half_order
        h(center-index) = coefficient(index+1);
        h(center+index) = coefficient(index+1);
    end
end


function magnitude = cic_normalized_magnitude(frequency, input_rate, ...
        rate_change, diff_delay, order)
    numerator = sin(pi*frequency*diff_delay/input_rate);
    denominator = rate_change*diff_delay* ...
        sin(pi*frequency/(rate_change*input_rate));
    ratio = ones(size(frequency));
    nonzero = abs(frequency) > 1e-15;
    ratio(nonzero) = numerator(nonzero)./denominator(nonzero);
    magnitude = abs(ratio).^order;
end


function data = build_candidate_table(candidate, coarse_pass, coarse_stop, ...
        peak, precise_pass, precise_stop, pass, taps)
    full_coeff = expand_symmetric(candidate);
    data = array2table(double(candidate), 'VariableNames', ...
        arrayfun(@(k) sprintf('C%d', k-1), 1:size(candidate, 2), ...
        'UniformOutput', false));
    data.TAPS = repmat(taps, size(candidate, 1), 1);
    data.COEFFICIENT_SUM = sum(double(full_coeff), 2);
    data.COARSE_WORST_PASS_DB = coarse_pass;
    data.COARSE_WORST_STOP_DB = coarse_stop;
    data.SEARCH_VECTOR_PEAK = peak;
    data.PRECISE_WORST_PASS_DB = precise_pass;
    data.PRECISE_WORST_STOP_DB = precise_stop;
    data.PASS = logical(pass);
end


function data = full_coverage(candidate, names, stage2_cases, out_min, out_max)
    max_abs = zeros(numel(names), 1);
    sat_count = zeros(numel(names), 1);
    safe = false(numel(names), 1);
    for index = 1:numel(names)
        basis = build_stage3_acc_basis(stage2_cases{index}, 11);
        acc = double(candidate)*basis;
        rounded = floor((acc+16383+(acc >= 0))/2^15);
        max_abs(index) = max(abs(rounded));
        sat_count(index) = nnz(rounded > out_max | rounded < out_min);
        safe(index) = sat_count(index) == 0;
    end
    data = table(names(:), max_abs, sat_count, safe, ...
        'VariableNames', {'CASE_NAME', 'MAX_ABS_STAGE3', ...
        'SIGNED20_SATURATION_COUNT', 'SIGNED20_SAFE'});
end
