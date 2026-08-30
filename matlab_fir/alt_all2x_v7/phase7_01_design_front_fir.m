%=============================================================
% 文件名      : phase7_01_design_front_fir.m
% 功能        : 重新生成 Phase7 正式前端 FIR 系数并与 RTL 基准逐项核对。
%               Stage1：105 taps 严格半带 FIR，44.1 -> 88.2 kHz；
%               Stage2：17 taps 等波纹 FIR，88.2 -> 176.4 kHz。
%               Stage3 的 11 taps 折叠 CIC 补偿由
%               phase7_05_search_folded_stage3.m 正式生成。
%
% 输出        : front_fir_results/phase7_front_fir_metrics.csv
%               front_fir_results/phase7_front_fir_summary.txt
%               front_fir_results/phase7_stage1_coeff_int.txt
%               front_fir_results/phase7_stage2_coeff_int.txt
%               front_fir_results/phase7_front_fir_design.mat
%               figures/phase7_front_fir_design.png
%=============================================================

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
v2_dir = fullfile(fileparts(script_dir), 'alt_all2x_v2');
reference_path = fullfile(v2_dir, 'stage1_strict_halfband_config.mat');
result_dir = fullfile(script_dir, 'front_fir_results');
figure_dir = fullfile(script_dir, 'figures');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
if ~exist(figure_dir, 'dir'); mkdir(figure_dir); end

FS_IN = 44100;
FS_STAGE1 = 88200;
FS_STAGE2 = 176400;
F_PASS_LOW = 10;
F_PASS_HIGH = 20000;
F_STOP_STAGE1 = 24100;
F_STOP_STAGE2 = 64100;
FRAC_W = 15;
COEFF_W = 17;
NFFT = 2^18;

fprintf('========================================================\n');
fprintf('Phase 7 正式前端 FIR 系数重新设计与 RTL 基准核对\n');
fprintf('Stage1: 44.1 kHz -> 88.2 kHz，105 taps 严格半带\n');
fprintf('Stage2: 88.2 kHz -> 176.4 kHz，17 taps 等波纹 FIR\n');
fprintf('========================================================\n\n');

%% 1）Stage1：严格半带设计与整数域校正
stage1_order = 104;
stage1_float = 2*firhalfband(stage1_order, ...
    F_PASS_HIGH/(FS_STAGE1/2));
stage1_coeff_int = quantize_strict_halfband(stage1_float, FRAC_W);
stage1_h = double(stage1_coeff_int)/2^FRAC_W;
stage1_metric = analyze_response(stage1_h, FS_STAGE1, 2, ...
    F_PASS_LOW, F_PASS_HIGH, F_STOP_STAGE1, NFFT);

%% 2）Stage2：按正式指标重新执行 Parks-McClellan 等波纹设计
stage2_order = 16;
stage2_ripple_pm_db = 0.006;
stage2_stop_db = 80;
delta_p = (10^(stage2_ripple_pm_db/20)-1) / ...
          (10^(stage2_ripple_pm_db/20)+1);
delta_s = 10^(-stage2_stop_db/20);
[~, fo, ao, weight] = firpmord([F_PASS_HIGH F_STOP_STAGE2], ...
    [1 0], [delta_p delta_s], FS_STAGE2);
stage2_float = 2*firpm(stage2_order, fo, ao, weight);
stage2_coeff_int = int64(round(stage2_float*2^FRAC_W));
stage2_h = double(stage2_coeff_int)/2^FRAC_W;
stage2_metric = analyze_response(stage2_h, FS_STAGE2, 2, ...
    F_PASS_LOW, F_PASS_HIGH, F_STOP_STAGE2, NFFT);

%% 3）与正式 RTL 配置使用的系数逐项核对
if ~exist(reference_path, 'file')
    error('缺少正式 FIR 配置：%s', reference_path);
end
reference = load(reference_path, 'best_config');
reference_stage1 = int64(reference.best_config(1).coeff_int(:).');
reference_stage2 = int64(reference.best_config(2).coeff_int(:).');
stage1_match = isequal(stage1_coeff_int(:).', reference_stage1);
stage2_match = isequal(stage2_coeff_int(:).', reference_stage2);
if ~stage1_match || ~stage2_match
    error('重新设计的 FIR 系数与正式 RTL 基准不一致。');
end

%% 4）构造前两级 4x 响应，作为进入折叠 Stage3 前的正式节点
stage1_up = zeros(1, 2*numel(stage1_h)-1);
stage1_up(1:2:end) = stage1_h;
front4_h = conv(stage1_up, stage2_h);
front4_metric = analyze_response(front4_h, FS_STAGE2, 4, ...
    F_PASS_LOW, F_PASS_HIGH, F_STOP_STAGE1, NFFT);

stage_name = {'Stage1 strict halfband'; 'Stage2 equiripple'; ...
              'Stage1+Stage2 front 4x'};
fs_out_hz = [FS_STAGE1; FS_STAGE2; FS_STAGE2];
taps = [numel(stage1_h); numel(stage2_h); numel(front4_h)];
frac_w = [FRAC_W; FRAC_W; NaN];
coeff_w = [COEFF_W; COEFF_W; NaN];
pass_abs_max_db = [stage1_metric.pass_abs_max_db; ...
                   stage2_metric.pass_abs_max_db; ...
                   front4_metric.pass_abs_max_db];
ripple_pp_db = [stage1_metric.ripple_pp_db; ...
                stage2_metric.ripple_pp_db; ...
                front4_metric.ripple_pp_db];
stop_attn_db = [stage1_metric.stop_attn_db; ...
                stage2_metric.stop_attn_db; ...
                front4_metric.stop_attn_db];
coeff_match_rtl = [stage1_match; stage2_match; true];
metric_table = table(stage_name, fs_out_hz, taps, frac_w, coeff_w, ...
    pass_abs_max_db, ripple_pp_db, stop_attn_db, coeff_match_rtl, ...
    'VariableNames', {'STAGE', 'FS_OUT_HZ', 'TAPS', 'FRAC_W', ...
    'COEFF_W', 'PASS_ABS_MAX_DB', 'RIPPLE_PP_DB', ...
    'STOP_ATTN_DB', 'COEFF_MATCH_RTL'});

csv_path = fullfile(result_dir, 'phase7_front_fir_metrics.csv');
summary_path = fullfile(result_dir, 'phase7_front_fir_summary.txt');
stage1_path = fullfile(result_dir, 'phase7_stage1_coeff_int.txt');
stage2_path = fullfile(result_dir, 'phase7_stage2_coeff_int.txt');
mat_path = fullfile(result_dir, 'phase7_front_fir_design.mat');
png_path = fullfile(figure_dir, 'phase7_front_fir_design.png');
writetable(metric_table, csv_path);
writematrix(stage1_coeff_int(:), stage1_path, 'Delimiter', 'tab');
writematrix(stage2_coeff_int(:), stage2_path, 'Delimiter', 'tab');
save(mat_path, 'stage1_coeff_int', 'stage2_coeff_int', ...
    'stage1_h', 'stage2_h', 'front4_h', 'metric_table');
write_summary(summary_path, metric_table, stage1_coeff_int, ...
    stage2_coeff_int);
plot_front_fir(png_path, stage1_metric, stage2_metric, ...
    front4_metric, F_PASS_HIGH, F_STOP_STAGE1, F_STOP_STAGE2);
drawnow;

disp(metric_table);
fprintf('\n================ 正式前端 FIR 设计结论 ================\n');
fprintf('Stage1 = %d taps，Q%d，%d bit，系数匹配 RTL = %d\n', ...
    numel(stage1_coeff_int), FRAC_W, COEFF_W, stage1_match);
fprintf('Stage2 = %d taps，Q%d，%d bit，系数匹配 RTL = %d\n', ...
    numel(stage2_coeff_int), FRAC_W, COEFF_W, stage2_match);
fprintf('前两级 4x 通带最大偏差 = %.8f dB\n', ...
    front4_metric.pass_abs_max_db);
fprintf('前两级 4x 阻带衰减     = %.8f dB\n', ...
    front4_metric.stop_attn_db);
fprintf('下一步：运行 phase7_05_search_folded_stage3.m 生成正式 Stage3。\n');
fprintf('CSV : %s\n', csv_path);
fprintf('TXT1: %s\n', summary_path);
fprintf('TXT2: %s\n', stage1_path);
fprintf('TXT3: %s\n', stage2_path);
fprintf('MAT : %s\n', mat_path);
fprintf('PNG : %s\n', png_path);
fprintf('最终判定：PASS\n');
fprintf('=======================================================\n');


% 5）局部函数模块：quantize_strict_halfband


% 功能说明：执行与 RTL 一致的定点量化、舍入、移位和饱和处理。
function coeff_int = quantize_strict_halfband(b_float, frac_w)
    coeff_int = int64(round(b_float(:).'*2^frac_w));
    center_idx = (numel(coeff_int)+1)/2;
    coeff_int(abs(b_float(:).') < 1e-12) = 0;
    coeff_int(center_idx) = int64(2^frac_w);
    coeff_int = int64(round((double(coeff_int) + ...
        fliplr(double(coeff_int)))/2));
    p0_idx = 1:2:numel(coeff_int);
    p1_idx = 2:2:numel(coeff_int);
    if any(p0_idx == center_idx)
        filtered_idx = p1_idx;
    else
        filtered_idx = p0_idx;
    end
    target_sum = int64(2^frac_w);
    delta = target_sum-sum(coeff_int(filtered_idx));
    if mod(delta, 2) ~= 0
        error('Stage1 整数相位和校正量不是偶数。');
    end
    coeff_int(center_idx-1) = coeff_int(center_idx-1)+delta/2;
    coeff_int(center_idx+1) = coeff_int(center_idx+1)+delta/2;
    if sum(coeff_int(p0_idx)) ~= target_sum || ...
            sum(coeff_int(p1_idx)) ~= target_sum
        error('Stage1 两相整数和校正失败。');
    end
end


% 6）局部函数模块：analyze_response


% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric = analyze_response(h, fs_hz, expected_gain, ...
        pass_low, pass_high, stop_begin, nfft)
    [H, f] = freqz(h, 1, nfft, fs_hz);
    H_db = 20*log10(abs(H/expected_gain)+1e-15);
    pass_index = f >= pass_low & f <= pass_high;
    stop_index = f >= stop_begin & f <= fs_hz/2;
    pass_response = H_db(pass_index);
    metric.f = f;
    metric.H_db = H_db;
    metric.pass_abs_max_db = max(abs(pass_response));
    metric.ripple_pp_db = max(pass_response)-min(pass_response);
    metric.stop_attn_db = -max(H_db(stop_index));
end


% 7）局部函数模块：required_signed_width


% 功能说明：封装 required_signed_width 对应的局部计算，供主流程复用并保持代码层次清晰。
function coeff_w = required_signed_width(coeff_int)
    coeff_w = 2;
    while max(coeff_int) > int64(2^(coeff_w-1)-1) || ...
            min(coeff_int) < int64(-2^(coeff_w-1))
        coeff_w = coeff_w+1;
    end
end


% 8）局部函数模块：write_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_summary(filename, metric_table, stage1_coeff, stage2_coeff)
    fid = fopen(filename, 'w');
    if fid < 0; error('无法创建总结文件：%s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Phase 7 formal front FIR coefficient design\n');
    fprintf(fid, '===========================================\n');
    fprintf(fid, 'Stage1: strict halfband, 105 taps, Q15/17bit\n');
    fprintf(fid, 'Stage2: equiripple, 17 taps, Q15/17bit\n');
    fprintf(fid, 'Both regenerated coefficient sets match RTL baseline.\n\n');
    for idx = 1:height(metric_table)
        fprintf(fid, ['%s: Fs=%.0f taps=%d pass=%.10f dB ' ...
            'ripple=%.10f dB stop=%.10f dB match=%d\n'], ...
            metric_table.STAGE{idx}, metric_table.FS_OUT_HZ(idx), ...
            metric_table.TAPS(idx), metric_table.PASS_ABS_MAX_DB(idx), ...
            metric_table.RIPPLE_PP_DB(idx), ...
            metric_table.STOP_ATTN_DB(idx), ...
            metric_table.COEFF_MATCH_RTL(idx));
    end
    fprintf(fid, '\nStage1 coeff_int:\n'); fprintf(fid, '%d ', stage1_coeff);
    fprintf(fid, '\n\nStage2 coeff_int:\n'); fprintf(fid, '%d ', stage2_coeff);
    fprintf(fid, '\n');
end


% 9）局部函数模块：plot_front_fir


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function plot_front_fir(filename, stage1, stage2, front4, ...
        pass_edge, stop1, stop2)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_yellow = [0.82 0.88 0.05];
    figure('Name', 'Phase 7 - 正式前端FIR系数设计', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [70 45 1540 900]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    plot(stage1.f/1e3, stage1.H_db, 'Color', color_purple, ...
        'LineWidth', 1.5); hold on;
    xline(pass_edge/1e3, '--', 'Color', color_green);
    xline(stop1/1e3, '--', 'Color', color_green);
    yline(-70, '--', 'Color', color_yellow);
    xlim([0 44.1]); ylim([-120 5]);
    title('Stage1：105 taps 严格半带 FIR');
    xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    legend('Stage1', '20 kHz', '24.1 kHz', '-70 dB', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(stage2.f/1e3, stage2.H_db, 'Color', color_blue, ...
        'LineWidth', 1.5); hold on;
    xline(pass_edge/1e3, '--', 'Color', color_green);
    xline(stop2/1e3, '--', 'Color', color_green);
    yline(-70, '--', 'Color', color_yellow);
    xlim([0 88.2]); ylim([-120 5]);
    title('Stage2：17 taps 等波纹 FIR');
    xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    legend('Stage2', '20 kHz', '64.1 kHz', '-70 dB', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(front4.f/1e3, front4.H_db, 'Color', color_purple, ...
        'LineWidth', 1.8); hold on;
    yline(0.05, '--', 'Color', color_yellow);
    yline(-0.05, '--', 'Color', color_yellow);
    xline(pass_edge/1e3, '--', 'Color', color_green);
    xlim([0 22]); ylim([-0.06 0.06]);
    title('前两级 4x 级联通带'); xlabel('频率 / kHz');
    ylabel('相对幅度 / dB');
    legend('Stage1 + Stage2', '+0.05 dB', '-0.05 dB', '20 kHz', ...
        'Location', 'southwest'); style_axes(gca);

    nexttile;
    plot(front4.f/1e3, front4.H_db, 'Color', color_blue, ...
        'LineWidth', 1.45); hold on;
    yline(-70, '--', 'Color', color_yellow);
    xline(stop1/1e3, '--', 'Color', color_green);
    xlim([20 88.2]); ylim([-130 5]);
    title('前两级 4x 级联阻带'); xlabel('频率 / kHz');
    ylabel('相对幅度 / dB');
    legend('Stage1 + Stage2', '-70 dB', '24.1 kHz', ...
        'Location', 'southwest'); style_axes(gca);
    sgtitle('Phase 7 正式前端 FIR：系数设计、量化与 4x 级联验证');
    exportgraphics(gcf, filename, 'Resolution', 220);
end


% 10）局部函数模块：style_axes


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function style_axes(ax)
    grid(ax, 'on'); box(ax, 'on');
    ax.FontName = 'Microsoft YaHei';
    ax.FontSize = 11;
    ax.LineWidth = 1.1;
    ax.XMinorTick = 'on'; ax.YMinorTick = 'on';
    ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';
end
