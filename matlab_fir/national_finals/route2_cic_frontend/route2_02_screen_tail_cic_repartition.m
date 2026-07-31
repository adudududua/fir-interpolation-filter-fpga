clearvars;
clc;

% Route 2B screening:
%   2x FIR -> 2x FIR -> 2x FIR -> 2x sparse HB -> 2x sparse HB
%   -> CIC R=4, N=2
%
% This re-partitions the existing 16x tail.  One CIC integrator/DSP is
% removed and the freed DSP is reused by a time-shared sparse-halfband
% engine.  The script rechecks all six official node/rate combinations,
% because the earlier Phase-8 research only made a 44.1-kHz full-chain
% decision against a stricter private 72-dB threshold.

script_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(fileparts(script_dir));
source_path = fullfile(matlab_root, 'alt_all2x_v8', 'results', ...
    'phase8_cic2_stage1_redesign_selected.mat');
result_dir = fullfile(script_dir, 'results');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
if ~exist(source_path, 'file')
    error('Missing Phase-8 candidate: %s', source_path);
end

data = load(source_path, 'selected');
candidate = data.selected;

FS_LIST = [44100 48000];
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
PASS_LIMIT_DB = 0.05;
STOP_LIMIT_DB = 70;
NFFT = 2^20;

h4 = append_interp2_stage(candidate.h_stage1, candidate.h_stage2);
h8 = append_interp2_stage(h4, candidate.h_stage3);
h16 = append_interp2_stage(h8, candidate.h_hb4);
h32 = append_interp2_stage(h16, candidate.h_hb5);
h128 = append_interp_stage(h32, candidate.h_cic4, 4);

node_name = strings(0, 1);
fs_in_hz = [];
fs_out_hz = [];
pass_abs_max_db = [];
ripple_pp_db = [];
stop_attn_db = [];
symmetry_error = [];
group_delay_samples = [];
pass = [];
for fs_in = FS_LIST
    node_ir = {h4, h8, h128};
    node_factor = [4 8 128];
    for node_index = 1:numel(node_factor)
        metric = analyze_node(node_ir{node_index}, ...
            node_factor(node_index)*fs_in, fs_in, ...
            F_PASS_LOW, F_PASS_HIGH, NFFT);
        node_name(end+1, 1) = sprintf('%dx', ...
            node_factor(node_index)); %#ok<SAGROW>
        fs_in_hz(end+1, 1) = fs_in; %#ok<SAGROW>
        fs_out_hz(end+1, 1) = node_factor(node_index)*fs_in; %#ok<SAGROW>
        pass_abs_max_db(end+1, 1) = metric.pass_abs_max_db; %#ok<SAGROW>
        ripple_pp_db(end+1, 1) = metric.ripple_pp_db; %#ok<SAGROW>
        stop_attn_db(end+1, 1) = metric.stop_attn_db; %#ok<SAGROW>
        symmetry_error(end+1, 1) = metric.symmetry_error; %#ok<SAGROW>
        group_delay_samples(end+1, 1) = ...
            metric.group_delay_samples; %#ok<SAGROW>
        pass(end+1, 1) = metric.pass_abs_max_db <= PASS_LIMIT_DB && ...
            metric.stop_attn_db >= STOP_LIMIT_DB && ...
            metric.symmetry_error < 1e-12; %#ok<SAGROW>
    end
end

metric_table = table(node_name, fs_in_hz, fs_out_hz, ...
    pass_abs_max_db, ripple_pp_db, stop_attn_db, symmetry_error, ...
    group_delay_samples, pass, ...
    'VariableNames', {'NODE', 'FS_IN_HZ', 'FS_OUT_HZ', ...
    'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', 'STOP_ATTN_DB', ...
    'SYMMETRY_ERROR', 'GROUP_DELAY_SAMPLES', 'PASS'});

screen.source_path = source_path;
screen.h4 = h4;
screen.h8 = h8;
screen.h16 = h16;
screen.h32 = h32;
screen.h128 = h128;
screen.metric_table = metric_table;
screen.overall_pass = all(metric_table.PASS);
screen.stage1_taps = numel(candidate.h_stage1);
screen.stage2_taps = numel(candidate.h_stage2);
screen.stage3_taps = numel(candidate.h_stage3);
screen.hb4_taps = numel(candidate.h_hb4);
screen.hb5_taps = numel(candidate.h_hb5);
screen.cic_rate = 4;
screen.cic_order = 2;
screen.estimated_dsp = 6;
screen.stage1_mac_pairs = candidate.row.MAC_PAIR_COUNT;
screen.stage1_history = candidate.row.REAL_HISTORY_LEN;

save(fullfile(result_dir, ...
    'route2_tail_cic_repartition_screen.mat'), 'screen', 'candidate');
writetable(metric_table, fullfile(result_dir, ...
    'route2_tail_cic_repartition_metrics.csv'));
write_summary(fullfile(result_dir, ...
    'route2_tail_cic_repartition_summary.md'), screen, candidate, ...
    PASS_LIMIT_DB, STOP_LIMIT_DB);

disp(metric_table);
fprintf('Route 2B MATLAB screen: %s\n', ...
    string_pass_fail(screen.overall_pass));
fprintf('Summary: %s\n', fullfile(result_dir, ...
    'route2_tail_cic_repartition_summary.md'));


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
    metric.group_delay_samples = (numel(h)-1)/2;
end


function write_summary(filename, screen, candidate, ...
        pass_limit, stop_limit)
    fid = fopen(filename, 'w');
    if fid < 0; error('Cannot create %s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '# Route 2B tail-CIC repartition screen\n\n');
    fprintf(fid, '- Overall MATLAB decision: **%s**\n', ...
        string_pass_fail(screen.overall_pass));
    fprintf(fid, ['- Structure: FIR2 x3 -> sparse HB2 x2 -> ' ...
        'CIC4 N=2\n']);
    fprintf(fid, '- Estimated DSP: %d (1 + 1 + 1 + 3)\n', ...
        screen.estimated_dsp);
    fprintf(fid, ['- Taps: Stage1=%d, Stage2=%d, Stage3=%d, ' ...
        'HB4=%d, HB5=%d\n'], ...
        screen.stage1_taps, screen.stage2_taps, ...
        screen.stage3_taps, screen.hb4_taps, screen.hb5_taps);
    fprintf(fid, '- Stage1 MAC pairs/history: %d/%d\n', ...
        screen.stage1_mac_pairs, screen.stage1_history);
    fprintf(fid, '- CIC: R=%d, N=%d\n', ...
        screen.cic_rate, screen.cic_order);
    fprintf(fid, '- Limits: pass <= +/-%.3f dB, stop >= %.1f dB\n', ...
        pass_limit, stop_limit);
    fprintf(fid, '- Source decision under old private 72-dB gate: %s\n\n', ...
        candidate.decision);
    fprintf(fid, '| Fs in | Node | Pass abs/dB | Ripple p-p/dB | Stop/dB | Symmetry | Delay | Pass |\n');
    fprintf(fid, '|---:|:---:|---:|---:|---:|---:|---:|:---:|\n');
    for idx = 1:height(screen.metric_table)
        fprintf(fid, '| %.0f | %s | %.9f | %.9f | %.9f | %.3g | %.1f | %d |\n', ...
            screen.metric_table.FS_IN_HZ(idx), ...
            screen.metric_table.NODE(idx), ...
            screen.metric_table.PASS_ABS_MAX_DB(idx), ...
            screen.metric_table.RIPPLE_PP_DB(idx), ...
            screen.metric_table.STOP_ATTN_DB(idx), ...
            screen.metric_table.SYMMETRY_ERROR(idx), ...
            screen.metric_table.GROUP_DELAY_SAMPLES(idx), ...
            screen.metric_table.PASS(idx));
    end
end


function text = string_pass_fail(value)
    if value
        text = 'PASS';
    else
        text = 'FAIL';
    end
end
