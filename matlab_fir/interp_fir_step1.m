clc;
clear;
close all;

%% 1. 基本参数
Fs_in = 48000;          % 输入采样率
L = 4;                  % 插值倍数
Fs_out = Fs_in * L;     % 输出采样率 192kHz

T = 0.02;               % 信号时长 20ms
t = (0:1/Fs_in:T-1/Fs_in)';   % 列向量时间轴

%% 2. 生成测试信号：1kHz + 8kHz + 18kHz
x = 0.5*sin(2*pi*1000*t) ...
  + 0.3*sin(2*pi*8000*t) ...
  + 0.2*sin(2*pi*18000*t);

% 防止幅度过大，留一点余量
x = 0.8 * x / max(abs(x));

%% 3. 模拟 24 位有符号输入（先量化，再转回 double 用于后续处理）
x_int24 = round(x * (2^23 - 1));      % 24位有符号整数范围
x_q = x_int24 / (2^23 - 1);           % 转回[-1,1]附近的double

disp('前10个输入样本（24位量化后）:');
disp(x_int24(1:10));

%% 4. 原始信号时域图
figure;
plot(t(1:200), x_q(1:200), 'LineWidth', 1.2);
grid on;
xlabel('时间 / s');
ylabel('幅值');
title('原始输入信号（时域）');

%% 5. 原始信号频谱
Nfft = 65536;
X = fft(x_q, Nfft);
f_in = (0:Nfft/2-1)' * Fs_in / Nfft;
magX = 20*log10(abs(X(1:Nfft/2)) + 1e-12);

figure;
plot(f_in, magX, 'LineWidth', 1.2);
grid on;
xlabel('频率 / Hz');
ylabel('幅度 / dB');
title('原始输入信号频谱');
xlim([0 Fs_in/2]);

%% 6. 4倍补零插值
x_up = upsample(x_q, L);

t_up = (0:length(x_up)-1)' / Fs_out;

figure;
stem(t_up(1:60), x_up(1:60), 'filled');
grid on;
xlabel('时间 / s');
ylabel('幅值');
title('4倍补零后的时域序列（前60个点）');

%% 7. 补零后的频谱
X_up = fft(x_up, Nfft);
f_out = (0:Nfft/2-1)' * Fs_out / Nfft;
magX_up = 20*log10(abs(X_up(1:Nfft/2)) + 1e-12);

figure;
plot(f_out, magX_up, 'LineWidth', 1.2);
grid on;
xlabel('频率 / Hz');
ylabel('幅度 / dB');
title('4倍补零后的频谱（未滤波）');
xlim([0 Fs_out/2]);

%% 8. 设计插值低通FIR
Fpass = 20000;      % 通带边缘
Fstop = 28000;      % 阻带起始

Ap = 0.05;          % 通带纹波（dB）
Ast = 70;           % 阻带衰减（dB）

% 将dB指标转换成线性偏差
dev_pass = (10^(Ap/20)-1) / (10^(Ap/20)+1);
dev_stop = 10^(-Ast/20);
dev = [dev_pass, dev_stop];

% Kaiser窗估算阶数
[n, Wn, beta, ftype] = kaiserord([Fpass Fstop], [1 0], dev, Fs_out);

% 为了让群延迟是整数，取偶数阶
if mod(n,2) ~= 0
    n = n + 1;
end

% 设计FIR
h = fir1(n, Wn, ftype, kaiser(n+1, beta), 'noscale');

% 对插值滤波器，通带增益要乘以 L
h = L * h;

fprintf('滤波器阶数 n = %d\n', n);
fprintf('滤波器长度 = %d\n', n+1);
fprintf('群延迟 = %d 个输出采样点\n', n/2);

%% 9. 查看FIR频率响应
figure;
freqz(h, 1, 4096, Fs_out);
title('插值低通FIR的频率响应');

%% 10. 进行FIR滤波
y = filter(h, 1, x_up);

% FIR线性相位滤波器会产生固定延迟
delay = n / 2;

% 为了后面更方便观察，把延迟补偿掉
y_align = [y(delay+1:end); zeros(delay,1)];

%% 11. 滤波后时域图
figure;
plot(t_up(1:400), y_align(1:400), 'LineWidth', 1.2);
grid on;
xlabel('时间 / s');
ylabel('幅值');
title('4倍插值并滤波后的输出时域波形');

%% 12. 滤波后频谱
Y = fft(y_align, Nfft);
magY = 20*log10(abs(Y(1:Nfft/2)) + 1e-12);

figure;
plot(f_out, magY, 'LineWidth', 1.2);
grid on;
xlabel('频率 / Hz');
ylabel('幅度 / dB');
title('4倍插值并滤波后的频谱');
xlim([0 Fs_out/2]);

%% 13. 简单验证：每隔4点取1点，与原输入比较
y_down = y_align(1:L:end);

min_len = min(length(x_q), length(y_down));

figure;
plot(t(1:min_len), x_q(1:min_len), 'b', 'LineWidth', 1.2); hold on;
plot(t(1:min_len), y_down(1:min_len), '--r', 'LineWidth', 1.2);
grid on;
xlabel('时间 / s');
ylabel('幅值');
title('原始输入 与 插值滤波后每4点抽取1点 的对比');
legend('原始输入', '插值后抽取');

%% 14. 把 FIR 系数量化成 Verilog 可用的定点整数


% -----------------------------
% 设定系数量化位宽
% 当前准备给 Verilog 用 18 位有符号系数
% 这里采用 Q2.16 的理解方式：
%   总位宽 18 位
%   其中 16 位作为小数位
%   剩余位用于符号和整数部分
%
% 量化公式：
%   h_q = round(h * 2^16)
% -----------------------------
COEFF_W = 18;      % 系数总位宽
FRAC_W  = 16;      % 小数位数

% -----------------------------
% 计算量化后的整数系数
% -----------------------------
h_q = round(h * 2^FRAC_W);

% -----------------------------
% 做饱和限制，防止超出 18 位有符号范围
% 18 位有符号整数范围：
%   -2^(17)  ~  2^(17)-1
% -----------------------------
q_max =  2^(COEFF_W-1) - 1;
q_min = -2^(COEFF_W-1);

h_q(h_q > q_max) = q_max;
h_q(h_q < q_min) = q_min;

% -----------------------------
% 显示前几个量化结果，方便检查
% -----------------------------
disp('前10个量化后的 FIR 系数（整数形式）:');
disp(h_q(1:min(10,length(h_q))).');

% -----------------------------
% 保存一个纯数字文本文件
% 每行一个整数，方便查看
% -----------------------------
writematrix(h_q(:), 'fir_coeff_decimal.txt');


%% 15. 生成 Verilog 可直接复制的系数赋值语句

fid = fopen('fir_coeff_for_verilog.txt', 'w');

fprintf(fid, '// =====================================================\n');
fprintf(fid, '// MATLAB 自动生成的 FIR 系数赋值语句\n');
fprintf(fid, '// 系数位宽: %d bit\n', COEFF_W);
fprintf(fid, '// 小数位宽: %d bit\n', FRAC_W);
fprintf(fid, '// 系数总数: %d\n', length(h_q));
fprintf(fid, '// =====================================================\n');

for k = 1:length(h_q)
    if h_q(k) >= 0
        fprintf(fid, '        coeff[%d] = 18''sd%d;\n', k-1, h_q(k));
    else
        fprintf(fid, '        coeff[%d] = -18''sd%d;\n', k-1, abs(h_q(k)));
    end
end      

fclose(fid);

disp('已生成文件:');
disp('1) fir_coeff_decimal.txt');
disp('2) fir_coeff_for_verilog.txt');

%% 16. 保存24位有符号数文件
writematrix(x_int24(:), 'input_24bit.txt');
fprintf('输入样本数 = %d\n', length(x_int24));