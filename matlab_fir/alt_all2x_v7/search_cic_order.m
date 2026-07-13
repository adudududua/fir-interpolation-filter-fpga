clc; clear; close all;

%=============================================================
% 文件名       : search_cic_order.m
% 脚本名       : search_cic_order
% 功能简述     : Phase 7-A CIC 插值阶数搜索。保留 Phase 6
%                Stage1～3，在 8x 节点后接标准 16x CIC，
%                对 N=3/4/5 的未补偿通带下垂、复合阻带、
%                线性相位和理论位增长进行比较。
%
%                本步骤只回答“哪一个 CIC 阶数值得进入补偿
%                FIR 搜索”，不会直接修改 RTL 或板级工程。
%
%                输出文件：
%                  results/cic_order_search.csv
%                  results/cic_order_search_summary.txt
%                  figures/cic_order_search.png
%
% 当前默认配置：
%                  CIC 输入采样率：352.8kHz
%                  CIC 输出采样率：5.6448MHz
%                  R = 16，M = 1，N = 3 / 4 / 5
%                  CIC 输入数据位宽：20bit
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：按 Phase 7 修正版指导新增阶数搜索。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
v2_dir = fullfile(repo_matlab_dir, 'alt_all2x_v2');
common_dir = fullfile(v2_dir, 'common');
result_dir = fullfile(script_dir, 'results');
figure_dir = fullfile(script_dir, 'figures');

addpath(common_dir);
addpath(script_dir);
if ~exist(result_dir, 'dir')
    mkdir(result_dir);
end
if ~exist(figure_dir, 'dir')
    mkdir(figure_dir);
end

config_path = fullfile(v2_dir, 'stage1_strict_halfband_config.mat');
if ~exist(config_path, 'file')
    error('未找到 Phase 6 系数配置：%s', config_path);
end
load(config_path, 'best_config');

% Phase 5/6 的 Stage3 已等价改写为 Q15。
best_config(3).coeff_int = int64(best_config(3).coeff_int)*2;
best_config(3).frac_w = best_config(3).frac_w+1;
best_config(3).acc_w_recommended = 38;

FS_IN = 44100;
FS_CIC_IN = FS_IN*8;
R_CIC = 16;
M_CIC = 1;
FS_OUT = FS_CIC_IN*R_CIC;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_BEGIN = FS_IN-F_PASS_HIGH;
EXPECTED_GAIN = 128;
CIC_INPUT_W = 20;
NFFT = 2^20;
ORDER_LIST = [3 4 5];

h_pre3 = build_multistage_ir(best_config(1:3));
row_order = zeros(numel(ORDER_LIST), 1);
row_droop = zeros(numel(ORDER_LIST), 1);
row_pass_abs = zeros(numel(ORDER_LIST), 1);
row_ripple = zeros(numel(ORDER_LIST), 1);
row_stop = zeros(numel(ORDER_LIST), 1);
row_dc = zeros(numel(ORDER_LIST), 1);
row_sym = zeros(numel(ORDER_LIST), 1);
row_gd = zeros(numel(ORDER_LIST), 1);
row_growth = zeros(numel(ORDER_LIST), 1);
row_full_width = zeros(numel(ORDER_LIST), 1);
row_pass = false(numel(ORDER_LIST), 1);
metric_list = cell(numel(ORDER_LIST), 1);

fprintf('Phase 7-A CIC 阶数搜索\n');
for order_idx = 1:numel(ORDER_LIST)
    cic_order = ORDER_LIST(order_idx);
    h_cic = design_cic16_interpolator(cic_order, R_CIC, M_CIC);
    h_pre3_up = zeros(1, R_CIC*(numel(h_pre3)-1)+1);
    h_pre3_up(1:R_CIC:end) = h_pre3;
    h_total = conv(h_pre3_up, h_cic);
    metric = analyze_cic_response(h_total, FS_IN, FS_OUT, ...
        F_PASS_LOW, F_PASS_HIGH, F_STOP_BEGIN, EXPECTED_GAIN, NFFT);
    metric_list{order_idx} = metric;

    cic_mag_20k = cic_passband_magnitude(F_PASS_HIGH, ...
        FS_CIC_IN, R_CIC, M_CIC, cic_order);
    droop_db = 20*log10(cic_mag_20k);
    growth_bits = cic_order*ceil(log2(R_CIC*M_CIC));

    row_order(order_idx) = cic_order;
    row_droop(order_idx) = droop_db;
    row_pass_abs(order_idx) = metric.pass_abs_max_db;
    row_ripple(order_idx) = metric.ripple_pp_db;
    row_stop(order_idx) = metric.stop_attn_db;
    row_dc(order_idx) = metric.dc_gain;
    row_sym(order_idx) = metric.sym_err;
    row_gd(order_idx) = metric.gd_mean;
    row_growth(order_idx) = growth_bits;
    row_full_width(order_idx) = CIC_INPUT_W+growth_bits;
    row_pass(order_idx) = metric.pass;

    fprintf(['N=%d droop20k=%+.6f dB passAbs=%.6f dB ' ...
             'stop=%.3f dB growth=%d fullW=%d pass=%d\n'], ...
        cic_order, droop_db, metric.pass_abs_max_db, ...
        metric.stop_attn_db, growth_bits, ...
        CIC_INPUT_W+growth_bits, metric.pass);
end

result_table = table(row_order, row_droop, row_pass_abs, row_ripple, ...
    row_stop, row_dc, row_sym, row_gd, row_growth, row_full_width, ...
    row_pass, 'VariableNames', {'CIC_ORDER', 'CIC_DROOP_20K_DB', ...
    'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', 'STOP_ATTN_DB', 'DC_GAIN', ...
    'SYMMETRY_ERROR', 'GROUP_DELAY_SAMPLES', 'GROWTH_BITS', ...
    'FULL_PRECISION_WIDTH', 'PASS_WITHOUT_COMPENSATION'});
writetable(result_table, fullfile(result_dir, 'cic_order_search.csv'));

summary_path = fullfile(result_dir, 'cic_order_search_summary.txt');
fid = fopen(summary_path, 'w');
if fid < 0
    error('无法写入：%s', summary_path);
end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'Phase 7-A CIC order search\n');
fprintf(fid, '===========================\n');
fprintf(fid, 'Structure: low-rate comb -> upsample16 -> high-rate integrator\n');
fprintf(fid, 'Input width at Stage3 output = %d bit\n\n', CIC_INPUT_W);
for row_idx = 1:height(result_table)
    fprintf(fid, ['N=%d droop20k=%+.8f passAbs=%.8f ripple=%.8f ' ...
        'stop=%.8f growth=%d fullWidth=%d pass=%d\n'], ...
        result_table.CIC_ORDER(row_idx), ...
        result_table.CIC_DROOP_20K_DB(row_idx), ...
        result_table.PASS_ABS_MAX_DB(row_idx), ...
        result_table.RIPPLE_PP_DB(row_idx), ...
        result_table.STOP_ATTN_DB(row_idx), ...
        result_table.GROWTH_BITS(row_idx), ...
        result_table.FULL_PRECISION_WIDTH(row_idx), ...
        result_table.PASS_WITHOUT_COMPENSATION(row_idx));
end
fprintf(fid, '\nAll CIC orders require passband compensation before RTL.\n');

plot_order_search(fullfile(figure_dir, 'cic_order_search.png'), ...
    metric_list, result_table, F_PASS_HIGH, F_STOP_BEGIN);


function magnitude = cic_passband_magnitude(frequency_hz, ...
        input_rate_hz, rate_change, diff_delay, cic_order)
    numerator = sin(pi*frequency_hz*diff_delay/input_rate_hz);
    denominator = rate_change*diff_delay * ...
        sin(pi*frequency_hz/(rate_change*input_rate_hz));
    if abs(frequency_hz) < 1e-15
        ratio = 1;
    else
        ratio = numerator/denominator;
    end
    magnitude = abs(ratio)^cic_order;
end


function plot_order_search(file_path, metric_list, result_table, ...
        pass_edge, stop_begin)
    colors = [0.20 0.39 0.63; 0.10 0.60 0.49; 0.28 0.15 0.49];
    color_yellow = [0.82 0.88 0.05];
    figure('Color', 'w', 'Position', [80 80 1480 900]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    for idx = 1:numel(metric_list)
        plot(metric_list{idx}.f/1e3, metric_list{idx}.H_db, ...
            'Color', colors(idx, :), 'LineWidth', 1.7); hold on;
    end
    xline(pass_edge/1e3, '--', 'Color', [0.10 0.60 0.49]);
    yline(0.01, '--', 'Color', color_yellow);
    yline(-0.01, '--', 'Color', color_yellow);
    xlim([0 22]); ylim([-0.3 0.04]);
    title('未补偿通带下垂'); xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    legend('N=3', 'N=4', 'N=5', '20 kHz', '+/-0.01 dB', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    bar(result_table.CIC_ORDER, -result_table.CIC_DROOP_20K_DB, ...
        0.58, 'FaceColor', colors(1, :));
    title('20 kHz CIC 下垂'); xlabel('CIC 阶数 N'); ylabel('下垂 / dB');
    style_axes(gca);

    nexttile;
    for idx = 1:numel(metric_list)
        plot(metric_list{idx}.f/1e3, metric_list{idx}.H_db, ...
            'Color', colors(idx, :), 'LineWidth', 1.2); hold on;
    end
    xline(stop_begin/1e3, '--', 'Color', colors(2, :));
    yline(-70, '--', 'Color', color_yellow);
    xlim([0 500]); ylim([-140 5]);
    title('首个镜像区'); xlabel('频率 / kHz'); ylabel('幅度 / dB');
    style_axes(gca);

    nexttile;
    yyaxis left;
    plot(result_table.CIC_ORDER, result_table.FULL_PRECISION_WIDTH, ...
        '-o', 'Color', colors(3, :), 'LineWidth', 1.8, ...
        'MarkerFaceColor', colors(3, :));
    ylabel('全精度位宽 / bit');
    yyaxis right;
    plot(result_table.CIC_ORDER, result_table.STOP_ATTN_DB, ...
        '-s', 'Color', colors(2, :), 'LineWidth', 1.8, ...
        'MarkerFaceColor', colors(2, :));
    ylabel('总阻带衰减 / dB'); xlabel('CIC 阶数 N');
    title('位增长与阻带权衡'); style_axes(gca);

    sgtitle('Phase 7-A：16x CIC 阶数搜索', 'FontWeight', 'bold');
    exportgraphics(gcf, file_path, 'Resolution', 200);
end


function style_axes(ax)
    grid(ax, 'on'); box(ax, 'on');
    ax.FontName = 'Microsoft YaHei';
    ax.FontSize = 11;
    ax.LineWidth = 1.1;
    ax.XMinorTick = 'off';
    ax.YMinorTick = 'off';
end
