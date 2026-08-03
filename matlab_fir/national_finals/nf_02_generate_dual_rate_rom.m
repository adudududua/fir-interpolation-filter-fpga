%=============================================================
% 文件名       : nf_02_generate_dual_rate_rom.m
% 功能简述     : 生成全国赛双采样率共用板级 15 kHz 测试 ROM。
%=============================================================

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(script_dir));
rtl_dir = fullfile(project_root, ...
    'XC7A35T_interp_audio_pcm_wordlen_opt', ...
    'XC7A35T_interp.srcs', 'sources_1', 'new', 'national_finals');
if ~exist(rtl_dir, 'dir'); mkdir(rtl_dir); end

DATA_W = 24;
AMPLITUDE = 0.5*(2^(DATA_W-1)-1);
TONE_HZ = 15000;
FS_44K1 = 44100;
FS_48K = 48000;
N_44K1 = 147;
N_48K = 16;
ROM_DEPTH = 256;

x44 = round(AMPLITUDE*sin(2*pi*TONE_HZ*(0:N_44K1-1)/FS_44K1));
x48 = round(AMPLITUDE*sin(2*pi*TONE_HZ*(0:N_48K-1)/FS_48K));
rom_data = zeros(ROM_DEPTH, 1, 'int64');
rom_data(1:N_44K1) = int64(x44(:));
rom_data(N_44K1+(1:N_48K)) = int64(x48(:));

mem_path = fullfile(rtl_dir, 'nf_sine_15k_dual_rate_24bit_256.mem');
fid = fopen(mem_path, 'w');
if fid < 0; error('无法创建 ROM：%s', mem_path); end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
modulus = 2^DATA_W;
for idx = 1:ROM_DEPTH
    value = double(rom_data(idx));
    if value < 0; value = value+modulus; end
    fprintf(fid, '%06X\n', value);
end

% Generate the resource-optimized 32-bit ROM in one offline pass. The high
% byte is the next address and the low 24 bits are exactly the signed PCM
% payload above. This avoids relying on a second Verilog procedural
% initialization, which Vivado 2018.3 did not reliably merge into RAMB18
% INIT values.
next_addr = zeros(ROM_DEPTH, 1, 'uint64');
next_addr(1:N_44K1-1) = uint64((1:N_44K1-1).');
next_addr(N_44K1) = uint64(0);
next_addr(N_44K1+(1:N_48K-1)) = ...
    uint64((N_44K1+1:N_44K1+N_48K-1).');
next_addr(N_44K1+N_48K) = uint64(N_44K1);

pcm_unsigned = uint64(mod(double(rom_data), modulus));
packed_data = bitshift(next_addr, DATA_W) + pcm_unsigned;
packed_mem_path = fullfile(rtl_dir, ...
    'nf_sine_15k_dual_rate_packed32_256.mem');
packed_fid = fopen(packed_mem_path, 'w');
if packed_fid < 0; error('无法创建 Packed ROM：%s', packed_mem_path); end
packed_cleanup = onCleanup(@() fclose(packed_fid)); %#ok<NASGU>
for idx = 1:ROM_DEPTH
    fprintf(packed_fid, '%08X\n', packed_data(idx));
end

if any(bitand(packed_data, uint64(2^DATA_W-1)) ~= pcm_unsigned)
    error('Packed ROM 低24 bit与PCM数据不一致。');
end
if any(bitshift(packed_data, -DATA_W) ~= next_addr)
    error('Packed ROM 高8 bit与下一地址不一致。');
end

reference_path = fullfile(project_root, ...
    'XC7A35T_interp_audio_pcm_wordlen_opt', ...
    'XC7A35T_interp.srcs', 'sources_1', 'new', ...
    'demo_sine_15k_44k1_24bit_147.mem');
reference_text = splitlines(strtrim(fileread(reference_path)));
generated_text = upper(string(dec2hex(mod(double(x44(:)), modulus), 6)));
if ~isequal(string(reference_text(:)), generated_text(:))
    error('重新生成的 44.1 kHz 序列与已板测 0.50FS ROM 不一致。');
end

fprintf('双采样率测试 ROM 生成完成：%s\n', mem_path);
fprintf('一次初始化 Packed ROM 生成完成：%s\n', packed_mem_path);
fprintf('44.1 kHz: %d 点；48 kHz: %d 点；总深度: %d\n', ...
    N_44K1, N_48K, ROM_DEPTH);
fprintf('44.1 kHz 已与板测 ROM 逐点一致：PASS\n');
