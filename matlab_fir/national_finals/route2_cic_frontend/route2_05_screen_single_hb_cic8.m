clearvars;
clc;

% Route 2C architecture screen:
% FIR2 x3 -> one canonical HB2 -> CIC8/N2.
% This removes one complete halfband stage versus Route 2B.  The screen is
% deliberately limited to the existing 11-tap Stage-3 schedule so a
% frequency-domain pass cannot hide an infeasible RTL MAC budget.

script_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(fileparts(script_dir));
source_path = fullfile(script_dir, 'results', ...
    'route2_canonical_tail_selected.mat');
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
STOP_WEIGHT_LIST = [1e-6 1e-5 1e-4 1e-3 1e-2 1e-1 1 10 100];
CIC_ORDER_LIST = [2 3];

hb_bank = { ...
    [-1 0 9 16 9 0 -1]/16, ...
    [20 0 -119 0 611 1024 611 0 -119 0 20]/1024, ...
    [29 0 -134 0 617 1024 617 0 -134 0 29]/1024};
hb_name = ["HB7_Q4", "HB11A_Q10", "HB11B_Q10"];
fs_stage3 = 8*FS_LIST(1);
fs_hb = 16*FS_LIST(1);
fs_out = 128*FS_LIST(1);

row = repmat(struct(), 0, 1);
store = repmat(struct(), 0, 1);
candidate_index = 0;
for cic_order = CIC_ORDER_LIST
    h_cic8 = cic_impulse(cic_order, 8);
    for hb_index = 1:numel(hb_bank)
        h_hb = hb_bank{hb_index};
        tail_frequency = linspace(0, F_PASS_HIGH, 2400).';
        tail_response = response_at_frequency( ...
            h_hb, tail_frequency, fs_hb).* ...
            response_at_frequency(h_cic8, tail_frequency, fs_out);
        tail_magnitude = abs(tail_response)/(sum(h_hb)*sum(h_cic8));
        desired_fun = @(frequency_hz) 2./max(interp1( ...
            tail_frequency, tail_magnitude, frequency_hz, ...
            'pchip', 'extrap'), 1e-12);

        for weight_index = 1:numel(STOP_WEIGHT_LIST)
            candidate_index = candidate_index+1;
            stop_weight = STOP_WEIGHT_LIST(weight_index);
            h_float = design_folded_stage3(11, fs_stage3, ...
                F_PASS_HIGH, 4*FS_LIST(1)-F_PASS_HIGH, ...
                desired_fun, stop_weight);
            coeff_int = quantize_gain(h_float, 14, 2);
            h_stage3 = double(coeff_int)/2^14;

            h4 = append_interp_stage(base.h_stage1, base.h_stage2, 2);
            h8 = append_interp_stage(h4, h_stage3, 2);
            h16 = append_interp_stage(h8, h_hb, 2);
            h128 = append_interp_stage(h16, h_cic8, 8);
            metrics = evaluate_six(h4, h8, h128, FS_LIST, ...
                F_PASS_LOW, F_PASS_HIGH, NFFT_SEARCH);

            row(candidate_index).CIC_ORDER = cic_order; %#ok<SAGROW>
            row(candidate_index).HB_NAME = hb_name(hb_index); %#ok<SAGROW>
            row(candidate_index).HB_TAPS = numel(h_hb); %#ok<SAGROW>
            row(candidate_index).STOP_WEIGHT = stop_weight; %#ok<SAGROW>
            row(candidate_index).COEFF_W = ...
                required_signed_width(coeff_int); %#ok<SAGROW>
            row(candidate_index).WORST_PASS_ABS_DB = ...
                max(metrics.PASS_ABS_MAX_DB); %#ok<SAGROW>
            row(candidate_index).WORST_STOP_ATTN_DB = ...
                min(metrics.STOP_ATTN_DB); %#ok<SAGROW>
            row(candidate_index).PASS = ...
                all(metrics.PASS_ABS_MAX_DB <= PASS_LIMIT_DB) && ...
                all(metrics.STOP_ATTN_DB >= STOP_LIMIT_DB); %#ok<SAGROW>
            store(candidate_index).coeff_int = coeff_int; %#ok<SAGROW>
            store(candidate_index).h_stage3 = h_stage3; %#ok<SAGROW>
            store(candidate_index).h_hb = h_hb; %#ok<SAGROW>
            store(candidate_index).h_cic8 = h_cic8; %#ok<SAGROW>
            store(candidate_index).h4 = h4; %#ok<SAGROW>
            store(candidate_index).h8 = h8; %#ok<SAGROW>
            store(candidate_index).h128 = h128; %#ok<SAGROW>
        end
    end
end

candidate_table = struct2table(row);
candidate_table.ORIGINAL_INDEX = (1:height(candidate_table)).';
candidate_table = sortrows(candidate_table, ...
    {'PASS', 'CIC_ORDER', 'HB_TAPS', 'COEFF_W', ...
     'WORST_STOP_ATTN_DB', 'WORST_PASS_ABS_DB'}, ...
    {'descend', 'ascend', 'ascend', 'ascend', 'descend', 'ascend'});
writetable(candidate_table, fullfile(result_dir, ...
    'route2_single_hb_cic8_candidates.csv'));

selected_row = candidate_table(1, :);
selected_index = selected_row.ORIGINAL_INDEX;
selected.row = selected_row;
selected.h_stage3 = store(selected_index).h_stage3;
selected.stage3_coeff_int = store(selected_index).coeff_int;
selected.h_hb = store(selected_index).h_hb;
selected.h_cic8 = store(selected_index).h_cic8;
selected.h4 = store(selected_index).h4;
selected.h8 = store(selected_index).h8;
selected.h128 = store(selected_index).h128;
selected.metric_table = evaluate_six( ...
    selected.h4, selected.h8, selected.h128, FS_LIST, ...
    F_PASS_LOW, F_PASS_HIGH, NFFT_FINAL);
selected.overall_pass = ...
    all(selected.metric_table.PASS_ABS_MAX_DB <= PASS_LIMIT_DB) && ...
    all(selected.metric_table.STOP_ATTN_DB >= STOP_LIMIT_DB);

save(fullfile(result_dir, ...
    'route2_single_hb_cic8_screen.mat'), 'selected');
writetable(selected.metric_table, fullfile(result_dir, ...
    'route2_single_hb_cic8_metrics.csv'));

disp(candidate_table);
disp(selected.metric_table);
fprintf('Best Stage3 Q14 coefficients:');
fprintf(' %d', selected.stage3_coeff_int);
fprintf('\nRoute 2 single-HB/CIC8 decision: %s\n', ...
    string_pass_fail(selected.overall_pass));


function h = cic_impulse(order, rate)
    h = 1;
    for idx = 1:order
        h = conv(h, ones(1, rate));
    end
    h = h*(rate/sum(h));
end


function table_out = evaluate_six(h4, h8, h128, fs_list, ...
        pass_low, pass_high, nfft)
    node_name = strings(0, 1);
    fs_in_hz = [];
    pass_abs_max_db = [];
    ripple_pp_db = [];
    stop_attn_db = [];
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
            pass(end+1, 1) = metric.pass_abs_max_db <= 0.05 && ...
                metric.stop_attn_db >= 70; %#ok<SAGROW>
        end
    end
    table_out = table(node_name, fs_in_hz, pass_abs_max_db, ...
        ripple_pp_db, stop_attn_db, pass, ...
        'VariableNames', {'NODE', 'FS_IN_HZ', ...
        'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', 'STOP_ATTN_DB', 'PASS'});
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
end


function text = string_pass_fail(value)
    if value
        text = 'PASS';
    else
        text = 'FAIL';
    end
end
