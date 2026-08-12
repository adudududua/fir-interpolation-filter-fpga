# 218-LUT 技术报告补充实验归档

本目录对应 `technical_report_supplementary_experiment_guide.md` 中当前环境可直接执行的
E0～E4 数字域实验，正式配置为 `24/20/20`、4-DSP、218-LUT 板测基线。

运行命令：

```powershell
& 'E:\app\MATLAB\R2023a\bin\matlab.exe' -batch "cd('D:/FpgaProject/XilinxProject/XC7A35T/fir_interpolation/matlab_fir/national_finals/report_experiments'); run('run_technical_report_experiments.m');"
```

RTL Smoke 复验命令：

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe `
  -NoProfile -ExecutionPolicy Bypass `
  -File "D:\FpgaProject\XilinxProject\XC7A35T\fir_interpolation\matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1" `
  -RegressionScale Smoke -StageWordLength 24_20_20 -CicIntegratorDspMode 2
```

目录内容：

- `raw/evidence_sources.txt`：已有签核和新回归证据的位置；
- `processed/`：E0～E4 的 CSV 和总门禁；
- `figures/`：报告所用 PNG；
- `logs/matlab_execution.txt`：MATLAB 完整运行日志；
- `SHA256SUMS`：关键结果哈希。

2026-08-12 实测结果：MATLAB 软件门禁通过；E1 固定模型/稳定 RTL 向量 6/6、0 LSB；
E2 六工况 6/6；E3 三频点×六工况 18/18；RTL Smoke 17/17。

## 2-DSP 固定资源补充复验

该补充项不改变本目录的218-LUT/4-DSP实验对象，而是用于说明同一24/20/20数值配置在
DSP模式0下的资源边界。当前2-DSP生产配置重新完成Smoke/Release 17/17与Vivado 2025.2
完整构建，结果为268 LUT/417 FF/2 DSP/4 RAMB18E1，WNS/WHS为+44.389/+0.078 ns，
DRC Error为0。实现策略和三项状态/调度候选均未低于268 LUT；相关结论已补入技术报告
第9章和附录C。完整记录见
`../../results/vivado2025_2_2dsp_fixed_resource_lut_optimization_execution_feedback.md`。
