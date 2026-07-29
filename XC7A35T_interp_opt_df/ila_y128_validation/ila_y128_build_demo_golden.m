function [steady_period, metadata] = ila_y128_build_demo_golden(force_rebuild)
%=============================================================
% 文件名       : ila_y128_build_demo_golden.m
% 函数名       : ila_y128_build_demo_golden
% 功能简述     : 读取板级 SW9 演示所用的 4.1kHz+15kHz 24bit ROM，
%                调用 Phase 7 正式整数位真模型，生成完整 128x 链
%                的稳态单周期 MATLAB 黄金结果。黄金周期可供 ILA
%                CSV 自动相位对齐和逐点 0 LSB 比较使用。
%
% 当前默认配置：
%                  输入采样率：44.1kHz
%                  输出采样率：5.6448MHz
%                  输入周期  ：441 点
%                  输出周期  ：441*128=56448 点
%                  正式链路  ：2x*2x*2x*CIC16，CIC N=3
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-20
% 版本         : V2018.3
% 开发工具     : MATLAB R2023a
% 修订记录     :
%                2026-07-20：新增板级 ILA 128x 黄金周期生成。
%=============================================================

    if nargin < 1
        force_rebuild = false;
    end

    script_dir = fileparts(mfilename('fullpath'));
    project_dir = fileparts(script_dir);
    workspace_dir = fileparts(project_dir);
    phase7_dir = fullfile(workspace_dir, 'matlab_fir', 'alt_all2x_v7');
    verify_dir = fullfile(phase7_dir, 'verification');
    config_dir = fullfile(verify_dir, 'config');
    result_dir = fullfile(script_dir, 'results');
    rom_path = fullfile(project_dir, 'XC7A35T_interp.srcs', ...
        'sources_1', 'new', 'ila_demo_mix_4k1_15k_441.mem');
    model_path = fullfile(verify_dir, 'phase7_build_bittrue_case.m');
    cache_path = fullfile(result_dir, ...
        'demo_y128_steady_period_24bit.mat');

    if ~exist(result_dir, 'dir')
        mkdir(result_dir);
    end
    if ~exist(rom_path, 'file')
        error('找不到 SW9 多音 ROM：%s', rom_path);
    end
    if ~exist(model_path, 'file')
        error('找不到 Phase 7 位真模型：%s', model_path);
    end

    rom_info = dir(rom_path);
    model_info = dir(model_path);
    source_stamp = [rom_info.datenum, model_info.datenum];
    if ~force_rebuild && exist(cache_path, 'file')
        cached = load(cache_path, 'steady_period', 'metadata', ...
            'source_stamp');
        if isfield(cached, 'source_stamp') && ...
                isequal(cached.source_stamp, source_stamp) && ...
                numel(cached.steady_period) == 441*128
            steady_period = int64(cached.steady_period(:));
            metadata = cached.metadata;
            metadata.cache_used = true;
            return;
        end
    end

    addpath(phase7_dir);
    addpath(verify_dir);
    addpath(config_dir);
    CFG = phase7_verify_config('daily');
    input_period = read_signed_hex_mem(rom_path, CFG.INPUT_W);
    if numel(input_period) ~= 441
        error('SW9 多音 ROM 长度应为 441，实际为 %d。', ...
            numel(input_period));
    end

    output_period_count = numel(input_period)*128;
    warmup_period_count = 8;
    model_period_count = 12;
    model_input = repmat(input_period(:).', 1, model_period_count);
    fprintf('正在生成 Phase 7 128x 位真黄金周期，请稍候...\n');
    bittrue = phase7_build_bittrue_case(model_input, CFG);
    y128 = int64(bittrue.y128_24(:));

    first_index = warmup_period_count*output_period_count+1;
    second_index = first_index+output_period_count;
    last_index = second_index+output_period_count-1;
    if last_index > numel(y128)
        error('位真模型输出长度不足，无法提取两个稳态周期。');
    end
    period_a = y128(first_index:second_index-1);
    period_b = y128(second_index:last_index);
    periodic_error = period_b-period_a;
    if any(periodic_error ~= 0)
        error(['MATLAB 黄金结果尚未进入严格周期稳态：' ...
            '周期间有 %d 个不一致点，最大误差 %d LSB。'], ...
            nnz(periodic_error), max(abs(periodic_error)));
    end

    steady_period = period_a;
    metadata.input_sample_rate_hz = CFG.FS_IN;
    metadata.output_sample_rate_hz = CFG.FS_128X;
    metadata.input_period_samples = numel(input_period);
    metadata.output_period_samples = output_period_count;
    metadata.warmup_period_count = warmup_period_count;
    metadata.cic_order = CFG.CIC_N;
    metadata.final_prune_lsb = CFG.CIC_PRUNE_LSB;
    metadata.rom_path = rom_path;
    metadata.model_path = model_path;
    metadata.cache_used = false;
    save(cache_path, 'steady_period', 'metadata', 'source_stamp');
    fprintf('黄金周期已生成：%d 个 24bit 样点。\n', ...
        numel(steady_period));
end


function data = read_signed_hex_mem(filename, data_w)
    fid = fopen(filename, 'r');
    if fid < 0
        error('无法读取 24bit ROM：%s', filename);
    end
    cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    raw = textscan(fid, '%s');
    unsigned_data = int64(hex2dec(raw{1}));
    threshold = int64(2^(data_w-1));
    modulus = int64(2^data_w);
    unsigned_data(unsigned_data >= threshold) = ...
        unsigned_data(unsigned_data >= threshold)-modulus;
    data = unsigned_data(:);
end
