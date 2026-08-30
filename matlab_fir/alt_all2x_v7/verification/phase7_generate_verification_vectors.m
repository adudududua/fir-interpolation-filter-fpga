function phase7_generate_verification_vectors(profile_name)
%=============================================================
% 文件名       : phase7_generate_verification_vectors.m
% 函数名       : phase7_generate_verification_vectors
% 功能简述     : 生成 Phase 7 完整顶层和 CIC 定向回归向量。
%                输出半满幅冲激、固定多种子随机 PCM、4x/8x/
%                128x 位真 golden，以及包含直流、满幅交替和
%                合法输入动态范围边界的 CIC 20bit 定向序列。
%
%                输出目录：
%                  verification/vectors/<profile>/
%                  verification/reports/
%
% 当前默认配置：
%                  回归档位：daily，4 seed x 1024 input
%                  比较标准：所有导出节点 0 LSB
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-14
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-14：新增 Phase 7 补充验证向量生成器。
%=============================================================
% 1）主函数模块：phase7_generate_verification_vectors
% 功能说明：运行规定工况的自动验证，汇总误差并给出通过或失败结论。
% 输入、输出、定点规则和结果文件由下方参数及代码段具体定义。


    if nargin < 1 || isempty(profile_name)
        profile_name = 'daily';
    end
    verify_dir = fileparts(mfilename('fullpath'));
    config_dir = fullfile(verify_dir, 'config');
    addpath(config_dir);
    addpath(verify_dir);
    CFG = phase7_verify_config(profile_name);

    vector_dir = fullfile(verify_dir, 'vectors', CFG.PROFILE);
    report_dir = fullfile(verify_dir, 'reports');
    for one_dir = {vector_dir, report_dir}
        if ~exist(one_dir{1}, 'dir')
            mkdir(one_dir{1});
        end
    end

    impulse = zeros(1, CFG.IMPULSE_INPUT_COUNT, 'int64');
    impulse(1) = int64(2^(CFG.INPUT_W-2));
    impulse_result = phase7_build_bittrue_case(impulse, CFG);
    write_case(vector_dir, 'impulse', impulse_result, CFG.INPUT_W);

    row_case = {'impulse'};
    row_input = numel(impulse);
    row_y4 = numel(impulse_result.y4_24);
    row_y8 = numel(impulse_result.y8_24);
    row_y128 = numel(impulse_result.y128_24);
    row_saturation = total_saturation(impulse_result);

    for seed_idx = 1:numel(CFG.SEEDS)
        rng(CFG.SEEDS(seed_idx), 'twister');
        random_limit = int64(2^(CFG.RANDOM_PEAK_BITS-1));
        random_input = int64(randi( ...
            [-double(random_limit), double(random_limit-1)], ...
            1, CFG.NUM_RANDOM_INPUT));
        random_result = phase7_build_bittrue_case(random_input, CFG);
        case_name = sprintf('random_seed%02d', seed_idx);
        write_case(vector_dir, case_name, random_result, CFG.INPUT_W);

        row_case{end+1, 1} = case_name; %#ok<AGROW>
        row_input(end+1, 1) = numel(random_input); %#ok<AGROW>
        row_y4(end+1, 1) = numel(random_result.y4_24); %#ok<AGROW>
        row_y8(end+1, 1) = numel(random_result.y8_24); %#ok<AGROW>
        row_y128(end+1, 1) = numel(random_result.y128_24); %#ok<AGROW>
        row_saturation(end+1, 1) = total_saturation(random_result); %#ok<AGROW>
    end

    directed_input = make_cic_directed_input(CFG);
    directed_profile = zeros(1, 2*CFG.CIC_N);
    [directed_output, directed_stat, directed_trace] = ...
        cic_interp16_bittrue(directed_input, CFG.CIC_R, CFG.CIC_N, ...
        CFG.CIC_M, CFG.CIC_INPUT_W, CFG.CIC_INPUT_W, directed_profile);
    write_signed_hex_mem(fullfile(vector_dir, ...
        'cic_directed_input_20bit.mem'), directed_input, CFG.CIC_INPUT_W);
    write_signed_hex_mem(fullfile(vector_dir, ...
        'cic_directed_golden_20bit.mem'), directed_output, CFG.CIC_INPUT_W);

    manifest = table(row_case, row_input, row_y4, row_y8, row_y128, ...
        row_saturation, 'VariableNames', {'CASE_NAME', 'INPUT_COUNT', ...
        'Y4_COUNT', 'Y8_COUNT', 'Y128_COUNT', 'SATURATION_COUNT'});
    writetable(manifest, fullfile(report_dir, ...
        sprintf('phase7_%s_vector_manifest.csv', CFG.PROFILE)));
    save(fullfile(report_dir, sprintf( ...
        'phase7_%s_vector_metadata.mat', CFG.PROFILE)), ...
        'CFG', 'manifest', 'impulse_result', 'directed_input', ...
        'directed_output', 'directed_stat', 'directed_trace');
    write_generation_summary(fullfile(report_dir, sprintf( ...
        'phase7_%s_vector_generation_summary.txt', CFG.PROFILE)), ...
        CFG, manifest, directed_stat, directed_trace);

    disp(manifest);
    fprintf(['Phase 7 %s verification vectors generated. ' ...
        'CIC directed wrap count=%d.\n'], CFG.PROFILE, ...
        directed_stat.modulo_wrap_count);
end


% 2）局部函数模块：write_case


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_case(vector_dir, case_name, result, data_w)
    write_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_input_24bit.mem']), result.input, data_w);
    write_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y4_golden_24bit.mem']), result.y4_24, data_w);
    write_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y8_golden_24bit.mem']), result.y8_24, data_w);
    write_signed_hex_mem(fullfile(vector_dir, ...
        [case_name '_y128_golden_24bit.mem']), result.y128_24, data_w);
end


% 3）局部函数模块：total_saturation


% 功能说明：执行与 RTL 一致的定点量化、舍入、移位和饱和处理。
function count = total_saturation(result)
    count = result.stat.stage1.output_sat_count + ...
        result.stat.bridge1.output_sat_count + ...
        result.stat.stage2.output_sat_count + ...
        result.stat.bridge2.output_sat_count + ...
        result.stat.stage3.output_sat_count + ...
        result.stat.cic.output_sat_count;
end


% 4）局部函数模块：make_cic_directed_input


% 功能说明：检查目标目录是否存在，并在缺失时创建，保证后续文件导出路径有效。
function x = make_cic_directed_input(CFG)
    max_value = int64(2^(CFG.CIC_INPUT_W-1)-1);
    min_value = int64(-2^(CFG.CIC_INPUT_W-1));
    rng(314159, 'twister');
    random_part = int64(randi( ...
        [double(min_value), double(max_value)], 1, 256));
    x = [int64([1 0 0 0 0 0]), ...
         repmat(int64(2^15), 1, 64), ...
         repmat(int64(-2^15), 1, 64), ...
         repmat([max_value min_value], 1, 128), ...
         int64([0 1 -1 max_value min_value max_value-1 min_value+1]), ...
         random_part];
end


% 5）局部函数模块：write_signed_hex_mem


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_signed_hex_mem(filename, data, data_w)
    digits = ceil(data_w/4);
    unsigned_data = mod(double(int64(data(:))), 2^data_w);
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建输出文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid));
    for sample_idx = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], ...
            unsigned_data(sample_idx));
    end
end


% 6）局部函数模块：write_generation_summary


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_generation_summary(filename, CFG, manifest, stat, trace)
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建总结文件：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid));
    fprintf(fid, 'Phase 7 verification vector generation\n');
    fprintf(fid, '======================================\n');
    fprintf(fid, 'Profile              : %s\n', CFG.PROFILE);
    fprintf(fid, 'Random seeds         : %d\n', numel(CFG.SEEDS));
    fprintf(fid, 'Random input / seed  : %d\n', CFG.NUM_RANDOM_INPUT);
    fprintf(fid, 'Expected shift 4x/8x : %d / %d\n', ...
        CFG.EXPECTED_SHIFT_4X, CFG.EXPECTED_SHIFT_8X);
    fprintf(fid, 'Expected shift 128x  : %d\n', CFG.EXPECTED_SHIFT_128X);
    fprintf(fid, 'IR length 4x/8x/128x: %d / %d / %d\n', ...
        CFG.IR_LEN_4X, CFG.IR_LEN_8X, CFG.IR_LEN_128X);
    fprintf(fid, 'Directed CIC vector  : %d\n', stat.input_count);
    fprintf(fid, 'Directed CIC flush   : %d valid zero samples\n', CFG.CIC_N);
    fprintf(fid, 'Directed CIC actual  : %d valid input samples\n', ...
        stat.input_count + CFG.CIC_N);
    fprintf(fid, 'Directed CIC output  : %d\n', stat.output_count);
    fprintf(fid, 'Directed CIC wraps   : %d\n', stat.modulo_wrap_count);
    fprintf(fid, 'Directed CIC sat     : %d\n', stat.output_sat_count);
    fprintf(fid, 'CIC stage widths     : %s\n', mat2str(trace.stage_width));
    fprintf(fid, 'CIC stage max abs    : %s\n\n', ...
        mat2str(trace.stage_max_abs));
    for row_idx = 1:height(manifest)
        fprintf(fid, '%s input=%d y4=%d y8=%d y128=%d sat=%d\n', ...
            manifest.CASE_NAME{row_idx}, manifest.INPUT_COUNT(row_idx), ...
            manifest.Y4_COUNT(row_idx), manifest.Y8_COUNT(row_idx), ...
            manifest.Y128_COUNT(row_idx), ...
            manifest.SATURATION_COUNT(row_idx));
    end
end
