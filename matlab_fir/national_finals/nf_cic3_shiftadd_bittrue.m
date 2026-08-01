function [y, stat] = nf_cic3_shiftadd_bittrue(x, input_w, output_w)
%NF_CIC3_SHIFTADD_BITTRUE Bit-true model of the signed-off 3-tap equalizer.
%   The signed input is not pre-clipped.  The internal expression is kept
%   at input_w+3 bits and the output is saturated only at output_w.

    if output_w ~= input_w && output_w ~= input_w+1
        error('Equalizer output_w must be input_w or input_w+1.');
    end

    x = int64(x(:).');
    input_max = int64(2^(input_w-1)-1);
    input_min = int64(-2^(input_w-1));
    if any(x > input_max | x < input_min)
        error('Equalizer input is outside signed-%d before processing.', ...
            input_w);
    end

    output_max = int64(2^(output_w-1)-1);
    output_min = int64(-2^(output_w-1));
    y = zeros(size(x), 'int64');
    x_z1 = int64(0);
    x_z2 = int64(0);
    sat_high_count = 0;
    sat_low_count = 0;
    max_abs_unclipped = 0;

    for idx = 1:numel(x)
        curvature = 2*x_z1-x(idx)-x_z2;
        correction = idivide(curvature, int64(8), 'floor');
        value = x_z1+correction;
        max_abs_unclipped = max(max_abs_unclipped, abs(double(value)));
        if value > output_max
            value = output_max;
            sat_high_count = sat_high_count+1;
        elseif value < output_min
            value = output_min;
            sat_low_count = sat_low_count+1;
        end
        y(idx) = value;
        x_z2 = x_z1;
        x_z1 = x(idx);
    end

    stat.input_w = input_w;
    stat.output_w = output_w;
    stat.input_count = numel(x);
    stat.output_count = numel(y);
    stat.sat_high_count = sat_high_count;
    stat.sat_low_count = sat_low_count;
    stat.output_sat_count = sat_high_count+sat_low_count;
    stat.max_abs_input = max(abs(double(x)));
    stat.max_abs_unclipped = max_abs_unclipped;
    stat.max_abs_output = max(abs(double(y)));
    stat.exceeds_input_width_count = nnz(y > input_max | y < input_min);
end
