%=============================================================
% 文件名       : nf_01_search_shared_cic_equalizer.m
% 功能简述     : 全国总决赛双采样率、三倍率共用数据通路的浮点搜索。
%
%                现有 Phase 7 Stage3 把 CIC16 通带补偿折叠进 8x FIR，
%                因而 8x 节点在 20 kHz 约有 +0.134 dB 预加重，不能
%                直接作为独立 8x 赛题输出。本脚本恢复原平坦 Stage3，
%                并在 CIC 前搜索如下无乘法器三抽头线性相位均衡器：
%
%                  y[n] = x[n-1]
%                       + K * (2*x[n-1] - x[n] - x[n-2])
%
%                K 限制为 N/2^S，RTL 可由加减和算术右移实现。均衡器
%                只进入 128x CIC 支路，4x/8x 输出保持原全 FIR 响应。
%
% 输出目录     : results/
%                  nf_shared_equalizer_candidates.csv
%                  nf_shared_equalizer_summary.txt
%                figures/
%                  nf_shared_equalizer_response.png
%=============================================================

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(script_dir);
v2_dir = fullfile(matlab_root, 'alt_all2x_v2');
all2x_dir = fullfile(matlab_root, 'alt_all2x');
result_dir = fullfile(script_dir, 'results');
figure_dir = fullfile(script_dir, 'figures');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
if ~exist(figure_dir, 'dir'); mkdir(figure_dir); end

FS_LIST = [44100 48000];
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
PASS_LIMIT_DB = 0.05;
STOP_LIMIT_DB = 70;
NFFT = 2^18;
FRAC_W = 15;

reference_path = fullfile(v2_dir, 'stage1_strict_halfband_config.mat');
if ~exist(reference_path, 'file')
    error('缺少 Stage1/2 正式配置：%s', reference_path);
end
reference = load(reference_path, 'best_config');
h1 = double(reference.best_config(1).coeff_int(:).') / 2^FRAC_W;
h2 = double(reference.best_config(2).coeff_int(:).') / 2^FRAC_W;

stage3_path = fullfile(all2x_dir, 'stage03_2x_coeff_decimal.txt');
if ~exist(stage3_path, 'file')
    error('缺少平坦 Stage3 系数：%s', stage3_path);
end
h3 = double(readmatrix(stage3_path).') / 2^FRAC_W;

h4 = conv(upsample_ir(h1, 2), h2);
h8 = conv(upsample_ir(h4, 2), h3);

% CIC R=16, M=1, N=3 的等效高采样率冲激。
h_cic = ones(1, 16);
h_cic = conv(h_cic, ones(1, 16));
h_cic = conv(h_cic, ones(1, 16));

candidate_num = [];
candidate_shift = [];
candidate_k = [];
candidate_worst_pass = [];
candidate_worst_stop = [];
candidate_pass = [];

% 搜索适合移位加法实现的小分母系数。重复 K 只保留最小分子表示。
seen_k = [];
for shift_n = 3:10
    for numerator = 1:2^(shift_n-1)
        k_value = numerator / 2^shift_n;
        if any(abs(seen_k-k_value) < eps)
            continue;
        end
        seen_k(end+1) = k_value; %#ok<SAGROW>

        h_eq = [-k_value, 1+2*k_value, -k_value];
        h8_equalized = conv(h8, h_eq);
        h128 = conv(upsample_ir(h8_equalized, 16), h_cic);

        worst_pass = 0;
        worst_stop = inf;
        pass_all = true;
        for fs_idx = 1:numel(FS_LIST)
            fs_in = FS_LIST(fs_idx);
            m4 = analyze_node(h4, 4*fs_in, fs_in, ...
                F_PASS_LOW, F_PASS_HIGH, NFFT);
            m8 = analyze_node(h8, 8*fs_in, fs_in, ...
                F_PASS_LOW, F_PASS_HIGH, NFFT);
            m128 = analyze_node(h128, 128*fs_in, fs_in, ...
                F_PASS_LOW, F_PASS_HIGH, NFFT);
            node_list = [m4 m8 m128];
            worst_pass = max(worst_pass, ...
                max([node_list.pass_abs_max_db]));
            worst_stop = min(worst_stop, ...
                min([node_list.stop_attn_db]));
            pass_all = pass_all && all([node_list.pass_abs_max_db] <= ...
                PASS_LIMIT_DB) && all([node_list.stop_attn_db] >= ...
                STOP_LIMIT_DB);
        end

        candidate_num(end+1, 1) = numerator; %#ok<SAGROW>
        candidate_shift(end+1, 1) = shift_n; %#ok<SAGROW>
        candidate_k(end+1, 1) = k_value; %#ok<SAGROW>
        candidate_worst_pass(end+1, 1) = worst_pass; %#ok<SAGROW>
        candidate_worst_stop(end+1, 1) = worst_stop; %#ok<SAGROW>
        candidate_pass(end+1, 1) = pass_all; %#ok<SAGROW>
    end
end

candidate_table = table(candidate_num, candidate_shift, candidate_k, ...
    candidate_worst_pass, candidate_worst_stop, candidate_pass, ...
    'VariableNames', {'NUMERATOR', 'SHIFT', 'K', ...
    'WORST_PASS_ABS_DB', 'WORST_STOP_ATTN_DB', 'PASS'});
candidate_table = sortrows(candidate_table, ...
    {'PASS', 'WORST_PASS_ABS_DB', 'SHIFT'}, ...
    {'descend', 'ascend', 'ascend'});

candidate_table.PASS = logical(candidate_table.PASS);
if ~any(candidate_table.PASS)
    error('没有找到满足双采样率三倍率门槛的移位加法均衡器。');
end

% 综合代价优先：从通过项里选最小 SHIFT，再选通带误差最小者。
passing = candidate_table(candidate_table.PASS, :);
min_shift = min(passing.SHIFT);
passing = passing(passing.SHIFT == min_shift, :);
passing = sortrows(passing, 'WORST_PASS_ABS_DB', 'ascend');
selected = passing(1, :);

k_selected = selected.K;
h_eq_selected = [-k_selected, 1+2*k_selected, -k_selected];
h128_selected = conv(upsample_ir(conv(h8, h_eq_selected), 16), h_cic);

node_name = {};
fs_in_hz = [];
fs_out_hz = [];
pass_abs_max_db = [];
ripple_pp_db = [];
stop_attn_db = [];
symmetry_error = [];
group_delay_samples = [];
pass = [];
for fs_idx = 1:numel(FS_LIST)
    fs_in = FS_LIST(fs_idx);
    node_ir = {h4, h8, h128_selected};
    node_factor = [4 8 128];
    for node_idx = 1:numel(node_factor)
        metric = analyze_node(node_ir{node_idx}, ...
            node_factor(node_idx)*fs_in, fs_in, ...
            F_PASS_LOW, F_PASS_HIGH, NFFT);
        node_name{end+1, 1} = sprintf('%dx', node_factor(node_idx)); %#ok<SAGROW>
        fs_in_hz(end+1, 1) = fs_in; %#ok<SAGROW>
        fs_out_hz(end+1, 1) = node_factor(node_idx)*fs_in; %#ok<SAGROW>
        pass_abs_max_db(end+1, 1) = metric.pass_abs_max_db; %#ok<SAGROW>
        ripple_pp_db(end+1, 1) = metric.ripple_pp_db; %#ok<SAGROW>
        stop_attn_db(end+1, 1) = metric.stop_attn_db; %#ok<SAGROW>
        symmetry_error(end+1, 1) = metric.symmetry_error; %#ok<SAGROW>
        group_delay_samples(end+1, 1) = metric.group_delay_samples; %#ok<SAGROW>
        pass(end+1, 1) = metric.pass_abs_max_db <= PASS_LIMIT_DB && ...
            metric.stop_attn_db >= STOP_LIMIT_DB && ...
            metric.symmetry_error < 1e-12; %#ok<SAGROW>
    end
end

metric_table = table(node_name, fs_in_hz, fs_out_hz, ...
    pass_abs_max_db, ripple_pp_db, stop_attn_db, symmetry_error, ...
    group_delay_samples, pass, ...
    'VariableNames', {'NODE', 'FS_IN_HZ', 'FS_OUT_HZ', ...
    'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', 'STOP_ATTN_DB', ...
    'SYMMETRY_ERROR', 'GROUP_DELAY_SAMPLES', 'PASS'});

candidate_path = fullfile(result_dir, ...
    'nf_shared_equalizer_candidates.csv');
metric_path = fullfile(result_dir, 'nf_shared_equalizer_metrics.csv');
summary_path = fullfile(result_dir, ...
    'nf_shared_equalizer_summary.txt');
figure_path = fullfile(figure_dir, ...
    'nf_shared_equalizer_response.png');
writetable(candidate_table, candidate_path);
writetable(metric_table, metric_path);
write_summary(summary_path, selected, metric_table, ...
    PASS_LIMIT_DB, STOP_LIMIT_DB);
plot_response(figure_path, h4, h8, h128_selected, FS_LIST, ...
    F_PASS_HIGH, PASS_LIMIT_DB, STOP_LIMIT_DB, NFFT);

disp(selected);
disp(metric_table);
fprintf('\n全国赛共用 FIR-CIC 架构搜索：PASS\n');
fprintf('选定 K = %d / 2^%d = %.9f\n', ...
    selected.NUMERATOR, selected.SHIFT, selected.K);
fprintf('均衡器 = [%.9f %.9f %.9f]\n', h_eq_selected);
fprintf('CSV: %s\n', metric_path);
fprintf('TXT: %s\n', summary_path);
fprintf('PNG: %s\n', figure_path);


function h_up = upsample_ir(h, rate)
    h = h(:).';
    h_up = zeros(1, rate*(numel(h)-1)+1);
    h_up(1:rate:end) = h;
end


function metric = analyze_node(h, fs_out, fs_in, ...
        pass_low, pass_high, nfft)
    [H, f] = freqz(h, 1, nfft, fs_out);
    H_db = 20*log10(abs(H/sum(h))+1e-15);
    pass_idx = f >= pass_low & f <= pass_high;
    stop_idx = f >= (fs_in-pass_high) & f <= fs_out/2;
    pass_db = H_db(pass_idx);
    metric.pass_abs_max_db = max(abs(pass_db));
    metric.ripple_pp_db = max(pass_db)-min(pass_db);
    metric.stop_attn_db = -max(H_db(stop_idx));
    metric.symmetry_error = max(abs(h-fliplr(h)));
    metric.group_delay_samples = (numel(h)-1)/2;
end


function write_summary(filename, selected, metric_table, ...
        pass_limit, stop_limit)
    fid = fopen(filename, 'w');
    if fid < 0; error('无法创建总结文件：%s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'National finals shared FIR-CIC equalizer search\n');
    fprintf(fid, '===============================================\n');
    fprintf(fid, 'Selected K = %d / 2^%d = %.12f\n', ...
        selected.NUMERATOR, selected.SHIFT, selected.K);
    fprintf(fid, ['RTL form: y[n]=x[n-1]+K*' ...
        '(2*x[n-1]-x[n]-x[n-2])\n']);
    fprintf(fid, 'Limits: pass <= +/-%.3f dB, stop >= %.1f dB\n\n', ...
        pass_limit, stop_limit);
    for idx = 1:height(metric_table)
        fprintf(fid, ['Fs_in=%g node=%s Fs_out=%g pass_abs=%.9f dB ' ...
            'ripple_pp=%.9f dB stop=%.9f dB symmetry=%.3g ' ...
            'gd=%.1f PASS=%d\n'], ...
            metric_table.FS_IN_HZ(idx), metric_table.NODE{idx}, ...
            metric_table.FS_OUT_HZ(idx), ...
            metric_table.PASS_ABS_MAX_DB(idx), ...
            metric_table.RIPPLE_PP_DB(idx), ...
            metric_table.STOP_ATTN_DB(idx), ...
            metric_table.SYMMETRY_ERROR(idx), ...
            metric_table.GROUP_DELAY_SAMPLES(idx), ...
            metric_table.PASS(idx));
    end
    fprintf(fid, '\nOVERALL_PASS=%d\n', all(metric_table.PASS));
end


function plot_response(filename, h4, h8, h128, fs_list, ...
        pass_edge, pass_limit, stop_limit, nfft)
    figure('Color', 'w', 'Position', [80 80 1420 780]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    colors = lines(3);
    for fs_idx = 1:numel(fs_list)
        fs_in = fs_list(fs_idx);
        node_ir = {h4, h8, h128};
        node_factor = [4 8 128];
        nexttile;
        hold on;
        for node_idx = 1:3
            [H, f] = freqz(node_ir{node_idx}, 1, nfft, ...
                node_factor(node_idx)*fs_in);
            H_db = 20*log10(abs(H/sum(node_ir{node_idx}))+1e-15);
            plot(f/1e3, H_db, 'LineWidth', 1.15, ...
                'Color', colors(node_idx, :));
        end
        xline(pass_edge/1e3, '--k');
        xline((fs_in-pass_edge)/1e3, ':k');
        yline(-stop_limit, '--r');
        xlim([0 min(120, 128*fs_in/2/1e3)]);
        ylim([-120 2]);
        grid on;
        title(sprintf('Fs_{in}=%.1f kHz，全带响应', fs_in/1e3));
        xlabel('频率 / kHz'); ylabel('归一化幅度 / dB');
        legend('4x', '8x', '128x', '20 kHz', ...
            '首镜像边界', '-70 dB', 'Location', 'southwest');

        nexttile;
        hold on;
        for node_idx = 1:3
            [H, f] = freqz(node_ir{node_idx}, 1, nfft, ...
                node_factor(node_idx)*fs_in);
            H_db = 20*log10(abs(H/sum(node_ir{node_idx}))+1e-15);
            idx = f <= pass_edge;
            plot(f(idx)/1e3, H_db(idx), 'LineWidth', 1.15, ...
                'Color', colors(node_idx, :));
        end
        yline(pass_limit, '--r');
        yline(-pass_limit, '--r');
        xlim([0 pass_edge/1e3]);
        ylim([-0.06 0.06]);
        grid on;
        title(sprintf('Fs_{in}=%.1f kHz，通带细节', fs_in/1e3));
        xlabel('频率 / kHz'); ylabel('归一化幅度 / dB');
        legend('4x', '8x', '128x', '+0.05 dB', ...
            '-0.05 dB', 'Location', 'best');
    end
    exportgraphics(gcf, filename, 'Resolution', 180);
    close(gcf);
end
