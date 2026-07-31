%=============================================================
% 文件名       : nf_04_analyze_rtl_impulse.m
% 功能简述     : 直接由 XSim 导出的全国赛正式 RTL 冲激响应验收
%                44.1/48 kHz 下的 4x、8x、128x 频响与线性相位。
%=============================================================

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
rtl_dir = fullfile(script_dir, 'rtl_outputs');
result_dir = fullfile(script_dir, 'results');
figure_dir = fullfile(script_dir, 'figures');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
if ~exist(figure_dir, 'dir'); mkdir(figure_dir); end

FS_LIST = [44100 48000];
FACTOR_LIST = [4 8 128];
NODE_LIST = {'4x', '8x', '128x'};
EXPECTED_LENGTH = [225 459 7406];
PASS_LOW = 10;
PASS_HIGH = 20000;
PASS_LIMIT_DB = 0.05;
STOP_LIMIT_DB = 70;
IMPULSE_AMPLITUDE = 2^22;
ABS_GAIN_LIMIT_DB = 0.01;
MODE_GAIN_DELTA_LIMIT_DB = 0.01;
NFFT = 2^18;

ir = cell(1, 3);
for idx = 1:3
    path_value = fullfile(rtl_dir, ...
        sprintf('rtl_impulse_y%d.csv', FACTOR_LIST(idx)));
    ir{idx} = readmatrix(path_value).';
    if numel(ir{idx}) ~= EXPECTED_LENGTH(idx)
        error('RTL %s 冲激长度错误：%d，应为 %d。', ...
            NODE_LIST{idx}, numel(ir{idx}), EXPECTED_LENGTH(idx));
    end
end

node = {};
fs_in_hz = [];
fs_out_hz = [];
impulse_length = [];
pass_abs_max_db = [];
ripple_pp_db = [];
stop_attn_db = [];
symmetry_lsb = [];
group_delay_samples = [];
phase_fit_residual_rad = [];
absolute_gain_linear = [];
absolute_gain_db = [];
pass = [];
metric_cell = cell(numel(FS_LIST), 3);

for fs_idx = 1:numel(FS_LIST)
    fs_in = FS_LIST(fs_idx);
    for node_idx = 1:3
        metric = analyze_rtl_node(ir{node_idx}, ...
            FACTOR_LIST(node_idx)*fs_in, fs_in, ...
            PASS_LOW, PASS_HIGH, NFFT, ...
            IMPULSE_AMPLITUDE*FACTOR_LIST(node_idx));
        metric_cell{fs_idx, node_idx} = metric;
        node{end+1, 1} = NODE_LIST{node_idx}; %#ok<SAGROW>
        fs_in_hz(end+1, 1) = fs_in; %#ok<SAGROW>
        fs_out_hz(end+1, 1) = FACTOR_LIST(node_idx)*fs_in; %#ok<SAGROW>
        impulse_length(end+1, 1) = numel(ir{node_idx}); %#ok<SAGROW>
        pass_abs_max_db(end+1, 1) = metric.pass_abs_max_db; %#ok<SAGROW>
        ripple_pp_db(end+1, 1) = metric.ripple_pp_db; %#ok<SAGROW>
        stop_attn_db(end+1, 1) = metric.stop_attn_db; %#ok<SAGROW>
        symmetry_lsb(end+1, 1) = metric.symmetry_lsb; %#ok<SAGROW>
        group_delay_samples(end+1, 1) = metric.group_delay_samples; %#ok<SAGROW>
        phase_fit_residual_rad(end+1, 1) = ...
            metric.phase_fit_residual_rad; %#ok<SAGROW>
        absolute_gain_linear(end+1, 1) = ...
            metric.absolute_gain_linear; %#ok<SAGROW>
        absolute_gain_db(end+1, 1) = metric.absolute_gain_db; %#ok<SAGROW>
        pass(end+1, 1) = metric.pass_abs_max_db <= PASS_LIMIT_DB && ...
            metric.stop_attn_db >= STOP_LIMIT_DB && ...
            metric.symmetry_lsb == 0 && ...
            metric.phase_fit_residual_rad < 1e-9 && ...
            abs(metric.absolute_gain_db) <= ABS_GAIN_LIMIT_DB; %#ok<SAGROW>
    end
end

% A mode-to-mode gain gate prevents separately normalized response curves
% from hiding a scale discontinuity at either selectable output boundary.
gain_delta_from_4x_db = zeros(size(absolute_gain_db));
for fs_idx = 1:numel(FS_LIST)
    row_index = (fs_idx-1)*numel(FACTOR_LIST)+(1:numel(FACTOR_LIST));
    gain_delta_from_4x_db(row_index) = ...
        absolute_gain_db(row_index)-absolute_gain_db(row_index(1));
    pass(row_index) = pass(row_index) & ...
        abs(gain_delta_from_4x_db(row_index)) <= ...
        MODE_GAIN_DELTA_LIMIT_DB;
end

metric_table = table(node, fs_in_hz, fs_out_hz, impulse_length, ...
    pass_abs_max_db, ripple_pp_db, stop_attn_db, symmetry_lsb, ...
    group_delay_samples, phase_fit_residual_rad, absolute_gain_linear, ...
    absolute_gain_db, gain_delta_from_4x_db, pass, ...
    'VariableNames', {'NODE', 'FS_IN_HZ', 'FS_OUT_HZ', ...
    'IMPULSE_LENGTH', 'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', ...
    'STOP_ATTN_DB', 'SYMMETRY_LSB', 'GROUP_DELAY_SAMPLES', ...
    'PHASE_FIT_RESIDUAL_RAD', 'ABSOLUTE_GAIN_LINEAR', ...
    'ABSOLUTE_GAIN_DB', 'GAIN_DELTA_FROM_4X_DB', 'PASS'});

metric_path = fullfile(result_dir, 'nf_rtl_impulse_metrics.csv');
summary_path = fullfile(result_dir, 'nf_rtl_impulse_summary.txt');
figure_path = fullfile(figure_dir, 'nf_rtl_impulse_response.png');
writetable(metric_table, metric_path);
write_summary(summary_path, metric_table, PASS_LIMIT_DB, STOP_LIMIT_DB, ...
    ABS_GAIN_LIMIT_DB, MODE_GAIN_DELTA_LIMIT_DB);
figure_written = false;
try
    plot_metrics(figure_path, metric_cell, FS_LIST, PASS_HIGH, ...
        PASS_LIMIT_DB, STOP_LIMIT_DB);
    figure_written = true;
catch plot_error
    warning('NF:PlotSkipped', ...
        '数值验收已完成，但当前主机图形驱动无法导出 PNG：%s', ...
        plot_error.message);
end

disp(metric_table);
if ~all(metric_table.PASS)
    error('全国赛正式 RTL 冲激频响验收失败。');
end
fprintf('全国赛正式 RTL 冲激频响与线性相位：PASS\n');
fprintf('CSV: %s\n', metric_path);
fprintf('TXT: %s\n', summary_path);
if figure_written
    fprintf('PNG: %s\n', figure_path);
end


function metric = analyze_rtl_node(y, fs_out, fs_in, ...
        pass_low, pass_high, nfft, expected_dc_sum)
    y = double(y(:).');
    [H, f] = freqz(y, 1, nfft, fs_out);
    H_db = 20*log10(abs(H/sum(y))+1e-15);
    pass_idx = f >= pass_low & f <= pass_high;
    stop_idx = f >= (fs_in-pass_high) & f <= fs_out/2;
    pass_db = H_db(pass_idx);

    phase_idx = pass_idx & abs(H) > max(abs(H))*1e-6;
    phase_value = unwrap(angle(H(phase_idx)));
    omega_value = 2*pi*f(phase_idx)/fs_out;
    phase_coeff = polyfit(omega_value, phase_value, 1);
    phase_fit = polyval(phase_coeff, omega_value);

    metric.f = f;
    metric.H_db = H_db;
    metric.pass_abs_max_db = max(abs(pass_db));
    metric.ripple_pp_db = max(pass_db)-min(pass_db);
    metric.stop_attn_db = -max(H_db(stop_idx));
    metric.symmetry_lsb = max(abs(y-fliplr(y)));
    metric.group_delay_samples = -phase_coeff(1);
    metric.phase_fit_residual_rad = max(abs(phase_value-phase_fit));
    metric.absolute_gain_linear = sum(y)/expected_dc_sum;
    metric.absolute_gain_db = ...
        20*log10(abs(metric.absolute_gain_linear)+1e-15);
end


function write_summary(filename, table_data, pass_limit, stop_limit, ...
        absolute_gain_limit, mode_gain_delta_limit)
    fid = fopen(filename, 'w');
    if fid < 0; error('无法创建总结：%s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'National finals formal RTL impulse acceptance\n');
    fprintf(fid, '=============================================\n');
    fprintf(fid, 'Source: XSim outputs, not coefficient-only model\n');
    fprintf(fid, ['Limits: pass <= +/-%.3f dB, stop >= %.1f dB, ' ...
        'absolute gain <= +/-%.3f dB, mode delta <= %.3f dB\n\n'], ...
        pass_limit, stop_limit, absolute_gain_limit, ...
        mode_gain_delta_limit);
    for idx = 1:height(table_data)
        fprintf(fid, ['Fs_in=%g node=%s Fs_out=%g len=%d ' ...
            'pass_abs=%.9f dB ripple=%.9f dB stop=%.9f dB ' ...
            'sym=%g LSB gd=%.6f phase_res=%.3g ' ...
            'gain=%.12f (%.9f dB) delta4x=%.9f dB PASS=%d\n'], ...
            table_data.FS_IN_HZ(idx), table_data.NODE{idx}, ...
            table_data.FS_OUT_HZ(idx), table_data.IMPULSE_LENGTH(idx), ...
            table_data.PASS_ABS_MAX_DB(idx), ...
            table_data.RIPPLE_PP_DB(idx), ...
            table_data.STOP_ATTN_DB(idx), ...
            table_data.SYMMETRY_LSB(idx), ...
            table_data.GROUP_DELAY_SAMPLES(idx), ...
            table_data.PHASE_FIT_RESIDUAL_RAD(idx), ...
            table_data.ABSOLUTE_GAIN_LINEAR(idx), ...
            table_data.ABSOLUTE_GAIN_DB(idx), ...
            table_data.GAIN_DELTA_FROM_4X_DB(idx), ...
            table_data.PASS(idx));
    end
    fprintf(fid, '\nOVERALL_PASS=%d\n', all(table_data.PASS));
end


function plot_metrics(filename, metric_cell, fs_list, ...
        pass_high, pass_limit, stop_limit)
    figure('Visible', 'off', 'Color', 'w', ...
        'Position', [70 60 1420 800]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    colors = lines(3);
    for fs_idx = 1:numel(fs_list)
        nexttile;
        hold on;
        for node_idx = 1:3
            metric = metric_cell{fs_idx, node_idx};
            plot(metric.f/1e3, metric.H_db, 'LineWidth', 1.15, ...
                'Color', colors(node_idx, :));
        end
        xline(pass_high/1e3, '--k');
        xline((fs_list(fs_idx)-pass_high)/1e3, ':k');
        yline(-stop_limit, '--r');
        xlim([0 120]); ylim([-120 2]); grid on;
        title(sprintf('RTL Fs_{in}=%.1f kHz，全带', fs_list(fs_idx)/1e3));
        xlabel('频率 / kHz'); ylabel('归一化幅度 / dB');
        legend('4x', '8x', '128x', '20 kHz', ...
            '首镜像边界', '-70 dB', 'Location', 'southwest');

        nexttile;
        hold on;
        for node_idx = 1:3
            metric = metric_cell{fs_idx, node_idx};
            index = metric.f <= pass_high;
            plot(metric.f(index)/1e3, metric.H_db(index), ...
                'LineWidth', 1.15, 'Color', colors(node_idx, :));
        end
        yline(pass_limit, '--r');
        yline(-pass_limit, '--r');
        xlim([0 pass_high/1e3]); ylim([-0.06 0.06]); grid on;
        title(sprintf('RTL Fs_{in}=%.1f kHz，通带', fs_list(fs_idx)/1e3));
        xlabel('频率 / kHz'); ylabel('归一化幅度 / dB');
        legend('4x', '8x', '128x', '+0.05 dB', ...
            '-0.05 dB', 'Location', 'best');
    end
    exportgraphics(gcf, filename, 'Resolution', 180);
    close(gcf);
end
