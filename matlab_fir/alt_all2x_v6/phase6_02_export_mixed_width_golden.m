clc; clear;

%=============================================================
% 文件名       : phase6_02_export_mixed_width_golden.m
% 脚本名       : phase6_02_export_mixed_width_golden
% 功能简述     : 导出 Phase 6 混合字长 RTL 对拍 golden。
%                使用 24/22/20/18/18/18/18bit 级间 Q 格式，
%                对冲激和随机 PCM 生成 Stage 2、Stage 3 及完整
%                128x 输出，并统一恢复到 24bit PCM 标度。
%
%                输出文件：
%                  mixed_width_golden/
%                    phase6_*_input_24bit.mem
%                    phase6_stage2_*_golden_24bit.mem
%                    phase6_stage3_*_golden_24bit.mem
%                    phase6_full_*_golden_24bit.mem
%                    phase6_mixed_width_golden_summary.txt
%
% 当前默认配置：
%                  输入采样率：44.1kHz
%                  输出采样率：5.6448MHz
%                  字长配置  ：24/22/20/18/18/18/18bit
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-13
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-13：新增 Phase 6 混合字长 golden 导出。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
repo_matlab_dir = fileparts(script_dir);
stable_dir = fullfile(repo_matlab_dir, 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
v2_dir = fullfile(repo_matlab_dir, 'alt_all2x_v2');
source_golden_dir = fullfile(v2_dir, 'golden');
output_dir = fullfile(script_dir, 'mixed_width_golden');

addpath(bittrue_dir);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

load(fullfile(v2_dir, 'stage1_strict_halfband_config.mat'), ...
     'best_config');
best_config(3).coeff_int = int64(best_config(3).coeff_int) * 2;
best_config(3).frac_w = best_config(3).frac_w + 1;
best_config(3).acc_w_recommended = 40;

DATA_W = 24;
WIDTH_PROFILE = [24 22 20 18 18 18 18];

impulse_input = read_signed_hex_mem(fullfile(source_golden_dir, ...
    'stage1_strict_impulse_input_24bit.mem'), DATA_W);
random_input = read_signed_hex_mem(fullfile(source_golden_dir, ...
    'stage1_strict_random_input_24bit.mem'), DATA_W);

[impulse_stage, impulse_stat] = simulate_profile_with_stages( ...
    impulse_input, best_config, WIDTH_PROFILE, DATA_W);
[random_stage, random_stat] = simulate_profile_with_stages( ...
    random_input, best_config, WIDTH_PROFILE, DATA_W);

if impulse_stat.total_acc_overflow ~= 0 || ...
        impulse_stat.total_saturation ~= 0 || ...
        random_stat.total_acc_overflow ~= 0 || ...
        random_stat.total_saturation ~= 0
    error('混合字长 golden 生成发生溢出或饱和。');
end

write_signed_hex_mem(fullfile(output_dir, ...
    'phase6_impulse_input_24bit.mem'), impulse_input, DATA_W);
write_signed_hex_mem(fullfile(output_dir, ...
    'phase6_random_input_24bit.mem'), random_input, DATA_W);

write_signed_hex_mem(fullfile(output_dir, ...
    'phase6_stage2_impulse_golden_24bit.mem'), impulse_stage{2}, DATA_W);
write_signed_hex_mem(fullfile(output_dir, ...
    'phase6_stage2_random_golden_24bit.mem'), random_stage{2}, DATA_W);
write_signed_hex_mem(fullfile(output_dir, ...
    'phase6_stage3_impulse_golden_24bit.mem'), impulse_stage{3}, DATA_W);
write_signed_hex_mem(fullfile(output_dir, ...
    'phase6_stage3_random_golden_24bit.mem'), random_stage{3}, DATA_W);
write_signed_hex_mem(fullfile(output_dir, ...
    'phase6_full_impulse_golden_24bit.mem'), impulse_stage{7}, DATA_W);
write_signed_hex_mem(fullfile(output_dir, ...
    'phase6_full_random_golden_24bit.mem'), random_stage{7}, DATA_W);

summary_path = fullfile(output_dir, ...
                        'phase6_mixed_width_golden_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Phase 6 mixed-width RTL golden\n');
fprintf(fid, '================================\n');
fprintf(fid, 'width_profile = 24/22/20/18/18/18/18\n');
fprintf(fid, 'impulse_input = %d\n', numel(impulse_input));
fprintf(fid, 'random_input = %d\n', numel(random_input));
fprintf(fid, 'impulse_stage2 = %d\n', numel(impulse_stage{2}));
fprintf(fid, 'random_stage2 = %d\n', numel(random_stage{2}));
fprintf(fid, 'impulse_stage3 = %d\n', numel(impulse_stage{3}));
fprintf(fid, 'random_stage3 = %d\n', numel(random_stage{3}));
fprintf(fid, 'impulse_full = %d\n', numel(impulse_stage{7}));
fprintf(fid, 'random_full = %d\n', numel(random_stage{7}));
fprintf(fid, 'acc_overflow = 0\n');
fprintf(fid, 'saturation = 0\n');
fclose(fid);

fprintf('Phase 6 混合字长冲激/随机 golden 已导出。\n');


function [stage_output_24, chain_stat] = simulate_profile_with_stages( ...
        x, stage_config, width_profile, final_data_w)
    y = int64(x(:).');
    current_w = final_data_w;
    total_overflow = 0;
    total_saturation = 0;
    stage_output_24 = cell(1, numel(stage_config));

    for stage_idx = 1:numel(stage_config)
        target_w = width_profile(stage_idx);
        if target_w < current_w
            [y, boundary_stat] = round_shift_sat_signed( ...
                y, current_w-target_w, target_w);
            total_saturation = total_saturation + ...
                               boundary_stat.output_sat_count;
            current_w = target_w;
        end

        cfg = stage_config(stage_idx);
        [y, one_stat] = interp2_polyphase_bittrue( ...
            y, cfg.coeff_int, cfg.frac_w, current_w, ...
            cfg.acc_w_recommended);
        total_overflow = total_overflow + one_stat.acc_overflow_count;
        total_saturation = total_saturation + one_stat.output_sat_count;
        stage_output_24{stage_idx} = ...
            y * int64(2^(final_data_w-current_w));
    end

    chain_stat.total_acc_overflow = total_overflow;
    chain_stat.total_saturation = total_saturation;
end


function data = read_signed_hex_mem(filename, data_w)
    fid = fopen(filename, 'r');
    if fid < 0
        error('无法打开输入文件：%s', filename);
    end
    raw = textscan(fid, '%s');
    fclose(fid);
    unsigned_value = hex2dec(raw{1});
    data = int64(unsigned_value(:).');
    sign_threshold = int64(2^(data_w-1));
    modulus = int64(2^data_w);
    data(data >= sign_threshold) = data(data >= sign_threshold) - modulus;
end


function write_signed_hex_mem(filename, data, data_w)
    digits = ceil(data_w/4);
    unsigned_data = mod(double(int64(data(:))), 2^data_w);
    fid = fopen(filename, 'w');
    if fid < 0
        error('无法创建输出文件：%s', filename);
    end
    for sample_idx = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], ...
                unsigned_data(sample_idx));
    end
    fclose(fid);
end

