clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(fileparts(script_dir));
source_path = fullfile(matlab_root, 'alt_all2x_v8', 'results', ...
    'phase8_cic2_stage1_redesign_selected.mat');
result_dir = fullfile(script_dir, 'results');
data = load(source_path, 'selected');
base = data.selected;

FS_LIST = [44100 48000];
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
PASS_LIMIT_DB = 0.05;
STOP_LIMIT_DB = 70;
NFFT_SEARCH = 2^18;
NFFT_FINAL = 2^20;
STOP_WEIGHT_LIST = [1e-4 1e-3 1e-2 1e-1 1 10];

h_hb = [-1 0 9 16 9 0 -1]/16;
h_cic4 = base.h_cic4;
fs_stage3 = 8*FS_LIST(1);
fs_hb4 = 16*FS_LIST(1);
fs_hb5 = 32*FS_LIST(1);
fs_out = 128*FS_LIST(1);

tail_frequency = linspace(0, F_PASS_HIGH, 2000).';
tail_response = response_at_frequency(h_hb, tail_frequency, fs_hb4).* ...
    response_at_frequency(h_hb, tail_frequency, fs_hb5).* ...
    response_at_frequency(h_cic4, tail_frequency, fs_out);
tail_magnitude = abs(tail_response)/(sum(h_hb)^2*sum(h_cic4));
desired_fun = @(frequency_hz) 2./max(interp1( ...
    tail_frequency, tail_magnitude, frequency_hz, ...
    'pchip', 'extrap'), 1e-12);

row = repmat(struct(), 0, 1);
store = repmat(struct(), 0, 1);
for weight_index = 1:numel(STOP_WEIGHT_LIST)
    stop_weight = STOP_WEIGHT_LIST(weight_index);
    h_float = design_folded_stage3(11, fs_stage3, ...
        F_PASS_HIGH, 4*FS_LIST(1)-F_PASS_HIGH, ...
        desired_fun, stop_weight);
    coeff_int = quantize_gain(h_float, 14, 2);
    h_stage3 = double(coeff_int)/2^14;

    h4 = append_interp2_stage(base.h_stage1, base.h_stage2);
    h8 = append_interp2_stage(h4, h_stage3);
    h16 = append_interp2_stage(h8, h_hb);
    h32 = append_interp2_stage(h16, h_hb);
    h128 = append_interp_stage(h32, h_cic4, 4);
    metrics = evaluate_six(h4, h8, h128, FS_LIST, ...
        F_PASS_LOW, F_PASS_HIGH, NFFT_SEARCH);

    row(weight_index).STOP_WEIGHT = stop_weight; %#ok<SAGROW>
    row(weight_index).COEFF_W = required_signed_width(coeff_int); %#ok<SAGROW>
    row(weight_index).WORST_PASS_ABS_DB = ...
        max(metrics.PASS_ABS_MAX_DB); %#ok<SAGROW>
    row(weight_index).WORST_STOP_ATTN_DB = ...
        min(metrics.STOP_ATTN_DB); %#ok<SAGROW>
    row(weight_index).PASS = ...
        all(metrics.PASS_ABS_MAX_DB <= PASS_LIMIT_DB) && ...
        all(metrics.STOP_ATTN_DB >= STOP_LIMIT_DB); %#ok<SAGROW>
    store(weight_index).coeff_int = coeff_int; %#ok<SAGROW>
    store(weight_index).h_stage3 = h_stage3; %#ok<SAGROW>
    store(weight_index).h4 = h4; %#ok<SAGROW>
    store(weight_index).h8 = h8; %#ok<SAGROW>
    store(weight_index).h128 = h128; %#ok<SAGROW>
end

candidate_table = struct2table(row);
candidate_table.ORIGINAL_INDEX = (1:height(candidate_table)).';
candidate_table = sortrows(candidate_table, ...
    {'PASS', 'COEFF_W', 'WORST_STOP_ATTN_DB', ...
     'WORST_PASS_ABS_DB'}, ...
    {'descend', 'ascend', 'descend', 'ascend'});
passing = candidate_table(candidate_table.PASS, :);
if isempty(passing)
    error('No canonical dual-halfband candidate meets official limits.');
end
selected_row = passing(1, :);
selected_index = selected_row.ORIGINAL_INDEX;

selected.row = selected_row;
selected.h_stage1 = base.h_stage1;
selected.stage1_coeff_int = base.coeff_int;
selected.h_stage2 = base.h_stage2;
selected.h_stage3 = store(selected_index).h_stage3;
selected.stage3_coeff_int = store(selected_index).coeff_int;
selected.h_hb4 = h_hb;
selected.h_hb5 = h_hb;
selected.h_cic4 = h_cic4;
selected.h4 = store(selected_index).h4;
selected.h8 = store(selected_index).h8;
selected.h128 = store(selected_index).h128;
selected.metric_table = evaluate_six( ...
    selected.h4, selected.h8, selected.h128, FS_LIST, ...
    F_PASS_LOW, F_PASS_HIGH, NFFT_FINAL);
selected.overall_pass = ...
    all(selected.metric_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB) && ...
    all(selected.metric_table.STOP_ATTN_DB >= STOP_LIMIT_DB) && ...
    all(selected.metric_table.SYMMETRY_ERROR < 1e-12);

save(fullfile(result_dir, ...
    'route2_canonical_tail_selected.mat'), 'selected');
writetable(candidate_table, fullfile(result_dir, ...
    'route2_canonical_tail_candidates.csv'));
writetable(selected.metric_table, fullfile(result_dir, ...
    'route2_canonical_tail_metrics.csv'));

disp(selected.row);
disp(selected.metric_table);
fprintf('Stage3 Q14 coefficients:');
fprintf(' %d', selected.stage3_coeff_int);
fprintf('\nRoute 2 canonical-tail decision: %s\n', ...
    string_pass_fail(selected.overall_pass));


function table_out = evaluate_six(h4, h8, h128, fs_list, ...
        pass_low, pass_high, nfft)
    node_name = strings(0, 1);
    fs_in_hz = [];
    pass_abs_max_db = [];
    ripple_pp_db = [];
    stop_attn_db = [];
    symmetry_error = [];
    pass = [];
    for fs_in = fs_list
        node_ir = {h4 h8 h128};
        factors = [4 8 128];
        for node_index = 1:3
            metric = analyze_node(node_ir{node_index}, ...
                factors(node_index)*fs_in, fs_in, ...
                pass_low, pass_high, nfft);
            node_name(end+1, 1) = sprintf('%dx', ...
                factors(node_index)); %#ok<SAGROW>
            fs_in_hz(end+1, 1) = fs_in; %#ok<SAGROW>
            pass_abs_max_db(end+1, 1) = ...
                metric.pass_abs_max_db; %#ok<SAGROW>
            ripple_pp_db(end+1, 1) = metric.ripple_pp_db; %#ok<SAGROW>
            stop_attn_db(end+1, 1) = metric.stop_attn_db; %#ok<SAGROW>
            symmetry_error(end+1, 1) = metric.symmetry_error; %#ok<SAGROW>
            pass(end+1, 1) = metric.pass_abs_max_db <= 0.05 && ...
                metric.stop_attn_db >= 70 && ...
                metric.symmetry_error < 1e-12; %#ok<SAGROW>
        end
    end
    table_out = table(node_name, fs_in_hz, pass_abs_max_db, ...
        ripple_pp_db, stop_attn_db, symmetry_error, pass, ...
        'VariableNames', {'NODE', 'FS_IN_HZ', ...
        'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', 'STOP_ATTN_DB', ...
        'SYMMETRY_ERROR', 'PASS'});
end


function h = design_folded_stage3(tap_count, sample_rate, pass_edge, ...
        stop_edge, desired_fun, stop_weight)
    half_order = (tap_count-1)/2;
    distance = 1:half_order;
    pass_frequency = linspace(0, pass_edge, 1600).';
    stop_frequency = linspace(stop_edge, sample_rate/2, 1000).';
    pass_omega = 2*pi*pass_frequency/sample_rate;
    stop_omega = 2*pi*stop_frequency/sample_rate;
    pass_matrix = [ones(size(pass_omega)), ...
        2*cos(pass_omega*distance)];
    stop_matrix = [ones(size(stop_omega)), ...
        2*cos(stop_omega*distance)];
    dc_matrix = [1 2*ones(1, half_order)];
    dc_weight = 1e4;
    matrix = [pass_matrix; sqrt(stop_weight)*stop_matrix; ...
        dc_weight*dc_matrix];
    target = [desired_fun(pass_frequency); ...
        zeros(size(stop_frequency)); 2*dc_weight];
    ridge_scale = 1e-10;
    augmented_matrix = [matrix; ...
        sqrt(ridge_scale)*eye(half_order+1)];
    augmented_target = [target; zeros(half_order+1, 1)];
    column_scale = sqrt(sum(abs(augmented_matrix).^2, 1));
    column_scale(column_scale < eps) = 1;
    coefficient = (augmented_matrix./column_scale)\augmented_target;
    coefficient = coefficient./column_scale.';
    h = zeros(1, tap_count);
    center = half_order+1;
    h(center) = coefficient(1);
    for idx = 1:half_order
        h(center-idx) = coefficient(idx+1);
        h(center+idx) = coefficient(idx+1);
    end
    h = h*(2/sum(h));
end


function coeff_int = quantize_gain(h, frac_w, gain)
    scale = int64(2^frac_w);
    coeff_int = int64(round(h*double(scale)));
    center = (numel(coeff_int)+1)/2;
    coeff_int(center) = coeff_int(center)+ ...
        int64(gain)*scale-sum(coeff_int);
end


function width = required_signed_width(coeff_int)
    width = 2;
    while max(coeff_int) > int64(2^(width-1)-1) || ...
            min(coeff_int) < int64(-2^(width-1))
        width = width+1;
    end
end


function H = response_at_frequency(h, frequency, sample_rate)
    omega = 2*pi*frequency(:)/sample_rate;
    H = exp(-1j*omega*(0:numel(h)-1))*h(:);
end


function h_total = append_interp2_stage(h_previous, h_stage)
    h_total = append_interp_stage(h_previous, h_stage, 2);
end


function h_total = append_interp_stage(h_previous, h_stage, rate)
    h_up = zeros(1, rate*(numel(h_previous)-1)+1);
    h_up(1:rate:end) = h_previous;
    h_total = conv(h_up, h_stage);
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


function text = string_pass_fail(value)
    if value
        text = 'PASS';
    else
        text = 'FAIL';
    end
end
