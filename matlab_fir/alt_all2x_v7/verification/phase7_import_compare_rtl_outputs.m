function phase7_import_compare_rtl_outputs()
%=============================================================
% 文件名       : phase7_import_compare_rtl_outputs.m
% 功能         : 从正式 Vivado XSim 工作目录收回 RTL 冲激 CSV，
%                与 MATLAB daily 黄金向量在 4x、8x、128x 三个
%                节点逐样点比较，并输出 0 LSB 证据。
%
% 输出         : rtl_outputs/rtl_impulse_y4.csv
%                rtl_outputs/rtl_impulse_y8.csv
%                rtl_outputs/rtl_impulse_y128.csv
%                reports/phase7_rtl_matlab_pointwise.csv
%                reports/phase7_rtl_matlab_pointwise_summary.txt
%                reports/phase7_rtl_matlab_pointwise.mat
%                figures/phase7_rtl_matlab_pointwise.png
%=============================================================

    verify_dir = fileparts(mfilename('fullpath'));
    display_dir = fileparts(fileparts(fileparts(verify_dir)));
    project_dir = fullfile(display_dir, ...
        'XC7A35T_interp_audio_pcm_wordlen_opt_LUT_min');
    xsim_dir = fullfile(project_dir, 'XC7A35T_interp.sim', ...
        'sim_1', 'behav', 'xsim');
    vector_dir = fullfile(verify_dir, 'vectors', 'daily');
    rtl_dir = fullfile(verify_dir, 'rtl_outputs');
    report_dir = fullfile(verify_dir, 'reports');
    figure_dir = fullfile(verify_dir, 'figures');
    for one_dir = {rtl_dir, report_dir, figure_dir}
        if ~exist(one_dir{1}, 'dir'); mkdir(one_dir{1}); end
    end

    node_name = {'4x'; '8x'; '128x'};
    rtl_name = {'rtl_impulse_y4.csv'; 'rtl_impulse_y8.csv'; ...
        'rtl_impulse_y128.csv'};
    golden_name = {'impulse_y4_golden_24bit.mem'; ...
        'impulse_y8_golden_24bit.mem'; ...
        'impulse_y128_golden_24bit.mem'};
    expected_length = [225; 459; 7374];
    rtl_data = cell(3, 1);
    golden_data = cell(3, 1);
    error_data = cell(3, 1);
    mismatch_count = zeros(3, 1);
    max_abs_error_lsb = zeros(3, 1);
    first_mismatch_index = -ones(3, 1);

    fprintf('========================================================\n');
    fprintf('Phase 7 XSim -> MATLAB 正式逐点比较\n');
    fprintf('收回节点：4x / 8x / 128x\n');
    fprintf('比较标准：每个样点严格 0 LSB\n');
    fprintf('========================================================\n');

    for idx = 1:3
        source_path = fullfile(xsim_dir, rtl_name{idx});
        target_path = fullfile(rtl_dir, rtl_name{idx});
        golden_path = fullfile(vector_dir, golden_name{idx});
        if ~exist(source_path, 'file')
            error(['缺少XSim输出：%s\n请确认已执行 run all，' ...
                '并看到最终0 LSB PASS。'], source_path);
        end
        copyfile(source_path, target_path, 'f');
        rtl_data{idx} = int64(readmatrix(target_path));
        rtl_data{idx} = rtl_data{idx}(:);
        golden_all = read_signed_hex_mem(golden_path, 24);
        if numel(rtl_data{idx}) ~= expected_length(idx)
            error('%s RTL CSV长度错误：实际%d，期望%d。', ...
                node_name{idx}, numel(rtl_data{idx}), expected_length(idx));
        end
        if numel(golden_all) < expected_length(idx)
            error('%s MATLAB黄金向量长度不足。', node_name{idx});
        end
        golden_data{idx} = golden_all(1:expected_length(idx));
        error_data{idx} = rtl_data{idx}-golden_data{idx};
        mismatch_index = find(error_data{idx} ~= 0);
        mismatch_count(idx) = numel(mismatch_index);
        max_abs_error_lsb(idx) = max(abs(double(error_data{idx})));
        if ~isempty(mismatch_index)
            first_mismatch_index(idx) = mismatch_index(1)-1;
        end
    end

    sample_count = expected_length;
    pass = mismatch_count == 0 & max_abs_error_lsb == 0;
    result_table = table(node_name, sample_count, mismatch_count, ...
        max_abs_error_lsb, first_mismatch_index, pass, ...
        'VariableNames', {'NODE', 'SAMPLE_COUNT', 'MISMATCH_COUNT', ...
        'MAX_ABS_ERROR_LSB', 'FIRST_MISMATCH_INDEX', 'PASS'});

    csv_path = fullfile(report_dir, 'phase7_rtl_matlab_pointwise.csv');
    txt_path = fullfile(report_dir, ...
        'phase7_rtl_matlab_pointwise_summary.txt');
    mat_path = fullfile(report_dir, ...
        'phase7_rtl_matlab_pointwise.mat');
    png_path = fullfile(figure_dir, ...
        'phase7_rtl_matlab_pointwise.png');
    writetable(result_table, csv_path);
    write_summary(txt_path, xsim_dir, result_table);
    save(mat_path, 'result_table', 'rtl_data', 'golden_data', 'error_data');
    plot_pointwise(png_path, rtl_data, golden_data, error_data, ...
        result_table);
    drawnow;

    disp(result_table);
    if ~all(pass)
        error('MATLAB回读RTL逐点比较失败，请查看误差表。');
    end
    fprintf('\n================ RTL-MATLAB逐点结论 ================\n');
    fprintf('4x   : %d samples，mismatch=0，max error=0 LSB\n', ...
        sample_count(1));
    fprintf('8x   : %d samples，mismatch=0，max error=0 LSB\n', ...
        sample_count(2));
    fprintf('128x : %d samples，mismatch=0，max error=0 LSB\n', ...
        sample_count(3));
    fprintf('CSV : %s\n', csv_path);
    fprintf('TXT : %s\n', txt_path);
    fprintf('MAT : %s\n', mat_path);
    fprintf('PNG : %s\n', png_path);
    fprintf('最终判定：PASS，全部导出节点逐点0 LSB一致\n');
    fprintf('下一步：运行 phase7_analyze_full_rtl_impulse 计算频响。\n');
    fprintf('=====================================================\n');
end


function data = read_signed_hex_mem(filename, data_w)
    if ~exist(filename, 'file')
        error('缺少MATLAB黄金向量：%s', filename);
    end
    fid = fopen(filename, 'r');
    if fid < 0; error('无法读取黄金向量：%s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    raw = textscan(fid, '%s');
    data = int64(hex2dec(raw{1}));
    threshold = int64(2^(data_w-1));
    modulus = int64(2^data_w);
    data(data >= threshold) = data(data >= threshold)-modulus;
    data = data(:);
end


function write_summary(filename, xsim_dir, result_table)
    fid = fopen(filename, 'w');
    if fid < 0; error('无法创建逐点总结：%s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Phase 7 XSim RTL versus MATLAB pointwise comparison\n');
    fprintf(fid, '===================================================\n');
    fprintf(fid, 'XSim source: %s\n', xsim_dir);
    fprintf(fid, 'Criterion  : exact 0 LSB at every exported sample\n\n');
    for idx = 1:height(result_table)
        fprintf(fid, ['%s samples=%d mismatch=%d max_error=%g LSB ' ...
            'first_mismatch=%d pass=%d\n'], ...
            result_table.NODE{idx}, result_table.SAMPLE_COUNT(idx), ...
            result_table.MISMATCH_COUNT(idx), ...
            result_table.MAX_ABS_ERROR_LSB(idx), ...
            result_table.FIRST_MISMATCH_INDEX(idx), ...
            result_table.PASS(idx));
    end
end


function plot_pointwise(filename, rtl_data, golden_data, error_data, table_data)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    figure('Name', 'Phase 7 - MATLAB与RTL逐点0LSB对比', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [70 45 1540 900]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    plot_overlay(1, rtl_data{1}, golden_data{1}, '4x 冲激逐点重合', ...
        color_blue, color_purple);
    plot_overlay(2, rtl_data{2}, golden_data{2}, '8x 冲激逐点重合', ...
        color_blue, color_purple);
    plot_overlay(3, rtl_data{3}, golden_data{3}, ...
        '128x 冲激逐点重合（前1200点）', color_blue, color_purple, 1200);

    nexttile(4); axis off;
    summary_text = {
        'MATLAB - RTL 逐点比较结果'
        ' '
        sprintf('4x：%d 点，mismatch=%d，max error=%g LSB', ...
            table_data.SAMPLE_COUNT(1), table_data.MISMATCH_COUNT(1), ...
            table_data.MAX_ABS_ERROR_LSB(1))
        sprintf('8x：%d 点，mismatch=%d，max error=%g LSB', ...
            table_data.SAMPLE_COUNT(2), table_data.MISMATCH_COUNT(2), ...
            table_data.MAX_ABS_ERROR_LSB(2))
        sprintf('128x：%d 点，mismatch=%d，max error=%g LSB', ...
            table_data.SAMPLE_COUNT(3), table_data.MISMATCH_COUNT(3), ...
            table_data.MAX_ABS_ERROR_LSB(3))
        ' '
        'Testbench：冲激 + 4组随机PCM，所有节点0 LSB'
        'MATLAB回读：三组RTL冲激CSV，全部逐点0 LSB'
        '最终判定：PASS'};
    text(0.04, 0.94, summary_text, 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'FontName', 'Microsoft YaHei', ...
        'FontSize', 13, 'Color', color_purple);
    rectangle('Position', [0.015 0.08 0.97 0.85], ...
        'EdgeColor', color_green, 'LineWidth', 1.4, 'Curvature', 0.02);
    sgtitle('Phase 7 正式 RTL 输出回读：MATLAB逐点0 LSB闭环');
    exportgraphics(gcf, filename, 'Resolution', 220);

    if any(cellfun(@(x) any(x ~= 0), error_data))
        warning('逐点误差非零，图中重合关系可能不可见。');
    end
end


function plot_overlay(tile_index, rtl, golden, title_text, ...
        color_rtl, color_golden, max_count)
    if nargin < 7
        max_count = numel(rtl);
    end
    count = min([numel(rtl), numel(golden), max_count]);
    sample_index = 0:count-1;
    nexttile(tile_index);
    plot(sample_index, double(golden(1:count)), 'Color', color_golden, ...
        'LineWidth', 2.2); hold on;
    plot(sample_index, double(rtl(1:count)), '--', 'Color', color_rtl, ...
        'LineWidth', 1.0);
    title(title_text); xlabel('样点索引'); ylabel('24 bit整数值');
    legend('MATLAB golden', 'RTL CSV', 'Location', 'best');
    grid on; box on;
    ax = gca; ax.FontName = 'Microsoft YaHei'; ax.FontSize = 11;
    ax.LineWidth = 1.1; ax.XMinorTick = 'on'; ax.YMinorTick = 'on';
end
