%=============================================================
% 文件名       : wav_to_pcm_mem_step1_generate_test_audio.m
% 功能简述     : 生成一段 48kHz、24bit signed 的测试音频 ROM 数据
%                用于 FPGA FIR 插值链的音频 PCM 输入验证。
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-06-21
% 版本         : 2023a
% 开发工具     : MATLAB
% 修订记录     :
%                2026-06-21：生成 8192 点 48kHz 音频测试数据。
%=============================================================

clear;
clc;
close all;

%=============================================================
% 1）基本参数
%=============================================================
fs = 48000;              % 输入采样率：48kHz
N  = 1024;               % ROM 深度：1024点
t  = (0:N-1).' / fs;     % 时间轴，列向量

%=============================================================
% 2）构造一段“像音频”的测试信号
%
% 不只用单一正弦，而是使用多个频率分量叠加：
%   440Hz  ：类似 A4 音
%   880Hz  ：二次谐波
%   1760Hz ：高频谐波
%
% 再乘以一个慢变化包络，让示波器上能看到音频包络变化。
%=============================================================
tone1 = 0.60 * sin(2*pi*440  * t);
tone2 = 0.25 * sin(2*pi*880  * t);
tone3 = 0.15 * sin(2*pi*1760 * t);

envelope = 0.65 + 0.35 * sin(2*pi*5*t);   % 5Hz 慢包络

x = envelope .* (tone1 + tone2 + tone3);

%=============================================================
% 3）归一化，避免溢出
%=============================================================
x = x / max(abs(x));
x = 0.85 * x;            % 留一点余量，避免后面量化顶到满幅

%=============================================================
% 4）量化为 24bit signed PCM
%
% 24bit signed 范围：
%   最大值：  2^23 - 1 =  8388607
%   最小值： -2^23     = -8388608
%=============================================================
MAX24 = 2^23 - 1;
MIN24 = -2^23;

x_q = round(x * MAX24);

x_q(x_q > MAX24) = MAX24;
x_q(x_q < MIN24) = MIN24;

x_q = int32(x_q);

%=============================================================
% 5）写出 Verilog readmemh 可读取的 .mem 文件
%
% 每一行一个 24bit 十六进制补码数据。
%=============================================================

% 获取当前脚本所在目录
script_full_path = mfilename('fullpath');
script_dir = fileparts(script_full_path);

% 如果脚本不是作为文件运行，而是在命令行直接粘贴运行，
% mfilename 可能为空，此时使用当前 MATLAB 工作目录
if isempty(script_dir)
    script_dir = pwd;
end

% 输出文件夹
out_dir = fullfile(script_dir, 'audio_data');

% 如果 audio_data 文件夹不存在，则创建
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% 输出 mem 文件路径
mem_file = fullfile(out_dir, 'audio_48k_24bit_1024.mem');

% 打开文件
fid = fopen(mem_file, 'w');

% 检查是否打开成功
if fid == -1
    error('无法创建 mem 文件，请检查当前路径是否有写入权限：%s', mem_file);
end

% 写入 24bit 十六进制补码数据
for i = 1:N
    val = x_q(i);

    % 如果是负数，转换成 24bit 二进制补码
    if val < 0
        val_u = 2^24 + double(val);
    else
        val_u = double(val);
    end

    fprintf(fid, '%06X\n', val_u);
end

fclose(fid);

%=============================================================
% 6）同时保存一个 wav 文件，方便电脑试听
%=============================================================
wav_file = fullfile(out_dir, 'audio_48k_test_1024.wav');
audiowrite(wav_file, x, fs);

disp('生成完成！');
disp('MEM 文件路径：');
disp(mem_file);
disp('WAV 文件路径：');
disp(wav_file);

%=============================================================
% 7）画图检查
%=============================================================
figure;
plot(t(1:1000)*1000, x(1:1000), "LineWidth", 1.2);
grid on;
xlabel("Time / ms");
ylabel("Amplitude");
title("Generated 48kHz Audio Test Signal");

figure;
NFFT = 8192;
X = fft(x, NFFT);
f = (0:NFFT/2-1).' * fs / NFFT;
mag_db = 20*log10(abs(X(1:NFFT/2)) / max(abs(X)) + 1e-12);

plot(f, mag_db, "LineWidth", 1.2);
grid on;
xlabel("Frequency / Hz");
ylabel("Magnitude / dB");
title("Spectrum of Generated Audio Test Signal");
xlim([0 5000]);

disp("生成完成！");
disp("MEM 文件路径：");
disp(mem_file);
disp("WAV 文件路径：");
disp(wav_file);