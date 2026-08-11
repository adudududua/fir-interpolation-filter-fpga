function config = nf_release_218_config()
%NF_RELEASE_218_CONFIG Auditable source of truth for the 218-LUT release.
%   The immutable P4-D configuration supplies coefficients and unchanged
%   accumulator proofs.  This function asserts that exact ancestry before
%   applying the signed-off 24/20/20 scaling and current implementation
%   identity, so legacy and current releases cannot be mixed silently.

    config = nf_release_v2_config();
    expected_base_id = 'NF-P4D-R2-479LUT-468FF-4DSP-2BRAM-2MMCM';
    assert(strcmp(config.config_id, expected_base_id), ...
        'Unexpected release-v2 ancestry: %s', config.config_id);

    config.schema = 'national-finals-release-config-218-v1';
    config.base_config_id = expected_base_id;
    config.config_id = 'NF-P3-STAGE123-24-20-20-CANDIDATE-R1';
    config.release_status = 'board-verified';
    config.board_verification_date = '2026-08-11';
    config.part = 'xc7a35tfgg484-2';
    config.vivado = '2025.2';
    config.top = 'board_demo_competition_dac8_top';
    config.rtl_define = 'NF_WORDLENGTH_24_20_20';

    config.bridge1.shift_w = 4;
    config.bridge1.output_w = 20;
    config.stage2.input_w = 20;
    config.stage2.output_w = 20;
    config.bridge2.shift_w = 0;
    config.bridge2.output_w = 20;

    config.stage3_comp.coeff_int = int64([ ...
        561 137 -4232 -1554 20046 35584 20046 -1554 -4232 137 561]);
    config.stage3_comp.frac_w = 15;
    config.stage3_comp.input_w = 20;
    config.stage3_comp.output_w = 21;
    config.stage3_comp.acc_w = 38;

    config.formal_outputs.x4 = 'stage2 signed-20 << 4';
    config.formal_outputs.x8 = 'stage3 signed-20 << 4';
    config.formal_outputs.x128 = 'CIC signed-20 << 4';

    config.implementation.lut = 218;
    config.implementation.ff = 365;
    config.implementation.dsp48e1 = 4;
    config.implementation.ramb18e1 = 4;
    config.implementation.bram_tile = 2;
    config.implementation.mmcm = 2;
    config.implementation.wns_ns = 45.279;
    config.implementation.whs_ns = 0.079;
    config.implementation.bitstream_sha256 = ...
        '1834675AB971FFA8BD6C03BF1B596D6F5D65C8A36A6B8D0182EEA6C5D408D110';
    config.implementation.routed_dcp_sha256 = ...
        'FC26756258EF14A60872D55CBDDAC928D536727937876788D180E2D3BE35A462';
end
