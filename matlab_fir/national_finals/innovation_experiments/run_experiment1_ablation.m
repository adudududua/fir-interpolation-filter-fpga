%=============================================================
% 文件名       : run_experiment1_ablation.m
% 脚本名       : run_experiment1_ablation
% 功能简述     : 统一调度相关实验步骤，检查依赖并生成报告、数据表和演示图。
% 处理说明     : 本文件按“参数准备—核心计算—指标判定—结果导出”
%                的顺序组织；各功能段和局部函数均有独立编号。
% 开发工具     : MATLAB R2023a
% 修订记录     : 2026-08-30：统一中文文件头、功能段编号和函数说明。
%=============================================================

%% 1）主流程：run_experiment1_ablation
% 功能说明：统一调度相关实验步骤，检查依赖并生成报告、数据表和演示图。

clearvars;
clc;

script_dir = fileparts(mfilename('fullpath'));
nf_dir = fileparts(script_dir);
addpath(nf_dir);
output_dir = getenv('NF_INNOVATION_WORK');
if isempty(output_dir)
    output_dir = fullfile(nf_dir, '_work', ...
        'innovation_validation_20260815', 'experiment1');
else
    output_dir = fullfile(output_dir, 'experiment1');
end
if ~exist(output_dir, 'dir'); mkdir(output_dir); end

cfg = nf_release_v2_config();
h1 = double(cfg.stage1.coeff_int(:).')/2^cfg.stage1.frac_w;
h2 = double(cfg.stage2.coeff_int(:).')/2^cfg.stage2.frac_w;
h3_flat = double(cfg.stage3.coeff_int(:).')/2^cfg.stage3.frac_w;
h4 = conv(upsample_ir_local(h1, 2), h2);
h8_flat = conv(upsample_ir_local(h4, 2), h3_flat);
h_cic = conv(conv(ones(1, 16), ones(1, 16)), ones(1, 16));
h_equalizer = [-1 10 -1]/8;
h_joint = double([561 137 -4232 -1554 20046 35584 ...
    20046 -1554 -4232 137 561])/2^15;

responses = {
    'no_compensation', conv(upsample_ir_local(h8_flat, 16), h_cic)/2^8;
    'independent_3tap', conv(upsample_ir_local(conv(h8_flat, h_equalizer), 16), h_cic)/2^8;
    'joint_stage3_cic', conv(upsample_ir_local(conv(upsample_ir_local(h4, 2), h_joint), 16), h_cic)/2^8};

architecture = {};
fs_in_hz = [];
pass_abs_max_db = [];
pass_ripple_pp_db = [];
stop_attenuation_db = [];
dc_gain_db = [];
phase_fit_residual_rad = [];
pass = [];
for response_index = 1:size(responses, 1)
    for fs_value = [44100 48000]
        metric = analyze_local(responses{response_index, 2}, fs_value, 2^19);
        architecture{end+1, 1} = responses{response_index, 1}; %#ok<SAGROW>
        fs_in_hz(end+1, 1) = fs_value; %#ok<SAGROW>
        pass_abs_max_db(end+1, 1) = metric.pass_abs_max_db; %#ok<SAGROW>
        pass_ripple_pp_db(end+1, 1) = metric.pass_ripple_pp_db; %#ok<SAGROW>
        stop_attenuation_db(end+1, 1) = metric.stop_attenuation_db; %#ok<SAGROW>
        dc_gain_db(end+1, 1) = metric.dc_gain_db; %#ok<SAGROW>
        phase_fit_residual_rad(end+1, 1) = metric.phase_fit_residual_rad; %#ok<SAGROW>
        pass(end+1, 1) = metric.pass_abs_max_db <= 0.05 && ... %#ok<SAGROW>
            metric.stop_attenuation_db >= 70;
    end
end
metric_table = table(architecture, fs_in_hz, pass_abs_max_db, ...
    pass_ripple_pp_db, stop_attenuation_db, dc_gain_db, ...
    phase_fit_residual_rad, logical(pass), 'VariableNames', ...
    {'ARCHITECTURE','FS_IN_HZ','PASS_ABS_MAX_DB','PASS_RIPPLE_PP_DB', ...
     'STOP_ATTENUATION_DB','DC_GAIN_DB','PHASE_FIT_RESIDUAL_RAD','PASS'});
writetable(metric_table, fullfile(output_dir, 'experiment1_metrics.csv'));

frequency_hz = linspace(0, 120000, 6001).';
response_table = table(frequency_hz);
fs_plot = 48000;
for response_index = 1:size(responses, 1)
    h = responses{response_index, 2};
    sample_index = 0:numel(h)-1;
    response_complex = exp(-1j*2*pi*frequency_hz*sample_index/(128*fs_plot))*h(:);
    response_table.(responses{response_index, 1}) = ...
        20*log10(abs(response_complex)/128+1e-15);
end
writetable(response_table, fullfile(output_dir, 'experiment1_response_48k.csv'));

assert(all(metric_table.PASS(~strcmp(metric_table.ARCHITECTURE, ...
    'no_compensation'))), ...
    'Compensated architectures failed the competition gate.');
assert(~all(metric_table.PASS(strcmp(metric_table.ARCHITECTURE, ...
    'no_compensation'))), ...
    'Negative control unexpectedly passed.');
fprintf('EXPERIMENT1_ABLATION_PASS: compensated=4/4, negative_control=NO_GO\n');

% 2）局部函数模块：upsample_ir_local

% 功能说明：按指定插值倍率展开冲激响应并构造当前级或完整链路的等效响应。
function output = upsample_ir_local(input, rate)
    output = zeros(1, (numel(input)-1)*rate+1);
    output(1:rate:end) = input;
end

% 3）局部函数模块：analyze_local

% 功能说明：计算局部幅频、相位、纹波或阻带指标，并返回结构化验收结果。
function metric = analyze_local(h, fs_in, nfft)
    fs_out = 128*fs_in;
    spectrum = fft(double(h(:).'), nfft);
    spectrum = spectrum(1:nfft/2+1);
    frequency = (0:nfft/2)*(fs_out/nfft);
    absolute_db = 20*log10(abs(spectrum)/128+1e-15);
    pass_index = frequency >= 10 & frequency <= 20000;
    stop_index = frequency >= (fs_in-20000) & frequency <= fs_out/2;
    phase_index = pass_index & abs(spectrum) > max(abs(spectrum))*1e-6;
    phase_value = unwrap(angle(spectrum(phase_index)));
    omega = 2*pi*frequency(phase_index)/fs_out;
    fit = polyfit(omega, phase_value, 1);
    metric.pass_abs_max_db = max(abs(absolute_db(pass_index)));
    metric.pass_ripple_pp_db = max(absolute_db(pass_index))-min(absolute_db(pass_index));
    metric.stop_attenuation_db = -max(absolute_db(stop_index));
    metric.dc_gain_db = 20*log10(abs(sum(h))/128+1e-15);
    metric.phase_fit_residual_rad = max(abs(phase_value-polyval(fit, omega)));
end
