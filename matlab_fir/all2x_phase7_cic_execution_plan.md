# 全 2x 插值滤波器 Phase 7 FIR-CIC 执行计划

## 1. 基线与保护原则

- 稳定回退版本：Phase 6 混合字长 FIR，已完成实板四档验证。
- Phase 6 板级资源：1395 LUT、1040 FF、2 DSP、1 BRAM Tile。
- Phase 6 同口径独立链：1222 LUT、868 FF、2 DSP、1 BRAM Tile。
- Phase 7 位于独立分支 `codex/phase7-fir-cic-hybrid`，Phase 6 RTL 文件和 generate 回退分支均保留。
- 板级展示接口保持 `15 kHz + 1x/4x/8x/128x + 单 DAC + 矩阵按键` 不变。

## 2. 修正版指导采纳结论

修正版已把标准 CIC 插值顺序更正为：

```text
低速输入 -> N 级 comb -> R 倍插零 -> N 级 integrator -> 高速输出
```

本阶段按该顺序完成 MATLAB、bit-true 和 RTL。补偿 FIR 放在 CIC 前的 352.8 kHz 低速端，CIC 实际输入为 20 bit。修正版的参数搜索、Hogenauer 风格剪枝、0 LSB 和 Stop/Go 门槛均有直接参考性，已采用。

由于 Phase 6 的 Stage4～7 已经是无 DSP 的 canonical halfband，CIC 不会降低现有 2 个 DSP。资源 Go 判据因此落实为独立链 LUT 至少下降 15%，而不是仅凭“CIC 无乘法器”判断。

## 3. 候选架构与变通

### 3.1 指导主方案：独立低速补偿 FIR

```text
Stage1 -> Stage2 -> Stage3 -> 15tap 补偿 FIR -> CIC16 -> 128x
```

该方案数学、定点和独立 RTL 0 LSB 均通过，但补偿 FIR 需要第 3 个 DSP。N=3 独立综合为 1199 LUT / 1154 FF / 3 DSP，N=4 为 1366 LUT / 1243 FF / 3 DSP，资源门槛 No-Go。

### 3.2 采用的变通：Stage3 折叠补偿

```text
Stage1 -> Stage2 -> 重新设计的 11tap Stage3 -> CIC16 -> 128x
```

把 CIC 通带逆下垂合并到原 Stage3 的 11tap Q15 系数中，Stage3 仍为每相位 3 次 MAC，继续复用 Stage2/3 的共享 DSP，不增加历史深度或调度周期。

## 4. 最终参数

| 项目 | 最终值 |
|---|---:|
| CIC 插值倍率 / 差分延迟 / 阶数 | R=16 / M=1 / N=3 |
| Stage3 taps | 11 |
| Stage3 系数格式 | Q15 / 17bit 数学系数 |
| CIC 输入输出 | 20bit signed |
| CIC 全精度内部宽度 | 32bit |
| CIC 剪枝 | 全精度，末级丢 0 LSB |
| Stage3 通带补偿后最大误差 | 0.00303062 dB |
| 总阻带衰减 | 72.349 dB |
| 随机 PCM Delta-SNR | 96.403 dB |
| 15 kHz / 20 kHz SINAD | 78.550 / 70.912 dB |
| MATLAB/RTL | 冲激与随机 PCM 均 0 LSB |

Stage3 Q15 系数为：

```text
561, 137, -4234, -1555, 20057, 35604,
20057, -1555, -4234, 137, 561
```

中心系数 `35604` 在 RTL 中等价拆成 `-29932 + 65536`。`-29932` 进入 16bit DSP 系数端，`65536*x` 在 MAC job 开始时预装进已有累加器，因此恢复 25x16 乘法器且输出不变。

## 5. Stop/Go 门槛

| 类别 | 门槛 | 最终 N=3 | 判定 |
|---|---:|---:|---|
| 通带最大绝对误差 | <0.01 dB | 0.00303062 dB | 通过 |
| 总阻带衰减 | >70 dB | 72.349 dB | 通过 |
| 随机 PCM Delta-SNR | >=94 dB | 96.403 dB | 通过 |
| MATLAB/RTL | 0 LSB | 前三级和 CIC 均 0 LSB | 通过 |
| 独立链 LUT | 至少下降 15% | 1222 -> 957，下降 21.69% | 通过 |
| DSP / BRAM | 不高于 Phase 6 | 2 / 1，保持不变 | 通过 |
| 独立综合时序 | WNS/WHS > 0 | +9.107 / +0.063 ns | 通过 |

最终决策：**折叠补偿 N=3 为 Go；独立补偿方案和 N=4 为 No-Go。**

## 6. 执行进度

| 步骤 | 状态 | 结果 |
|---|---|---|
| 7-A1：修正版指导复核 | 已完成 | 正确采用低速 comb -> 插零 -> 高速 integrator |
| 7-A2：CIC 阶数搜索 | 已完成 | N3/N4/N5 阻带 72.52/79.06/79.17 dB，均需补偿 |
| 7-B：独立补偿 FIR 搜索 | 已完成 | N3/N4 15tap Q12 数学通过，资源 No-Go |
| 7-C1：定点增长与剪枝 | 已完成 | 独立 N3/N4 分别 32/36bit；折叠候选重新搜索剪枝 |
| 7-C2：Stage3 折叠补偿 | 已完成 | 11tap Q15，N3/N4 数学与定点通过 |
| 7-D：CIC RTL 与 bit-true | 已完成 | 前三级四条流和 CIC 两组激励均 0 LSB |
| 7-D2：板级四档 XSim 回归 | 已完成 | 1x/4x/8x/128x 边沿数为 32/128/256/4096，数据持续变化 |
| 7-E：独立综合 Pareto | 已完成 | 最终 N3 957 LUT / 791 FF / 2 DSP / 1 BRAM |
| 7-F：板级接入 | 已完成 | 已登记工程、重跑实现并生成 Phase 7 bitstream |
| 7-G：报告与 README | 已完成 | 执行报告、资源图与 README 已同步 |
| 7-H：实板复测 | 待人工下载 | 复测 1x/4x/8x/128x DA_CLK 与波形平滑度 |

## 7. 板级构建结果

| 资源 / 时序 | Phase 6 | Phase 7 N=3 | 变化 |
|---|---:|---:|---:|
| LUT | 1395 | 1135 | -260，-18.64% |
| FF | 1040 | 962 | -78，-7.50% |
| DSP | 2 | 2 | 不变 |
| BRAM Tile | 1 | 1 | 不变 |
| WNS | +45.145 ns | +44.704 ns | 均通过 |
| WHS | +0.121 ns | +0.107 ns | 均通过 |
| DRC Error | 0 | 0 | 通过 |

Phase 7 bitstream：

```text
matlab_fir/alt_all2x_v7/vivado_results/board_folded_n3/
board_demo_competition_dac8_top_phase7_folded_n3.bit
```
