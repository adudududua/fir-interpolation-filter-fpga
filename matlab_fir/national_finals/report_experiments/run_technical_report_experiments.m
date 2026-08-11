% Technical-report supplementary experiments for the board-verified
% 218-LUT, Stage1/2/3=24/20/20 release.
%
% This runner covers the software-executable part of E0-E4:
%   E0 environment/provenance manifest
%   E1 floating arithmetic vs bit-true model, plus stable RTL-vector gate
%   E2 six-mode magnitude/phase/group-delay analysis
%   E3 six-mode coherent-tone spectra and image rejection
%   E4 archived architecture/word-length Pareto tables and figures
%
% It intentionally does not turn vectorless power, a single timing run, or
% missing laboratory measurements into SAIF/Fmax/board-audio claims.

clearvars;
close all;
clc;

script_path = mfilename('fullpath');
script_dir = fileparts(script_path);
nf_dir = fileparts(script_dir);
matlab_root = fileparts(nf_dir);
repo_root = fileparts(matlab_root);
bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
vector_dir = fullfile(nf_dir, 'vectors', 'release_218_smoke');
experiment_dir = fullfile(script_dir, 'technical_report_218');
raw_dir = fullfile(experiment_dir, 'raw');
processed_dir = fullfile(experiment_dir, 'processed');
figure_dir = fullfile(experiment_dir, 'figures');
log_dir = fullfile(experiment_dir, 'logs');
report_asset_dir = fullfile(repo_root, 'submit', 'finally', 'reports', ...
    'test_report_assets');

dirs = {experiment_dir, raw_dir, processed_dir, figure_dir, log_dir, ...
    report_asset_dir};
for index = 1:numel(dirs)
    if ~exist(dirs{index}, 'dir'); mkdir(dirs{index}); end
end

addpath(nf_dir);
addpath(bittrue_dir);
addpath(fullfile(nf_dir, 'wordlength_experiments'));

diary_path = fullfile(log_dir, 'matlab_execution.txt');
if exist(diary_path, 'file'); delete(diary_path); end
diary(diary_path);
cleanup_diary = onCleanup(@() diary('off')); %#ok<NASGU>

cfg = nf_release_218_config();
assert(strcmp(cfg.release_status, 'board-verified'));
assert(strcmp(cfg.config_id, 'NF-P3-STAGE123-24-20-20-CANDIDATE-R1'));
fprintf('CONFIG_ID=%s\n', cfg.config_id);
fprintf('EXPERIMENT_DIR=%s\n', experiment_dir);

%% E0: environment and provenance
[git_status, git_head] = system(sprintf('git -C "%s" rev-parse HEAD', repo_root));
if git_status ~= 0; git_head = 'unavailable'; end
[branch_status, git_branch] = system(sprintf( ...
    'git -C "%s" branch --show-current', repo_root));
if branch_status ~= 0; git_branch = 'unavailable'; end
git_head = strtrim(git_head);
git_branch = strtrim(git_branch);

env_key = { ...
    'experiment_id'; 'execution_date'; 'config_id'; 'release_status'; ...
    'board_verification_date'; 'git_head'; 'git_branch'; 'matlab'; ...
    'vivado'; 'part'; 'top'; 'input_bits'; 'stage_word_length'; ...
    'input_sample_rates_hz'; 'output_factors'; 'passband_hz'; ...
    'passband_limit_db'; 'stopband_min_db'; 'frequency_nfft'; ...
    'spectrum_nfft'; 'spectrum_window'; 'power_evidence'; ...
    'board_audio_evidence'};
env_value = { ...
    'technical_report_218_20260811'; datestr(now, 31); cfg.config_id; ...
    cfg.release_status; cfg.board_verification_date; git_head; git_branch; ...
    version; cfg.vivado; cfg.part; cfg.top; '24 signed'; '24/20/20'; ...
    '44100,48000'; '4,8,128'; '10,20000'; ...
    num2str(cfg.passband_limit_db, '%.6g'); ...
    num2str(cfg.stopband_attenuation_min_db, '%.6g'); ...
    num2str(2^20); num2str(2^18); 'coherent rectangular'; ...
    'vectorless Medium-confidence archive only; no SAIF claim'; ...
    'user-confirmed functional board pass only; no instrument data'};
environment_table = table(env_key, env_value, ...
    'VariableNames', {'KEY', 'VALUE'});
writetable(environment_table, fullfile(processed_dir, ...
    'e0_environment_manifest.csv'));

critical_rel = { ...
    'matlab_fir/national_finals/nf_release_218_config.m'; ...
    ['matlab_fir/national_finals/wordlength_experiments/' ...
     'nf_p3_build_bittrue_case_24_20_20.m']; ...
    ['matlab_fir/national_finals/vectors/release_218_smoke/' ...
     'p3_rtl_vector_manifest.csv']; ...
    ['XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/' ...
     '20260811_231722/release_config.txt']; ...
    ['XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/' ...
     '20260811_231722/board_routed_2025_2.dcp']; ...
    ['XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/' ...
     '20260811_231722/board_demo_competition_dac8_top_2025_2.bit']};
critical_sha256 = cell(size(critical_rel));
critical_bytes = zeros(size(critical_rel));
for index = 1:numel(critical_rel)
    filename = fullfile(repo_root, strrep(critical_rel{index}, '/', filesep));
    assert(exist(filename, 'file') == 2, 'Missing E0 input: %s', filename);
    critical_sha256{index} = sha256_file(filename);
    info = dir(filename);
    critical_bytes(index) = info.bytes;
end
hash_table = table(critical_rel, critical_bytes, critical_sha256, ...
    'VariableNames', {'RELATIVE_PATH', 'BYTES', 'SHA256'});
writetable(hash_table, fullfile(processed_dir, 'e0_sha256_manifest.csv'));

%% E1a: stable RTL-vector contract against the current bit-true model
rtl_rows = struct([]);
rtl_row_index = 0;
stable_cases = {'impulse', 'random_seed01'};
node_names = {'4x', '8x', '128x'};
node_factors = [4 8 128];
for case_index = 1:numel(stable_cases)
    case_name = stable_cases{case_index};
    x = read_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_input_24bit.mem']), 24);
    model = nf_p3_build_bittrue_case_24_20_20(x);
    model_nodes = {model.y4_24, model.y8_24, model.y128_24};
    for node_index = 1:3
        rtl_golden = read_signed_hex_mem(fullfile(vector_dir, sprintf( ...
            '%s_y%d_golden_24bit.mem', case_name, ...
            node_factors(node_index))), 24);
        actual = int64(model_nodes{node_index}(:));
        expected = int64(rtl_golden(:));
        assert(numel(actual) == numel(expected), ...
            'Stable vector length mismatch: %s %s', case_name, ...
            node_names{node_index});
        delta = actual-expected;
        rtl_row_index = rtl_row_index+1;
        rtl_rows(rtl_row_index).CASE_NAME = case_name; %#ok<SAGROW>
        rtl_rows(rtl_row_index).NODE = node_names{node_index};
        rtl_rows(rtl_row_index).SAMPLE_COUNT = numel(delta);
        rtl_rows(rtl_row_index).MISMATCH_COUNT = nnz(delta);
        rtl_rows(rtl_row_index).MAX_ERROR_LSB = max(abs(double(delta)));
        rtl_rows(rtl_row_index).PASS = nnz(delta) == 0;
    end
end
rtl_table = struct2table(rtl_rows);
writetable(rtl_table, fullfile(processed_dir, ...
    'e1_fixed_rtl_vector_metrics.csv'));
assert(all(rtl_table.PASS), 'Stable fixed/RTL vector contract failed.');

%% E1b: floating arithmetic versus the current bit-true data path
case_list = build_e1_cases();
e1_rows = struct([]);
e1_row_index = 0;
for case_index = 1:numel(case_list)
    case_item = case_list(case_index);
    fprintf('E1 %02d/%02d: %s\n', case_index, numel(case_list), ...
        case_item.name);
    fixed_result = nf_p3_build_bittrue_case_24_20_20(case_item.x);
    float_result = build_float_case(case_item.x, cfg);
    fixed_nodes = {fixed_result.y4_24, fixed_result.y8_24, ...
        fixed_result.y128_24};
    float_nodes = {float_result.y4_24, float_result.y8_24, ...
        float_result.y128_24};
    acc_overflow = count_acc_overflow(fixed_result.stat);
    whole_run_saturation = count_saturation(fixed_result.stat);
    for node_index = 1:3
        test = double(fixed_nodes{node_index}(:));
        reference = double(float_nodes{node_index}(:));
        assert(numel(test) == numel(reference), ...
            'Float/fixed length mismatch: %s %s.', case_item.name, ...
            node_names{node_index});
        if case_item.analysis_input_count > 0
            first_sample = (case_item.analysis_input_start-1)* ...
                node_factors(node_index)+1;
            last_sample = first_sample+case_item.analysis_input_count* ...
                node_factors(node_index)-1;
            assert(last_sample <= numel(test));
            test = test(first_sample:last_sample);
            reference = reference(first_sample:last_sample);
        end
        error_lsb = test-reference;
        error_rms = sqrt(mean(error_lsb.^2));
        signal_rms = sqrt(mean(reference.^2));
        if error_rms == 0
            sqnr_db = inf;
        elseif signal_rms == 0
            sqnr_db = -inf;
        else
            sqnr_db = 20*log10(signal_rms/error_rms);
        end
        e1_row_index = e1_row_index+1;
        e1_rows(e1_row_index).CASE_NAME = case_item.name; %#ok<SAGROW>
        e1_rows(e1_row_index).FS_IN_HZ = case_item.fs_in;
        e1_rows(e1_row_index).NODE = node_names{node_index};
        e1_rows(e1_row_index).OUTPUT_FACTOR = node_factors(node_index);
        e1_rows(e1_row_index).SAMPLE_COUNT = numel(test);
        e1_rows(e1_row_index).MAX_ERROR_LSB = max(abs(error_lsb));
        e1_rows(e1_row_index).RMS_ERROR_LSB = error_rms;
        e1_rows(e1_row_index).SQNR_DB = sqnr_db;
        e1_rows(e1_row_index).DC_ERROR_LSB = mean(error_lsb);
        e1_rows(e1_row_index).ACC_OVERFLOW_COUNT = acc_overflow;
        e1_rows(e1_row_index).WHOLE_RUN_SATURATION_COUNT = ...
            whole_run_saturation;
        e1_rows(e1_row_index).ANALYZED_OUTPUT_RAIL_COUNT = ...
            count_output_rails(test);
        e1_rows(e1_row_index).EXPECTED_BOUNDARY_CASE = ...
            case_item.expected_boundary_case;
    end
end
e1_table = struct2table(e1_rows);
writetable(e1_table, fullfile(processed_dir, ...
    'e1_float_fixed_case_metrics.csv'));

fig = figure('Visible', 'off', 'Color', 'w', ...
    'Position', [100 100 1700 850]);
hold on;
markers = {'o-', 's-', '^-'};
for node_index = 1:3
    selector = strcmp(e1_table.NODE, node_names{node_index});
    values = e1_table.SQNR_DB(selector);
    finite_values = values(isfinite(values));
    ceiling_value = 180;
    if ~isempty(finite_values); ceiling_value = max(180, max(finite_values)+10); end
    values(isinf(values) & values > 0) = ceiling_value;
    plot(find(selector, 1)-find(selector, 1)+(1:nnz(selector)), values, ...
        markers{node_index}, 'LineWidth', 1.4, 'MarkerSize', 5);
end
grid on;
xlabel('E1 directed/random case index');
ylabel('SQNR versus floating arithmetic (dB)');
title('E1: 24/20/20 arithmetic quantization error');
legend(node_names, 'Location', 'best');
ylim([-10 200]);
save_report_figure(fig, figure_dir, report_asset_dir, ...
    'e1_float_fixed_sqnr.png');
close(fig);

%% E2: six-mode frequency, phase and group-delay evidence
impulse_input = read_signed_hex_mem(fullfile(vector_dir, ...
    'impulse_input_24bit.mem'), 24);
impulse_amplitude = double(impulse_input(1));
impulse_nodes = cell(1, 3);
for node_index = 1:3
    impulse_nodes{node_index} = double(read_signed_hex_mem(fullfile( ...
        vector_dir, sprintf('impulse_y%d_golden_24bit.mem', ...
        node_factors(node_index))), 24)).';
end

e2_rows = struct([]);
e2_row_index = 0;
e2_plot = cell(2, 3);
nfft_e2 = 2^20;
fs_list = [44100 48000];
for fs_index = 1:2
    for node_index = 1:3
        fs_in = fs_list(fs_index);
        factor = node_factors(node_index);
        fs_out = factor*fs_in;
        [metric, plot_data] = analyze_impulse_response( ...
            impulse_nodes{node_index}, fs_out, fs_in, ...
            cfg.passband_hz, nfft_e2, impulse_amplitude*factor);
        e2_plot{fs_index, node_index} = plot_data;
        e2_row_index = e2_row_index+1;
        e2_rows(e2_row_index).MODE_ID = sprintf('F%d_M%d', ...
            round(fs_in/100), factor); %#ok<SAGROW>
        e2_rows(e2_row_index).FS_IN_HZ = fs_in;
        e2_rows(e2_row_index).OUTPUT_FACTOR = factor;
        e2_rows(e2_row_index).FS_OUT_HZ = fs_out;
        fields = fieldnames(metric);
        for field_index = 1:numel(fields)
            e2_rows(e2_row_index).(fields{field_index}) = ...
                metric.(fields{field_index});
        end
        e2_rows(e2_row_index).PASS = ...
            metric.PASSBAND_MAX_ABS_DB <= cfg.passband_limit_db && ...
            metric.STOPBAND_ATTENUATION_DB >= ...
                cfg.stopband_attenuation_min_db && ...
            metric.SYMMETRY_MAX_ERROR_LSB == 0 && ...
            metric.PHASE_RESIDUAL_MAX_RAD < 1e-9;
    end
end
e2_table = struct2table(e2_rows);
writetable(e2_table, fullfile(processed_dir, 'e2_mode_metrics.csv'));
assert(all(e2_table.PASS), 'E2 six-mode acceptance failed.');

fig = figure('Visible', 'off', 'Color', 'w', ...
    'Position', [100 100 1700 1050]);
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
for fs_index = 1:2
    for node_index = 1:3
        nexttile;
        d = e2_plot{fs_index, node_index};
        plot(d.frequency_hz/1e6, d.absolute_db, 'LineWidth', 1.0);
        hold on;
        yline(-70, '--r', '70 dB gate');
        xline((fs_list(fs_index)-cfg.passband_hz(2))/1e6, ':k', ...
            'stop start');
        grid on;
        ylim([-130 1]);
        xlim([0 node_factors(node_index)*fs_list(fs_index)/2/1e6]);
        title(sprintf('%.1f kHz, %dx', fs_list(fs_index)/1000, ...
            node_factors(node_index)));
        xlabel('Frequency (MHz)');
        ylabel('Amplitude (dBFS gain)');
    end
end
sgtitle('E2: six-mode full-band response, NFFT=2^{20}');
save_report_figure(fig, figure_dir, report_asset_dir, ...
    'e2_six_mode_fullband_response.png');
close(fig);

fig = figure('Visible', 'off', 'Color', 'w', ...
    'Position', [100 100 1700 1050]);
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
for fs_index = 1:2
    for node_index = 1:3
        nexttile;
        d = e2_plot{fs_index, node_index};
        plot(d.pass_frequency_hz/1000, d.phase_residual_rad*1e12, ...
            'LineWidth', 1.0);
        grid on;
        xlim([0 20]);
        title(sprintf('%.1f kHz, %dx', fs_list(fs_index)/1000, ...
            node_factors(node_index)));
        xlabel('Frequency (kHz)');
        ylabel('Phase residual (prad)');
    end
end
sgtitle('E2: passband phase residual after best-fit linear phase');
save_report_figure(fig, figure_dir, report_asset_dir, ...
    'e2_six_mode_phase_residual.png');
close(fig);

%% E3: coherent fixed-point spectra and image rejection
target_tones_hz = [997 10000 19000];
nfft_e3 = 2^18;
pre_input_count = 512;
e3_rows = struct([]);
e3_row_index = 0;
e3_plot_997 = cell(2, 3);
e3_plot_19k = cell(2, 3);
for fs_index = 1:2
    fs_in = fs_list(fs_index);
    for node_index = 1:3
        factor = node_factors(node_index);
        samples_per_period = nfft_e3/factor;
        assert(mod(samples_per_period, 1) == 0);
        for tone_index = 1:numel(target_tones_hz)
            target_hz = target_tones_hz(tone_index);
            tone_bin = round(target_hz*samples_per_period/fs_in);
            actual_hz = tone_bin*fs_in/samples_per_period;
            total_input_count = pre_input_count+samples_per_period;
            n = 0:total_input_count-1;
            amplitude = (2^23-1)*10^(-1/20);
            x = int64(round(amplitude*sin(2*pi*actual_hz*n/fs_in)));
            [fixed_output, saturation] = simulate_fixed_to_node(x, ...
                factor, cfg);
            first_output = pre_input_count*factor+1;
            last_output = first_output+nfft_e3-1;
            assert(last_output <= numel(fixed_output), ...
                'E3 extraction exceeds output length.');
            steady_output = fixed_output(first_output:last_output);
            [metric, spectrum_plot] = analyze_coherent_spectrum( ...
                steady_output, fs_in*factor, fs_in, actual_hz, ...
                cfg.passband_hz(2));
            e3_row_index = e3_row_index+1;
            e3_rows(e3_row_index).MODE_ID = sprintf('F%d_M%d', ...
                round(fs_in/100), factor); %#ok<SAGROW>
            e3_rows(e3_row_index).FS_IN_HZ = fs_in;
            e3_rows(e3_row_index).OUTPUT_FACTOR = factor;
            e3_rows(e3_row_index).FS_OUT_HZ = fs_in*factor;
            e3_rows(e3_row_index).TARGET_TONE_HZ = target_hz;
            e3_rows(e3_row_index).ACTUAL_COHERENT_TONE_HZ = actual_hz;
            e3_rows(e3_row_index).FFT_LENGTH = nfft_e3;
            fields = fieldnames(metric);
            for field_index = 1:numel(fields)
                e3_rows(e3_row_index).(fields{field_index}) = ...
                    metric.(fields{field_index});
            end
            e3_rows(e3_row_index).STARTUP_TRANSIENT_SATURATION_COUNT = ...
                saturation;
            e3_rows(e3_row_index).STEADY_OUTPUT_RAIL_COUNT = ...
                count_output_rails(double(steady_output));
            e3_rows(e3_row_index).PASS = ...
                metric.WORST_IMAGE_REJECTION_DBC >= ...
                    cfg.stopband_attenuation_min_db && ...
                e3_rows(e3_row_index).STEADY_OUTPUT_RAIL_COUNT == 0;
            if target_hz == 997
                e3_plot_997{fs_index, node_index} = spectrum_plot;
            elseif target_hz == 19000
                e3_plot_19k{fs_index, node_index} = spectrum_plot;
            end
            fprintf(['E3 %.1f kHz %dx target=%g actual=%.6f Hz ' ...
                'image=%.3f dBc\n'], fs_in/1000, factor, target_hz, ...
                actual_hz, metric.WORST_IMAGE_REJECTION_DBC);
        end
    end
end
e3_table = struct2table(e3_rows);
writetable(e3_table, fullfile(processed_dir, ...
    'e3_spectrum_metrics.csv'));

plot_spectrum_grid(e3_plot_997, fs_list, node_factors, ...
    figure_dir, report_asset_dir, 'e3_997hz_six_mode_spectrum.png', ...
    'E3: coherent 997 Hz-class tone, six-mode digital spectrum');
plot_spectrum_grid(e3_plot_19k, fs_list, node_factors, ...
    figure_dir, report_asset_dir, 'e3_19khz_six_mode_spectrum.png', ...
    'E3: coherent 19 kHz-class tone, six-mode digital spectrum');

%% E4: archived same-tool architecture ablation and word-length Pareto
version_id = {'292'; '276'; '258'; '249'; '239'; '234'; '221'; '218'};
primary_change = { ...
    'Vivado 2025.2 migration baseline'; ...
    'DSP tap-valid gating'; ...
    'Stage1 sequential taps'; ...
    'CIC DSP role exchange'; ...
    'Stage1 center-delay CE'; ...
    'control-state merge'; ...
    'routed invariant reuse'; ...
    'Stage2 word length 22 to 20'};
lut = [292; 276; 258; 249; 239; 234; 221; 218];
ff = [376; 379; 376; 377; 377; 369; 367; 365];
dsp = repmat(4, 8, 1);
bram_tile = repmat(2, 8, 1);
wns_ns = [nan; nan; nan; nan; nan; nan; 44.556; 45.279];
relation = {'baseline'; 'equivalent'; 'equivalent'; 'equivalent'; ...
    'equivalent'; 'equivalent'; 'equivalent'; 'word-length Pareto'};
board_status = {'archive'; 'archive'; 'archive'; 'board-verified'; ...
    'board-verified'; 'board-verified'; 'board-verified'; ...
    'board-verified'};
e4_arch = table(version_id, primary_change, lut, ff, dsp, bram_tile, ...
    wns_ns, relation, board_status, 'VariableNames', ...
    {'VERSION_ID', 'PRIMARY_CHANGE', 'LUT', 'FF', 'DSP', 'BRAM_TILE', ...
     'WNS_NS', 'NUMERIC_RELATION', 'BOARD_STATUS'});
writetable(e4_arch, fullfile(processed_dir, ...
    'e4_architecture_ablation.csv'));

word_length = {'24/22/20'; '24/20/20'};
word_lut = [221; 218];
word_ff = [367; 365];
pass_abs_db = [0.007730; 0.007605];
stop_db = [72.371; 72.355];
rtl_relation = {'self-golden 0 LSB'; 'self-golden 0 LSB'};
word_board = {'board-verified'; 'board-verified'};
e4_word = table(word_length, word_lut, word_ff, pass_abs_db, stop_db, ...
    rtl_relation, word_board, 'VariableNames', ...
    {'WORD_LENGTH', 'LUT', 'FF', 'WORST_PASS_ABS_DB', ...
     'WORST_STOP_DB', 'RTL_RELATION', 'BOARD_STATUS'});
writetable(e4_word, fullfile(processed_dir, ...
    'e4_wordlength_pareto.csv'));

fig = figure('Visible', 'off', 'Color', 'w', ...
    'Position', [100 100 1600 760]);
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plot(1:numel(lut), lut, 'o-', 'LineWidth', 1.8, 'MarkerSize', 7);
grid on;
xticks(1:numel(lut));
xticklabels(version_id);
xlabel('Archived routed version (LUT label)');
ylabel('Post-route LUT');
title('Same-tool structural evolution');
for index = 1:numel(lut)
    text(index, lut(index)+2, sprintf('%d', lut(index)), ...
        'HorizontalAlignment', 'center');
end
nexttile;
scatter(word_lut, stop_db, 110, [0.10 0.45 0.85; 0.85 0.25 0.15], ...
    'filled');
grid on;
xlim([217.8 221.4]);
xlabel('Post-route LUT');
ylabel('Worst stopband attenuation (dB)');
title('Word-length quality/resource Pareto');
text(word_lut(1)-0.12, stop_db(1)+0.002, word_length{1}, ...
    'HorizontalAlignment', 'right');
text(word_lut(2)+0.15, stop_db(2)+0.002, word_length{2});
ylim([72.33 72.39]);
sgtitle('E4: architecture ablation and 221/218 word-length Pareto');
save_report_figure(fig, figure_dir, report_asset_dir, ...
    'e4_architecture_wordlength_pareto.png');
close(fig);

%% Compact machine-readable summary
summary_key = { ...
    'config_id'; 'rtl_vector_cases_passed'; 'rtl_vector_cases_total'; ...
    'rtl_max_error_lsb'; 'e1_max_acc_overflow'; ...
    'e1_normal_max_analyzed_output_rail_count'; ...
    'e1_boundary_max_whole_run_saturation'; ...
    'e2_modes_passed'; 'e2_modes_total'; ...
    'e2_worst_pass_abs_db'; 'e2_worst_stop_db'; ...
    'e2_worst_phase_residual_rad'; 'e2_worst_symmetry_lsb'; ...
    'e3_cases_passed'; 'e3_cases_total'; ...
    'e3_worst_image_rejection_dbc'; ...
    'e3_max_steady_output_rail_count'; ...
    'e3_max_startup_transient_saturation'; ...
    'implementation_lut'; 'implementation_ff'; 'implementation_dsp'; ...
    'implementation_bram_tile'; 'implementation_wns_ns'; ...
    'implementation_whs_ns'; 'overall_software_gate'};
normal_e1 = ~e1_table.EXPECTED_BOUNDARY_CASE;
overall_gate = all(rtl_table.PASS) && all(e2_table.PASS) && ...
    all(e3_table.PASS) && max(e1_table.ACC_OVERFLOW_COUNT) == 0 && ...
    max(e1_table.ANALYZED_OUTPUT_RAIL_COUNT(normal_e1)) == 0;
summary_value = { ...
    cfg.config_id; num2str(nnz(rtl_table.PASS)); num2str(height(rtl_table)); ...
    num2str(max(rtl_table.MAX_ERROR_LSB), '%.12g'); ...
    num2str(max(e1_table.ACC_OVERFLOW_COUNT)); ...
    num2str(max(e1_table.ANALYZED_OUTPUT_RAIL_COUNT(normal_e1))); ...
    num2str(max(e1_table.WHOLE_RUN_SATURATION_COUNT( ...
        e1_table.EXPECTED_BOUNDARY_CASE))); ...
    num2str(nnz(e2_table.PASS)); num2str(height(e2_table)); ...
    num2str(max(e2_table.PASSBAND_MAX_ABS_DB), '%.12g'); ...
    num2str(min(e2_table.STOPBAND_ATTENUATION_DB), '%.12g'); ...
    num2str(max(e2_table.PHASE_RESIDUAL_MAX_RAD), '%.12g'); ...
    num2str(max(e2_table.SYMMETRY_MAX_ERROR_LSB), '%.12g'); ...
    num2str(nnz(e3_table.PASS)); num2str(height(e3_table)); ...
    num2str(min(e3_table.WORST_IMAGE_REJECTION_DBC), '%.12g'); ...
    num2str(max(e3_table.STEADY_OUTPUT_RAIL_COUNT)); ...
    num2str(max(e3_table.STARTUP_TRANSIENT_SATURATION_COUNT)); ...
    num2str(cfg.implementation.lut); num2str(cfg.implementation.ff); ...
    num2str(cfg.implementation.dsp48e1); ...
    num2str(cfg.implementation.bram_tile); ...
    num2str(cfg.implementation.wns_ns, '%.6f'); ...
    num2str(cfg.implementation.whs_ns, '%.6f'); ...
    num2str(overall_gate)};
summary_table = table(summary_key, summary_value, ...
    'VariableNames', {'KEY', 'VALUE'});
writetable(summary_table, fullfile(processed_dir, ...
    'experiment_summary.csv'));

fprintf('E1_RTL_VECTOR_PASS=%d/%d max_error=%g LSB\n', ...
    nnz(rtl_table.PASS), height(rtl_table), max(rtl_table.MAX_ERROR_LSB));
fprintf('E2_PASS=%d/%d worst_pass=%.9f dB worst_stop=%.9f dB\n', ...
    nnz(e2_table.PASS), height(e2_table), ...
    max(e2_table.PASSBAND_MAX_ABS_DB), ...
    min(e2_table.STOPBAND_ATTENUATION_DB));
fprintf('E3_PASS=%d/%d worst_image=%.9f dBc\n', ...
    nnz(e3_table.PASS), height(e3_table), ...
    min(e3_table.WORST_IMAGE_REJECTION_DBC));
fprintf('TECHNICAL_REPORT_SOFTWARE_GATE=%d\n', overall_gate);


function cases = build_e1_cases()
    cases = struct('name', {}, 'fs_in', {}, 'x', {}, ...
        'analysis_input_start', {}, 'analysis_input_count', {}, ...
        'expected_boundary_case', {});
    index = 0;
    directed_values = [int64(2^23-1), int64(-2^23)];
    directed_names = {'impulse_positive_fullscale', ...
        'impulse_negative_fullscale'};
    for item = 1:2
        index = index+1;
        x = zeros(1, 256, 'int64');
        x(1) = directed_values(item);
        cases(index) = make_case(directed_names{item}, 0, x, ...
            1, 0, true); %#ok<AGROW>
    end
    fs_list = [44100 48000];
    tone_hz = [997 10000 19000];
    for fs_index = 1:numel(fs_list)
        for tone_index = 1:numel(tone_hz)
            index = index+1;
            name = sprintf('tone_%gHz_m1dBFS_Fs%d', ...
                tone_hz(tone_index), fs_list(fs_index));
            x = make_tone(tone_hz(tone_index), -1, 1536, ...
                fs_list(fs_index));
            cases(index) = make_case(name, fs_list(fs_index), x, ...
                513, 1024, false); %#ok<AGROW>
        end
        for level = [-60 -90]
            index = index+1;
            name = sprintf('tone_997Hz_m%ddBFS_Fs%d', -level, ...
                fs_list(fs_index));
            x = make_tone(997, level, 1536, fs_list(fs_index));
            cases(index) = make_case(name, fs_list(fs_index), x, ...
                513, 1024, false); %#ok<AGROW>
        end
    end
    seeds = [294753618 104729 130363 155921 181081 ...
        206369 231761 257053 282407 307817];
    for seed_index = 1:numel(seeds)
        rng(seeds(seed_index), 'twister');
        x = int64(randi([-2^20, 2^20-1], 1, 1024));
        index = index+1;
        cases(index) = make_case(sprintf('random_seed%02d', seed_index), ...
            0, x, 1, 0, false); %#ok<AGROW>
    end
    index = index+1;
    x = repmat(int64([2^23-1, -2^23]), 1, 128);
    cases(index) = make_case('alternating_fullscale', 0, x, ...
        1, 0, true);
end


function result = make_case(name, fs_in, x, analysis_input_start, ...
        analysis_input_count, expected_boundary_case)
    result.name = name;
    result.fs_in = fs_in;
    result.x = int64(x);
    result.analysis_input_start = analysis_input_start;
    result.analysis_input_count = analysis_input_count;
    result.expected_boundary_case = expected_boundary_case;
end


function x = make_tone(frequency_hz, level_dbfs, sample_count, fs_in)
    amplitude = (2^23-1)*10^(level_dbfs/20);
    n = 0:sample_count-1;
    x = int64(round(amplitude*sin(2*pi*frequency_hz*n/fs_in)));
end


function result = build_float_case(x, cfg)
    x = double(x(:).');
    stage1 = interp2_float(x, cfg.stage1.coeff_int, ...
        cfg.stage1.frac_w);
    bridge1 = stage1/(2^cfg.bridge1.shift_w);
    stage2 = interp2_float(bridge1, cfg.stage2.coeff_int, ...
        cfg.stage2.frac_w);
    bridge2 = stage2/(2^cfg.bridge2.shift_w);
    stage3_flat = interp2_float(bridge2, cfg.stage3.coeff_int, ...
        cfg.stage3.frac_w);
    stage3_comp = interp2_float(bridge2, cfg.stage3_comp.coeff_int, ...
        cfg.stage3_comp.frac_w);
    cic = cic_float([stage3_comp 0 0]);
    result.y4_24 = stage2*16;
    result.y8_24 = stage3_flat*16;
    result.y128_24 = cic*16;
end


function y = interp2_float(x, coeff_int, frac_w)
    coefficient = double(coeff_int(:).')/(2^frac_w);
    phase0 = coefficient(1:2:end);
    phase1 = coefficient(2:2:end);
    acc0 = conv(double(x), phase0);
    acc1 = conv(double(x), phase1);
    y = zeros(1, 2*numel(x)+numel(coefficient)-2);
    y(1:2:end) = acc0;
    y(2:2:end) = acc1;
end


function y = cic_float(x)
    low_data = [double(x(:).') zeros(1, 3)];
    for stage_index = 1:2
        low_data = low_data-[0 low_data(1:end-1)];
    end
    hold_data = repelem(low_data, 16);
    y = cumsum(cumsum(hold_data))/(2^8);
end


function count = count_acc_overflow(stat)
    count = stat.stage1.acc_overflow_count+ ...
        stat.stage2.acc_overflow_count+ ...
        stat.stage3_flat.acc_overflow_count+ ...
        stat.stage3_comp.acc_overflow_count;
end


function count = count_saturation(stat)
    count = stat.stage1.output_sat_count+ ...
        stat.bridge1.output_sat_count+ ...
        stat.stage2.output_sat_count+ ...
        stat.bridge2.output_sat_count+ ...
        stat.stage3_flat.output_sat_count+ ...
        stat.stage3_comp.output_sat_count+ ...
        stat.cic.output_sat_count;
end


function count = count_output_rails(y)
    positive_rail = 2^23-16;
    negative_rail = -2^23;
    count = nnz(double(y) >= positive_rail | double(y) <= negative_rail);
end


function [metric, plot_data] = analyze_impulse_response(y, fs_out, fs_in, ...
        passband_hz, nfft, expected_dc_sum)
    y = double(y(:).');
    spectrum = fft(y, nfft);
    spectrum = spectrum(1:nfft/2+1);
    frequency = (0:nfft/2)*(fs_out/nfft);
    absolute_db = 20*log10(abs(spectrum)/expected_dc_sum+1e-18);
    pass_index = frequency >= passband_hz(1) & ...
        frequency <= passband_hz(2);
    stop_start = fs_in-passband_hz(2);
    stop_index = frequency >= stop_start & frequency <= fs_out/2;
    pass_value = absolute_db(pass_index);
    [worst_stop_db, stop_local] = max(absolute_db(stop_index));
    stop_frequency = frequency(stop_index);
    worst_stop_frequency = stop_frequency(stop_local);

    phase_index = pass_index & abs(spectrum) > max(abs(spectrum))*1e-8;
    pass_frequency = frequency(phase_index);
    omega = 2*pi*pass_frequency/fs_out;
    phase_value = unwrap(angle(spectrum(phase_index)));
    phase_line = polyfit(omega, phase_value, 1);
    phase_residual = phase_value-polyval(phase_line, omega);
    group_delay = -phase_line(1);
    if numel(omega) > 20
        instantaneous_delay = -gradient(phase_value)./gradient(omega);
        instantaneous_delay = instantaneous_delay(11:end-10);
        group_delay_variation = max(abs(instantaneous_delay-group_delay));
    else
        group_delay_variation = nan;
    end

    nonzero_index = find(y ~= 0);
    support = y(nonzero_index(1):nonzero_index(end));
    symmetry_error = max(abs(support-fliplr(support)));

    metric.PASSBAND_MAX_POS_DB = max(pass_value);
    metric.PASSBAND_MAX_NEG_DB = min(pass_value);
    metric.PASSBAND_MAX_ABS_DB = max(abs(pass_value));
    metric.PASSBAND_PP_DB = max(pass_value)-min(pass_value);
    metric.STOPBAND_START_HZ = stop_start;
    metric.STOPBAND_ATTENUATION_DB = -worst_stop_db;
    metric.STOPBAND_PEAK_HZ = worst_stop_frequency;
    metric.DC_GAIN_DB = absolute_db(1);
    metric.GROUP_DELAY_OUTPUT_SAMPLES = group_delay;
    metric.GROUP_DELAY_VARIATION_SAMPLES = group_delay_variation;
    metric.GROUP_DELAY_US = group_delay/fs_out*1e6;
    metric.PHASE_RESIDUAL_MAX_RAD = max(abs(phase_residual));
    metric.SYMMETRY_MAX_ERROR_LSB = symmetry_error;
    metric.IMPULSE_SUPPORT_SAMPLES = numel(support);

    stride = max(1, floor(numel(frequency)/50000));
    plot_data.frequency_hz = frequency(1:stride:end);
    plot_data.absolute_db = absolute_db(1:stride:end);
    plot_data.pass_frequency_hz = pass_frequency;
    plot_data.phase_residual_rad = phase_residual;
end


function [y, saturation] = simulate_fixed_to_node(x, factor, cfg)
    [stage1, stat1] = interp2_polyphase_bittrue(int64(x), ...
        cfg.stage1.coeff_int, cfg.stage1.frac_w, ...
        cfg.stage1.input_w, cfg.stage1.acc_w);
    [stage1_q20, bridge1_stat] = round_shift_sat_signed( ...
        stage1, cfg.bridge1.shift_w, cfg.bridge1.output_w);
    [stage2, stat2] = interp2_polyphase_bittrue(stage1_q20, ...
        cfg.stage2.coeff_int, cfg.stage2.frac_w, ...
        cfg.stage2.input_w, cfg.stage2.acc_w);
    [stage2_q20, bridge2_stat] = round_shift_sat_signed( ...
        stage2, cfg.bridge2.shift_w, cfg.bridge2.output_w);
    saturation = stat1.output_sat_count+bridge1_stat.output_sat_count+ ...
        stat2.output_sat_count+bridge2_stat.output_sat_count;
    if factor == 4
        y = bitshift(stage2, 4);
        return;
    end
    if factor == 8
        [stage3, stat3] = interp2_polyphase_bittrue(stage2_q20, ...
            cfg.stage3.coeff_int, cfg.stage3.frac_w, ...
            cfg.stage3.output_w, cfg.stage3.acc_w);
        saturation = saturation+stat3.output_sat_count;
        y = bitshift(stage3, 4);
        return;
    end
    assert(factor == 128);
    [stage3_comp, stat3] = interp2_polyphase_bittrue(stage2_q20, ...
        cfg.stage3_comp.coeff_int, cfg.stage3_comp.frac_w, ...
        cfg.stage3_comp.output_w, cfg.stage3_comp.acc_w);
    [cic_output, cic_stat] = nf_cic_n3_hold2_bittrue( ...
        [stage3_comp int64([0 0])], cfg.cic.input_w, cfg.cic.output_w);
    saturation = saturation+stat3.output_sat_count+ ...
        cic_stat.output_sat_count;
    y = bitshift(cic_output, 4);
end


function [metric, plot_data] = analyze_coherent_spectrum(y, fs_out, ...
        fs_in, tone_hz, pass_high_hz)
    y = double(y(:).');
    nfft = numel(y);
    spectrum = fft(y);
    amplitude = 2*abs(spectrum(1:nfft/2+1))/nfft/(2^23-1);
    amplitude(1) = amplitude(1)/2;
    amplitude(end) = amplitude(end)/2;
    amplitude_dbfs = 20*log10(amplitude+1e-18);
    frequency = (0:nfft/2)*(fs_out/nfft);
    fundamental_bin = round(tone_hz/fs_out*nfft)+1;
    guard = max(1, round(3));
    local_range = max(2, fundamental_bin-guard): ...
        min(numel(amplitude), fundamental_bin+guard);
    [fundamental_dbfs, local_index] = max(amplitude_dbfs(local_range));
    fundamental_bin = local_range(local_index);

    first_image_index = frequency >= fs_in-pass_high_hz & ...
        frequency <= min(fs_in+pass_high_hz, fs_out/2);
    all_image_index = frequency >= fs_in-pass_high_hz;
    first_image_dbfs = max(amplitude_dbfs(first_image_index));
    worst_image_dbfs = max(amplitude_dbfs(all_image_index));

    spur_mask = true(size(amplitude_dbfs));
    spur_mask(1) = false;
    spur_mask(max(1, fundamental_bin-guard): ...
        min(numel(spur_mask), fundamental_bin+guard)) = false;
    worst_spur_dbfs = max(amplitude_dbfs(spur_mask));

    harmonic_power = 0;
    for harmonic = 2:5
        harmonic_frequency = mod(harmonic*tone_hz, fs_out);
        if harmonic_frequency > fs_out/2
            harmonic_frequency = fs_out-harmonic_frequency;
        end
        harmonic_bin = round(harmonic_frequency/fs_out*nfft)+1;
        harmonic_power = harmonic_power+amplitude(harmonic_bin)^2;
    end
    fundamental_amplitude = 10^(fundamental_dbfs/20);
    thd_db = 20*log10(sqrt(harmonic_power)/fundamental_amplitude+1e-18);

    metric.FUNDAMENTAL_DBFS = fundamental_dbfs;
    metric.FIRST_IMAGE_PEAK_DBFS = first_image_dbfs;
    metric.WORST_IMAGE_PEAK_DBFS = worst_image_dbfs;
    metric.FIRST_IMAGE_REJECTION_DBC = fundamental_dbfs-first_image_dbfs;
    metric.WORST_IMAGE_REJECTION_DBC = fundamental_dbfs-worst_image_dbfs;
    metric.SFDR_DB = fundamental_dbfs-worst_spur_dbfs;
    metric.THD_2_TO_5_DB = thd_db;
    metric.DC_DBFS = amplitude_dbfs(1);

    stride = max(1, floor(numel(frequency)/40000));
    plot_data.frequency_over_fsin = frequency(1:stride:end)/fs_in;
    plot_data.amplitude_dbfs = amplitude_dbfs(1:stride:end);
end


function plot_spectrum_grid(plot_data, fs_list, factors, figure_dir, ...
        asset_dir, filename, title_text)
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Position', [100 100 1700 1050]);
    tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for fs_index = 1:2
        for factor_index = 1:3
            nexttile;
            d = plot_data{fs_index, factor_index};
            plot(d.frequency_over_fsin, d.amplitude_dbfs, ...
                'LineWidth', 0.8);
            hold on;
            xline(1-20000/fs_list(fs_index), ':r', 'image search');
            grid on;
            ylim([-150 1]);
            xlim([0 factors(factor_index)/2]);
            title(sprintf('%.1f kHz, %dx', fs_list(fs_index)/1000, ...
                factors(factor_index)));
            xlabel('Frequency / F_{s,in}');
            ylabel('Digital output (dBFS)');
        end
    end
    sgtitle(title_text);
    save_report_figure(fig, figure_dir, asset_dir, filename);
    close(fig);
end


function save_report_figure(fig, figure_dir, asset_dir, filename)
    experiment_path = fullfile(figure_dir, filename);
    exportgraphics(fig, experiment_path, 'Resolution', 180);
    copyfile(experiment_path, fullfile(asset_dir, filename), 'f');
end


function data = read_signed_hex_mem(filename, data_w)
    text_value = strtrim(fileread(filename));
    tokens = regexp(text_value, '\r?\n|\s+', 'split');
    tokens = tokens(~cellfun('isempty', tokens));
    unsigned_value = hex2dec(tokens);
    negative = unsigned_value >= 2^(data_w-1);
    unsigned_value(negative) = unsigned_value(negative)-2^data_w;
    data = int64(unsigned_value(:).');
end


function hash_value = sha256_file(filename)
    digest = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(filename, 'rb');
    assert(fid >= 0, 'Unable to hash %s.', filename);
    cleanup_file = onCleanup(@() fclose(fid)); %#ok<NASGU>
    while true
        bytes = fread(fid, 1024*1024, '*uint8');
        if isempty(bytes); break; end
        digest.update(typecast(bytes, 'int8'));
    end
    digest_bytes = typecast(digest.digest(), 'uint8');
    hash_value = lower(reshape(dec2hex(digest_bytes, 2).', 1, []));
end
