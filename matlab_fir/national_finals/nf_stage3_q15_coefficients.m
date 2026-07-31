function coeff = nf_stage3_q15_coefficients()
%NF_STAGE3_Q15_COEFFICIENTS Authoritative national-finals Stage3 taps.
%   The natural-order 11-tap interpolator is stored as signed Q15.  Its
%   even and odd polyphase sums are both 32764/32768, so a constant input
%   retains unity amplitude after 2x interpolation.

    coeff = int64([404, -148, -3272, 522, 19250, 32016, ...
        19250, 522, -3272, -148, 404]);

    phase0_sum = sum(coeff(1:2:end));
    phase1_sum = sum(coeff(2:2:end));
    assert(phase0_sum == 32764 && phase1_sum == 32764, ...
        'National-finals Stage3 Q15 polyphase gain invariant failed.');
end
