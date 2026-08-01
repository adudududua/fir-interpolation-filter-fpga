# P4-C 3-DSP 完整工程分支

本分支将全国总决赛 P4-C 工程的默认配置锁定为：

- 504 LUT / 494 FF / 198 Slice；
- 3 DSP / 2 BRAM Tile / 2 MMCM；
- WNS/WHS：+45.853/+0.121 ns；
- vectorless Total/Dynamic Power：0.271/0.199 W；
- `USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=1`。

与4-DSP推荐版使用相同的滤波器系数、定点格式和最终 RTL。区别仅为第一段26-bit CIC积分器使用 CARRY4，第二段29-bit CIC积分器仍使用 DSP48E1；因此以25 LUT和26 FF换取1个DSP。

Vivado工程、顶层RTL默认参数、GUI配置检查、板级测试默认参数及命令行构建脚本均已统一为模式1。打开 `XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.xpr` 后重置综合/实现并生成bitstream，即会得到3-DSP工程。

默认命令行复现：

```powershell
& ".\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1" -Step all -ResultTag p4c_branch_3dsp_full_project
```

签核bitstream位于：

`matlab_fir/national_finals/vivado_results/p4c_signed_3dsp_2bram/national_finals_dual_rate_4x8x128x_areaopt.bit`

SHA-256：`81AA1B27AE84D24071507E7FB06E9FAE357BF85400FCE4C3DFCA18A14F915DFA`
