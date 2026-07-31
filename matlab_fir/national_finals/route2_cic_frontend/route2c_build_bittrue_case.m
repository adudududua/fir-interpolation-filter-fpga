function result = route2c_build_bittrue_case(x)
% Integer bit-true model for Route 2C:
% FIR2 x3 -> canonical HB2 -> CIC8/N3.

    script_dir = fileparts(mfilename('fullpath'));
    matlab_root = fileparts(fileparts(script_dir));
    bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
    v2_dir = fullfile(matlab_root, 'alt_all2x_v2');
    v7_dir = fullfile(matlab_root, 'alt_all2x_v7');
    selected_path = fullfile(script_dir, 'results', ...
        'route2_single_hb_cic8_screen.mat');
    addpath(bittrue_dir);
    addpath(v7_dir);

    reference = load(fullfile(v2_dir, ...
        'stage1_strict_halfband_config.mat'), 'best_config');
    selected_data = load(selected_path, 'selected');
    selected = selected_data.selected;

    stage1_coeff = int64(load_stage1(script_dir));
    stage2_coeff = int64(reference.best_config(2).coeff_int(:).');
    stage3_coeff = int64(selected.stage3_coeff_int(:).');
    hb_coeff = int64([-1 0 9 16 9 0 -1]);

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
    [hb, stat4] = interp2_polyphase_bittrue( ...
        stage3, hb_coeff, 4, 20, 30);
    [cic_output, cic_stat, cic_trace] = cic_interp16_bittrue( ...
        hb, 8, 3, 1, 20, 20, zeros(1, 6));

    result.input = x;
    result.y4_internal = stage2;
    result.y8_internal = stage3;
    result.y16_internal = hb;
    result.y128_internal = cic_output;
    result.y4_24 = bitshift(stage2, 2);
    result.y8_24 = bitshift(stage3, 4);
    result.y128_24 = bitshift(cic_output, 4);
    result.stat.stage1 = stat1;
    result.stat.bridge1 = bridge1_stat;
    result.stat.stage2 = stat2;
    result.stat.bridge2 = bridge2_stat;
    result.stat.stage3 = stat3;
    result.stat.hb = stat4;
    result.stat.cic = cic_stat;
    result.trace.cic = cic_trace;
end


function coeff = load_stage1(script_dir)
    source_path = fullfile(fileparts(fileparts(script_dir)), ...
        'alt_all2x_v8', 'results', ...
        'phase8_cic2_stage1_redesign_selected.mat');
    source = load(source_path, 'selected');
    coeff = source.selected.coeff_int(:).';
end
