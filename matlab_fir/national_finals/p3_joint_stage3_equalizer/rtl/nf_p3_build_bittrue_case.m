function result = nf_p3_build_bittrue_case(x, stage3_variant)
% Bit-true model for flat 4x/8x and compensated-Stage3 128x P3 RTL.

    if nargin < 2 || isempty(stage3_variant)
        stage3_variant = 'BASELINE';
    end
    stage3_variant = upper(strtrim(stage3_variant));

    script_dir = fileparts(mfilename('fullpath'));
    p3_dir = fileparts(script_dir);
    nf_dir = fileparts(p3_dir);
    matlab_root = fileparts(nf_dir);
    bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
    addpath(nf_dir);
    addpath(bittrue_dir);

    release = nf_release_v2_config();
    switch stage3_variant
        case 'BASELINE'
            p3_coeff = int64([561 137 -4232 -1554 20046 35584 ...
                20046 -1554 -4232 137 561]);
            config_id = 'NF-P3-RTL-JOINT-STAGE3-EQ-R1';
        case 'NINE_TAP'
            p3_coeff = int64([-943 -2793 2406 19161 29851 ...
                19161 2406 -2793 -943]);
            config_id = 'NF-P3J-STAGE3-9TAP-R1';
        otherwise
            error('Unknown P3 Stage3 variant: %s', stage3_variant);
    end

    x = int64(x(:).');
    [stage1, stat1] = interp2_polyphase_bittrue(x, ...
        release.stage1.coeff_int, release.stage1.frac_w, ...
        release.stage1.input_w, release.stage1.acc_w);
    [stage1_q22, bridge1_stat] = round_shift_sat_signed(stage1, 2, 22);
    [stage2, stat2] = interp2_polyphase_bittrue(stage1_q22, ...
        release.stage2.coeff_int, release.stage2.frac_w, ...
        release.stage2.input_w, release.stage2.acc_w);
    [stage2_q20, bridge2_stat] = round_shift_sat_signed(stage2, 2, 20);

    % Official 8x output remains the P4-D flat Stage3.
    [stage3_flat, stat3_flat] = interp2_polyphase_bittrue(stage2_q20, ...
        release.stage3.coeff_int, release.stage3.frac_w, ...
        release.stage3.input_w, release.stage3.acc_w);

    % 128x uses the independent compensated bank and retains signed-21.
    [stage3_comp, stat3_comp] = interp2_polyphase_bittrue(stage2_q20, ...
        p3_coeff, 15, 21, 38);
    [cic_output, cic_stat, cic_trace] = ...
        nf_cic_n3_hold2_bittrue([stage3_comp int64([0 0])], 21, 20);

    result.config_id = config_id;
    result.input = x;
    result.y4_internal = stage2;
    result.y8_internal = stage3_flat;
    result.p3_stage3_internal = stage3_comp;
    result.y128_internal = cic_output;
    result.y4_24 = bitshift(stage2, 2);
    result.y8_24 = bitshift(stage3_flat, 4);
    result.y128_24 = bitshift(cic_output, 4);
    result.stat.stage1 = stat1;
    result.stat.bridge1 = bridge1_stat;
    result.stat.stage2 = stat2;
    result.stat.bridge2 = bridge2_stat;
    result.stat.stage3_flat = stat3_flat;
    result.stat.stage3_comp = stat3_comp;
    result.stat.cic = cic_stat;
    result.trace.cic = cic_trace;
end
