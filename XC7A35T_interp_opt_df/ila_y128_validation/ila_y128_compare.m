function result = ila_y128_compare(csv_file, output_tag)
%=============================================================
% 文件名       : ila_y128_compare.m
% 函数名       : ila_y128_compare
% 功能简述     : 导入 Vivado ILA 导出的 24bit y128 CSV，自动查找
%                ila_final128_sample_w 探针，完成二进制补码转换、
%                MATLAB 黄金周期相位对齐、逐点误差统计、误差直方图
%                和频谱重合图输出。
%
% 使用方法     : result = ila_y128_compare( ...
%                    'captures/ila_y128_capture.csv');
%
% 验收标准     : 全部捕获样点与 MATLAB 黄金结果逐点 0 LSB。
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-20
% 版本         : V2018.3
% 开发工具     : MATLAB R2023a
% 修订记录     :
%                2026-07-20：新增 ILA-MATLAB 板级逐点验证闭环。
%=============================================================

    script_dir = fileparts(mfilename('fullpath'));
    if nargin < 2
        output_tag = '';
    end
    if nargin < 1 || isempty(csv_file)
        csv_file = fullfile(script_dir, 'captures', ...
            'ila_y128_capture.csv');
    elseif ~isfile(csv_file)
        csv_file = fullfile(script_dir, csv_file);
    end
    if ~isfile(csv_file)
        error(['找不到 ILA CSV：%s\n请先把 ila_final128_sample_w ' ...
            '设为 Hex，再从 Vivado 导出 CSV。'], csv_file);
    end

    if isempty(output_tag)
        result_dir = fullfile(script_dir, 'results');
        figure_dir = fullfile(script_dir, 'figures');
    else
        if isempty(regexp(output_tag, '^[A-Za-z0-9_-]+$', 'once'))
            error('output_tag 只能包含字母、数字、下划线和连字符。');
        end
        result_dir = fullfile(script_dir, 'results', output_tag);
        figure_dir = fullfile(script_dir, 'figures', output_tag);
    end
    if ~exist(result_dir, 'dir'); mkdir(result_dir); end
    if ~exist(figure_dir, 'dir'); mkdir(figure_dir); end

    [ila_data, capture_info] = read_vivado_ila_csv(csv_file);
    if numel(ila_data) < 128
        error('有效 y128 样点仅 %d 个，数量过少。', numel(ila_data));
    end
    if capture_info.demo_sync_present && ...
            ~all(capture_info.demo_sync_value == 1)
        error(['CSV 中 demo_audio_sync 不全为 1。请打开 SW9，等待至少 ' ...
            '0.5 秒后重新抓取。']);
    end

    [steady_period, golden_info] = ila_y128_build_demo_golden(false);
    repeat_count = ceil((numel(steady_period)+numel(ila_data)-1) / ...
        numel(steady_period));
    search_reference = repmat(steady_period, repeat_count, 1);
    search_reference = search_reference(1: ...
        numel(steady_period)+numel(ila_data)-1);
    [golden_data, alignment_offset, alignment_score] = ...
        align_periodic_reference(ila_data, search_reference);

    error_lsb = ila_data-golden_data;
    mismatch_index = find(error_lsb ~= 0);
    mismatch_count = numel(mismatch_index);
    max_abs_error_lsb = max(abs(error_lsb));
    rms_error_lsb = sqrt(mean(double(error_lsb).^2));
    pass = mismatch_count == 0;
    first_mismatch_index = -1;
    if ~isempty(mismatch_index)
        first_mismatch_index = mismatch_index(1)-1;
    end

    sample_index = (0:numel(ila_data)-1).';
    pointwise_table = table(sample_index, ila_data, golden_data, ...
        error_lsb, 'VariableNames', {'SAMPLE_INDEX', 'ILA_Y128', ...
        'MATLAB_GOLDEN', 'ERROR_LSB'});
    pointwise_csv = fullfile(result_dir, ...
        'ila_y128_pointwise_comparison.csv');
    summary_txt = fullfile(result_dir, ...
        'ila_y128_pointwise_summary.txt');
    result_mat = fullfile(result_dir, ...
        'ila_y128_pointwise_result.mat');
    figure_png = fullfile(figure_dir, ...
        'ila_y128_pointwise_error_histogram.png');
    writetable(pointwise_table, pointwise_csv);

    result.csv_file = csv_file;
    result.sample_count = numel(ila_data);
    result.alignment_offset = alignment_offset;
    result.alignment_score = alignment_score;
    result.mismatch_count = mismatch_count;
    result.max_abs_error_lsb = max_abs_error_lsb;
    result.rms_error_lsb = rms_error_lsb;
    result.first_mismatch_index = first_mismatch_index;
    result.pass = pass;
    result.capture_info = capture_info;
    result.golden_info = golden_info;
    result.pointwise_csv = pointwise_csv;
    result.summary_txt = summary_txt;
    result.result_mat = result_mat;
    result.figure_png = figure_png;
    save(result_mat, 'result', 'ila_data', 'golden_data', ...
        'error_lsb', 'pointwise_table');
    write_summary(summary_txt, result);
    plot_validation(figure_png, ila_data, golden_data, error_lsb, result);

    fprintf('\n================ ILA y128 逐点验证 ================\n');
    fprintf('捕获样点数     : %d\n', result.sample_count);
    fprintf('黄金对齐偏移   : %d / %d\n', alignment_offset, ...
        numel(steady_period));
    fprintf('不一致样点数   : %d\n', mismatch_count);
    fprintf('最大绝对误差   : %d LSB\n', max_abs_error_lsb);
    fprintf('RMS 误差       : %.6f LSB\n', rms_error_lsb);
    fprintf('最终判定       : %s\n', pass_text(pass));
    fprintf('逐点 CSV       : %s\n', pointwise_csv);
    fprintf('误差直方图     : %s\n', figure_png);
    fprintf('====================================================\n');
    if ~pass
        warning(['ILA y128 未达到逐点 0 LSB。请优先检查 SW9、Hex 进制、' ...
            'bit/ltx 是否配套，以及打开 SW9 后是否等待至少 0.5 秒。']);
    end
end


function [data, info] = read_vivado_ila_csv(filename)
    target_name = 'ila_final128_sample_w';
    raw_text = fileread(filename);
    lines = regexp(raw_text, '\r\n|\n|\r', 'split');
    header_index = 0;
    signal_column = 0;
    demo_column = 0;
    for line_idx = 1:numel(lines)
        if contains(lines{line_idx}, target_name)
            fields = split_csv_line(lines{line_idx});
            signal_match = find(contains(string(fields), target_name), 1);
            if ~isempty(signal_match)
                header_index = line_idx;
                signal_column = signal_match;
                demo_match = find(contains(string(fields), ...
                    'demo_audio_sync'), 1);
                if ~isempty(demo_match); demo_column = demo_match; end
                break;
            end
        end
    end
    if header_index == 0
        error('CSV 表头中找不到探针 %s。', target_name);
    end

    data = zeros(numel(lines)-header_index, 1, 'int64');
    demo_data = zeros(numel(lines)-header_index, 1, 'int64');
    data_count = 0;
    for line_idx = header_index+1:numel(lines)
        fields = split_csv_line(lines{line_idx});
        if numel(fields) < signal_column
            continue;
        end
        [valid_value, sample_value] = parse_24bit_value( ...
            fields{signal_column});
        if ~valid_value
            continue;
        end
        data_count = data_count+1;
        data(data_count) = sample_value;
        if demo_column > 0 && numel(fields) >= demo_column
            [valid_demo, demo_value] = parse_logic_value( ...
                fields{demo_column});
            if valid_demo
                demo_data(data_count) = demo_value;
            else
                demo_data(data_count) = -1;
            end
        end
    end
    data = data(1:data_count);
    demo_data = demo_data(1:data_count);
    if isempty(data)
        error(['找到了 y128 表头，但没有读到有效样点。请把该探针 ' ...
            'Radix 设为 Hex 后重新导出。']);
    end

    info.header_line = header_index;
    info.signal_column = signal_column;
    info.signal_name = target_name;
    info.value_format = '24bit two''s-complement Hex';
    info.demo_sync_present = demo_column > 0;
    info.demo_sync_value = demo_data;
end


function fields = split_csv_line(line_text)
    fields = regexp(line_text, ',', 'split');
    for idx = 1:numel(fields)
        token = strtrim(fields{idx});
        if numel(token) >= 2 && token(1) == '"' && token(end) == '"'
            token = token(2:end-1);
        end
        fields{idx} = strtrim(token);
    end
end


function [valid, value] = parse_24bit_value(token)
    valid = false;
    value = int64(0);
    token = strtrim(token);
    token = strrep(token, '_', '');
    token = regexprep(token, '^24''[hH]', '');
    token = regexprep(token, '^0[xX]', '');
    token = regexprep(token, '^[xX]"', '');
    token = regexprep(token, '"$', '');
    if isempty(token) || ~isempty(regexp(token, '[xXzZ]', 'once'))
        return;
    end

    if ~isempty(regexp(token, '^-[0-9]+$', 'once'))
        number = str2double(token);
        if number < -2^23 || number > 2^23-1
            return;
        end
        value = int64(number);
        valid = true;
        return;
    end
    if isempty(regexp(token, '^[0-9A-Fa-f]{1,6}$', 'once'))
        return;
    end
    unsigned_value = int64(hex2dec(token));
    if unsigned_value >= int64(2^23)
        unsigned_value = unsigned_value-int64(2^24);
    end
    value = unsigned_value;
    valid = true;
end


function [valid, value] = parse_logic_value(token)
    token = strtrim(token);
    token = regexprep(token, '^1''[bB]', '');
    valid = strcmp(token, '0') || strcmp(token, '1');
    value = int64(0);
    if valid; value = int64(str2double(token)); end
end


function [golden, best_offset, best_score] = ...
        align_periodic_reference(capture, reference)
    capture = int64(capture(:));
    reference = int64(reference(:));
    capture_count = numel(capture);
    reference_count = numel(reference);
    if reference_count < capture_count
        error('黄金搜索序列短于 ILA 捕获序列。');
    end

    scale = 2^23;
    capture_double = double(capture)/scale;
    reference_double = double(reference)/scale;
    fft_count = 2^nextpow2(reference_count+capture_count-1);
    correlation_full = ifft(fft(reference_double, fft_count).* ...
        fft(flipud(capture_double), fft_count), 'symmetric');
    dot_product = correlation_full(capture_count:reference_count);
    square_sum = cumsum([0; reference_double.^2]);
    window_energy = square_sum(capture_count+1:end)- ...
        square_sum(1:end-capture_count);
    score = window_energy+sum(capture_double.^2)-2*dot_product;

    candidate_count = min(64, numel(score));
    [~, candidates] = mink(score, candidate_count);
    best_metric = [inf, inf, inf];
    best_offset = candidates(1)-1;
    best_score = score(candidates(1));
    for candidate_idx = 1:numel(candidates)
        start_index = candidates(candidate_idx);
        trial = reference(start_index:start_index+capture_count-1);
        trial_error = capture-trial;
        trial_metric = [nnz(trial_error), ...
            max(abs(double(trial_error))), ...
            sum(abs(double(trial_error)))];
        if lexicographic_less(trial_metric, best_metric)
            best_metric = trial_metric;
            best_offset = start_index-1;
            best_score = score(start_index);
        end
    end
    golden = reference(best_offset+1:best_offset+capture_count);
end


function less = lexicographic_less(candidate, current)
    less = false;
    for idx = 1:numel(candidate)
        if candidate(idx) < current(idx)
            less = true;
            return;
        elseif candidate(idx) > current(idx)
            return;
        end
    end
end


function write_summary(filename, result)
    fid = fopen(filename, 'w');
    if fid < 0; error('无法创建验证总结：%s', filename); end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'ILA y128 versus MATLAB bit-true golden\n');
    fprintf(fid, '=======================================\n');
    fprintf(fid, 'ILA CSV             : %s\n', result.csv_file);
    fprintf(fid, 'Signal              : ila_final128_sample_w[23:0]\n');
    fprintf(fid, 'Stimulus            : SW9 coherent 4.1kHz + 15kHz ROM\n');
    fprintf(fid, 'Output sample rate  : %.0f Hz\n', ...
        result.golden_info.output_sample_rate_hz);
    fprintf(fid, 'Captured samples    : %d\n', result.sample_count);
    fprintf(fid, 'Alignment offset    : %d samples\n', ...
        result.alignment_offset);
    fprintf(fid, 'Mismatch count      : %d\n', result.mismatch_count);
    fprintf(fid, 'Maximum error       : %d LSB\n', ...
        result.max_abs_error_lsb);
    fprintf(fid, 'RMS error           : %.9f LSB\n', ...
        result.rms_error_lsb);
    fprintf(fid, 'First mismatch      : %d\n', ...
        result.first_mismatch_index);
    fprintf(fid, 'Criterion           : exact 0 LSB at every sample\n');
    fprintf(fid, 'Final result        : %s\n', pass_text(result.pass));
end


function plot_validation(filename, ila_data, golden_data, error_lsb, result)
    color_blue = [0.20 0.39 0.63];
    color_purple = [0.28 0.15 0.49];
    color_green = [0.10 0.60 0.49];
    color_red = [0.82 0.22 0.24];
    sample_rate = result.golden_info.output_sample_rate_hz;
    plot_count = min(1200, numel(ila_data));
    sample_index = 0:plot_count-1;

    figure('Name', 'ILA y128 - MATLAB 黄金结果逐点验证', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [60 40 1540 900]);
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    plot(sample_index, double(golden_data(1:plot_count)), ...
        'Color', color_purple, 'LineWidth', 2.1); hold on;
    plot(sample_index, double(ila_data(1:plot_count)), '--', ...
        'Color', color_blue, 'LineWidth', 1.0);
    title(sprintf('前 %d 点波形重合', plot_count));
    xlabel('128x 样点索引'); ylabel('24bit signed PCM');
    legend('MATLAB golden', 'ILA y128', 'Location', 'best');
    style_axes(gca);

    nexttile;
    plot(0:numel(error_lsb)-1, double(error_lsb), ...
        'Color', color_red, 'LineWidth', 1.0);
    yline(0, '--', 'Color', color_green);
    title(sprintf('逐点误差：mismatch=%d，max=%d LSB', ...
        result.mismatch_count, result.max_abs_error_lsb));
    xlabel('128x 样点索引'); ylabel('ILA - MATLAB / LSB');
    style_axes(gca);

    nexttile;
    if all(error_lsb == 0)
        histogram(double(error_lsb), [-0.5 0.5], ...
            'FaceColor', color_green);
        xlim([-1 1]);
    else
        histogram(double(error_lsb), 'BinMethod', 'integers', ...
            'FaceColor', color_blue);
    end
    title('逐点误差直方图'); xlabel('误差 / LSB'); ylabel('样点数');
    style_axes(gca);

    nexttile;
    [frequency, ila_spectrum] = make_spectrum(ila_data, sample_rate);
    [~, golden_spectrum] = make_spectrum(golden_data, sample_rate);
    plot(frequency/1e3, golden_spectrum, 'Color', color_purple, ...
        'LineWidth', 2.0); hold on;
    plot(frequency/1e3, ila_spectrum, '--', 'Color', color_blue, ...
        'LineWidth', 1.0);
    xlim([0 60]); ylim([-130 5]);
    xline(4.1, ':', '4.1kHz'); xline(15, ':', '15kHz');
    title('ILA 与 MATLAB 频谱重合');
    xlabel('频率 / kHz'); ylabel('相对幅度 / dB');
    legend('MATLAB golden', 'ILA y128', 'Location', 'best');
    style_axes(gca);

    sgtitle(sprintf(['24bit y128 板级闭环：%d 点，%s，' ...
        '最大误差 %d LSB'], result.sample_count, ...
        pass_text(result.pass), result.max_abs_error_lsb));
    exportgraphics(gcf, filename, 'Resolution', 220);
end


function [frequency, spectrum_db] = make_spectrum(data, sample_rate)
    data = double(data(:));
    sample_count = numel(data);
    index = (0:sample_count-1).';
    if sample_count > 1
        window = 0.5-0.5*cos(2*pi*index/(sample_count-1));
    else
        window = 1;
    end
    data = (data-mean(data)).*window;
    fft_count = 2^nextpow2(max(16384, sample_count));
    spectrum = abs(fft(data, fft_count));
    spectrum = spectrum(1:fft_count/2+1);
    spectrum_db = 20*log10(spectrum/max(max(spectrum), eps)+eps);
    frequency = (0:fft_count/2).'*sample_rate/fft_count;
end


function style_axes(ax)
    grid(ax, 'on'); box(ax, 'on');
    ax.FontName = 'Microsoft YaHei';
    ax.FontSize = 11;
    ax.LineWidth = 1.1;
    ax.XMinorTick = 'on';
    ax.YMinorTick = 'on';
    set_single_minor_tick(ax.XAxis, ax.XTick);
    set_single_minor_tick(ax.YAxis, ax.YTick);
end


function set_single_minor_tick(ruler, major_tick)
    if numel(major_tick) < 2 || ~isprop(ruler, 'MinorTickValues')
        return;
    end
    ruler.MinorTickValues = ...
        (major_tick(1:end-1)+major_tick(2:end))/2;
end


function text_value = pass_text(pass)
    if pass
        text_value = 'PASS';
    else
        text_value = 'FAIL';
    end
end
