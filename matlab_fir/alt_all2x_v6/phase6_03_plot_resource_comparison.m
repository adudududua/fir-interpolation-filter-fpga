clc; clear; close all;

%=============================================================
% 文件名       : phase6_03_plot_resource_comparison.m
% 脚本名       : phase6_03_plot_resource_comparison
% 功能简述     : 绘制 Phase 6 独立链与板级资源对比图。
%                上图比较 Phase 5、三 DSP 候选和混合字长候选；
%                下图比较 Phase 5 与 Phase 6 最终板级实现。
%
%                输出文件：
%                  figures/phase6_resource_comparison.png
%
% 当前默认配置：
%                  独立链资源：综合后 Slice LUT / Register
%                  板级资源  ：实现后 Slice LUT / Register
%                  图片格式  ：PNG，白色背景，180 dpi
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 Phase 6 资源对比图。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
figure_dir = fullfile(script_dir, 'figures');
if ~exist(figure_dir, 'dir')
    mkdir(figure_dir);
end

independent_resource = [1379 1015; 1431 1052; 1224 867];
board_resource = [1536 1181; 1395 1040];

color_blue = [0.18 0.36 0.60];
color_purple = [0.27 0.15 0.47];
color_teal = [0.08 0.58 0.47];

fig = figure('Color', 'w', 'Position', [100 100 1320 820]);
t = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', ...
                'Padding', 'compact');

ax1 = nexttile(t, 1);
b1 = bar(ax1, independent_resource, 'grouped', 'BarWidth', 0.78);
b1(1).FaceColor = color_blue;
b1(2).FaceColor = color_purple;
style_axes(ax1);
set(ax1, 'XTickLabel', {'Phase 5 2 DSP', ...
    'Phase 6 3 DSP', 'Phase 6 混合字长'});
ylabel(ax1, '资源数量');
title(ax1, '独立七级插值链综合资源');
legend(ax1, {'Slice LUT', 'Register'}, 'Location', 'northeast', ...
       'Box', 'off');
ylim(ax1, [0 1650]);
add_bar_labels(ax1, b1);

ax2 = nexttile(t, 2);
b2 = bar(ax2, board_resource, 'grouped', 'BarWidth', 0.70);
b2(1).FaceColor = color_blue;
b2(2).FaceColor = color_teal;
style_axes(ax2);
set(ax2, 'XTickLabel', {'Phase 5 板级', 'Phase 6 板级'});
ylabel(ax2, '资源数量');
title(ax2, '完整板级实现资源');
legend(ax2, {'Slice LUT', 'Register'}, 'Location', 'northeast', ...
       'Box', 'off');
ylim(ax2, [0 1750]);
add_bar_labels(ax2, b2);

title(t, 'Phase 6 混合数据字长资源优化对比', ...
      'FontWeight', 'bold', 'FontSize', 17);

output_path = fullfile(figure_dir, ...
                       'phase6_resource_comparison.png');
exportgraphics(fig, output_path, 'Resolution', 180);
fprintf('已导出：%s\n', output_path);


function style_axes(ax)
    set(ax, 'FontName', 'Microsoft YaHei', 'FontSize', 11, ...
        'FontWeight', 'bold', 'LineWidth', 1.2, ...
        'TickDir', 'out', 'Box', 'on');
    grid(ax, 'on');
    ax.GridAlpha = 0.23;
    ax.MinorGridAlpha = 0;
    ax.XMinorTick = 'off';
    ax.YMinorTick = 'off';
end


function add_bar_labels(ax, bar_handle)
    for bar_idx = 1:numel(bar_handle)
        text(ax, bar_handle(bar_idx).XEndPoints, ...
            bar_handle(bar_idx).YEndPoints + 25, ...
            string(bar_handle(bar_idx).YData), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', ...
            'FontName', 'Microsoft YaHei', ...
            'FontWeight', 'bold', 'FontSize', 10);
    end
end
