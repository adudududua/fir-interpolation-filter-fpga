% Analyze the Phase-6 impulse vectors after the national-finals all-2x RTL
% has passed a zero-LSB XSim comparison against those vectors.

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
repo_dir = fileparts(fileparts(script_dir));
golden_dir = fullfile(repo_dir, 'matlab_fir', 'alt_all2x_v6', ...
    'mixed_width_golden');
result_dir = fullfile(script_dir, 'results');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end

FS_LIST = [44100 48000];
FACTOR_LIST = [4 8 128];
NODE_LIST = {'4x', '8x', '128x'};
FILES = {'phase6_stage2_impulse_golden_24bit.mem', ...
         'phase6_stage3_impulse_golden_24bit.mem', ...
         'phase6_full_impulse_golden_24bit.mem'};
EXPECTED_LENGTH = [1245 2499 40059];
PASS_LOW = 10;
PASS_HIGH = 20000;
PASS_LIMIT_DB = 0.05;
STOP_LIMIT_DB = 70;
NFFT = 2^19;

ir = cell(1, 3);
for idx = 1:3
    ir{idx} = read_signed_hex24(fullfile(golden_dir, FILES{idx}));
    if numel(ir{idx}) ~= EXPECTED_LENGTH(idx)
        error('All-2x %s impulse length is %d, expected %d.', ...
            NODE_LIST{idx}, numel(ir{idx}), EXPECTED_LENGTH(idx));
    end
end

node = {};
fs_in_hz = [];
fs_out_hz = [];
impulse_length = [];
pass_abs_max_db = [];
ripple_pp_db = [];
stop_attn_db = [];
symmetry_lsb = [];
group_delay_samples = [];
phase_fit_residual_rad = [];
pass = [];

for fs_idx = 1:numel(FS_LIST)
    fs_in = FS_LIST(fs_idx);
    for node_idx = 1:3
        metric = analyze_node(ir{node_idx}, ...
            FACTOR_LIST(node_idx)*fs_in, fs_in, ...
            PASS_LOW, PASS_HIGH, NFFT);
        node{end+1, 1} = NODE_LIST{node_idx}; %#ok<SAGROW>
        fs_in_hz(end+1, 1) = fs_in; %#ok<SAGROW>
        fs_out_hz(end+1, 1) = FACTOR_LIST(node_idx)*fs_in; %#ok<SAGROW>
        impulse_length(end+1, 1) = numel(ir{node_idx}); %#ok<SAGROW>
        pass_abs_max_db(end+1, 1) = metric.pass_abs_max_db; %#ok<SAGROW>
        ripple_pp_db(end+1, 1) = metric.ripple_pp_db; %#ok<SAGROW>
        stop_attn_db(end+1, 1) = metric.stop_attn_db; %#ok<SAGROW>
        symmetry_lsb(end+1, 1) = metric.symmetry_lsb; %#ok<SAGROW>
        group_delay_samples(end+1, 1) = metric.group_delay_samples; %#ok<SAGROW>
        phase_fit_residual_rad(end+1, 1) = ...
            metric.phase_fit_residual_rad; %#ok<SAGROW>
        pass(end+1, 1) = metric.pass_abs_max_db <= PASS_LIMIT_DB && ...
            metric.stop_attn_db >= STOP_LIMIT_DB && ...
            metric.symmetry_lsb == 0 && ...
            metric.phase_fit_residual_rad < 1e-9; %#ok<SAGROW>
    end
end

metric_table = table(node, fs_in_hz, fs_out_hz, impulse_length, ...
    pass_abs_max_db, ripple_pp_db, stop_attn_db, symmetry_lsb, ...
    group_delay_samples, phase_fit_residual_rad, pass, ...
    'VariableNames', {'NODE', 'FS_IN_HZ', 'FS_OUT_HZ', ...
    'IMPULSE_LENGTH', 'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', ...
    'STOP_ATTN_DB', 'SYMMETRY_LSB', 'GROUP_DELAY_SAMPLES', ...
    'PHASE_FIT_RESIDUAL_RAD', 'PASS'});

csv_path = fullfile(result_dir, 'all2x_rtl_impulse_metrics.csv');
txt_path = fullfile(result_dir, 'all2x_rtl_impulse_summary.txt');
writetable(metric_table, csv_path);

fid = fopen(txt_path, 'w');
if fid < 0; error('Cannot create %s.', txt_path); end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'National-finals all-2x RTL impulse acceptance\n');
fprintf(fid, '============================================\n');
fprintf(fid, ['Source: Phase-6 MATLAB golden, independently verified by ' ...
    'XSim at 0 LSB for impulse and random PCM.\n']);
fprintf(fid, 'Limits: pass <= +/-%.3f dB, stop >= %.1f dB\n\n', ...
    PASS_LIMIT_DB, STOP_LIMIT_DB);
for idx = 1:height(metric_table)
    fprintf(fid, ['Fs_in=%g node=%s Fs_out=%g len=%d ' ...
        'pass_abs=%.9f dB ripple=%.9f dB stop=%.9f dB ' ...
        'sym=%g LSB gd=%.6f phase_res=%.3g PASS=%d\n'], ...
        metric_table.FS_IN_HZ(idx), metric_table.NODE{idx}, ...
        metric_table.FS_OUT_HZ(idx), metric_table.IMPULSE_LENGTH(idx), ...
        metric_table.PASS_ABS_MAX_DB(idx), ...
        metric_table.RIPPLE_PP_DB(idx), ...
        metric_table.STOP_ATTN_DB(idx), ...
        metric_table.SYMMETRY_LSB(idx), ...
        metric_table.GROUP_DELAY_SAMPLES(idx), ...
        metric_table.PHASE_FIT_RESIDUAL_RAD(idx), ...
        metric_table.PASS(idx));
end
fprintf(fid, '\nOVERALL_PASS=%d\n', all(metric_table.PASS));

disp(metric_table);
if ~all(metric_table.PASS)
    error('National-finals all-2x impulse acceptance failed.');
end
fprintf('NATIONAL FINALS ALL2X MATLAB/RTL IMPULSE PASS\n');
fprintf('CSV: %s\nTXT: %s\n', csv_path, txt_path);


function y = read_signed_hex24(filename)
    lines = readlines(filename);
    % readlines() preserves the final empty record when a .mem file ends
    % with a newline.  It is not an RTL sample, so discard blank records.
    lines = lines(strlength(strtrim(lines)) > 0);
    u = uint32(hex2dec(lines));
    y = double(u);
    negative = u >= uint32(2^23);
    y(negative) = y(negative) - 2^24;
    y = y(:).';
end


function metric = analyze_node(y, fs_out, fs_in, ...
        pass_low, pass_high, nfft)
    y = double(y(:).');
    active_idx = find(y ~= 0);
    if isempty(active_idx)
        error('Impulse response contains no non-zero samples.');
    end
    active_y = y(active_idx(1):active_idx(end));
    [H, f] = freqz(y, 1, nfft, fs_out);
    H_db = 20*log10(abs(H/sum(y))+1e-15);
    pass_idx = f >= pass_low & f <= pass_high;
    stop_idx = f >= (fs_in-pass_high) & f <= fs_out/2;
    pass_db = H_db(pass_idx);

    phase_idx = pass_idx & abs(H) > max(abs(H))*1e-6;
    phase_value = unwrap(angle(H(phase_idx)));
    omega_value = 2*pi*f(phase_idx)/fs_out;
    phase_coeff = polyfit(omega_value, phase_value, 1);
    phase_fit = polyval(phase_coeff, omega_value);

    metric.pass_abs_max_db = max(abs(pass_db));
    metric.ripple_pp_db = max(pass_db)-min(pass_db);
    metric.stop_attn_db = -max(H_db(stop_idx));
    % The exported RTL vector deliberately includes pipeline lead-in and a
    % long post-response drain.  Linear-phase symmetry applies to the
    % non-zero impulse support, not to those unequal capture margins.
    metric.symmetry_lsb = max(abs(active_y-fliplr(active_y)));
    metric.group_delay_samples = -phase_coeff(1);
    metric.phase_fit_residual_rad = max(abs(phase_value-phase_fit));
end
