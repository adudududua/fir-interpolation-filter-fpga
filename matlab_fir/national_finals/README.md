# 全国总决赛：双采样率可配置插值滤波器

当前版本已完成 MATLAB 建模、24 bit 定点模型、RTL、9 项 XSim 回归、Vivado 综合/布局布线/时序/DRC/功耗评估和 bitstream 生成。所有软件与 FPGA 工具验收均已通过；由于当前环境无法接触实物开发板，物理板下载和仪器测量仍需按本文最后一节执行，不能把 bitstream 成功等同于实板通过。

开发分支：`codex/national-finals-cic-6dsp-further-opt`

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

当前正式版布局布线后为 **528 LUT / 532 FF / 229 Slice / 6 DSP / 3 BRAM / 2 MMCM**。相对最初指定的 573 LUT / 621 FF / 255 Slice / 6 DSP CIC 基线，减少 45 LUT、89 FF 和 26 Slice；相对上一轮 557 LUT / 536 FF 正式版又减少 29 LUT 和 4 FF。DSP、BRAM、MMCM 以及 0.271 W Vectorless 功耗均不增加。

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
| 串行 comb CIC 等价性 | 连续、停顿、burst 中复位和 3840 个输出 | PASS |
| MMCM/BUFGMUX | 双频率、往返切换、无 runt 高脉冲 | PASS |
| 矩阵键盘 | SW1～SW8 家族/倍率映射 | PASS |
| 板级顶层 | 上电复位、共享扫描、SW2、SW6、保护切换 | PASS |
| 全链路 bit-true | impulse + 固定种子随机 PCM；4x/8x/128x | PASS，0 LSB |
| 全链路复位恢复 | 8 个内部状态场景，每场景比较 4096 个 128x 输出 | PASS，8/8 |
| 动态倍率切换 | 不复位连续切换 10 次；检查 runt、X、锁死和冻结 | PASS，10/10 |

最终一次发布回归目录为 `_work/rtl_regression/20260730_205231`。九项测试全部通过；所有逐点比较节点无 X、无丢样、无数值失配。证据摘要见 [nf_rtl_regression_summary.txt](results/nf_rtl_regression_summary.txt)。

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
| Slice | 229 / 8150（2.81%） |
| Slice LUT | 528 / 20800（2.54%） |
| Slice register | 532 / 41600（1.28%） |
| BRAM tile | 3 / 50（6.00%） |
| DSP48E1 | 6 / 90（6.67%） |
| BUFGCTRL / MMCM | 2 / 2 |
| WNS / TNS | +45.075 ns / 0 ns |
| WHS / THS | +0.078 ns / 0 ns |
| 路由错误 | 0，1547/1547 可布线网络全部完成 |
| DRC Error | 0 |
| Vectorless 功耗 | 0.271 W（动态 0.199 W，静态 0.072 W，Medium confidence） |

Vivado DRC 报告仍有 73 条 Warning 和 1 条 Advisory，主要是面积优先结构中未加流水的 DSP 性能建议，以及 DSP/BRAM 异步控制检查。当前时序余量很大、路由完整、DRC Error 为 0 且 bitstream 已成功生成；这些警告不是“已物理验证”的替代品，首次上板仍要重点检查复位和采样率切换。

签核摘要见 [nf_hardware_signoff_summary.txt](results/nf_hardware_signoff_summary.txt)。

bitstream：

```text
matlab_fir/national_finals/vivado_results/board_dual_rate_cic6_opt/
national_finals_dual_rate_4x8x128x_areaopt.bit
```

SHA-256：`C9C9421D07B02D39F90423D83BDC6AE2B1D60C49D43A4FFF4D19C4EF62EB6203`

### 5.1 两轮 6-DSP CIC 优化结果

第一轮固定同一个综合 DCP 对五个 `opt_design` 指令进行了完整实现扫描；第二轮在继续压缩 RTL 后对 `Default / Explore / AddRemap` 再做完整实现扫描。每个最终候选均完成布局布线、时序、DRC 和 bitstream：

| 候选 | LUT | FF | Slice | DSP | WNS / WHS | 结论 |
|---|---:|---:|---:|---:|---:|---|
| 原 6-DSP 基线，ExploreArea | 573 | 621 | 255 | 6 | +46.339 / +0.072 ns | 对照 |
| 基线 RTL，Default | **556** | 621 | 229 | 6 | +45.294 / +0.092 ns | 策略最低 LUT |
| DSP PREG，Default | **556** | 557 | 231 | 6 | +45.936 / +0.106 ns | 最低 LUT 候选 |
| DSP PREG + 组合交接，Default | 557 | 536 | 228 | 6 | +45.614 / +0.105 ns | 上一轮正式版 |
| 第二轮 RTL，Explore | **528** | **532** | **229** | **6** | **+45.075 / +0.078 ns** | 与 Default 同资源 |
| 第二轮 RTL，AddRemap | **528** | **532** | **229** | **6** | **+45.075 / +0.078 ns** | 与 Default 同资源 |
| **第二轮 RTL，Default** | **528** | **532** | **229** | **6** | **+45.075 / +0.078 ns** | **当前正式版本** |

当前正式版综合后为 554 LUT / 532 FF，`opt_design` 后布局布线结果进一步收敛到 528 LUT / 532 FF。三种最终实现策略资源和时序完全一致，因此选择流程最简单、复现性最好的 `Default`。两轮累计保留的结构优化是：

1. 两个隐藏 CIC 积分状态采用 DSP48E1 PREG 原生同步复位；所有外部可见控制、最终状态、valid 和输出仍保持异步复位，并已通过 8 个复位恢复场景。
2. 仅在串行 CIC 模式下取消均衡器冗余输出寄存器，由 CIC 输入事务直接捕获组合结果；均衡器默认的寄存输出兼容接口没有改变。
3. 串行 CIC 的三级 comb 历史统一为 22 bit，并在三个 comb 周期中轮转，使 DSP 输入固定读取第 0 级历史，消除了原 23 bit 三选一宽位复用器。该模块由 44 LUT / 136 FF 降到 18 LUT / 138 FF；增加 2 个 FF，换得 26 个 LUT。
4. CIC 的 16 拍 burst 剩余计数由 5 bit 收窄为 4 bit，`burst_pending` 继续单独表示首拍，因此 16 个输出的协议没有改变。
5. Stage1 累加器由 42 bit 收窄到 41 bit。26 个非零系数绝对值之和为 44756，最坏界 `2^24 × 44756 = 750881079296`，小于 signed 41 bit 正上限 `2^40-1 = 1099511627775`，因此不会溢出；默认兼容配置仍保留 42 bit。
6. Stage2/3 调度状态由 2 bit 的级号压成 1 bit `job_stage3`，固定 MAC 次数改为由级号和相位组合生成，不再保存 4 bit `job_mac_count`。

淘汰项也进行了真实综合或仿真：均衡运算融合进串行 comb DSP 为 581 LUT / 622 FF；改为共享 Stage2/3 DSP 的版本在修正 signed 系数扩展后虽 0 LSB 通过，但综合为 592 LUT / 558 FF；Stage1 显式 DSP48 预加器为 586 LUT / 578 FF；均衡器再缩 1 bit 没有 LUT 收益；把 pending 合并进 burst 计数则在第 16 个样点破坏等价性。上述候选均已回退，不进入正式 RTL。整个 CIC 改同步复位也因破坏异步复位断言而淘汰。完整策略数据见 [cic6_implementation_strategy_scan.csv](results/cic6_implementation_strategy_scan.csv)，优化记录见 [cic6_further_optimization_summary.txt](results/cic6_further_optimization_summary.txt)。

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

包装脚本先执行面积优化综合，再以低内存单进程完成布局布线、报告和 bitstream。默认实现指令是本轮扫描选出的 `Default`，默认结果目录为 `vivado_results/board_dual_rate_cic6_opt`。日志与 `.Xil` 均写入 `matlab_fir/national_finals/_work/vivado/<时间戳>`，不会污染项目根目录。

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
