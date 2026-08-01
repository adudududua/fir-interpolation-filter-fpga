clear; clc;

script_dir = fileparts(mfilename('fullpath'));
nf_dir = fileparts(script_dir);
addpath(nf_dir);

M = 2^24;
directed_low = [hex2dec('FFFFFE') hex2dec('FFFFFF') 0 1];
directed_high = [0 1 2 3];
directed_u = zeros(1, numel(directed_low)*numel(directed_high), 'int64');
cursor = 1;
for high_bits = directed_high
    for low_bits = directed_low
        directed_u(cursor) = join_parts(high_bits, low_bits, 26);
        cursor = cursor+1;
    end
end
directed_u = [directed_u int64([1 -1 2^20-1 -2^20 2^25-1 -2^25])];

rows = cell(0, 8);
result = simulate_schedule(directed_u, true(1, numel(directed_u)), ...
    false(1, numel(directed_u)), true);
rows(end+1, :) = {'directed-continuous', 0, numel(directed_u), ...
    result.cycles, result.commits, result.s_mismatches, ...
    result.l_mapping_mismatches, result.invariant_mismatches}; %#ok<SAGROW>

for seed_index = 1:20
    rng(92000+seed_index, 'twister');
    event_count = 1000;
    raw_bits = floor(rand(1, event_count)*2^26);
    u = wrap_signed(int64(raw_bits), 26);

    continuous = simulate_schedule(u, true(1, event_count), ...
        false(1, event_count), false);
    rows(end+1, :) = {'random-continuous', seed_index, event_count, ...
        continuous.cycles, continuous.commits, continuous.s_mismatches, ...
        continuous.l_mapping_mismatches, ...
        continuous.invariant_mismatches}; %#ok<SAGROW>

    [valid_mask, reset_mask] = random_schedule(event_count, seed_index);
    stalled = simulate_schedule(u, valid_mask, reset_mask, false);
    rows(end+1, :) = {'random-stall-reset', seed_index, event_count, ...
        stalled.cycles, stalled.commits, stalled.s_mismatches, ...
        stalled.l_mapping_mismatches, ...
        stalled.invariant_mismatches}; %#ok<SAGROW>
end

metrics = cell2table(rows, 'VariableNames', { ...
    'test_name', 'seed', 'event_count', 'cycle_count', 'commit_count', ...
    'p1s_mismatches', 'p1l_mapping_mismatches', 'q_invariant_mismatches'});
assert(all(metrics.p1s_mismatches == 0));
assert(all(metrics.p1l_mapping_mismatches == 0));
assert(all(metrics.q_invariant_mismatches == 0));

% Use the signed-off finite-vector contract to audit the P1-L tail.  P1-L
% emits Q_n=B_(n-1); after N state updates it has no B_N value.  Producing
% B_N needs either an N+1 state update (forbidden by the guide) or the same
% 29-bit Q_N+A_N fabric adder used by P1-S.  The present three low-rate zero
% frames make B_N zero, but omitting it still violates the exact N-output
% count, so P1-L is a protocol No-Go rather than an arithmetic failure.
impulse_case = nf_build_bittrue_case(int64([2^22 zeros(1, 31)]));
hold_stream = make_c2_hold16_stream(impulse_case.equalized_internal);
[a_ref, b_ref] = reference_states(hold_stream);
assert(numel(b_ref) == numel(hold_stream));
assert(b_ref(end) == 0, 'Signed-off finite tail did not end at zero.');
last_nonzero_index = find(b_ref ~= 0, 1, 'last');
assert(~isempty(last_nonzero_index) && last_nonzero_index < numel(b_ref), ...
    'Tail audit did not contain a nonzero value before the final zero run.');
assert(all(b_ref(last_nonzero_index+1:end) == 0), ...
    'Tail after the last nonzero sample was not entirely zero.');
p1l_available = [int64(0) b_ref(1:end-1)];
assert(numel(p1l_available) == numel(b_ref));
assert(any(p1l_available ~= b_ref), ...
    'P1-L unexpectedly preserved the unshifted output sequence.');

tail = struct();
tail.high_rate_updates = numel(hold_stream);
tail.reference_outputs = numel(b_ref);
tail.p1l_outputs_without_extra_update_after_latency = numel(b_ref)-1;
tail.last_reference_b = b_ref(end);
tail.last_reference_a = a_ref(end);
tail.last_nonzero_reference_index = last_nonzero_index;
tail.missing_output_requires_extra_state_update_or_p1s_adder = true;
tail.p1l_protocol_go = false;
tail.p1s_protocol_go = true;

out_dir = fullfile(nf_dir, 'results');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
writetable(metrics, fullfile(out_dir, 'p1a_two24_cycle_metrics.csv'));

summary_path = fullfile(out_dir, 'p1a_two24_cycle_summary.txt');
fid = fopen(summary_path, 'w');
assert(fid >= 0, 'Unable to write %s.', summary_path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'P1 TWO24 INTEGER CYCLE MODEL PASS\n');
fprintf(fid, 'Directed low limbs: FFFFFE, FFFFFF, 000000, 000001\n');
fprintf(fid, 'Random seeds: 20; events per continuous/stall-reset test: 1000\n');
fprintf(fid, 'P1-S state/output mismatches: %d\n', sum(metrics.p1s_mismatches));
fprintf(fid, 'P1-L Q_n=B_(n-1) mapping mismatches: %d\n', ...
    sum(metrics.p1l_mapping_mismatches));
fprintf(fid, 'Q invariant mismatches: %d\n', ...
    sum(metrics.q_invariant_mismatches));
fprintf(fid, 'Finite high-rate updates/reference outputs: %d/%d\n', ...
    tail.high_rate_updates, tail.reference_outputs);
fprintf(fid, 'P1-L outputs after latency without extra update: %d\n', ...
    tail.p1l_outputs_without_extra_update_after_latency);
fprintf(fid, 'Last nonzero reference output index: %d; final A/B: %d/%d\n', ...
    tail.last_nonzero_reference_index, tail.last_reference_a, ...
    tail.last_reference_b);
fprintf(fid, 'P1-S: GO to UNISIM. P1-L: NO-GO on exact finite output count.\n');
clear cleanup;

disp(metrics);
fprintf(['P1A_TWO24_PASS: P1-S exact and II=1-capable in the integer ' ...
    'model; P1-L arithmetic mapping exact but finite-count No-Go.\n']);


function result = simulate_schedule(events, valid_mask, reset_mask, trace_enable)
    assert(numel(valid_mask) == numel(reset_mask));
    assert(sum(valid_mask) == numel(events));

    a_ref = int64(0);
    b_ref = int64(0);
    a_high = int64(0);
    q_high = int64(0);
    a_low = int64(0);
    q_low = int64(0);
    pending = false;
    pending_u_high = int64(0);
    pending_carry_a = int64(0);
    pending_carry_q = int64(0);
    pending_expected_a = int64(0);
    pending_expected_b = int64(0);
    pending_expected_prev_b = int64(0);

    event_cursor = 1;
    commits = 0;
    s_mismatches = 0;
    l_mapping_mismatches = 0;
    invariant_mismatches = 0;
    trace_rows = zeros(0, 12); %#ok<NASGU>

    total_cycles = numel(valid_mask)+1;
    for cycle = 1:total_cycles
        valid = cycle <= numel(valid_mask) && valid_mask(cycle);
        reset = cycle <= numel(reset_mask) && reset_mask(cycle);
        if reset
            a_ref = int64(0); b_ref = int64(0);
            a_high = int64(0); q_high = int64(0);
            a_low = int64(0); q_low = int64(0);
            pending = false;
            continue;
        end

        if pending
            a_high_next = wrap_signed( ...
                a_high+pending_u_high+pending_carry_a, 2);
            q_high_next = wrap_signed( ...
                q_high+a_high+pending_carry_q, 5);
            a_commit = join_parts(a_high_next, a_low, 26);
            q_commit = join_parts(q_high_next, q_low, 29);
            b_commit = wrap_signed(q_commit+a_commit, 29);
            commits = commits+1;
            s_mismatches = s_mismatches+(a_commit ~= pending_expected_a || ...
                b_commit ~= pending_expected_b);
            l_mapping_mismatches = l_mapping_mismatches+(q_commit ~= ...
                pending_expected_prev_b);
            invariant_mismatches = invariant_mismatches+(q_commit ~= ...
                wrap_signed(pending_expected_b-pending_expected_a, 29));
            a_high = a_high_next;
            q_high = q_high_next;
        end

        next_pending = false;
        if valid
            u = events(event_cursor);
            event_cursor = event_cursor+1;
            [u_high, u_low] = split_parts(u, 26);
            raw_a_low = a_low+u_low;
            raw_q_low = q_low+a_low;
            next_a_low = mod(raw_a_low, int64(2^24));
            next_q_low = mod(raw_q_low, int64(2^24));
            carry_a = idivide(raw_a_low, int64(2^24), 'floor');
            carry_q = idivide(raw_q_low, int64(2^24), 'floor');

            prev_b = b_ref;
            a_ref = wrap_signed(a_ref+u, 26);
            b_ref = wrap_signed(b_ref+a_ref, 29);

            pending_u_high = u_high;
            pending_carry_a = carry_a;
            pending_carry_q = carry_q;
            pending_expected_a = a_ref;
            pending_expected_b = b_ref;
            pending_expected_prev_b = prev_b;
            a_low = next_a_low;
            q_low = next_q_low;
            next_pending = true;
        end
        pending = next_pending;

        if trace_enable
            trace_rows(end+1, :) = [cycle valid reset double(a_high) ...
                double(a_low) double(q_high) double(q_low) pending ...
                double(a_ref) double(b_ref) s_mismatches ...
                l_mapping_mismatches]; %#ok<AGROW,NASGU>
        end
    end
    assert(event_cursor-1 == numel(events));
    assert(~pending, 'Final low-limb result was not committed.');
    result.cycles = total_cycles;
    result.commits = commits;
    result.s_mismatches = s_mismatches;
    result.l_mapping_mismatches = l_mapping_mismatches;
    result.invariant_mismatches = invariant_mismatches;
end


function [valid_mask, reset_mask] = random_schedule(event_count, seed_index)
    rng(130000+seed_index, 'twister');
    valid_mask = false(1, event_count*3+80);
    reset_mask = false(size(valid_mask));
    event_cursor = 1;
    for cycle = 1:numel(valid_mask)
        if event_cursor <= event_count && rand() < 0.58
            valid_mask(cycle) = true;
            event_cursor = event_cursor+1;
        end
    end
    if event_cursor <= event_count
        first_free = find(~valid_mask, event_count-event_cursor+1, 'last');
        valid_mask(first_free) = true;
    end
    % Resets are inserted only in idle slots.  The model deliberately drops
    % any pending low-limb transaction, matching synchronous reset behavior.
    reset_candidates = find(~valid_mask(2:end-1))+1;
    reset_count = min(8, numel(reset_candidates));
    if reset_count > 0
        chosen = reset_candidates(round(linspace(1, numel(reset_candidates), ...
            reset_count)));
        reset_mask(chosen) = true;
    end
end


function [a_states, b_states] = reference_states(events)
    a_states = zeros(size(events), 'int64');
    b_states = zeros(size(events), 'int64');
    a = int64(0); b = int64(0);
    for index = 1:numel(events)
        a = wrap_signed(a+events(index), 26);
        b = wrap_signed(b+a, 29);
        a_states(index) = a;
        b_states(index) = b;
    end
end


function hold_stream = make_c2_hold16_stream(x)
    low_data = [int64(x(:).') zeros(1, 3, 'int64')];
    for stage = 1:2
        low_data = low_data-[int64(0) low_data(1:end-1)];
    end
    hold_stream = repelem(low_data, 16);
end


function [high, low] = split_parts(value, width)
    bits = mod(int64(value), int64(2^width));
    low = mod(bits, int64(2^24));
    high_width = width-24;
    high_bits = idivide(bits, int64(2^24), 'floor');
    high = wrap_signed(high_bits, high_width);
end


function value = join_parts(high, low, width)
    high_width = width-24;
    high_bits = mod(int64(high), int64(2^high_width));
    bits = high_bits*int64(2^24)+int64(low);
    value = wrap_signed(bits, width);
end


function value = wrap_signed(value, width)
    modulus = int64(2^width);
    half_range = int64(2^(width-1));
    value = mod(int64(value)+half_range, modulus)-half_range;
end
