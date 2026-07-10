clc; clear; close all;

%=============================================================
% 文件名       : export_all2x_rtl_files.m
% 脚本名       : export_all2x_rtl_files
% 功能简述     : 将最新全 2x MATLAB 设计导出为 RTL 参数和 bit-true
%                随机测试向量。
%
%                输出文件：
%                  all2x_rtl_stage_params.vh
%                  all2x_random_input_24bit.mem
%                  all2x_random_golden_24bit.mem
%                  all2x_random_vector_summary.txt
%
%                .mem 文件采用 24bit 二进制补码十六进制格式，可由
%                Verilog 的 $readmemh 直接读取。
%
% 当前默认配置：
%                  输入向量长度：128 点
%                  随机数种子  ：20260710
%                  输入幅度范围：±2^20
%                  数据位宽    ：24bit signed
%
% 设计作者     : kafeizizi
% 创建日期     : 2026-07-10
% 版本         : V2018.3
% 开发工具     : MATLAB
% 修订记录     :
%                2026-07-10：新增 RTL 参数与随机 golden 向量导出脚本。
%=============================================================

%% 1) 路径与配置
%=============================================================

script_dir = fileparts(mfilename('fullpath'));
design_dir = fullfile(script_dir, '..');
bittrue_dir = fullfile(design_dir, 'bittrue');
addpath(bittrue_dir);

DATA_W = 24;
RANDOM_SEED = 20260710;
INPUT_COUNT = 128;
INPUT_LIMIT = 2^20;

stage_config = load_all2x_stage_config(design_dir, DATA_W);

%% 2) 生成 bit-true 输入与 golden 输出
%=============================================================

rng(RANDOM_SEED, 'twister');
x_in = int64(randi([-INPUT_LIMIT INPUT_LIMIT], 1, INPUT_COUNT));
[y_golden, stage_stat] = simulate_all2x_bittrue(x_in, stage_config);

overflow_count = sum([stage_stat.acc_overflow_count]);
sat_count = sum([stage_stat.output_sat_count]);

if overflow_count ~= 0 || sat_count ~= 0
    error('随机 golden 向量出现 overflow=%d、sat=%d，不适合作为基础对拍向量。', ...
          overflow_count, sat_count);
end

%% 3) 导出参数和 .mem 文件
%=============================================================

param_path = fullfile(script_dir, 'all2x_rtl_stage_params.vh');
input_mem_path = fullfile(script_dir, 'all2x_random_input_24bit.mem');
golden_mem_path = fullfile(script_dir, 'all2x_random_golden_24bit.mem');
summary_path = fullfile(script_dir, 'all2x_random_vector_summary.txt');

export_verilog_params(param_path, stage_config);
export_hex_mem(input_mem_path, x_in, DATA_W);
export_hex_mem(golden_mem_path, y_golden, DATA_W);

fid = fopen(summary_path, 'w');
fprintf(fid, 'All-2x RTL random test vector summary\n');
fprintf(fid, '=====================================\n');
fprintf(fid, 'Random seed             = %d\n', RANDOM_SEED);
fprintf(fid, 'Input samples           = %d\n', numel(x_in));
fprintf(fid, 'Golden output samples   = %d\n', numel(y_golden));
fprintf(fid, 'Input minimum           = %d\n', min(x_in));
fprintf(fid, 'Input maximum           = %d\n', max(x_in));
fprintf(fid, 'Golden output minimum   = %d\n', min(y_golden));
fprintf(fid, 'Golden output maximum   = %d\n', max(y_golden));
fprintf(fid, 'Accumulator overflows   = %d\n', overflow_count);
fprintf(fid, 'Output saturations      = %d\n', sat_count);
fprintf(fid, 'Pass all                = %d\n', overflow_count == 0 && sat_count == 0);
fclose(fid);

fprintf('====================================================\n');
fprintf('全 2x RTL 参数与随机测试向量导出完成\n');
fprintf('输入样点数      = %d\n', numel(x_in));
fprintf('golden 输出点数 = %d\n', numel(y_golden));
fprintf('累加器溢出      = %d\n', overflow_count);
fprintf('输出饱和        = %d\n', sat_count);
fprintf('====================================================\n');


%% ============================================================
% 本地函数：导出 24bit 二进制补码十六进制文件
% ============================================================
function export_hex_mem(filename, data, data_w)
    fid = fopen(filename, 'w');
    hex_digits = ceil(data_w / 4);
    modulus = 2^data_w;

    for idx = 1:numel(data)
        unsigned_value = mod(double(data(idx)), modulus);
        fprintf(fid, '%0*X\n', hex_digits, unsigned_value);
    end

    fclose(fid);
end


%% ============================================================
% 本地函数：导出 Verilog 参数头文件
% ============================================================
function export_verilog_params(filename, stage_config)
    fid = fopen(filename, 'w');

    fprintf(fid, '//=============================================================\n');
    fprintf(fid, '// 文件名       : all2x_rtl_stage_params.vh\n');
    fprintf(fid, '// 功能简述     : 全 2x 级联 128 倍插值链路的自动导出 RTL 参数。\n');
    fprintf(fid, '//                本文件由 export_all2x_rtl_files.m 生成。\n');
    fprintf(fid, '//\n');
    fprintf(fid, '// 设计作者     : kafeizizi\n');
    fprintf(fid, '// 创建日期     : 2026-07-10\n');
    fprintf(fid, '// 版本         : V2018.3\n');
    fprintf(fid, '// 开发工具     : Vivado\n');
    fprintf(fid, '// 修订记录     :\n');
    fprintf(fid, '//                2026-07-10：自动导出全 2x 逐级 RTL 参数。\n');
    fprintf(fid, '//=============================================================\n\n');

    for idx = 1:numel(stage_config)
        cfg = stage_config(idx);
        fprintf(fid, 'localparam integer STAGE%d_TAPS    = %d;\n', idx, cfg.taps);
        fprintf(fid, 'localparam integer STAGE%d_COEFF_W = %d;\n', idx, cfg.coeff_w_min);
        fprintf(fid, 'localparam integer STAGE%d_FRAC_W  = %d;\n', idx, cfg.frac_w);
        fprintf(fid, 'localparam integer STAGE%d_ACC_W   = %d;\n', idx, cfg.acc_w_recommended);
        fprintf(fid, '\n');
    end

    fclose(fid);
end
