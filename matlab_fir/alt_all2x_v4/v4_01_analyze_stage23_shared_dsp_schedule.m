%=============================================================
% 文件名       : v4_01_analyze_stage23_shared_dsp_schedule.m
% 脚本名       : v4_01_analyze_stage23_shared_dsp_schedule
% 功能简述     : Stage 2/3 共享单 DSP 的周期预算与调度可行性分析。
%                脚本按 5.6448MHz 最终时钟建立 64 拍超周期，
%                使用 Stage 3 优先策略，并保守计入 1 拍派发开销。
%
%                输出文件：
%                  phase4_stage23_schedule.csv
%                  phase4_stage23_schedule_summary.txt
%
% 当前默认配置：
%                  Stage 2 CE 周期：32 拍
%                  Stage 3 CE 周期：16 拍
%                  Stage 2 MAC 数 ：phase0=5，phase1=4
%                  Stage 3 MAC 数 ：phase0=3，phase1=3
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-12
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-12：新增 Phase 4A 共享 DSP 调度分析。
%=============================================================

clear;
clc;

SCRIPT_DIR = fileparts(mfilename('fullpath'));
SUPER_PERIOD = 64;
DISPATCH_CYCLES = 1;

% phase 初值与 RTL 一致：第一次 CE 处理 phase1，之后交替。
stage2_arrival = [0 32];
stage2_phase = [1 0];
stage2_mac = [4 5];
stage2_deadline = stage2_arrival + 16;

stage3_arrival = [0 16 32 48];
stage3_phase = [1 0 1 0];
stage3_mac = [3 3 3 3];
stage3_deadline = stage3_arrival + 8;

stage = [2 2 3 3 3 3].';
phase = [stage2_phase stage3_phase].';
arrival = [stage2_arrival stage3_arrival].';
mac_count = [stage2_mac stage3_mac].';
deadline = [stage2_deadline stage3_deadline].';

job_count = numel(stage);
start_cycle = zeros(job_count, 1);
finish_cycle = zeros(job_count, 1);
slack_cycle = zeros(job_count, 1);
dispatch_order = zeros(job_count, 1);

pending = false(job_count, 1);
completed = false(job_count, 1);
current_cycle = 0;
order = 0;

while any(~completed)
    pending = pending | ((arrival <= current_cycle) & ~completed);

    ready_index = find(pending & ~completed);
    if isempty(ready_index)
        current_cycle = current_cycle + 1;
        continue;
    end

    % Stage 3 优先；同一级按到达时间和原始索引排序。
    priority_matrix = [-stage(ready_index), ...
                       arrival(ready_index), ready_index];
    [~, sorted_row] = sortrows(priority_matrix, [1 2 3]);
    selected = ready_index(sorted_row(1));

    order = order + 1;
    dispatch_order(selected) = order;
    start_cycle(selected) = current_cycle + DISPATCH_CYCLES;
    finish_cycle(selected) = start_cycle(selected) + mac_count(selected);
    slack_cycle(selected) = deadline(selected) - finish_cycle(selected);

    pending(selected) = false;
    completed(selected) = true;
    current_cycle = finish_cycle(selected);
end

pass = slack_cycle >= 0;
schedule_table = table(dispatch_order, stage, phase, arrival, mac_count, ...
    start_cycle, finish_cycle, deadline, slack_cycle, pass);
schedule_table = sortrows(schedule_table, 'dispatch_order');

csv_path = fullfile(SCRIPT_DIR, 'phase4_stage23_schedule.csv');
summary_path = fullfile(SCRIPT_DIR, ...
    'phase4_stage23_schedule_summary.txt');
writetable(schedule_table, csv_path);

worst_slack = min(schedule_table.slack_cycle);
all_pass = all(schedule_table.pass);
max_simultaneous_mac = max(stage2_mac) + max(stage3_mac);

fp = fopen(summary_path, 'w');
assert(fp >= 0, '无法创建调度 summary 文件。');
fprintf(fp, 'Phase 4 Stage 2/3 shared DSP schedule summary\n');
fprintf(fp, '================================================\n');
fprintf(fp, 'Super period cycles       = %d\n', SUPER_PERIOD);
fprintf(fp, 'Dispatch overhead cycles  = %d\n', DISPATCH_CYCLES);
fprintf(fp, 'Stage 2 CE period         = 32\n');
fprintf(fp, 'Stage 3 CE period         = 16\n');
fprintf(fp, 'Stage 2 consumer deadline = 16 cycles\n');
fprintf(fp, 'Stage 3 consumer deadline = 8 cycles\n');
fprintf(fp, 'Worst simultaneous MAC    = %d\n', max_simultaneous_mac);
fprintf(fp, 'Worst schedule slack      = %d cycles\n', worst_slack);
fprintf(fp, 'All jobs pass             = %d\n', all_pass);
fclose(fp);

disp(schedule_table);
fprintf('\nWorst schedule slack = %d cycles\n', worst_slack);
fprintf('All jobs pass        = %d\n', all_pass);
fprintf('CSV                  = %s\n', csv_path);
fprintf('Summary              = %s\n', summary_path);

assert(max_simultaneous_mac <= 8, ...
    '最坏同拍 MAC 数超过 Phase 4A 预算。');
assert(worst_slack >= 4, ...
    '保守调度余量低于 4 拍，禁止进入 Phase 4B。');
assert(all_pass, '存在共享 DSP deadline 违例。');
