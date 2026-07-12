clc; clear;

%=============================================================
% 文件名       : generate_demo_sine_15k_44k1.m
% 脚本名       : generate_demo_sine_15k_44k1
% 功能简述     : 生成示波器插值粗糙度对比用 15kHz 单正弦 ROM。
%                输入采样率固定为 44.1kHz，147 个采样点正好
%                包含 50 个完整正弦周期，循环播放时首尾连续。
%
%                该测试信号用于对比：
%                  1x   ：44.1kHz，约 2.94 sample/cycle
%                  4x   ：176.4kHz，约 11.76 sample/cycle
%                  8x   ：352.8kHz，约 23.52 sample/cycle
%                  128x ：5.6448MHz，约 376.32 sample/cycle
%
%                输出文件：
%                  demo_sine_15k_44k1_24bit_147.mem
%
% 当前默认配置：
%                  采样率：44.1kHz
%                  正弦频率：15kHz
%                  数据位宽：24bit signed
%                  峰值幅度：0.80FS
%                  ROM 深度：147 点
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-12
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-12：新增四档插值粗糙度对比正弦 ROM。
%=============================================================

FS = 44100;
TONE_HZ = 15000;
DEPTH = 147;
AMPLITUDE = 0.80;
DATA_W = 24;

cycle_count = TONE_HZ * DEPTH / FS;
if abs(cycle_count - round(cycle_count)) > 1e-12
    error('ROM 深度没有包含整数个正弦周期。');
end

sample_index = 0:DEPTH-1;
tone = AMPLITUDE * sin(2*pi*TONE_HZ*sample_index/FS);
max_positive = 2^(DATA_W-1) - 1;
tone_q = round(tone * max_positive);

script_dir = fileparts(mfilename('fullpath'));
repo_dir = fileparts(script_dir);
output_dir = fullfile(repo_dir, ...
    'XC7A35T_interp_audio_pcm_wordlen_opt', ...
    'XC7A35T_interp.srcs', 'sources_1', 'new');
output_path = fullfile(output_dir, ...
    'demo_sine_15k_44k1_24bit_147.mem');

fid = fopen(output_path, 'w');
if fid == -1
    error('无法创建 ROM 文件：%s', output_path);
end

for sample_idx = 1:DEPTH
    value = tone_q(sample_idx);
    if value < 0
        value = value + 2^DATA_W;
    end
    fprintf(fid, '%06X\n', value);
end
fclose(fid);

fprintf('已生成：%s\n', output_path);
fprintf('采样率：%d Hz\n', FS);
fprintf('正弦频率：%d Hz\n', TONE_HZ);
fprintf('ROM 深度：%d 点，共 %.0f 个完整周期\n', DEPTH, cycle_count);
fprintf('1x/4x/8x/128x 每周期采样点：%.2f / %.2f / %.2f / %.2f\n', ...
    FS/TONE_HZ, 4*FS/TONE_HZ, 8*FS/TONE_HZ, 128*FS/TONE_HZ);
