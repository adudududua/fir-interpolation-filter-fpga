%% 1）主流程：v3_03_generate_stage1_rtl_golden
% 功能说明：整理计算结果并导出后续 RTL、仿真或报告流程需要的技术文件。

clc; clear;

%=============================================================
% 文件名       : v3_03_generate_stage1_rtl_golden.m
% 脚本名       : v3_03_generate_stage1_rtl_golden
% 功能简述     : 为 Stage 1 strict-halfband RTL 单元测试生成
%                冲激和随机 PCM 输入及对应的 24bit bit-true golden。
%
%                输出文件：
%                  golden/v3_stage1_impulse_input_24bit.mem
%                  golden/v3_stage1_impulse_golden_24bit.mem
%                  golden/v3_stage1_random_input_24bit.mem
%                  golden/v3_stage1_random_golden_24bit.mem
%                  stage1_strict_unit_golden_summary.txt
%
% 当前默认配置：
%                  数据位宽：24bit signed
%                  候选    ：105 tap Q15 conservative_A
%                  随机种子：20260711
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-11
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-11：新增 Stage 1 RTL 单元 golden。
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
stable_dir = fullfile(script_dir, '..', 'alt_all2x');
bittrue_dir = fullfile(stable_dir, 'bittrue');
addpath(bittrue_dir);

selected_path = fullfile(script_dir, ...
                         'stage1_strict_halfband_selected.mat');
if ~exist(selected_path, 'file')
    error('请先运行 v3_01_select_stage1_pareto.m。');
end
load(selected_path, 'selected_table', 'selected_config');

selected_idx = find(strcmp(selected_table.NAME, 'conservative_A'), ...
                    1, 'first');
cfg = selected_config{selected_idx}(1);

DATA_W = 24;
rng(20260711, 'twister');
impulse_input = int64([2^22 zeros(1, 255)]);
random_input = int64(randi([-2^20 2^20], 1, 128));

[impulse_golden, impulse_stat] = interp2_polyphase_bittrue( ...
    impulse_input, cfg.coeff_int, cfg.frac_w, DATA_W, ...
    cfg.acc_w_recommended);
[random_golden, random_stat] = interp2_polyphase_bittrue( ...
    random_input, cfg.coeff_int, cfg.frac_w, DATA_W, ...
    cfg.acc_w_recommended);

golden_dir = fullfile(script_dir, 'golden');
if ~exist(golden_dir, 'dir')
    mkdir(golden_dir);
end

write_signed_hex_mem(fullfile(golden_dir, ...
    'v3_stage1_impulse_input_24bit.mem'), impulse_input, DATA_W);
write_signed_hex_mem(fullfile(golden_dir, ...
    'v3_stage1_impulse_golden_24bit.mem'), impulse_golden, DATA_W);
write_signed_hex_mem(fullfile(golden_dir, ...
    'v3_stage1_random_input_24bit.mem'), random_input, DATA_W);
write_signed_hex_mem(fullfile(golden_dir, ...
    'v3_stage1_random_golden_24bit.mem'), random_golden, DATA_W);

summary_path = fullfile(script_dir, ...
                        'stage1_strict_unit_golden_summary.txt');
fid = fopen(summary_path, 'w');
fprintf(fid, 'Stage 1 strict-halfband RTL unit golden\n');
fprintf(fid, '=======================================\n');
fprintf(fid, 'Impulse input count  = %d\n', numel(impulse_input));
fprintf(fid, 'Impulse output count = %d\n', numel(impulse_golden));
fprintf(fid, 'Impulse overflow     = %d\n', ...
        impulse_stat.acc_overflow_count);
fprintf(fid, 'Impulse saturation   = %d\n', ...
        impulse_stat.output_sat_count);
fprintf(fid, 'Random input count   = %d\n', numel(random_input));
fprintf(fid, 'Random output count  = %d\n', numel(random_golden));
fprintf(fid, 'Random overflow      = %d\n', ...
        random_stat.acc_overflow_count);
fprintf(fid, 'Random saturation    = %d\n', ...
        random_stat.output_sat_count);
fclose(fid);

fprintf('Stage 1 单元 golden 已生成。\n');


% 2）局部函数模块：write_signed_hex_mem


% 功能说明：把计算指标、系数或总结内容写入指定技术文件，供复核和报告引用。
function write_signed_hex_mem(filename, data, data_w)
    digits = ceil(data_w / 4);
    unsigned_data = mod(double(int64(data(:))), 2^data_w);
    fid = fopen(filename, 'w');
    for data_idx = 1:numel(unsigned_data)
        fprintf(fid, ['%0' num2str(digits) 'X\n'], ...
                unsigned_data(data_idx));
    end
    fclose(fid);
end
