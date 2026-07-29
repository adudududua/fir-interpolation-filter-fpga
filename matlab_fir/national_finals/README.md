# 全国总决赛：双采样率可配置插值滤波器

## 2026-07-30 最终优化结论

当前提供两个已全面优化、可独立生成 bitstream 的分支：

- `codex/national-finals-cic-6dsp-opt`：推荐 FIR-CIC 主方案。
- `codex/national-finals-all2x-opt`：全 2x 低 DSP 对照方案。

| 架构 | 布局后 LUT | FF | DSP | BRAM | MMCM | WNS/WHS | 功耗 | 结论 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| **FIR-CIC 6-DSP** | **573** | **621** | 6 | 3 | 2 | +46.339/+0.072 ns | 0.271 W | 最低 LUT，推荐 |
| 全 2x 3-DSP | 714 | 662 | 3 | 3 | 2 | +46.438/+0.105 ns | 0.271 W | 全 2x 最低 LUT |
| **全 2x 2-DSP** | 728 | 662 | **2** | 3 | 2 | +46.441/+0.105 ns | 0.271 W | 最低 DSP |

FIR-CIC 通过串行复用 comb DSP 将整链从 8 DSP 降到 6 DSP。全 2x 则把
Stage 4～7 的四份半带算术合并为共享数据通路，并对尾级是否使用 DSP48
预加器保留 2-DSP/3-DSP 两个 Pareto 点。全 2x 的滤波性能稍高，128x
阻带为 78.447/78.881 dB；FIR-CIC 为 72.348 dB，但两者都超过 70 dB。
完整六工况表、否决方案与 bitstream 哈希见仓库根
[README](../../README.md) 和
[架构比较摘要](results/architecture_comparison_summary.txt)。

全 2x 一键 RTL 回归：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\sim\run_national_finals_all2x_rtl_regression.ps1
```

全 2x 2-DSP 一键实现：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1 `
  -Step all -Architecture all2x -All2xSharedTail 1 -All2xTailDsp48 0 `
  -SynthesisDirective AreaOptimized_high -FlattenHierarchy rebuilt `
  -ResourceSharing on -ResultTag board_dual_rate_all2x_2dsp_areaopt
```

全 2x 3-DSP 只需把 `-All2xTailDsp48` 改为 `1`，并使用不同
`-ResultTag`。FIR-CIC 对应 `-Architecture cic`。

> 注意：两种架构均已通过 MATLAB、RTL、实现和 bitstream 工具链签核；
> 物理板卡下载、DA_CLK 与频谱仪测量仍需执行本文第 8 节，不能把
> “bitstream 已生成”写成“实物板级已经通过”。

## 2026-07-29 基线交付记录

当前版本已完成 MATLAB 建模、24 bit 定点模型、RTL、六组 XSim 回归、Vivado 综合/布局布线/时序/DRC/功耗评估和 bitstream 生成。所有软件与 FPGA 工具验收均已通过；由于当前环境无法接触实物开发板，物理板下载和仪器测量仍需按本文最后一节执行，不能把 bitstream 成功等同于实板通过。

开发分支：`codex/national-finals-configurable`

## 1. 完成状态

- [x] 44.1 kHz / 48 kHz、signed 24 bit 输入数据通路
- [x] 4x / 8x / 128x 三档正式输出
- [x] 10 Hz～20 kHz、±0.05 dB、阻带不低于 70 dB、严格线性相位
- [x] MATLAB 浮点搜索和六工况验证
- [x] MATLAB/RTL bit-true 向量生成
- [x] RTL 单元、时钟、键盘、板级集成和全链路仿真
- [x] Vivado 2018.3 综合、布局布线、时序、DRC、功耗与 bitstream
- [ ] 实物 FPGA 下载、DA_CLK 示波器测量和 DAC 频谱验收

## 2. 低资源共享架构

```text
24 bit PCM
   |
   +-> 105 tap 严格半带 2x -> 17 tap 2x -> 11 tap 平坦 2x
                                |              |
                                +-- 4x 输出    +-- 8x 输出
                                               |
                                               +-> [-1,10,-1]/8 移位加减均衡
                                                   -> CIC16, N=3 -> 128x 输出
```

44.1 kHz 与 48 kHz 共用同一 FIR/CIC 数据通路、DSP 和数据 BRAM，只增加两路 MMCM 与一个 `BUFGMUX_CTRL`。128x 支路的三抽头对称均衡器为

```text
y[n] = x[n-1] + (2*x[n-1] - x[n] - x[n-2]) / 8
```

它仅用加减和算术右移，不增加乘法器；4x/8x 输出保持平坦 FIR 响应。双采样率板级测试正弦也打包在同一个 256×24 bit ROM 中。

与区域赛 44.1 kHz 最低 LUT 版的 472 LUT / 8 DSP / 3 BRAM 相比，本版为 602 LUT / 8 DSP / 3 BRAM：增加约 130 LUT 完成双采样率、安全时钟切换、独立 8x 合规和共享双速率 ROM，DSP 与 BRAM 数量不增加。

## 3. 正式 RTL 冲激指标

以下数据直接来自 XSim 导出的最终 RTL 冲激响应，不是只分析浮点系数。

| 输入采样率 | 输出 | 通带最大绝对偏差 | 通带峰峰值 | 阻带衰减 | 冲激对称误差 | 判定 |
|---:|---:|---:|---:|---:|---:|---|
| 44.1 kHz | 4x / 176.4 kHz | 0.004610 dB | 0.005703 dB | 78.669 dB | 0 LSB | PASS |
| 44.1 kHz | 8x / 352.8 kHz | 0.005495 dB | 0.006274 dB | 78.161 dB | 0 LSB | PASS |
| 44.1 kHz | 128x / 5.6448 MHz | 0.006918 dB | 0.008111 dB | 72.348 dB | 0 LSB | PASS |
| 48 kHz | 4x / 192 kHz | 0.004610 dB | 0.005703 dB | 78.669 dB | 0 LSB | PASS |
| 48 kHz | 8x / 384 kHz | 0.005495 dB | 0.005738 dB | 78.161 dB | 0 LSB | PASS |
| 48 kHz | 128x / 6.144 MHz | 0.006918 dB | 0.006917 dB | 72.348 dB | 0 LSB | PASS |

所有六工况均满足 ±0.05 dB 和 70 dB 门槛，冲激响应逐点严格对称，拟合相位残差最大约 `1.42e-13 rad`。

![最终 RTL 六工况频响](figures/nf_rtl_impulse_response.png)

详细数值见 [nf_rtl_impulse_summary.txt](results/nf_rtl_impulse_summary.txt)。

## 4. RTL 回归结果

| 测试 | 覆盖内容 | 结果 |
|---|---|---|
| ROM | 双采样率数据、回卷、同步复位 | PASS |
| 移位加减均衡器 | 2009 个定向样本 | PASS |
| MMCM/BUFGMUX | 双频率、往返切换、无 runt 高脉冲 | PASS |
| 矩阵键盘 | SW1～SW8 家族/倍率映射 | PASS |
| 板级顶层 | 上电复位、共享扫描、SW2、SW6、保护切换 | PASS |
| 全链路 bit-true | impulse + 固定种子随机 PCM；4x/8x/128x | PASS，0 LSB |

全链路样本数：impulse 为 `1245 / 2499 / 40064`，随机输入为 `4317 / 8643 / 138368`；所有节点无 X、无丢样、无数值失配。证据摘要见 [nf_rtl_regression_summary.txt](results/nf_rtl_regression_summary.txt)。

一键重跑：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1 `
  -PublishImpulseOutputs
```

脚本每次使用新的 `matlab_fir/national_finals/_work/rtl_regression/<时间戳>` 空编译目录，任一 PASS 标志缺失或工具退出码非零都会终止。Vivado/XSim 的 `.Xil`、`xsim.dir`、journal 和 log 均留在 `_work` 内，不会写入项目根目录。

## 5. Vivado 实现签核

器件：`XC7A35T-FGG484-2`，顶层：`board_demo_competition_dac8_top`。

| 项目 | 结果 |
|---|---:|
| Slice LUT | 602 / 20800（2.89%） |
| Slice register | 616 / 41600（1.48%） |
| BRAM tile | 3 / 50（6.00%） |
| DSP48E1 | 8 / 90（8.89%） |
| BUFGCTRL / MMCM | 2 / 2 |
| WNS / TNS | +46.309 ns / 0 ns |
| WHS / THS | +0.103 ns / 0 ns |
| 路由错误 | 0，1831/1831 可布线网络全部完成 |
| DRC Error | 0 |
| Vectorless 功耗 | 0.271 W（动态 0.199 W，静态 0.072 W，Medium confidence） |

Vivado 报告仍有 211 条 Warning/Advisory，主要是面积优先结构中未加流水的 DSP 性能建议，以及 DSP/BRAM 异步控制检查。当前时序余量很大、路由完整、DRC Error 为 0 且 bitstream 已成功生成；这些警告不是“已物理验证”的替代品，首次上板仍要重点检查复位和采样率切换。

签核摘要见 [nf_hardware_signoff_summary.txt](results/nf_hardware_signoff_summary.txt)。

bitstream：

```text
matlab_fir/national_finals/vivado_results/board_dual_rate_areaopt/
national_finals_dual_rate_4x8x128x_areaopt.bit
```

SHA-256：`28A18B572FC53E816CCB709BAF04DA3129E1F2B2BF51A1749682075A29EB043B`

## 6. MATLAB 与 Vivado 复现

MATLAB：

```matlab
cd('D:/FpgaProject/XilinxProject/XC7A35T/fir_interpolation/matlab_fir/national_finals');
run('nf_01_search_shared_cic_equalizer.m');
run('nf_02_generate_dual_rate_rom.m');
run('nf_03_generate_bittrue_vectors.m');
% 先运行 RTL 回归并发布 impulse CSV，再执行：
run('nf_04_analyze_rtl_impulse.m');
```

Vivado 2018.3 一键综合、实现和 bitstream：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1 `
  -Step all
```

包装脚本先执行面积优化综合，再以低内存单进程完成布局布线、报告和 bitstream。日志与 `.Xil` 均写入 `matlab_fir/national_finals/_work/vivado/<时间戳>`，正式报告和 bitstream 仍发布到 `vivado_results/board_dual_rate_areaopt`。

## 7. SW1～SW8 与预期 DA_CLK

板载 15 kHz、0.5FS、signed 24 bit 测试音用于直观验收。1x 是保留的诊断档，正式赛题输出为 4x/8x/128x。

| 按键 | 家族 | 模式 | 理论/实现 DA_CLK |
|---|---:|---:|---:|
| SW1 | 44.1 kHz | 1x 诊断 | 44,099.972 Hz |
| SW2 | 44.1 kHz | 4x | 176,399.887 Hz |
| SW3 | 44.1 kHz | 8x | 352,799.774 Hz |
| SW4 | 44.1 kHz | 128x | 5,644,796.380 Hz |
| SW5 | 48 kHz | 1x 诊断 | 48,000.530 Hz |
| SW6 | 48 kHz | 4x | 192,002.119 Hz |
| SW7 | 48 kHz | 8x | 384,004.237 Hz |
| SW8 | 48 kHz | 128x | 6,144,067.797 Hz |

## 8. 实板验收清单

1. 用 Vivado Hardware Manager 下载上述 `.bit`，记录器件 ID、下载时间和 DONE 状态。
2. 上电默认应为 44.1 kHz / 128x；确认 DAC 静态中点正常，无持续满量程。
3. 依次按 SW2、SW3、SW4、SW6、SW7、SW8，用频率计或示波器测 `DA_CLK`，与上表比较；建议允许 ±0.02%。
4. 在 44.1↔48 kHz 家族切换时同时观察 `DA_CLK` 和 DAC 输出。允许受控静音/复位窗口，不允许持续毛刺时钟、锁死或满量程直流。
5. 用示波器确认 `dac_data` 在 `DA_CLK` 上升沿前稳定；当前 RTL 在音频主时钟下降沿更新 DAC 数据。
6. 用频谱仪检查六个正式档均有约 15 kHz 主音；记录主音幅度、首镜像频带和噪声底。重点验证 128x 首镜像抑制不低于 70 dB。
7. 每档至少切换 20 次并进行 10 分钟连续运行，检查无失锁、无异常啸叫、无输出冻结。
8. 如需 ILA，优先观察 `family_active`、`rst_audio_n`、`mode_state`、`selected_valid`、`dac_clk`；ILA 会改变资源与布局，最终提交仍应使用无 ILA bitstream。
9. 将六档 DA_CLK 实测值、频谱截图、板卡照片和供电电流回填到本文；全部满足后再把“实物 FPGA 验证”复选框改为 `[x]`。
