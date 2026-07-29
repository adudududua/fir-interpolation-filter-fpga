function phase7_prepare_xsim_vectors()
%=============================================================
% 文件名       : phase7_prepare_xsim_vectors.m
% 功能         : 生成正式 daily MATLAB 黄金向量，并复制到 Vivado
%                XSim 工作目录。测试平台随后用 $readmemh 读取这些
%                文件，对 4x、8x、128x 三个节点执行 0 LSB 比较。
%
% 输出         : vectors/daily/*.mem
%                reports/phase7_xsim_vector_exchange.csv
%                reports/phase7_xsim_vector_exchange_summary.txt
%                <Vivado工程>/phase7_verification_vectors/daily/*.mem
%                <Vivado工程>/XC7A35T_interp.sim/sim_1/behav/xsim/*.mem
%=============================================================

    verify_dir = fileparts(mfilename('fullpath'));
    display_dir = fileparts(fileparts(fileparts(verify_dir)));
    project_dir = fullfile(display_dir, ...
        'XC7A35T_interp_audio_pcm_wordlen_opt_LUT_min');
    vector_dir = fullfile(verify_dir, 'vectors', 'daily');
    report_dir = fullfile(verify_dir, 'reports');
    archive_dir = fullfile(project_dir, ...
        'phase7_verification_vectors', 'daily');
    xsim_dir = fullfile(project_dir, 'XC7A35T_interp.sim', ...
        'sim_1', 'behav', 'xsim');

    fprintf('========================================================\n');
    fprintf('Phase 7 MATLAB -> XSim 正式黄金向量交换\n');
    fprintf('1) 重新生成 daily 冲激和4组随机PCM黄金向量\n');
    fprintf('2) 复制到正式工程归档目录和XSim工作目录\n');
    fprintf('========================================================\n');

    phase7_generate_verification_vectors('daily');

    for one_dir = {report_dir, archive_dir, xsim_dir}
        if ~exist(one_dir{1}, 'dir')
            mkdir(one_dir{1});
        end
    end

    required_files = required_daily_files();
    row_name = cell(numel(required_files), 1);
    row_bytes = zeros(numel(required_files), 1);
    row_archive = false(numel(required_files), 1);
    row_xsim = false(numel(required_files), 1);
    for idx = 1:numel(required_files)
        one_name = required_files{idx};
        source_path = fullfile(vector_dir, one_name);
        if ~exist(source_path, 'file')
            error('黄金向量生成后仍缺少文件：%s', source_path);
        end
        copyfile(source_path, fullfile(archive_dir, one_name), 'f');
        copyfile(source_path, fullfile(xsim_dir, one_name), 'f');
        info = dir(source_path);
        row_name{idx} = one_name;
        row_bytes(idx) = info.bytes;
        row_archive(idx) = exist(fullfile(archive_dir, one_name), ...
            'file') == 2;
        row_xsim(idx) = exist(fullfile(xsim_dir, one_name), 'file') == 2;
    end

    exchange_table = table(row_name, row_bytes, row_archive, row_xsim, ...
        'VariableNames', {'FILE_NAME', 'BYTES', ...
        'ARCHIVE_COPY_OK', 'XSIM_COPY_OK'});
    csv_path = fullfile(report_dir, 'phase7_xsim_vector_exchange.csv');
    txt_path = fullfile(report_dir, ...
        'phase7_xsim_vector_exchange_summary.txt');
    writetable(exchange_table, csv_path);
    write_summary(txt_path, vector_dir, archive_dir, xsim_dir, ...
        exchange_table);

    disp(exchange_table);
    fprintf('\n================ 向量交换结论 ================\n');
    fprintf('回归档位       = daily（冲激 + 4组随机PCM）\n');
    fprintf('逐点比较节点   = 4x / 8x / 128x\n');
    fprintf('比较标准       = 0 LSB，不允许X，不允许数量错误\n');
    fprintf('已复制文件数   = %d\n', height(exchange_table));
    fprintf('XSim工作目录   = %s\n', xsim_dir);
    fprintf('CSV            = %s\n', csv_path);
    fprintf('TXT            = %s\n', txt_path);
    fprintf('下一步：Vivado运行 tb_phase7_full_chain_bittrue。\n');
    fprintf('最终判定       = READY FOR XSIM\n');
    fprintf('================================================\n');
end


function names = required_daily_files()
    names = {'impulse_input_24bit.mem'; ...
        'impulse_y4_golden_24bit.mem'; ...
        'impulse_y8_golden_24bit.mem'; ...
        'impulse_y128_golden_24bit.mem'};
    for seed_idx = 1:4
        prefix = sprintf('random_seed%02d', seed_idx);
        names{end+1, 1} = [prefix '_input_24bit.mem']; %#ok<AGROW>
        names{end+1, 1} = [prefix '_y4_golden_24bit.mem']; %#ok<AGROW>
        names{end+1, 1} = [prefix '_y8_golden_24bit.mem']; %#ok<AGROW>
        names{end+1, 1} = [prefix '_y128_golden_24bit.mem']; %#ok<AGROW>
    end
    names{end+1, 1} = 'cic_directed_input_20bit.mem';
    names{end+1, 1} = 'cic_directed_golden_20bit.mem';
end


function write_summary(filename, vector_dir, archive_dir, xsim_dir, table_data)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建向量交换总结：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Phase 7 MATLAB to XSim vector exchange\n');
    fprintf(fid, '======================================\n');
    fprintf(fid, 'Profile       : daily\n');
    fprintf(fid, 'Source        : %s\n', vector_dir);
    fprintf(fid, 'Project copy  : %s\n', archive_dir);
    fprintf(fid, 'XSim work dir : %s\n', xsim_dir);
    fprintf(fid, 'File count    : %d\n', height(table_data));
    fprintf(fid, 'Total bytes   : %d\n', sum(table_data.BYTES));
    fprintf(fid, 'All archive OK: %d\n', all(table_data.ARCHIVE_COPY_OK));
    fprintf(fid, 'All XSim OK   : %d\n', all(table_data.XSIM_COPY_OK));
end
