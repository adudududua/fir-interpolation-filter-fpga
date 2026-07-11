clc; clear;

%=============================================================
% 文件名       : v3_02_export_stage1_rtl.m
% 脚本名       : v3_02_export_stage1_rtl
% 功能简述     : 将已复核的 Stage 1 严格半带保守候选拆分为
%                true-polyphase RTL 所需的纯延迟相和对称滤波相，
%                自动导出 Verilog 头文件、系数清单和摘要。
%
%                输出文件：
%                  stage1_strict_rtl_manifest.csv
%                  stage1_strict_rtl_summary.txt
%                  sources_1/new/all2x_v3/
%                    all2x_v3_stage1_coeff_pkg.vh
%
% 当前默认配置：
%                  FIR 长度        ：105 tap
%                  小数位宽        ：Q15
%                  滤波相长度      ：52 tap
%                  对称 MAC 对数   ：26
%                  纯延迟相延迟    ：26 个输入样点
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB / Vivado
% 修订记录     :
%                2026-07-11：新增 Stage 1 strict-halfband RTL 导出。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
workspace_dir = fileparts(fileparts(script_dir));
rtl_dir = fullfile(workspace_dir, ...
    'XC7A35T_interp_audio_pcm_wordlen_opt', ...
    'XC7A35T_interp.srcs', 'sources_1', 'new', 'all2x_v3');
selected_path = fullfile(script_dir, ...
                         'stage1_strict_halfband_selected.mat');

if ~exist(selected_path, 'file')
    error('请先运行 v3_01_select_stage1_pareto.m。');
end
load(selected_path, 'selected_table', 'selected_config');

selected_idx = find(strcmp(selected_table.NAME, 'conservative_A'), ...
                    1, 'first');
if isempty(selected_idx)
    error('找不到 conservative_A 候选。');
end

cfg = selected_config{selected_idx}(1);
coeff_int = int64(cfg.coeff_int(:).');
tap_count = numel(coeff_int);
center_idx = (tap_count + 1) / 2;
phase0 = coeff_int(1:2:end);
phase1 = coeff_int(2:2:end);

if tap_count ~= 105 || cfg.frac_w ~= 15
    error('当前 RTL 导出要求 105 tap Q15，实际为 %d tap Q%d。', ...
          tap_count, cfg.frac_w);
end
if coeff_int(center_idx) ~= int64(2^cfg.frac_w)
    error('严格半带中心系数不是 2^FRAC_W。');
end
if nnz(phase0) ~= 1 || phase0((numel(phase0)+1)/2) ~= 2^cfg.frac_w
    error('phase0 未退化为纯延迟相。');
end
if any(phase1 ~= fliplr(phase1))
    error('phase1 系数不满足严格对称。');
end

pair_coeff = phase1(1:numel(phase1)/2);
pair_count = numel(pair_coeff);
history_len = numel(phase1);
delay_samples = (numel(phase0) - 1) / 2;

if ~exist(rtl_dir, 'dir')
    mkdir(rtl_dir);
end

manifest_table = table((0:pair_count-1).', pair_coeff(:), ...
    'VariableNames', {'PAIR_INDEX', 'COEFF_INT'});
writetable(manifest_table, fullfile(script_dir, ...
           'stage1_strict_rtl_manifest.csv'));

summary_path = fullfile(script_dir, 'stage1_strict_rtl_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Stage 1 strict-halfband RTL export summary\n');
fprintf(fid, '==========================================\n');
fprintf(fid, 'Taps                = %d\n', tap_count);
fprintf(fid, 'FRAC_W              = %d\n', cfg.frac_w);
fprintf(fid, 'COEFF_W             = %d\n', cfg.coeff_w_design);
fprintf(fid, 'ACC_W               = %d\n', cfg.acc_w_recommended);
fprintf(fid, 'Filter phase length = %d\n', history_len);
fprintf(fid, 'MAC pair count      = %d\n', pair_count);
fprintf(fid, 'Delay phase samples = %d\n', delay_samples);
fprintf(fid, 'Phase0 sum int      = %.0f\n', sum(phase0));
fprintf(fid, 'Phase1 sum int      = %.0f\n', sum(phase1));
fprintf(fid, 'Pair checksum       = %.0f\n', ...
        sum(double(pair_coeff).*(1:pair_count)));
fclose(fid);

header_path = fullfile(rtl_dir, 'all2x_v3_stage1_coeff_pkg.vh');
fid = fopen(header_path, 'w');
fprintf(fid, '`ifndef ALL2X_V3_STAGE1_COEFF_PKG_VH\n');
fprintf(fid, '`define ALL2X_V3_STAGE1_COEFF_PKG_VH\n\n');
fprintf(fid, '//=============================================================\n');
fprintf(fid, '// 文件名       : all2x_v3_stage1_coeff_pkg.vh\n');
fprintf(fid, '// 功能简述     : Stage 1 strict-halfband true-polyphase 系数。\n');
fprintf(fid, '//                本文件由 v3_02_export_stage1_rtl.m 自动生成。\n');
fprintf(fid, '//\n');
fprintf(fid, '// 设计作者     : kafeizizi\n');
fprintf(fid, '// 创建日期     : 2026-07-11\n');
fprintf(fid, '// 版本         : V2018.3\n');
fprintf(fid, '// 开发工具     : MATLAB / Vivado\n');
fprintf(fid, '// 修订记录     :\n');
fprintf(fid, '//                2026-07-11：新增 Stage 1 严格半带系数。\n');
fprintf(fid, '//=============================================================\n\n');
fprintf(fid, '`define V3_S1_TAPS          %d\n', tap_count);
fprintf(fid, '`define V3_S1_FRAC_W        %d\n', cfg.frac_w);
fprintf(fid, '`define V3_S1_COEFF_W       %d\n', cfg.coeff_w_design);
fprintf(fid, '`define V3_S1_ACC_W         %d\n', cfg.acc_w_recommended);
fprintf(fid, '`define V3_S1_HISTORY_LEN   %d\n', history_len);
fprintf(fid, '`define V3_S1_PAIR_COUNT    %d\n', pair_count);
fprintf(fid, '`define V3_S1_DELAY_INDEX   %d\n\n', delay_samples-1);

for pair_idx = 1:pair_count
    coeff_value = pair_coeff(pair_idx);
    if coeff_value < 0
        fprintf(fid, '`define V3_S1_C%02d (-%d''sd%d)\n', ...
                pair_idx-1, cfg.coeff_w_design, abs(coeff_value));
    else
        fprintf(fid, '`define V3_S1_C%02d (%d''sd%d)\n', ...
                pair_idx-1, cfg.coeff_w_design, coeff_value);
    end
end

fprintf(fid, '\n`endif\n');
fclose(fid);

fprintf('Stage 1 RTL 系数已导出：%s\n', header_path);
