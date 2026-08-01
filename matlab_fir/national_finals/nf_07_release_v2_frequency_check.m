% Release-v2 frequency and provenance acceptance using MATLAB base FFT.

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(script_dir));
release_dir = fullfile(script_dir, 'release_v2');
vector_dir = fullfile(script_dir, '_work', 'release_vectors');
rtl_dir = fullfile(script_dir, 'rtl_outputs');
result_dir = fullfile(script_dir, 'results');
addpath(script_dir);

verify_sha256_manifest(fullfile(release_dir, 'SHA256SUMS'), repo_root);
config = jsondecode(fileread(fullfile(release_dir, ...
    'p4d_release_v2_config.json')));
q = jsondecode(fileread(fullfile(release_dir, ...
    'q_format_and_scaling.json')));
source_config = nf_release_v2_config();
assert(strcmp(config.config_id, source_config.config_id));
assert(strcmp(q.config_id, source_config.config_id));

coefficient_table = readtable(fullfile(release_dir, 'coefficients.csv'), ...
    'TextType', 'string');
expected_coefficient = [source_config.stage1.coeff_int(:); ...
    source_config.stage2.coeff_int(:); source_config.stage3.coeff_int(:)];
assert(isequal(int64(coefficient_table.COEFFICIENT_INTEGER), ...
    expected_coefficient), 'Coefficient CSV does not match source config.');

vector_manifest = readtable(fullfile(vector_dir, ...
    'release_vector_manifest.csv'), 'TextType', 'string');
assert(all(vector_manifest.CONFIG_ID == string(source_config.config_id)), ...
    'Vector manifest CONFIG_ID mismatch.');
assert(all(vector_manifest.EQUALIZER_SAT == 0), ...
    'Unexpected equalizer saturation in release vectors.');
assert(all(vector_manifest.CIC_SAT == 0), ...
    'Unexpected CIC output saturation in release vectors.');
directed_index = startsWith(vector_manifest.CASE_NAME, 'fullscale_');
assert(nnz(directed_index) == 2 && ...
    all(vector_manifest.EQUALIZER_EXCEEDS_SIGNED20(directed_index) > 0), ...
    'Directed release vectors did not prove signed-20/21 coverage.');

fs_list = source_config.input_sample_rates_hz;
factor_list = source_config.output_factors;
node_list = {'4x', '8x', '128x'};
expected_length = [225 459 7406];
nfft = 2^18;
impulse_amplitude = 2^22;
pass_low = source_config.passband_hz(1);
pass_high = source_config.passband_hz(2);

rtl_ir = cell(1, 3);
for node_index = 1:3
    rtl_path = fullfile(rtl_dir, sprintf('rtl_impulse_y%d.csv', ...
        factor_list(node_index)));
    rtl_ir{node_index} = int64(readmatrix(rtl_path).');
    assert(numel(rtl_ir{node_index}) == expected_length(node_index), ...
        'RTL %s impulse length mismatch.', node_list{node_index});
    golden_path = fullfile(vector_dir, sprintf( ...
        'impulse_y%d_golden_24bit.mem', factor_list(node_index)));
    golden = read_signed_hex_mem(golden_path, 24);
    assert(isequal(rtl_ir{node_index}(:), ...
        golden(1:expected_length(node_index))), ...
        'RTL %s impulse differs from the golden prefix.', ...
        node_list{node_index});
    assert(all(golden(expected_length(node_index)+1:end) == 0), ...
        'Golden %s tail is not zero.', node_list{node_index});
end

node = {};
fs_in_hz = [];
fs_out_hz = [];
shape_pass_abs_max_db = [];
shape_ripple_pp_db = [];
absolute_pass_abs_max_db = [];
absolute_stop_attenuation_db = [];
worst_stop_frequency_hz = [];
dc_gain_db = [];
symmetry_lsb = [];
group_delay_samples = [];
phase_fit_residual_rad = [];
pass = [];

for fs_index = 1:numel(fs_list)
    fs_in = fs_list(fs_index);
    for node_index = 1:3
        metric = analyze_node(double(rtl_ir{node_index}), ...
            factor_list(node_index)*fs_in, fs_in, pass_low, pass_high, ...
            nfft, impulse_amplitude*factor_list(node_index));
        node{end+1, 1} = node_list{node_index}; %#ok<SAGROW>
        fs_in_hz(end+1, 1) = fs_in; %#ok<SAGROW>
        fs_out_hz(end+1, 1) = factor_list(node_index)*fs_in; %#ok<SAGROW>
        shape_pass_abs_max_db(end+1, 1) = ...
            metric.shape_pass_abs_max_db; %#ok<SAGROW>
        shape_ripple_pp_db(end+1, 1) = metric.shape_ripple_pp_db; %#ok<SAGROW>
        absolute_pass_abs_max_db(end+1, 1) = ...
            metric.absolute_pass_abs_max_db; %#ok<SAGROW>
        absolute_stop_attenuation_db(end+1, 1) = ...
            metric.absolute_stop_attenuation_db; %#ok<SAGROW>
        worst_stop_frequency_hz(end+1, 1) = ...
            metric.worst_stop_frequency_hz; %#ok<SAGROW>
        dc_gain_db(end+1, 1) = metric.dc_gain_db; %#ok<SAGROW>
        symmetry_lsb(end+1, 1) = metric.symmetry_lsb; %#ok<SAGROW>
        group_delay_samples(end+1, 1) = ...
            metric.group_delay_samples; %#ok<SAGROW>
        phase_fit_residual_rad(end+1, 1) = ...
            metric.phase_fit_residual_rad; %#ok<SAGROW>
        pass(end+1, 1) = ...
            metric.absolute_pass_abs_max_db <= ...
                source_config.passband_limit_db && ...
            metric.absolute_stop_attenuation_db >= ...
                source_config.stopband_attenuation_min_db && ...
            metric.symmetry_lsb == 0 && ...
            metric.phase_fit_residual_rad < 1e-9; %#ok<SAGROW>
    end
end

mode_delta_from_4x_db = zeros(size(dc_gain_db));
for fs_index = 1:numel(fs_list)
    rows = (fs_index-1)*3+(1:3);
    mode_delta_from_4x_db(rows) = dc_gain_db(rows)-dc_gain_db(rows(1));
    pass(rows) = pass(rows) & abs(mode_delta_from_4x_db(rows)) <= 0.01;
end

metric_table = table(node, fs_in_hz, fs_out_hz, ...
    shape_pass_abs_max_db, shape_ripple_pp_db, ...
    absolute_pass_abs_max_db, absolute_stop_attenuation_db, ...
    worst_stop_frequency_hz, dc_gain_db, mode_delta_from_4x_db, ...
    symmetry_lsb, group_delay_samples, phase_fit_residual_rad, pass, ...
    'VariableNames', {'NODE', 'FS_IN_HZ', 'FS_OUT_HZ', ...
    'SHAPE_PASS_ABS_MAX_DB', 'SHAPE_RIPPLE_PP_DB', ...
    'ABSOLUTE_PASS_ABS_MAX_DB', 'ABSOLUTE_STOP_ATTENUATION_DB', ...
    'WORST_STOP_FREQUENCY_HZ', 'DC_GAIN_DB', ...
    'MODE_DELTA_FROM_4X_DB', 'SYMMETRY_LSB', ...
    'GROUP_DELAY_SAMPLES', 'PHASE_FIT_RESIDUAL_RAD', 'PASS'});
writetable(metric_table, fullfile(result_dir, ...
    'nf_release_v2_frequency_metrics.csv'));
write_summary(fullfile(result_dir, ...
    'nf_release_v2_frequency_summary.txt'), metric_table, ...
    source_config, vector_manifest);
disp(metric_table);
assert(all(metric_table.PASS), 'Release-v2 frequency acceptance failed.');
fprintf('NF_RELEASE_V2_FREQUENCY_PASS: config=%s, hashes and 6 modes PASS.\n', ...
    source_config.config_id);


function metric = analyze_node(y, fs_out, fs_in, pass_low, pass_high, ...
        nfft, expected_dc_sum)
    y = y(:).';
    spectrum = fft(y, nfft);
    spectrum = spectrum(1:nfft/2+1);
    frequency = (0:nfft/2)*(fs_out/nfft);
    shape_db = 20*log10(abs(spectrum)/abs(sum(y))+1e-15);
    absolute_db = 20*log10(abs(spectrum)/expected_dc_sum+1e-15);
    pass_index = frequency >= pass_low & frequency <= pass_high;
    stop_index = frequency >= (fs_in-pass_high) & ...
        frequency <= fs_out/2;
    [worst_stop_db, local_index] = max(absolute_db(stop_index));
    stop_frequency = frequency(stop_index);
    coarse_frequency = stop_frequency(local_index);
    bin_width = fs_out/nfft;
    refine_frequency = linspace(max(fs_in-pass_high, ...
        coarse_frequency-bin_width), min(fs_out/2, ...
        coarse_frequency+bin_width), 1001);
    sample_index = (0:numel(y)-1).';
    refine_response = y*exp(-1i*2*pi/fs_out* ...
        (sample_index*refine_frequency));
    refine_db = 20*log10(abs(refine_response)/expected_dc_sum+1e-15);
    [refined_worst_db, refined_index] = max(refine_db);
    if refined_worst_db > worst_stop_db
        worst_stop_db = refined_worst_db;
        coarse_frequency = refine_frequency(refined_index);
    end

    phase_index = pass_index & abs(spectrum) > max(abs(spectrum))*1e-6;
    phase_value = unwrap(angle(spectrum(phase_index)));
    omega = 2*pi*frequency(phase_index)/fs_out;
    coefficient = polyfit(omega, phase_value, 1);

    metric.shape_pass_abs_max_db = max(abs(shape_db(pass_index)));
    metric.shape_ripple_pp_db = max(shape_db(pass_index))- ...
        min(shape_db(pass_index));
    metric.absolute_pass_abs_max_db = max(abs(absolute_db(pass_index)));
    metric.absolute_stop_attenuation_db = -worst_stop_db;
    metric.worst_stop_frequency_hz = coarse_frequency;
    metric.dc_gain_db = 20*log10(abs(sum(y)/expected_dc_sum)+1e-15);
    metric.symmetry_lsb = max(abs(y-fliplr(y)));
    metric.group_delay_samples = -coefficient(1);
    metric.phase_fit_residual_rad = max(abs(phase_value- ...
        polyval(coefficient, omega)));
end


function write_summary(filename, data, config, vector_manifest)
    fid = fopen(filename, 'w');
    if fid < 0; error('Unable to create %s.', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'National finals P4-D release-v2 frequency acceptance\n');
    fprintf(fid, '====================================================\n');
    fprintf(fid, 'CONFIG_ID=%s\n', config.config_id);
    fprintf(fid, 'ENGINE=MATLAB base fft (no freqz/toolbox dependency)\n');
    fprintf(fid, 'SHA256_MANIFEST=PASS\n');
    fprintf(fid, 'RTL_GOLDEN_PREFIX=0_LSB; GOLDEN_TAIL=ALL_ZERO\n');
    fprintf(fid, 'VECTOR_CASES=%d; EQ_SAT=%d; CIC_SAT=%d; BOUNDARY_CROSSES=%d\n\n', ...
        height(vector_manifest), sum(vector_manifest.EQUALIZER_SAT), ...
        sum(vector_manifest.CIC_SAT), ...
        sum(vector_manifest.EQUALIZER_EXCEEDS_SIGNED20));
    for index = 1:height(data)
        fprintf(fid, ['Fs=%g node=%s shape_abs=%.9f dB ' ...
            'shape_pp=%.9f dB abs_pass=%.9f dB abs_stop=%.9f dB ' ...
            'worst_stop_hz=%.6f dc=%.9f dB mode_delta=%.9f dB ' ...
            'sym=%g LSB gd=%.6f phase_res=%.3g PASS=%d\n'], ...
            data.FS_IN_HZ(index), data.NODE{index}, ...
            data.SHAPE_PASS_ABS_MAX_DB(index), ...
            data.SHAPE_RIPPLE_PP_DB(index), ...
            data.ABSOLUTE_PASS_ABS_MAX_DB(index), ...
            data.ABSOLUTE_STOP_ATTENUATION_DB(index), ...
            data.WORST_STOP_FREQUENCY_HZ(index), data.DC_GAIN_DB(index), ...
            data.MODE_DELTA_FROM_4X_DB(index), data.SYMMETRY_LSB(index), ...
            data.GROUP_DELAY_SAMPLES(index), ...
            data.PHASE_FIT_RESIDUAL_RAD(index), data.PASS(index));
    end
    fprintf(fid, '\nOVERALL_PASS=%d\n', all(data.PASS));
end


function verify_sha256_manifest(manifest_path, repo_root)
    bytes = fileread(manifest_path);
    raw = fopen(manifest_path, 'rb');
    leading = fread(raw, 3, '*uint8').';
    fclose(raw);
    assert(~isequal(leading, uint8([239 187 191])), ...
        'SHA256SUMS contains a UTF-8 BOM.');
    lines = regexp(strtrim(bytes), '\r?\n', 'split');
    for index = 1:numel(lines)
        token = regexp(lines{index}, ...
            '^([0-9a-fA-F]{64})\s+\*?(.+)$', 'tokens', 'once');
        assert(~isempty(token), 'Malformed SHA256SUMS line %d.', index);
        filename = fullfile(repo_root, strrep(token{2}, '/', filesep));
        actual = sha256_file(filename);
        assert(strcmpi(token{1}, actual), ...
            'SHA-256 mismatch: %s.', token{2});
    end
end


function hash_value = sha256_file(filename)
    assert(exist(filename, 'file') == 2, 'Hashed file missing: %s.', filename);
    digest = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(filename, 'rb');
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    while true
        data = fread(fid, 1024*1024, '*uint8');
        if isempty(data); break; end
        digest.update(typecast(data, 'int8'));
    end
    digest_bytes = typecast(digest.digest(), 'uint8');
    hash_value = lower(reshape(dec2hex(digest_bytes, 2).', 1, []));
end


function data = read_signed_hex_mem(filename, data_w)
    text_value = strtrim(fileread(filename));
    tokens = regexp(text_value, '\s+', 'split');
    unsigned_value = hex2dec(tokens);
    signed_value = unsigned_value;
    negative = unsigned_value >= 2^(data_w-1);
    signed_value(negative) = signed_value(negative)-2^data_w;
    data = int64(signed_value(:));
end
