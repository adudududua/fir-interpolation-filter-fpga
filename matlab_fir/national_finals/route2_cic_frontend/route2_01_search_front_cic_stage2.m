clearvars;
clc;

% Route 2A feasibility search:
%   CIC2 front end -> dedicated 2x compensation/interpolation FIR.
%
% The front CIC is normalized to gain 2.  The compensation FIR has gain 2,
% so the 4x output has gain 4.  Every candidate is quantized to Q15 before
% it is measured.  The search also enforces the 128-clock real-time budget
% of the existing board architecture.

script_dir = fileparts(mfilename('fullpath'));
result_dir = fullfile(script_dir, 'results');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end

FS_LIST = [44100 48000];
FS_DESIGN = 44100;
FS4_DESIGN = 4*FS_DESIGN;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_DESIGN = FS_DESIGN-F_PASS_HIGH;
PASS_LIMIT_DB = 0.05;
STOP_LIMIT_DB = 70;
FRAC_W = 15;
NFFT_SEARCH = 2^15;
NFFT_EXACT = 2^20;

% A dedicated Stage2 engine performs two input transactions per original
% PCM word.  Its approximate schedule is 2*TAPS+8 clocks.  TAPS<=57 leaves
% at least six clocks of guard inside the 128-clock input period.
CIC_ORDER_LIST = 1:6;
% 17:4:57 is the implementable region.  The longer points are deliberately
% included as a control experiment: they show how long the FIR must become
% before the frequency-domain limits can be met, even though those points
% cannot fit the real-time schedule.
TAP_LIST = unique([17:4:57 65:16:257]);
PASS_WEIGHT_LIST = [1 3 10 30 100];
STOP_WEIGHT_LIST = [1 3 10 30 100 300 1000];

candidate = repmat(struct(), 0, 1);
store = repmat(struct(), 0, 1);
candidate_index = 0;

fprintf('Route 2A: front CIC + Stage2 compensation search\n');
for cic_order = CIC_ORDER_LIST
    h_cic = front_cic_ir(cic_order);
    h_cic_at_fs4 = upsample_ir(h_cic, 2);

    for taps = TAP_LIST
        for pass_weight = PASS_WEIGHT_LIST
            for stop_weight = STOP_WEIGHT_LIST
                h_stage2_float = design_compensation_fir( ...
                    h_cic_at_fs4, taps, FS4_DESIGN, ...
                    F_PASS_HIGH, F_STOP_DESIGN, ...
                    pass_weight, stop_weight);
                coeff_int = quantize_gain_symmetric( ...
                    h_stage2_float, FRAC_W, 2);
                h_stage2 = double(coeff_int)/2^FRAC_W;
                h4 = conv(h_cic_at_fs4, h_stage2);

                metric_44 = analyze_node(h4, 4*FS_LIST(1), FS_LIST(1), ...
                    F_PASS_LOW, F_PASS_HIGH, NFFT_SEARCH);
                metric_48 = analyze_node(h4, 4*FS_LIST(2), FS_LIST(2), ...
                    F_PASS_LOW, F_PASS_HIGH, NFFT_SEARCH);

                candidate_index = candidate_index+1;
                candidate(candidate_index).CIC_ORDER = cic_order; %#ok<SAGROW>
                candidate(candidate_index).STAGE2_TAPS = taps; %#ok<SAGROW>
                candidate(candidate_index).PASS_WEIGHT = pass_weight; %#ok<SAGROW>
                candidate(candidate_index).STOP_WEIGHT = stop_weight; %#ok<SAGROW>
                candidate(candidate_index).COEFF_W = ...
                    required_signed_width(coeff_int); %#ok<SAGROW>
                candidate(candidate_index).CYCLE_ESTIMATE = 2*taps+8; %#ok<SAGROW>
                candidate(candidate_index).WORST_PASS_ABS_DB = max( ...
                    metric_44.pass_abs_max_db, metric_48.pass_abs_max_db); %#ok<SAGROW>
                candidate(candidate_index).WORST_RIPPLE_PP_DB = max( ...
                    metric_44.ripple_pp_db, metric_48.ripple_pp_db); %#ok<SAGROW>
                candidate(candidate_index).WORST_STOP_ATTN_DB = min( ...
                    metric_44.stop_attn_db, metric_48.stop_attn_db); %#ok<SAGROW>
                candidate(candidate_index).FREQUENCY_PASS = ...
                    candidate(candidate_index).WORST_PASS_ABS_DB <= PASS_LIMIT_DB && ...
                    candidate(candidate_index).WORST_STOP_ATTN_DB >= STOP_LIMIT_DB; %#ok<SAGROW>
                candidate(candidate_index).PASS = ...
                    candidate(candidate_index).FREQUENCY_PASS && ...
                    candidate(candidate_index).CYCLE_ESTIMATE <= 128; %#ok<SAGROW>
                store(candidate_index).h_cic = h_cic; %#ok<SAGROW>
                store(candidate_index).coeff_int = coeff_int; %#ok<SAGROW>
                store(candidate_index).h_stage2 = h_stage2; %#ok<SAGROW>
                store(candidate_index).h4 = h4; %#ok<SAGROW>
            end
        end
    end
    fprintf('  CIC order %d complete\n', cic_order);
end

candidate_table = struct2table(candidate);
candidate_table.ORIGINAL_INDEX = (1:height(candidate_table)).';
candidate_table = sortrows(candidate_table, ...
    {'PASS', 'STAGE2_TAPS', 'CIC_ORDER', 'WORST_STOP_ATTN_DB', ...
     'WORST_PASS_ABS_DB'}, ...
    {'descend', 'ascend', 'ascend', 'descend', 'ascend'});
writetable(candidate_table, fullfile(result_dir, ...
    'route2_front_cic_stage2_candidates.csv'));

passing = candidate_table(candidate_table.PASS, :);
if isempty(passing)
    frequency_passing = candidate_table( ...
        candidate_table.FREQUENCY_PASS, :);
    if ~isempty(frequency_passing)
        frequency_passing = sortrows(frequency_passing, ...
            {'STAGE2_TAPS', 'CYCLE_ESTIMATE', 'CIC_ORDER', ...
             'WORST_STOP_ATTN_DB'}, ...
            {'ascend', 'ascend', 'ascend', 'descend'});
        selected_row = frequency_passing(1, :);
        decision = "NO-GO-TIMING";
    else
        near = candidate_table(candidate_table.WORST_PASS_ABS_DB <= ...
            PASS_LIMIT_DB, :);
        if isempty(near)
            near = sortrows(candidate_table, ...
                {'WORST_PASS_ABS_DB', 'WORST_STOP_ATTN_DB'}, ...
                {'ascend', 'descend'});
        else
            near = sortrows(near, ...
                {'WORST_STOP_ATTN_DB', 'STAGE2_TAPS'}, ...
                {'descend', 'ascend'});
        end
        selected_row = near(1, :);
        decision = "NO-GO-FREQUENCY";
    end
else
    selected_row = passing(1, :);
    decision = "GO";
end

selected_index = selected_row.ORIGINAL_INDEX;
selected.row = selected_row;
selected.h_cic = store(selected_index).h_cic;
selected.stage2_coeff_int = store(selected_index).coeff_int;
selected.h_stage2 = store(selected_index).h_stage2;
selected.h4 = store(selected_index).h4;
selected.decision = decision;

node_name = strings(0, 1);
fs_in_hz = [];
pass_abs_max_db = [];
ripple_pp_db = [];
stop_attn_db = [];
symmetry_error = [];
pass = [];
for fs_in = FS_LIST
    metric = analyze_node(selected.h4, 4*fs_in, fs_in, ...
        F_PASS_LOW, F_PASS_HIGH, NFFT_EXACT);
    node_name(end+1, 1) = "4x"; %#ok<SAGROW>
    fs_in_hz(end+1, 1) = fs_in; %#ok<SAGROW>
    pass_abs_max_db(end+1, 1) = metric.pass_abs_max_db; %#ok<SAGROW>
    ripple_pp_db(end+1, 1) = metric.ripple_pp_db; %#ok<SAGROW>
    stop_attn_db(end+1, 1) = metric.stop_attn_db; %#ok<SAGROW>
    symmetry_error(end+1, 1) = metric.symmetry_error; %#ok<SAGROW>
    pass(end+1, 1) = metric.pass_abs_max_db <= PASS_LIMIT_DB && ...
        metric.stop_attn_db >= STOP_LIMIT_DB && ...
        metric.symmetry_error < 1e-12; %#ok<SAGROW>
end
metric_table = table(node_name, fs_in_hz, pass_abs_max_db, ...
    ripple_pp_db, stop_attn_db, symmetry_error, pass, ...
    'VariableNames', {'NODE', 'FS_IN_HZ', 'PASS_ABS_MAX_DB', ...
    'RIPPLE_PP_DB', 'STOP_ATTN_DB', 'SYMMETRY_ERROR', 'PASS'});

if ~all(metric_table.PASS)
    selected.decision = "NO-GO-FREQUENCY";
elseif selected.row.CYCLE_ESTIMATE > 128
    selected.decision = "NO-GO-TIMING";
end
selected.metric_table = metric_table;
save(fullfile(result_dir, ...
    'route2_front_cic_stage2_selected.mat'), 'selected');
writetable(metric_table, fullfile(result_dir, ...
    'route2_front_cic_stage2_metrics.csv'));
write_summary(fullfile(result_dir, ...
    'route2_front_cic_stage2_summary.md'), selected, ...
    PASS_LIMIT_DB, STOP_LIMIT_DB);

disp(selected.row);
disp(metric_table);
fprintf('Route 2A decision: %s\n', selected.decision);
fprintf('Summary: %s\n', fullfile(result_dir, ...
    'route2_front_cic_stage2_summary.md'));


function h = front_cic_ir(order_n)
    h = 1;
    for section = 1:order_n
        h = conv(h, [1 1]);
    end
    h = h*(2/sum(h));
end


function h = design_compensation_fir(h_front_at_fs4, taps, fs_out, ...
        pass_edge, stop_edge, pass_weight, stop_weight)
    half_len = (taps-1)/2;
    f_pass = linspace(0, pass_edge, 700).';
    f_stop = linspace(stop_edge, fs_out/2, 1100).';
    H_front = response_at_frequency( ...
        h_front_at_fs4, f_pass, fs_out);
    target_pass = 4./max(abs(H_front), 1e-12);

    f = [f_pass; f_stop];
    target = [target_pass; zeros(size(f_stop))];
    weight = [pass_weight*ones(size(f_pass)); ...
        stop_weight*ones(size(f_stop))];
    omega = 2*pi*f/fs_out;
    cosine_matrix = ones(numel(f), half_len+1);
    for k = 1:half_len
        cosine_matrix(:, k+1) = 2*cos(omega*k);
    end
    weighted_matrix = cosine_matrix.*weight;
    weighted_target = target.*weight;
    side_center = weighted_matrix\weighted_target;

    h = zeros(1, taps);
    center = half_len+1;
    h(center) = side_center(1);
    for k = 1:half_len
        h(center-k) = side_center(k+1);
        h(center+k) = side_center(k+1);
    end
    h(center) = h(center)+(2-sum(h));
end


function coeff_int = quantize_gain_symmetric(h, frac_w, gain)
    scale = int64(2^frac_w);
    coeff_int = int64(round(h(:).'*double(scale)));
    coeff_int = int64(round((double(coeff_int)+ ...
        fliplr(double(coeff_int)))/2));
    center = (numel(coeff_int)+1)/2;
    coeff_int(center) = coeff_int(center)+ ...
        int64(gain)*scale-sum(coeff_int);
end


function h_up = upsample_ir(h, rate)
    h = h(:).';
    h_up = zeros(1, rate*(numel(h)-1)+1);
    h_up(1:rate:end) = h;
end


function H = response_at_frequency(h, frequency, sample_rate)
    omega = 2*pi*frequency(:)/sample_rate;
    sample_index = 0:numel(h)-1;
    H = exp(-1j*omega*sample_index)*h(:);
end


function metric = analyze_node(h, fs_out, fs_in, ...
        pass_low, pass_high, nfft)
    [H, f] = freqz(h, 1, nfft, fs_out);
    H_db = 20*log10(abs(H/sum(h))+1e-15);
    pass_idx = f >= pass_low & f <= pass_high;
    stop_idx = f >= (fs_in-pass_high) & f <= fs_out/2;
    pass_db = H_db(pass_idx);
    metric.pass_abs_max_db = max(abs(pass_db));
    metric.ripple_pp_db = max(pass_db)-min(pass_db);
    metric.stop_attn_db = -max(H_db(stop_idx));
    metric.symmetry_error = max(abs(h-fliplr(h)));
end


function width = required_signed_width(coeff_int)
    width = 2;
    while max(coeff_int) > int64(2^(width-1)-1) || ...
            min(coeff_int) < int64(-2^(width-1))
        width = width+1;
    end
end


function write_summary(filename, selected, pass_limit, stop_limit)
    fid = fopen(filename, 'w');
    if fid < 0; error('Cannot create %s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '# Route 2A front-CIC feasibility result\n\n');
    fprintf(fid, '- Decision: **%s**\n', selected.decision);
    fprintf(fid, '- Front CIC: R=2, N=%d, normalized gain=2\n', ...
        selected.row.CIC_ORDER);
    fprintf(fid, '- Compensation/interpolation FIR: %d taps, Q15/%d-bit\n', ...
        selected.row.STAGE2_TAPS, selected.row.COEFF_W);
    fprintf(fid, '- Estimated schedule: %d/128 clocks\n', ...
        selected.row.CYCLE_ESTIMATE);
    fprintf(fid, '- Frequency-only pass: %d\n', ...
        selected.row.FREQUENCY_PASS);
    fprintf(fid, '- Limits: pass <= +/-%.3f dB, stop >= %.1f dB\n\n', ...
        pass_limit, stop_limit);
    fprintf(fid, '| Fs in | Node | Pass abs/dB | Ripple p-p/dB | Stop/dB | Symmetry | Pass |\n');
    fprintf(fid, '|---:|:---:|---:|---:|---:|---:|:---:|\n');
    for idx = 1:height(selected.metric_table)
        fprintf(fid, '| %.0f | %s | %.9f | %.9f | %.9f | %.3g | %d |\n', ...
            selected.metric_table.FS_IN_HZ(idx), ...
            selected.metric_table.NODE(idx), ...
            selected.metric_table.PASS_ABS_MAX_DB(idx), ...
            selected.metric_table.RIPPLE_PP_DB(idx), ...
            selected.metric_table.STOP_ATTN_DB(idx), ...
            selected.metric_table.SYMMETRY_ERROR(idx), ...
            selected.metric_table.PASS(idx));
    end
    fprintf(fid, '\n## Q15 coefficients\n\n```text\n');
    fprintf(fid, '%d\n', selected.stage2_coeff_int);
    fprintf(fid, '```\n');
end
