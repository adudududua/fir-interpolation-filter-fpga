clc; clear; close all;

%=============================================================
% 文件名       : v2_05_export_stage23_polyphase.m
% 脚本名       : v2_05_export_stage23_polyphase
% 功能简述     : 从稳定版配置读取 Stage 2、Stage 3 整数系数，拆分
%                为偶相和奇相，并自动生成 Phase 2 RTL 头文件及
%                系数 manifest，作为 MATLAB/RTL 的单一系数来源。
%
%                输出文件：
%                  stage23_polyphase_manifest.csv
%                  stage23_polyphase_summary.txt
%                  sources_1/new/all2x_v2/all2x_v2_coeff_pkg.vh
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 Stage 2/3 两相系数自动导出。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
stable_dir = fullfile(script_dir, '..', 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
repo_dir = fileparts(fileparts(script_dir));
rtl_dir = fullfile(repo_dir, ...
    'XC7A35T_interp_audio_pcm_wordlen_opt', ...
    'XC7A35T_interp.srcs', 'sources_1', 'new', 'all2x_v2');

addpath(bittrue_dir);
stage_config = load_all2x_stage_config(stable_dir, 24);

stage_list = [2 3];
row_stage = [];
row_phase = [];
row_index = [];
row_value = [];
row_frac_w = [];
row_coeff_w = [];
row_checksum = [];

if ~exist(rtl_dir, 'dir')
    mkdir(rtl_dir);
end

header_path = fullfile(rtl_dir, 'all2x_v2_coeff_pkg.vh');
fid_h = fopen(header_path, 'w');
fprintf(fid_h, '`ifndef ALL2X_V2_COEFF_PKG_VH\n');
fprintf(fid_h, '`define ALL2X_V2_COEFF_PKG_VH\n\n');
fprintf(fid_h, '//=============================================================\n');
fprintf(fid_h, '// 文件名       : all2x_v2_coeff_pkg.vh\n');
fprintf(fid_h, '// 功能简述     : Stage 2/3 true-polyphase RTL 自动导出系数。\n');
fprintf(fid_h, '//                本文件由 v2_05_export_stage23_polyphase.m 生成。\n');
fprintf(fid_h, '//\n');
fprintf(fid_h, '// 设计作者     : kafeizizi\n');
fprintf(fid_h, '// 创建日期     : 2026-07-11\n');
fprintf(fid_h, '// 版本         : V2018.3\n');
fprintf(fid_h, '// 开发工具     : MATLAB / Vivado\n');
fprintf(fid_h, '// 修订记录     :\n');
fprintf(fid_h, '//                2026-07-11：新增 Stage 2/3 两相系数。\n');
fprintf(fid_h, '//=============================================================\n\n');

summary_path = fullfile(script_dir, 'stage23_polyphase_summary.txt');
fid_s = fopen(summary_path, 'w');
fprintf(fid_s, 'Stage 2/3 polyphase coefficient export\n');
fprintf(fid_s, '======================================\n');

for stage_idx = stage_list
    cfg = stage_config(stage_idx);
    phase_coeff = {cfg.coeff_int(1:2:end), cfg.coeff_int(2:2:end)};
    checksum = sum(double(1:numel(cfg.coeff_int)) .* ...
                   double(cfg.coeff_int));

    fprintf(fid_s, ['Stage %d: taps=%d coeff_w=%d frac_w=%d ' ...
                    'checksum=%.0f\n'], ...
            stage_idx, cfg.taps, cfg.coeff_w_min, cfg.frac_w, checksum);

    for phase_idx = 0:1
        coeff = phase_coeff{phase_idx + 1};
        fprintf(fid_s, '  phase%d = [%s]\n', phase_idx, ...
                strtrim(sprintf('%d ', coeff)));

        for coeff_idx = 1:numel(coeff)
            macro_name = sprintf('V2_S%d_P%d_C%d', ...
                stage_idx, phase_idx, coeff_idx - 1);
            value = double(coeff(coeff_idx));
            if value < 0
                literal = sprintf('(-%d''sd%d)', cfg.coeff_w_min, abs(value));
            else
                literal = sprintf('(%d''sd%d)', cfg.coeff_w_min, value);
            end
            fprintf(fid_h, '`define %-16s %s\n', macro_name, literal);

            row_stage(end+1, 1) = stage_idx;
            row_phase(end+1, 1) = phase_idx;
            row_index(end+1, 1) = coeff_idx - 1;
            row_value(end+1, 1) = value;
            row_frac_w(end+1, 1) = cfg.frac_w;
            row_coeff_w(end+1, 1) = cfg.coeff_w_min;
            row_checksum(end+1, 1) = checksum;
        end
        fprintf(fid_h, '\n');
    end
end

fprintf(fid_h, '`endif\n');
fclose(fid_h);
fclose(fid_s);

manifest = table(row_stage, row_phase, row_index, row_value, ...
                 row_frac_w, row_coeff_w, row_checksum, ...
    'VariableNames', {'STAGE', 'PHASE', 'INDEX', 'INTEGER_VALUE', ...
                      'FRAC_W', 'COEFF_W', 'CONFIG_CHECKSUM'});
writetable(manifest, ...
    fullfile(script_dir, 'stage23_polyphase_manifest.csv'));

fprintf('Stage 2/3 polyphase 系数、manifest 和 RTL 头文件导出完成。\n');
