# Vivado 2025.2 Stage1 延迟寄存器使能 239-LUT 执行反馈

## 1. 结论

在已通过用户物理板验证的 249-LUT 版本上，本轮只修改 Stage1 中心延迟样本寄存器的启动期
更新条件，正式 Vivado 2025.2 工程从 `reset_run` 开始完成综合、实现、时序、DRC、功耗和
bitstream，布局布线后得到：

**239 LUT / 0 LUTRAM / 377 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**。

相对 249-LUT 实板安全基线减少 10 LUT（4.02%），FF、DSP、BRAM、IO、MMCM 和功耗不变。
该版本已经完成 RTL、实现和 routed-DCP 工具闭环，当前状态为 **tool-verified**；物理板验证
仍需用户下载本文件所列 bitstream 完成，不能把工具结果提前写成板测结果。

## 2. Git 与回退边界

- 优化分支：`national-finals-v2025.2-post249-lut-optimization`；
- 249-LUT 工具标签：`nf-vivado2025.2-249lut-377ff-4dsp-2bram-toolverified`；
- 249-LUT 实板回退标签：`nf-vivado2025.2-249lut-377ff-4dsp-2bram-board-pass`；
- 本轮提交和标签不使用 `codex` 字样；
- 临时网表、仿真和审计文件全部位于 `matlab_fir/national_finals/_work`，未放入仓库主目录。

若新版本板测异常，应立即切换到 249-LUT 实板标签，不要在故障现场继续叠加修改。

## 3. 资源热点审计

从 249-LUT 正式 routed DCP 导出物理 LUT 单元后，Stage1 中出现 24 个与
`delay_result` 相关的 LUT。对应 RTL 为：

```verilog
delay_result <= read_mask ? read_data : {DATA_W{1'b0}};
```

该写法要求综合器在 24 位 BRAM 数据与零之间选择。进一步检查控制时序可知：

1. `delay_result` 在复位时为零；
2. 中心抽头历史在启动期无效，此时预期值始终为零；
3. 历史有效性在一次复位周期内单调增加；
4. 中心抽头第一次有效后，直到下次复位前后续中心抽头读取始终有效。

因此启动期“不更新并保持复位零”与“每次写零”逐周期等价。正式 RTL 改为：

```verilog
if (read_coeff_index == DELAY_INDEX && read_mask)
    delay_result <= read_data;
```

综合器可将条件映射为寄存器 CE，而不再构造 24 位数据/零 mux。没有修改滤波器系数、定点
字长、舍入/饱和、有效时序、输出顺序、DSP/BRAM 数量、时钟或 DAC 接口。

## 4. A/B 资源结果

| 检查点 | 综合 LUT/FF | Routed LUT/FF | DSP | RAMB18E1 | MMCM | WNS/WHS |
|---|---:|---:|---:|---:|---:|---:|
| 249-LUT 实板基线 | 325 / 385 | 249 / 377 | 4 | 4 | 2 | +43.997/+0.085 ns |
| Stage1 延迟使能 | 314 / 385 | **239 / 377** | 4 | 4 | 2 | **+45.306/+0.082 ns** |

正式实现还满足：TNS/THS=0、setup/hold 失败端点=0、路由错误=0、DRC Error=0。总/动态/静态
功耗为 `0.271/0.199/0.072 W`，Confidence=Medium。

正式结果目录：

`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260809_173232`

关键文件：

- `board_demo_competition_dac8_top_2025_2.bit`；
- `board_routed_2025_2.dcp`；
- `utilization_synthesized.rpt`、`utilization_routed.rpt`；
- `timing_summary_routed.rpt`、`drc_routed.rpt`、`route_status_routed.rpt`；
- `power_routed.rpt`、`check_timing_routed.rpt`、`vivado_full_build.log`。

SHA-256：

- bitstream：`56248A6FFD013B020012B397ED32E9FA9F2285644978E5016CEB2F5506911EEA`；
- routed DCP：`0AFBDAFA7D6ECAED9D7DEF72A53F7ECBB7DF0FFC29823071B4A8D43A31B38729`。

## 5. RTL 回归

### Smoke

- 入口：`matlab_fir/national_finals/sim/run_national_finals_rtl_regression.ps1`；
- 规模：Smoke；
- 结果目录：`matlab_fir/national_finals/_work/rtl_regression/20260809_170652`；
- 结果：17/17 PASS。

### Release

- 结果目录：`matlab_fir/national_finals/_work/rtl_regression/20260809_171732`；
- 结果：17/17 PASS；
- 17 份 `xsim.log` 全部含 PASS，行首 `ERROR/FATAL/FAIL` 为 0；
- Stage1 行为 RAM 和 RAMB18E1 原语各 1400 个输出为 0 LSB；
- 全链冲激、10 个随机 seed、正/负满量程和强 −1 dBFS 共 14 组，在 4x/8x/128x 三节点
  全部为 0 LSB；
- 8 类内部状态复位恢复和 10 次无复位动态切档通过；
- ROM、DAC offset-binary、系数/历史 BRAM、CDC、按键和双时钟族用例通过。

## 6. Routed-DCP 六模式后仿真

后仿真直接从本轮 `board_routed_2025_2.dcp` 导出实现后功能网表，不以行为级顶层替代：

| 输入族 / 档位 | 1 ms DA_CLK 边沿 | DAC 数据变化次数 |
|---|---:|---:|
| 44.1 kHz / 4x | 177 | 175 |
| 44.1 kHz / 8x | 353 | 342 |
| 44.1 kHz / 128x | 5645 | 3710 |
| 48 kHz / 4x | 192 | 192 |
| 48 kHz / 8x | 384 | 372 |
| 48 kHz / 128x | 6144 | 3810 |

六档均无 X，最终标记为 `BOARD POSTROUTE SIX-MODE DAC PASS`。结果目录：

`matlab_fir/national_finals/_work/postroute_six_mode_dac/20260809_174151`

177/353/5645 是 1 ms 有限观察窗口的整数计数，分别对应理论
176.4/352.8/5644.8 kHz，不表示频率被改成 177/353/5645 kHz。

## 7. 插值核心 OOC 复测

独立顶层 `interp128_all2x_v7_folded_fir_cic_top_ce` 使用与整板一致的核心 RTL 和参数完成
Vivado 2025.2 post-route：

**197 LUT / 0 LUTRAM / 290 FF / 4 DSP48E1 / 3 RAMB18E1（1.5 BRAM Tile）/
0 MMCM**，内部 WNS/WHS=`+151.665/+0.054 ns`，路由错误=0、DRC Error=0。

正式 PASS 目录：

`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/core_ooc/results/20260809_180024`

第一次复测已经得到 197 LUT，但被旧的“必须等于 210 LUT”防回归门槛主动拦截；更新精确
门槛为 197 后从空目录完整复跑，输出 `CORE_OOC_2025_2_PASS` 和
`CORE_OOC_2025_2_DEMO_PASS`。这不是设计失败，而是旧基准门禁正常工作。

OOC 不包含板级 ROM/激励源、模式控制、双采样率 MMCM、DAC 包装、IO。不得用 `239-197`
直接声称外围精确占用 42 LUT，因为 OOC 与整板存在跨层级综合、打包和边界优化差异。

## 8. 频响与算法边界

本轮不改系数和数值路径，因此沿用已签核的严格频响：

| 输出节点 | 最大通带绝对偏差 | 峰峰纹波 | 阻带衰减 | 相位 |
|---|---:|---:|---:|---|
| 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 严格线性相位 |
| 8x | 0.003521 dB | 0.006192 dB | 78.609 dB | 严格线性相位 |
| 128x | 0.007730 dB | 0.005848 dB | 72.371 dB | 严格线性相位 |

全部满足通带纹波不超过 ±0.05 dB、阻带衰减不低于 70 dB 的要求。

## 9. 手动复现

### GUI

1. 关闭其他 Vivado 进程；
2. 打开 `XC7A35T_interp_opt_2025.2/XC7A35T_interp.xpr`；
3. 对 `synth_1` 执行 Reset Run，再运行 Synthesis；
4. 对 `impl_1` 执行 Reset Run，再运行 Implementation 和 Generate Bitstream；
5. 打开最新 `impl_1` Utilization Report，应看到 239 LUT、377 FF、4 DSP、2 BRAM Tile、
   17 IO、2 MMCM；
6. 打开 Timing Summary 和 DRC，确认 WNS/WHS 非负且 DRC Error 为 0。

### 一键低内存构建

```powershell
powershell -ExecutionPolicy Bypass -File .\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\run_full_build_2025_2.ps1 -Jobs 1
```

脚本硬门槛为 LUT≤239、DSP=4、RAMB18E1=4、MMCM=2、FF≤390、WNS/WHS≥0、DRC Error=0，
可防止误看旧 run 或错误工程结果。

### 核心 OOC

```powershell
powershell -ExecutionPolicy Bypass -File .\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\core_ooc\run_core_ooc_2025_2.ps1
```

终端必须出现 `CORE_OOC_2025_2_DEMO_PASS`，并精确报告 197 LUT。

## 10. 本轮遇到的问题与处理

1. 沙箱内首次启动 routed-DCP 后仿真时，Vivado 2025.2 无法加载本机 Xilinx Tcl Store，报
   `[Common 17-539]`。改用获准的本机 Vivado 调用后，网表导出、编译、展开和六模式仿真
   全部通过；该问题不是 RTL 或实现错误。
2. 核心 OOC 首次复跑被旧的 210-LUT 精确门槛拦截。报告证明实际资源已降为 197 LUT，随后
   更新门槛并完整复跑通过。
3. 工作区原有大量无关修改、删除和未跟踪历史结果。本轮提交只应包含 239-LUT 正式 RTL、
   构建门槛、OOC 复现脚本/说明、README、执行反馈和对应正式报告，不能混入无关文件。

## 11. 板测门槛

工具验证不能替代物理板验证。用户板测时至少应确认：

- 44.1 kHz 与 48 kHz 输入族下 4x、8x、128x 输出采样率正确；
- 六档 DAC 均有持续波形输出，无静默、卡码或切档后失锁；
- 多次复位和切档后仍可恢复正常；
- 使用的 bitstream SHA-256 与本文件一致。

只有上述板测通过后，才能创建 `board-pass` 标签并将 239-LUT 版本升级为正式实板版。
