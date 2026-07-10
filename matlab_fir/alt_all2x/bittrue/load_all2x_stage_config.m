function stage_config = load_all2x_stage_config(design_dir, data_w)
%=============================================================
% 文件名       : load_all2x_stage_config.m
% 函数名       : load_all2x_stage_config
% 功能简述     : 读取全 2x MATLAB 设计汇总及逐级整数系数，并生成
%                bit-true 仿真和 RTL 导出共用的逐级配置结构体。
%
%                本函数同时计算：
%                  1. 实际最小有符号系数字长；
%                  2. 两相直流增益；
%                  3. 理论最小累加器位宽；
%                  4. 建议累加器位宽（最小值加 1 位保护位）。
%
% 当前默认配置：
%                  数据位宽：24bit signed
%                  插值结构：7 级 2x
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增全 2x 配置读取与位宽估算函数。
%=============================================================

    if nargin < 1 || isempty(design_dir)
        design_dir = fullfile(fileparts(mfilename('fullpath')), '..');
    end

    if nargin < 2 || isempty(data_w)
        data_w = 24;
    end

    summary_path = fullfile(design_dir, 'all2x_interp128_summary.txt');
    if ~exist(summary_path, 'file')
        error('未找到全 2x 设计汇总：%s', summary_path);
    end

    summary_text = fileread(summary_path);
    pattern = ['Stage\s+(\d+):\s+Fs\s+([0-9.]+)\s+->\s+([0-9.]+)\s+Hz,\s+' ...
               'f_stop=([0-9.]+)\s+Hz,\s+order=(\d+),\s+taps=(\d+),\s+' ...
               'COEFF_W=(\d+),\s+FRAC_W=(\d+),\s+prune=(\d+),\s+nz_half=(\d+)'];
    token_list = regexp(summary_text, pattern, 'tokens');

    if numel(token_list) ~= 7
        error('设计汇总中应包含 7 级配置，实际解析到 %d 级。', numel(token_list));
    end

    stage_config = struct([]);
    x_max = 2^(data_w - 1) - 1;

    for idx = 1:numel(token_list)
        token = token_list{idx};
        stage_idx = str2double(token{1});
        coeff_path = fullfile(design_dir, ...
            sprintf('stage%02d_2x_coeff_decimal.txt', stage_idx));

        if ~exist(coeff_path, 'file')
            error('未找到 Stage %d 整数系数：%s', stage_idx, coeff_path);
        end

        coeff_int = int64(dlmread(coeff_path));
        coeff_int = coeff_int(:).';
        taps = str2double(token{6});
        frac_w = str2double(token{8});

        if numel(coeff_int) ~= taps
            error('Stage %d 系数数目为 %d，但汇总中的 tap 数为 %d。', ...
                  stage_idx, numel(coeff_int), taps);
        end

        if any(coeff_int ~= fliplr(coeff_int))
            error('Stage %d 整数系数不满足严格对称。', stage_idx);
        end

        phase0_int = coeff_int(1:2:end);
        phase1_int = coeff_int(2:2:end);
        phase_abs_sum = max(sum(abs(double(phase0_int))), ...
                            sum(abs(double(phase1_int))));
        acc_max = double(x_max) * phase_abs_sum;
        acc_w_min = max(2, ceil(log2(acc_max + 1)) + 1);

        stage_config(stage_idx).stage_idx = stage_idx;
        stage_config(stage_idx).Fs_in = str2double(token{2});
        stage_config(stage_idx).Fs_out = str2double(token{3});
        stage_config(stage_idx).f_stop_begin = str2double(token{4});
        stage_config(stage_idx).order_n = str2double(token{5});
        stage_config(stage_idx).taps = taps;
        stage_config(stage_idx).coeff_w_design = str2double(token{7});
        stage_config(stage_idx).frac_w = frac_w;
        stage_config(stage_idx).prune_thr = str2double(token{9});
        stage_config(stage_idx).nonzero_half = str2double(token{10});
        stage_config(stage_idx).coeff_int = coeff_int;
        stage_config(stage_idx).coeff_w_min = required_signed_width(coeff_int);
        stage_config(stage_idx).data_w = data_w;
        stage_config(stage_idx).acc_w_min = acc_w_min;
        stage_config(stage_idx).acc_w_recommended = acc_w_min + 1;
        stage_config(stage_idx).dc_gain = double(sum(coeff_int)) / 2^frac_w;
        stage_config(stage_idx).phase0_gain = double(sum(phase0_int)) / 2^frac_w;
        stage_config(stage_idx).phase1_gain = double(sum(phase1_int)) / 2^frac_w;
        stage_config(stage_idx).gain_mode = 'COEFF_X2';
    end
end


function coeff_w = required_signed_width(coeff_int)
    max_pos = max(coeff_int);
    min_neg = min(coeff_int);
    coeff_w = 2;

    while max_pos > int64(2^(coeff_w - 1) - 1) || ...
          min_neg < int64(-2^(coeff_w - 1))
        coeff_w = coeff_w + 1;
    end
end
