# P3 Stage 3/三抽头均衡器联合设计 MATLAB 门禁总结

## 结论

P3 按指导要求只执行 MATLAB 硬件感知可行性门禁，**未修改 RTL，未生成 P3 bitstream，也不把资源模型当成 Vivado 实现数字**。

最终选中一组 11-tap、Q15/18-bit 对称系数，仅供 128x 模式使用，4x/8x 仍使用 P4-D 平坦 Stage 3：

```text
[561, 137, -4232, -1554, 20046, 35584,
 20046, -1554, -4232, 137, 561]
```

该候选通过六工况浮点频响、10 类定点激励、18-bit 系数边界、线性相位和共享 DSP 调度门禁，因此结论为 **MATLAB Go，允许在后续独立分支进入 RTL A/B**。它并非已经优于 P4-D 的实现版。

## 搜索范围与修正过程

1. 保留 P4-D 平坦 Stage 3 + `[-1,10,-1]/8` 作为对照。
2. 把机械 13-tap 卷积加入反例组，但不宣称它与现有中间舍入严格 0 LSB 等价。
3. 将旧 Phase-7 11-tap 结果只作为种子，重新执行 44.1/48 kHz 六工况绝对指标。
4. 扫描 11/13/15/17 tap、9 组阻带权重和双采样率联合最小二乘候选。
5. 首次定点检查证明 20-bit Stage 3 输出会在强激励下截幅，因此保留 P4-D 已经使用的 signed-21 Stage3→CIC 峰值余量。
6. 原 11-tap 种子在 44.1 kHz/-1 dBFS 突然起振时比 P4-D 多 2 次 CIC 输出饱和；对称增益精扫后，`trim=0.99945` 把 CIC 计数降回与 P4-D 相同的 16 次，同时保持所有频响门禁。

## 六工况频响

| 输入 | 节点 | 形状最大偏差 | 峰峰纹波 | 绝对通带最大偏差 | 绝对阻带衰减 | DC 增益 | 相对 4x DC |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.004613 dB | 0.005709 dB | 0.003022 dB | 78.568 dB | -0.001591 dB | 0 dB |
| 44.1 kHz | 8x | 0.005322 dB | 0.006192 dB | 0.003521 dB | 78.609 dB | -0.002651 dB | -0.001060 dB |
| 44.1 kHz | 128x | 0.004482 dB | 0.005848 dB | **0.007730 dB** | **72.371 dB** | -0.006363 dB | -0.004773 dB |
| 48 kHz | 4x | 0.004613 dB | 0.005709 dB | 0.003022 dB | 78.568 dB | -0.001591 dB | 0 dB |
| 48 kHz | 8x | 0.005322 dB | 0.005678 dB | 0.003007 dB | 78.609 dB | -0.002651 dB | -0.001060 dB |
| 48 kHz | 128x | 0.004482 dB | 0.005724 dB | **0.007606 dB** | **72.371 dB** | -0.006363 dB | -0.004773 dB |

六工况对称误差为 0，相位拟合残差不超过 `1.42e-13 rad`。P3 入口门禁是绝对通带 ≤0.045 dB、128x 阻带 ≥71 dB、`|DC|≤0.01 dB`和模式 DC 差 ≤0.01 dB，全部通过。

## 定点边界与噪声

| 用例 | P3 Stage3 饱和 | P3 CIC 饱和 | P4-D CIC 饱和 | P3-P4D | SNR vs 浮点 |
|---|---:|---:|---:|---:|---:|
| 冲激 | 0 | 0 | 0 | 0 | — |
| 正满幅冲激 | 0 | 0 | 0 | 0 | 103.47 dB |
| 负满幅冲激 | 0 | 0 | 0 | 0 | 103.48 dB |
| seed 307817 随机噪声 | 0 | 0 | 0 | 0 | 97.81 dB |
| 44.1 kHz / -1 dBFS / 997 Hz | 0 | 16 | 16 | **0** | 80.86 dB |
| 44.1 kHz / -60 dBFS | 0 | 0 | 0 | 0 | 58.07 dB |
| 44.1 kHz / -90 dBFS | 0 | 0 | 0 | 0 | 29.86 dB |
| 48 kHz / -1 dBFS / 997 Hz | 0 | 0 | 0 | 0 | 116.73 dB |
| 48 kHz / -60 dBFS | 0 | 0 | 0 | 0 | 57.82 dB |
| 48 kHz / -90 dBFS | 0 | 0 | 0 | 0 | 30.28 dB |

正满幅冲激的 1 次总饱和位于未改动的 Stage1/2 前端，P3 Stage3/CIC 计数为 0；表中将继承前端计数与 P3 新路径分开报告。定点冲激重新测得 128x 绝对通带偏差 0.007741/0.007615 dB，阻带 72.372 dB，两家族都通过。

## 硬件调度和资源入口

- 11-tap 两相 MAC 任务数仍为 6/5，与 P4-D 平坦 Stage 3 一致。
- 按当前调度器的“1 拍接受 + N 拍 MAC + 1 拍结果 + 1 拍输出”计算，最坏延迟 9 拍，在 16 拍 `ce8` 窗口中保留 **7 拍余量**。
- 系数最大绝对值 35584，17 位有符号可表示，选择 18-bit 物理通道。
- P4-D 单块系数 RAMB18E1 的物理宽度已是 18 bit；后续 RTL 可重排地址为 Stage2 `0..31`、flat Stage3 `32..63`、Stage1 `64..89`、compensated Stage3 `96..127`，避免增加 BRAM。
- 模式必须在 Stage3 job 接受时原子快照；8x→128x 仍必须使用现有 mute/reset/warmup 协议，不允许新旧系数和旧 CIC 状态交叉。

保守 RTL 前资源模型：删除现有均衡器层级的 46 LUT/40 FF，为双 bank 地址/模式快照、18-bit 系数通道、21-bit Stage3 输出和调度常量预留 17 LUT/9 FF，预测净变化约 **-29 LUT / -31 FF**。只有在后续完整板级 post-route 报告确认后，才能将它改写为真实节省。

## 产物与下一步

- 搜索脚本：`p3_joint_stage3_equalizer/p3_01_search_joint_stage3_equalizer.m`
- 全部候选：`p3_joint_stage3_equalizer/results/p3_joint_stage3_equalizer_candidates.csv`
- 六工况指标：`p3_joint_stage3_equalizer/results/p3_joint_stage3_equalizer_six_mode_metrics.csv`
- 定点指标：`p3_joint_stage3_equalizer/results/p3_joint_stage3_equalizer_bittrue_metrics.csv`
- 选中系数与配置：`p3_joint_stage3_equalizer/results/p3_joint_stage3_equalizer_selected_coefficients.csv` 和 `p3_joint_stage3_equalizer_config.json`
- 响应图：`p3_joint_stage3_equalizer/figures/p3_joint_stage3_equalizer_response.png`

后续如进入 RTL，必须新建独立分支和 config ID，重新生成 golden，补齐 ROM 原语全地址测试、Stage3 单元对比、Smoke/Release 17/17、动态模式切换、完整 Vivado post-route/bitstream。在这些完成前，P4-D 仍是默认交付版。
