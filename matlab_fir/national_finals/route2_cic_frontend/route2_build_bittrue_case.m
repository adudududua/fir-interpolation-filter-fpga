function result = route2_build_bittrue_case(x)
% Integer bit-true model for Route 2B:
% FIR2 x3 -> sparse HB2 x2 -> CIC4/N2.

    script_dir = fileparts(mfilename('fullpath'));
    matlab_root = fileparts(fileparts(script_dir));
    bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
    v2_dir = fullfile(matlab_root, 'alt_all2x_v2');
    v7_dir = fullfile(matlab_root, 'alt_all2x_v7');
    candidate_path = fullfile(script_dir, 'results', ...
        'route2_canonical_tail_selected.mat');
    addpath(bittrue_dir);
    addpath(v7_dir);

    reference = load(fullfile(v2_dir, ...
        'stage1_strict_halfband_config.mat'), 'best_config');
    selected_data = load(candidate_path, 'selected');
    selected = selected_data.selected;

    stage1_coeff = int64(selected.stage1_coeff_int(:).');
    stage2_coeff = int64(reference.best_config(2).coeff_int(:).');
    stage3_coeff = int64(selected.stage3_coeff_int(:).');
    hb4_coeff = int64([-1 0 9 16 9 0 -1]);
    hb5_coeff = hb4_coeff;

    x = int64(x(:).');
    [stage1, stat1] = interp2_polyphase_bittrue( ...
        x, stage1_coeff, 16, 24, 42);
    [stage1_q22, bridge1_stat] = round_shift_sat_signed( ...
        stage1, 2, 22);
    [stage2, stat2] = interp2_polyphase_bittrue( ...
        stage1_q22, stage2_coeff, 15, 22, 38);
    [stage2_q20, bridge2_stat] = round_shift_sat_signed( ...
        stage2, 2, 20);
    [stage3, stat3] = interp2_polyphase_bittrue( ...
        stage2_q20, stage3_coeff, 14, 20, 38);
    [hb4, stat4] = interp2_polyphase_bittrue( ...
        stage3, hb4_coeff, 4, 20, 30);
    [hb5, stat5] = interp2_polyphase_bittrue( ...
        hb4, hb5_coeff, 4, 20, 30);

    [cic_output, cic_stat, cic_trace] = cic_interp16_bittrue( ...
        hb5, 4, 2, 1, 20, 20, zeros(1, 4));

    result.input = x;
    result.y4_internal = stage2;
    result.y8_internal = stage3;
    result.y16_internal = hb4;
    result.y32_internal = hb5;
    result.y128_internal = cic_output;
    result.y4_24 = bitshift(stage2, 2);
    result.y8_24 = bitshift(stage3, 4);
    result.y128_24 = bitshift(cic_output, 4);
    result.stat.stage1 = stat1;
    result.stat.bridge1 = bridge1_stat;
    result.stat.stage2 = stat2;
    result.stat.bridge2 = bridge2_stat;
    result.stat.stage3 = stat3;
    result.stat.hb4 = stat4;
    result.stat.hb5 = stat5;
    result.stat.cic = cic_stat;
    result.trace.cic = cic_trace;
end
