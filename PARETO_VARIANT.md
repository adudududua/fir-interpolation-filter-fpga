# P4-C 2-DSP 完整工程分支

本分支将全国总决赛 P4-C 工程的默认配置锁定为：

- 523 LUT / 523 FF / 197 Slice；
- 2 DSP / 2 BRAM Tile / 2 MMCM；
- WNS/WHS：+45.802/+0.121 ns；
- vectorless Total/Dynamic Power：0.270/0.198 W；
- `USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=0`。

与4-DSP推荐版使用相同的滤波器系数、定点格式和最终 RTL。区别仅为26-bit和29-bit两个CIC积分器均使用 LUT CARRY4；因此以44 LUT和55 FF换取2个DSP。

Vivado工程、顶层RTL默认参数、GUI配置检查、板级测试默认参数及命令行构建脚本均已统一为模式0。打开 `XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.xpr` 后重置综合/实现并生成bitstream，即会得到2-DSP工程。

默认命令行复现：

```powershell
& ".\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1" -Step all -ResultTag p4c_branch_2dsp_full_project
```

签核bitstream位于：

`matlab_fir/national_finals/vivado_results/p4c_signed_2dsp_2bram/national_finals_dual_rate_4x8x128x_areaopt.bit`

SHA-256：`0F82EB84C2E22264454F504F183FC979486DF0BD4103F0F275334FB78EC66CDD`
