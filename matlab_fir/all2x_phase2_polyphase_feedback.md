# 全 2x V2 Phase 2 true-polyphase 执行反馈

## 1. 结论

Phase 2 已完成 Stage 2、Stage 3 true-polyphase 和轻量级 bridge 的 RTL 实验闭环。

推荐结构为：

```text
Stage 1：稳定版单 DSP MAC
Stage 2：共享两相数据通路 true-polyphase
Stage 3：共享两相数据通路 true-polyphase
Stage 4～7：canonical halfband7 shift-add true-polyphase
级间桥接：valid-only，不复制 24bit 数据缓存
```

最终独立插值链结果：

```text
3975 LUT / 3103 FF / 1 DSP
WNS = +156.988 ns
随机 PCM RTL 对拍 = 0 LSB
冲激响应 RTL 对拍 = 0 LSB
```

相对最初稳定全 2x 基线：

```text
LUT：5912 -> 3975，减少 1937，下降 32.76%
FF ：4218 -> 3103，减少 1115，下降 26.43%
DSP：1 -> 1
```

相对 Phase 1 canonical tail 基线：

```text
LUT：4302 -> 3975，减少 327，下降 7.60%
FF ：3678 -> 3103，减少 575，下降 15.63%
```

## 2. 系数单一数据源

新增 MATLAB 导出脚本：

```text
v2_05_export_stage23_polyphase.m
```

它从稳定配置读取 Stage 2/3 整数系数，自动拆分为：

```text
Stage 2 phase0：9 tap
Stage 2 phase1：8 tap
Stage 3 phase0：6 tap
Stage 3 phase1：5 tap
```

并生成：

```text
stage23_polyphase_manifest.csv
stage23_polyphase_summary.txt
all2x_v2_coeff_pkg.vh
```

系数核对结果：

```text
Stage 2 phase0 = [-115 534 -1302 2116 30298 2116 -1302 534 -115]
Stage 2 phase1 = [-203 1233 -4595 19945 19945 -4595 1233 -203]
Stage 3 phase0 = [202 -1636 9625 9625 -1636 202]
Stage 3 phase1 = [-74 261 16008 261 -74]
```

## 3. 第一版实现及问题

第一版 true-polyphase 分别展开偶相和奇相组合乘加，并实例化两套舍入器。

结果：

| 版本 | LUT | FF | DSP | WNS / ns | 相对 Phase 1 |
|---|---:|---:|---:|---:|---|
| Phase 1 | 4302 | 3678 | 1 | +165.930 | 基准 |
| S3 双数据通路 | 4387 | 3492 | 1 | +161.885 | LUT +85，FF -186 |
| S2～S3 双数据通路 | 4570 | 3233 | 1 | +160.605 | LUT +268，FF -445 |

这一版虽然减少了真实历史状态，但两相组合网络重复展开，导致 LUT 上升。它满足功能要求，但不满足以 LUT 和 FF 同时下降为目标的合并条件，因此未作为最终结构。

## 4. 共享两相数据通路

根据第一版综合结果，将偶相和奇相改为：

```text
phase 选择输入样点与系数
        ↓
共享对称预加法与常系数乘加
        ↓
共享累加器组合路径
        ↓
共享舍入/饱和模块
```

结果：

| 版本 | LUT | FF | DSP | WNS / ns | 相对 Phase 1 |
|---|---:|---:|---:|---:|---|
| S3 共享数据通路 | 4141 | 3498 | 1 | +161.846 | LUT -161，FF -180 |
| S2～S3 共享数据通路 | 3985 | 3247 | 1 | +159.856 | LUT -317，FF -431 |

共享数据通路解决了第一版 LUT 上升问题，并保持 DSP 数量不变。

## 5. 轻量 bridge

原 `bridge_to_interp2_ce` 每级保存：

```text
24bit data_buf
1bit pending
1bit phase_mirror
```

综合后的六个 bridge 合计约占：

```text
180 LUT / 156 FF
```

上一级 FIR 输出已经是寄存器，并会保持到下一有效输出。因此 V2 新增：

```text
bridge_valid_only_to_interp2_ce.v
```

它只保存：

```text
1bit pending
1bit phase_mirror
```

数据直接使用上一级保持的寄存输出，不再复制 24bit 数据缓存。同时加入断言：

```text
pending=1
且本拍未消费
且又到达新输入
```

若出现该条件，仿真立即 `$fatal`。随机 PCM 和冲激响应仿真均未触发断言。

轻量 bridge 最终结果：

```text
3975 LUT / 3103 FF / 1 DSP
```

相对完整 bridge 版本额外减少：

```text
10 LUT / 144 FF
```

## 6. RTL 对拍

| 测试 | 候选 | 固定延迟 | 最大误差 | 不一致点数 |
|---|---|---:|---:|---:|
| 随机 PCM | S3 true-polyphase | 321 | 0 LSB | 0 |
| 随机 PCM | S2～S3 true-polyphase | 321 | 0 LSB | 0 |
| 随机 PCM | S2～S3 + light bridge | 319 | 0 LSB | 0 |
| 冲激响应 | S3 true-polyphase | 321 | 0 LSB | 0 |
| 冲激响应 | S2～S3 true-polyphase | 321 | 0 LSB | 0 |
| 冲激响应 | S2～S3 + light bridge | 319 | 0 LSB | 0 |

轻量 bridge 少两拍固定延迟，但没有改变输出样本值和顺序。

## 7. 频响

Phase 2 没有修改任何整数系数、FRAC_W 或逐级舍入规则，只把显式插零 FIR 改写为数学等价的两相结构。因此总频响沿用 Phase 1 结果：

```text
通带最大绝对误差：0.00715181 dB
阻带衰减        ：77.67735619 dB
严格线性相位    ：通过
```

## 8. 本阶段的变通

1. 指导建议直接删除 bridge。实际保留了两个控制位，因为完全无状态直连会让正确性隐含依赖 Verilog NBA 同拍行为。
2. 第一版两相独立展开虽然符合公式，但资源不理想，因此改为共享组合数据通路。
3. 没有增加 DSP。Stage 2/3 仍通过 LUT 常系数网络实现，保持总 DSP 为 1。
4. 没有覆盖 Phase 1 顶层。Phase 2 使用独立顶层和测试平台，方便回退和资源对照。

## 9. 下一步判断

Phase 2 已满足继续条件。下一优先级是指导中的 Phase 3：Stage 1 严格半带 + 单 DSP polyphase MAC。

Stage 1 目前仍是最大的状态来源：

```text
93 个显式插零历史样点
约 2295 FF 的 FIR 核状态
```

下一阶段应先在 MATLAB 设计严格半带系数并验证总链路，不应直接改 Stage 1 RTL。若严格半带量化后无法维持 `>=75 dB` 阻带和 `<=0.01 dB` 通带误差，则保留当前 Stage 1，不为结构整齐牺牲指标。
