function result = nf_p3_build_bittrue_case_24_20_20(x)
% Bit-true candidate with Stage1/Stage2/Stage3 data widths 24/20/20.
%
% The first bridge moves the complete four-bit scale reduction in front of
% Stage2.  Stage2 therefore consumes and emits signed-20 data.  There is no
% second arithmetic quantizer: Stage2 feeds Stage3 at the same Q format.

    script_dir = fileparts(mfilename('fullpath'));
    nf_dir = fileparts(script_dir);
    matlab_root = fileparts(nf_dir);
    bittrue_dir = fullfile(matlab_root, 'alt_all2x', 'bittrue');
    addpath(nf_dir);
    addpath(bittrue_dir);

    release = nf_release_v2_config();
    p3_coeff = int64([561 137 -4232 -1554 20046 35584 ...
        20046 -1554 -4232 137 561]);

    x = int64(x(:).');
    [stage1, stat1] = interp2_polyphase_bittrue(x, ...
        release.stage1.coeff_int, release.stage1.frac_w, ...
        release.stage1.input_w, release.stage1.acc_w);
    [stage1_q20, bridge1_stat] = round_shift_sat_signed(stage1, 4, 20);
    [stage2, stat2] = interp2_polyphase_bittrue(stage1_q20, ...
        release.stage2.coeff_int, release.stage2.frac_w, 20, ...
        release.stage2.acc_w);

    % Stage2 already has the signed-20 Q format required by both Stage3
    % banks.  Keep a named identity bridge in the model so its statistics
    % and RTL correspondence remain explicit and auditable.
    [stage2_q20, bridge2_stat] = round_shift_sat_signed(stage2, 0, 20);

    [stage3_flat, stat3_flat] = interp2_polyphase_bittrue(stage2_q20, ...
        release.stage3.coeff_int, release.stage3.frac_w, 20, ...
        release.stage3.acc_w);
    [stage3_comp, stat3_comp] = interp2_polyphase_bittrue(stage2_q20, ...
        p3_coeff, 15, 21, 38);
    [cic_output, cic_stat, cic_trace] = ...
        nf_cic_n3_hold2_bittrue([stage3_comp int64([0 0])], 21, 20);

    result.config_id = 'NF-P3-STAGE123-24-20-20-CANDIDATE-R1';
    result.input = x;
    result.y4_internal = stage2;
    result.y8_internal = stage3_flat;
    result.p3_stage3_internal = stage3_comp;
    result.y128_internal = cic_output;
    result.y4_24 = bitshift(stage2, 4);
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
