%% Generate figures and compact CSV evidence for the innovation report.
% Raw Vivado/MATLAB/XSim outputs stay in national_finals/_work.  Only the
% presentation assets written below are intended for the final report.

script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(fileparts(script_dir)));
work_root = fullfile(repo_root, 'matlab_fir', 'national_finals', '_work', ...
    'innovation_validation_20260815');
out_dir = fullfile(repo_root, 'submit', 'finally', 'reports', 'assets', ...
    'innovation_validation_20260815');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

set(groot, 'defaultFigureVisible', 'off');
set(groot, 'defaultAxesFontName', 'Arial');
set(groot, 'defaultAxesFontSize', 9);
colors = [0.35 0.50 0.66; 0.18 0.49 0.38; 0.70 0.30 0.30; ...
          0.55 0.39 0.63; 0.78 0.48 0.27];

%% Experiment 1: compensation response ablation.
resp = readtable(fullfile(work_root, 'experiment1', ...
    'experiment1_response_48k.csv'), 'VariableNamingRule', 'preserve');
f = figure('Color', 'w', 'Position', [100 100 1320 560]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile;
plot(resp.frequency_hz/1e3, resp.no_compensation, '--', 'Color', colors(3,:), ...
    'LineWidth', 1.4); hold on;
plot(resp.frequency_hz/1e3, resp.independent_3tap, '-', 'Color', colors(1,:), ...
    'LineWidth', 1.4);
plot(resp.frequency_hz/1e3, resp.joint_stage3_cic, '-', 'Color', colors(2,:), ...
    'LineWidth', 1.6);
yline(0.05, ':', 'Color', [0.45 0.45 0.45]);
yline(-0.05, ':', 'Color', [0.45 0.45 0.45]);
xlim([0 22]); ylim([-0.16 0.06]); grid on;
xlabel('Frequency (kHz)'); ylabel('Magnitude (dB)');
title('Passband detail');
legend({'No compensation','Independent 3-tap','Joint Stage3-CIC'}, ...
    'Location', 'southwest', 'Box', 'off');
nexttile;
plot(resp.frequency_hz/1e3, resp.no_compensation, '--', 'Color', colors(3,:), ...
    'LineWidth', 1.2); hold on;
plot(resp.frequency_hz/1e3, resp.independent_3tap, '-', 'Color', colors(1,:), ...
    'LineWidth', 1.2);
plot(resp.frequency_hz/1e3, resp.joint_stage3_cic, '-', 'Color', colors(2,:), ...
    'LineWidth', 1.4);
yline(-70, ':', 'Stopband specification', 'Color', [0.35 0.35 0.35]);
xlim([0 128]); ylim([-100 1]); grid on;
xlabel('Frequency (kHz), 48 kHz input / 128x output');
ylabel('Magnitude (dB)'); title('Full-band view');
sgtitle('Experiment 1 - Stage3/CIC compensation ablation');
exportgraphics(f, fullfile(out_dir, 'exp1_compensation_ablation.png'), ...
    'Resolution', 180); close(f);

%% Experiment 2: structural ablation from the genuine non-shared baseline.
variant = ["Direct parallel 24-bit"; "Stage1 TDM, tail DSP"; ...
    "Stage1 TDM, tail LUT"; "Canonical tail"; ...
    "S2/S3 shared polyphase"; "Strict-HB BRAM history"; ...
    "S2/S3 shared DSP"; "Compact round ACC40"; ...
    "Mixed-width independent core"];
lut = [9376;4604;5912;4302;3975;3222;1648;1379;1224];
ff = [4118;4178;4218;3678;3103;925;1016;1015;867];
dsp = [38;15;1;1;1;1;2;2;2];
bram_tile = [0;0;0;0;0;1;1;1;1];
tool = repmat("Vivado 2018.3", size(variant));
Tstruct = table(variant,lut,ff,dsp,bram_tile,tool);
writetable(Tstruct, fullfile(out_dir, 'exp2_structural_ablation.csv'));

f = figure('Color','w','Position',[100 100 1450 820]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile;
semilogy(1:numel(lut), lut, 'o-', 'Color', colors(1,:), 'LineWidth', 1.5, ...
    'MarkerFaceColor', colors(1,:)); hold on;
semilogy(1:numel(ff), ff, 's-', 'Color', colors(4,:), 'LineWidth', 1.5, ...
    'MarkerFaceColor', colors(4,:));
grid on; ylabel('Count (log scale)');
title('Experiment 2 - structural ablation from the non-shared baseline');
legend({'LUT','FF'},'Location','southwest','Box','off');
nexttile;
bar([dsp bram_tile], 'grouped'); grid on;
ylabel('Primitive count');
xticks(1:numel(variant)); xticklabels(variant); xtickangle(24);
legend({'DSP48E1','BRAM tile'},'Location','northeast','Box','off');
exportgraphics(f, fullfile(out_dir, 'exp2_structural_ablation.png'), ...
    'Resolution', 180); close(f);

%% Experiment 3: paired place/route recipes for two word-length points.
widths = ["24/22/20";"24/22/20";"24/22/20"; ...
          "24/20/20";"24/20/20";"24/20/20"];
recipe_names = ["explore";"default";"extra_timing"; ...
                "explore";"default";"extra_timing"];
lut_w = zeros(6,1); ff_w = zeros(6,1); wns = zeros(6,1); whs = zeros(6,1);
dirs = ["24_22_20_explore","24_22_20_default","24_22_20_extra_timing", ...
        "24_20_20_explore","24_20_20_default","24_20_20_extra_timing"];
for idx = 1:numel(dirs)
    kv = read_key_values(fullfile(work_root, 'experiment3', ...
        'implementation_recipes', dirs(idx), 'recipe_summary.txt'));
    lut_w(idx) = str2double(kv.LUT);
    ff_w(idx) = str2double(kv.FF);
    wns(idx) = str2double(kv.WNS_NS);
    whs(idx) = str2double(kv.WHS_NS);
end
Tword = table(widths,recipe_names,lut_w,ff_w,wns,whs, ...
    'VariableNames', {'word_length','recipe','lut','ff','wns_ns','whs_ns'});
writetable(Tword, fullfile(out_dir, 'exp3_wordlength_recipes.csv'));

f = figure('Color','w','Position',[100 100 1300 470]);
tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
nexttile; scatter(lut_w(1:3),ff_w(1:3),70,colors(1,:),'filled'); hold on;
scatter(lut_w(4:6),ff_w(4:6),70,colors(2,:),'filled'); grid on;
xlabel('LUT'); ylabel('FF'); title('Area');
legend({'24/22/20','24/20/20'},'Location','best','Box','off');
nexttile; scatter(lut_w(1:3),wns(1:3),70,colors(1,:),'filled'); hold on;
scatter(lut_w(4:6),wns(4:6),70,colors(2,:),'filled'); grid on;
xlabel('LUT'); ylabel('WNS (ns)'); title('Setup margin');
nexttile; scatter(lut_w(1:3),whs(1:3),70,colors(1,:),'filled'); hold on;
scatter(lut_w(4:6),whs(4:6),70,colors(2,:),'filled'); grid on;
xlabel('LUT'); ylabel('WHS (ns)'); title('Hold margin');
sgtitle('Experiment 3 - paired P&R recipes for stage word length');
exportgraphics(f, fullfile(out_dir, 'exp3_wordlength_pareto.png'), ...
    'Resolution', 180); close(f);

%% Experiment 4a: OOC constraint-frequency scan.
rows = [];
for mode = [2 1 0]
    for period = [12 10 8]
        token = strrep(sprintf('%.1f',period),'.','p');
        kv = read_key_values(fullfile(work_root, 'experiment4', 'fmax', ...
            sprintf('mode%d_period%sns',mode,token), 'core_ooc_summary.txt'));
        rows = [rows; mode, 2+mode, str2double(kv.CLOCK_MHZ), ...
            str2double(kv.INTERNAL_WNS_NS), str2double(kv.POST_ROUTE_LUT), ...
            str2double(kv.POST_ROUTE_FF)]; %#ok<AGROW>
    end
end
Tfmax = array2table(rows, 'VariableNames', ...
    {'cic_mode','dsp','clock_mhz','wns_ns','lut','ff'});
writetable(Tfmax, fullfile(out_dir, 'exp4_fmax_scan.csv'));

f = figure('Color','w','Position',[100 100 1050 560]);
hold on;
for idx = 1:3
    dsp_count = 5-idx;
    take = rows(:,2)==dsp_count;
    [freq, order] = sort(rows(take,3));
    vals = rows(take,4); vals = vals(order);
    plot(freq, vals, 'o-', 'LineWidth', 1.5, 'Color', colors(idx,:), ...
        'MarkerFaceColor', colors(idx,:));
end
yline(0,'k-'); grid on;
xlabel('Constraint frequency (MHz)'); ylabel('Internal WNS (ns)');
title('Experiment 4 - routed OOC frequency scan');
legend({'4 DSP','3 DSP','2 DSP'},'Location','southwest','Box','off');
exportgraphics(f, fullfile(out_dir, 'exp4_fmax_scan.png'), ...
    'Resolution', 180); close(f);

%% Experiment 4b: activity-annotated power.
power_dirs = ["dsp4_218lut","dsp3_239lut","dsp2_268lut"];
dsp_power = [4;3;2]; lut_power = [218;239;268];
static_w = zeros(3,1); dynamic_w = zeros(3,1); confidence = strings(3,1);
for idx = 1:3
    kv = read_key_values(fullfile(work_root,'experiment4','saif', ...
        power_dirs(idx),'power_saif_summary.txt'));
    static_w(idx) = str2double(kv.STATIC_W);
    dynamic_w(idx) = str2double(kv.DYNAMIC_W);
    confidence(idx) = string(kv.CONFIDENCE);
end
Tpower = table(dsp_power,lut_power,static_w,dynamic_w,confidence, ...
    'VariableNames',{'dsp','lut','static_w','dynamic_w','confidence'});
writetable(Tpower, fullfile(out_dir, 'exp4_saif_power.csv'));

f = figure('Color','w','Position',[100 100 900 520]);
b = bar([static_w dynamic_w],'stacked');
b(1).FaceColor = [0.51 0.57 0.63]; b(2).FaceColor = colors(5,:);
grid on; ylabel('Estimated power (W)');
xticklabels({'4 DSP / 218 LUT','3 DSP / 239 LUT','2 DSP / 268 LUT'});
title('Experiment 4 - SAIF-based board power (High confidence)');
legend({'Static','Dynamic'},'Location','northwest','Box','off');
for idx = 1:3
    text(idx,static_w(idx)+dynamic_w(idx)+0.004, ...
        sprintf('%.3f W',static_w(idx)+dynamic_w(idx)), ...
        'HorizontalAlignment','center');
end
exportgraphics(f, fullfile(out_dir, 'exp4_saif_power.png'), ...
    'Resolution', 180); close(f);

%% Experiment 5: same-tool OOC architecture comparison, when available.
cic = read_key_values(fullfile(work_root,'experiment5','ooc', ...
    'fir_cic_3dsp','core_ooc_summary.txt'));
all2x_summary = fullfile(work_root,'experiment5','ooc','all2x_2dsp', ...
    'all2x_core_ooc_summary.txt');
if exist(all2x_summary,'file')
    all2x = read_key_values(all2x_summary);
    architecture = ["FIR-CIC 24/20/20";"All-2x mixed width"];
    lut_a = [str2double(cic.POST_ROUTE_LUT); str2double(all2x.POST_ROUTE_LUT)];
    ff_a = [str2double(cic.POST_ROUTE_FF); str2double(all2x.POST_ROUTE_FF)];
    dsp_a = [str2double(cic.POST_ROUTE_DSP48E1); ...
        str2double(all2x.POST_ROUTE_DSP48E1)];
    ramb18_a = [str2double(cic.POST_ROUTE_RAMB18E1); ...
        str2double(all2x.POST_ROUTE_RAMB18E1)];
    wns_a = [str2double(cic.INTERNAL_WNS_NS); ...
        str2double(all2x.INTERNAL_WNS_NS)];
    Tarch = table(architecture,lut_a,ff_a,dsp_a,ramb18_a,wns_a, ...
        'VariableNames',{'architecture','lut','ff','dsp','ramb18','wns_ns'});
    writetable(Tarch, fullfile(out_dir, 'exp5_architecture_ooc.csv'));
    f = figure('Color','w','Position',[100 100 1100 500]);
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    nexttile; bar([lut_a ff_a]); grid on; ylabel('Count');
    xticklabels(architecture); xtickangle(10); title('Logic');
    legend({'LUT','FF'},'Location','northwest','Box','off');
    nexttile; bar([dsp_a ramb18_a]); grid on; ylabel('Primitive count');
    xticklabels(architecture); xtickangle(10); title('Dedicated resources');
    legend({'DSP48E1','RAMB18E1'},'Location','northwest','Box','off');
    sgtitle('Experiment 5 - same-tool architecture comparison');
    exportgraphics(f, fullfile(out_dir, 'exp5_architecture_ooc.png'), ...
        'Resolution', 180); close(f);
end

%% Experiment 6: exact N3 Hold architecture ablation.
hold_csv = fullfile(work_root,'experiment6','ooc','cic_hold_ooc.csv');
if exist(hold_csv,'file')
    Thold = readtable(hold_csv,'TextType','string');
    writetable(Thold, fullfile(out_dir, 'exp6_cic_hold_ablation.csv'));
    f = figure('Color','w','Position',[100 100 1050 470]);
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    nexttile;
    bar([Thold.LUT Thold.FF]); grid on; ylabel('Count');
    xticklabels({'Legacy N3 zero-insert','N3 Hold equivalent'});
    xtickangle(8); title('Logic resources');
    legend({'LUT','FF'},'Location','northwest','Box','off');
    nexttile;
    bar([Thold.DSP Thold.RAMB18]); grid on; ylabel('Primitive count');
    xticklabels({'Legacy N3 zero-insert','N3 Hold equivalent'});
    xtickangle(8); title('Dedicated resources');
    legend({'DSP48E1','RAMB18E1'},'Location','northwest','Box','off');
    sgtitle('Experiment 6 - exact N3 Hold architecture ablation');
    exportgraphics(f, fullfile(out_dir, 'exp6_cic_hold_ablation.png'), ...
        'Resolution', 180); close(f);
end

fprintf('REPORT_ASSETS_GENERATED=%s\n', out_dir);

function kv = read_key_values(path)
    text = fileread(path);
    lines = splitlines(string(text));
    kv = struct();
    for idx = 1:numel(lines)
        line = strtrim(lines(idx));
        pivot = strfind(line,'=');
        if isempty(pivot)
            continue;
        end
        key = matlab.lang.makeValidName(char(extractBefore(line,pivot(1))));
        value = char(extractAfter(line,pivot(1)));
        kv.(key) = strtrim(value);
    end
end
