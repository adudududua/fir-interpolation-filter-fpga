%% 1）主流程：phase7_07_plot_resource_comparison
% 功能说明：读取指标数据并生成带中文标注的报告或答辩展示图。

clc; clear; close all;

%=============================================================
% 文件名       : phase7_07_plot_resource_comparison.m
% 脚本名       : phase7_07_plot_resource_comparison
% 功能简述     : 生成 Phase 7 FIR-CIC 候选与 Phase 6 基线的资源
%                对比图。左图比较同口径独立插值链，右图比较完整
%                四档板级工程，输出 PNG 供报告和 README 引用。
%
% 当前默认配置：
%                  独立链：Phase6、独立补偿 N3/N4、折叠 N3/N4
%                  板级  ：Phase6 与 Phase7 折叠 N3
%                  输出  ：figures/phase7_resource_comparison.png
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 Phase 7 资源对比图。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
figure_dir = fullfile(script_dir, 'figures');
if ~exist(figure_dir, 'dir')
    mkdir(figure_dir);
end

color_blue = [0.20 0.39 0.63];
color_purple = [0.28 0.15 0.49];
color_green = [0.10 0.60 0.49];
color_yellow = [0.82 0.88 0.05];

chain_name = {'Phase 6', '独立 N3', '独立 N4', '折叠 N3', '折叠 N4'};
chain_lut = [1222 1199 1366 957 1116];
chain_ff = [868 1154 1243 791 876];
board_name = {'Phase 6', 'Phase 7 N3'};
board_lut = [1395 1128];
board_ff = [1040 964];

figure('Color', 'w', 'Position', [80 80 1500 720]);
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
bar_handle = bar(categorical(chain_name), [chain_lut(:), chain_ff(:)], ...
    'grouped');
bar_handle(1).FaceColor = color_blue;
bar_handle(2).FaceColor = color_purple;
yline(1222*0.85, '--', '15% LUT 门槛', 'Color', color_yellow, ...
    'LineWidth', 1.4, 'LabelHorizontalAlignment', 'left');
ylabel('资源数量');
title('128x 插值链独立综合');
legend('LUT', 'FF', 'Location', 'northwest');
ylim([0 1500]);
style_axes(gca);
add_bar_labels(bar_handle);

nexttile;
board_bar = bar(categorical(board_name), ...
    [board_lut(:), board_ff(:)], 'grouped');
board_bar(1).FaceColor = color_green;
board_bar(2).FaceColor = color_purple;
ylabel('资源数量');
title('完整四档板级实现');
legend('LUT', 'FF', 'Location', 'northwest');
ylim([0 1550]);
style_axes(gca);
add_bar_labels(board_bar);
text(1.5, 1450, sprintf('LUT -19.14%%\nFF -7.31%%\nDSP/BRAM 不变'), ...
    'HorizontalAlignment', 'center', 'Color', color_green, ...
    'FontWeight', 'bold', 'FontSize', 12);

sgtitle('Phase 7 折叠补偿 FIR-CIC 资源对比');
exportgraphics(gcf, fullfile(figure_dir, ...
    'phase7_resource_comparison.png'), 'Resolution', 180);


% 2）局部函数模块：add_bar_labels


% 功能说明：封装 add_bar_labels 对应的局部计算，供主流程复用并保持代码层次清晰。
function add_bar_labels(bar_handle)
    for series_idx = 1:numel(bar_handle)
        x_value = bar_handle(series_idx).XEndPoints;
        y_value = bar_handle(series_idx).YEndPoints;
        label = string(bar_handle(series_idx).YData);
        text(x_value, y_value+20, label, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontWeight', 'bold', ...
            'FontSize', 10);
    end
end


% 3）局部函数模块：style_axes


% 功能说明：生成或美化结果图，统一中文标签、刻度、线型和版面布局。
function style_axes(axis_handle)
    axis_handle.FontName = 'Microsoft YaHei';
    axis_handle.FontSize = 11;
    axis_handle.FontWeight = 'bold';
    axis_handle.LineWidth = 1.1;
    axis_handle.XMinorTick = 'off';
    axis_handle.YMinorTick = 'on';
    axis_handle.YMinorGrid = 'off';
    axis_handle.GridAlpha = 0.22;
    axis_handle.MinorGridAlpha = 0.10;
    grid(axis_handle, 'on');
    box(axis_handle, 'on');
end
