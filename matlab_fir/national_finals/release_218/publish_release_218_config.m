%=============================================================
% 文件名       : publish_release_218_config.m
% 脚本名       : publish_release_218_config
% 功能简述     : 整理计算结果并导出后续 RTL、仿真或报告流程需要的技术文件。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================

% Publish the board-verified 218-LUT configuration as machine-readable JSON.

%% 1）主流程：publish_release_218_config
% 功能说明：整理计算结果并导出后续 RTL、仿真或报告流程需要的技术文件。

clearvars;
script_dir = fileparts(mfilename('fullpath'));
nf_dir = fileparts(script_dir);
addpath(nf_dir);

config = nf_release_218_config();
json_text = jsonencode(config, PrettyPrint=true);
output_path = fullfile(script_dir, 'nf_release_218_config.json');
fid = fopen(output_path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Could not open release JSON: %s', output_path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', json_text);
fprintf('NF_RELEASE_218_CONFIG_PASS: %s\n', output_path);
