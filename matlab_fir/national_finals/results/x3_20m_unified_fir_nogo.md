# X3：20 MHz 统一三级 FIR 共享 MAC 执行报告

日期：2026-08-01

器件/工具：XC7A35T-FGG484-2 / Vivado、XSim 2018.3

研究分支：`codex/national-finals-x3-20m-unified-fir`

## 1. 结论

指导中的创新点“把 Stage1/2/3 搬到 20 MHz 系统时钟域，并让三级 FIR 共用一颗 DSP48E1”已经实际完成，不再只是预算分析。X3 的 RTL 位真结果为 **Go**：冲激加 10 个固定 seed×4096 的 Release 回归 **11/11 PASS**，4x/8x/128x 三个节点逐样本 **0 LSB**，没有输入 FIFO overflow、输出 bank overrun 或未知输出；20 MHz 与 6.144 MHz 两个时钟域的布局布线时序也都满足。

资源结果为明确的 **No-Go**。X3 滤波核心 post-route 为 **910 LUT / 692 FF / 307 Slice / 3 DSP / 5 RAMB18（2.5 BRAM Tile）**。同一 P4-D 板级实现中原滤波核心层级为 **377 LUT / 361 FF / 4 DSP / 3 RAMB18（1.5 BRAM Tile）**。公平的核心对核心比较表明，X3 只节省 1 DSP，却增加 **533 LUT、331 FF、2 RAMB18（1 BRAM Tile）**，因此不替代当前 P4-D `479 LUT / 468 FF / 4 DSP / 2 BRAM Tile` 发布版，也不继续做板级集成和 bitstream。

## 2. 实现的架构与调度

X3 保留既有真 Q15 系数、舍入、饱和、补偿器和 N3 Hold CIC，只重写前三段 FIR 与跨时钟传输：

```text
音频域 24-bit 输入
  -> 4-deep Gray 异步 FIFO
  -> 20 MHz 域 160-clock 帧调度器
       Stage1 / Stage2 / Stage3 共用 1×DSP48E1
  -> y2/y4/y8 双 bank 提交缓冲
  -> 音频域固定节拍读出
  -> 既有补偿器 + N3 Hold CIC（2×DSP48E1）
  -> 128x
```

每个输入帧使用 160 个 20 MHz 时钟，低于 48 kHz 最坏情况下相邻输入约 416.67 个 20 MHz 时钟的预算。调度表在 sys cycle 0/32 发出两个 Stage1 相位，在 0/32/64/96 发出四个 Stage2 相位；Stage3 安排在 8/24/.../120，使 Stage2 的结果有确定的交接窗口。输出采用 ping-pong bank：只有一帧全部写完才翻转 commit，源 bank 在两个输入帧内不会被重写，音频域在一个输入帧内读完，因此 payload 在消费窗口中保持稳定。

## 3. 实现过程中发现并修复的问题

1. 早期共享 MAC 的 Stage1 启动历史填充掩码不完整，冲激前沿不等价；补齐物理历史有效掩码后修复。
2. 6-bit 环形历史地址与无尺寸表达式混用，在地址 64 回绕后可能形成负数组下标；显式截断地址后，前端冲激对拍覆盖了物理回绕。
3. 导入的 Stage3 系数仍是历史 Q14 半幅值；改为签核真 Q15 系数 `404,-3272,19250,19250,-3272,404` 与 `-148,522,32016,522,-148`。
4. 输入 Gray FIFO 的 `wr_full` 组合定义自引用，形成组合环；改成寄存的 next-full 判定，最终 DRC 不再有 LUTLP。
5. FIFO 和输出 bank 的数据阵列若与控制一起复位，会阻止 LUTRAM 推断；拆分为无复位写进程后，64 个 LUT 被正确推断为分布式 RAM。
6. 异步复位进入 RAM 控制路径触发 BRAM `REQP-1840`；sys 域状态改为同步复位后该项消失。

这些修复只服务于 X3 研究分支，未修改稳定 P4-D 板级路径。

## 4. RTL 位真与跨时钟验证

| 验证 | 覆盖 | 结果 |
|---|---|---|
| FIR 前端单元测试 | 256 点冲激；y4 1245 点、y8 2499 点；覆盖 Stage1 历史地址回绕 | **0 LSB PASS** |
| Smoke 全链 | 冲激及短随机；y4/y8/y128 分别达到 1245/2499/40064 与 4317/8643/138368 点 | **2/2 PASS** |
| Release 全链 | 冲激 + 10 个固定 seed×4096；每个随机用例 16605/33219/531584 点 | **11/11 PASS，全部节点 0 LSB** |
| CDC 压力 | sys/audio 相位在每次复位后变化；监视 FIFO overflow、bank overrun 与 X 输出 | **无异常** |

Release 中 4x/8x/128x 仍按既有固定前导丢弃 3/7/112 点；testbench 对输出数量和逐点 golden 同时检查。XSim 最终用时约 374 s。

由于 Release 与 P4-D golden 逐样本 0 LSB，X3 继承相同的六工况频响：

| 输入 | 输出 | 通带最大绝对偏差 | 峰峰纹波 | 阻带衰减 |
|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.004610 dB | 0.005703 dB | 78.669 dB |
| 44.1 kHz | 8x | 0.005395 dB | 0.006174 dB | 78.562 dB |
| 44.1 kHz | 128x | 0.006116 dB | 0.008056 dB | 72.331 dB |
| 48 kHz | 4x | 0.004610 dB | 0.005703 dB | 78.669 dB |
| 48 kHz | 8x | 0.005395 dB | 0.005719 dB | 78.562 dB |
| 48 kHz | 128x | 0.006116 dB | 0.006116 dB | 72.331 dB |

## 5. 实现、时序、功耗与 CDC/DRC

### 5.1 资源的公平比较

| 滤波核心口径 | LUT | FF | Slice | DSP | RAMB18 / BRAM Tile |
|---|---:|---:|---:|---:|---:|
| P4-D 已布线滤波层级 | 377 | 361 | — | 4 | 3 / 1.5 |
| X3 20 MHz 统一 FIR OOC post-route | 910 | 692 | 307 | 3 | 5 / 2.5 |
| X3 相对 P4-D 核心 | **+533** | **+331** | — | **-1** | **+2 / +1.0** |

X3 的 910 LUT 中有 846 个逻辑 LUT 和 64 个 LUTRAM。不能把 X3 的 OOC 核心功耗或资源直接与 P4-D 完整板级数字混用；若只按已知层级做粗略板级面积估算，X3 约为 `479-377+910≈1012 LUT`，已经足以触发 No-Go。

### 5.2 时序与功耗

| 时钟域 | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|
| 6.144 MHz audio | +149.833 ns | 0 ns | +0.081 ns | 0 ns |
| 20 MHz sys | +34.839 ns | 0 ns | +0.072 ns | 0 ns |

X3 OOC vectorless 功耗为总/动态/静态 **0.076/0.005/0.070 W**。它不含板级双 MMCM、PCM ROM、按键和 DAC 包装，不能与 P4-D 完整板级 **0.271/0.199/0.072 W** 相减，也不能据此声称省电。

### 5.3 CDC 与 DRC 解释

Gray FIFO 的读写指针及输出 bank 的 commit/select 信号都经过同步；payload 使用 bundled-data 所有权协议，不在每一位上加同步器。CDC 报告因此对 FIFO 数据 RAM 和 y2/y4/y8 bank 给出 `CDC-15`，但 bank 只在完整帧提交后交给音频域、两帧内不重写，稳定窗口远大于同步延迟和一帧消费时间。若未来重启板级候选，仍应补充针对这些 bank 的物理 bus-skew/max-delay 约束和 post-route 检查。

最终 DRC 已消除 FIFO 组合环和 BRAM 复位控制告警。剩余 `NSTD-1/UCIO-1` 是 OOC 顶层没有绑定板级引脚的预期告警；DSP 的 DPIP/DPOP 是 20 MHz 下未增加额外流水级的性能建议，不构成功能或时序失败。

## 6. Go/No-Go 与回退路线

- **功能：Go。** 架构和 CDC 协议能工作，Release 长回归逐样本等价，双时钟时序满足。
- **资源：No-Go。** 节省 1 DSP 的代价是核心多 533 LUT、331 FF 和 1 BRAM Tile，明显劣于 P4-D。
- **板级：未进入。** 核心级面积已经越过停止线，因此没有修改稳定工程、没有伪造 X3 板级资源，也没有生成无意义的 X3 bitstream。可下载并做实物验收的默认版本仍是 P4-D。

复现实验使用已跟踪的 `vivado/synth_x3_20m_core.tcl`、`vivado/implement_x3_20m_core.tcl` 和两个 X3 testbench。Vivado/XSim 生成物保存在被 `.gitignore` 排除的 `matlab_fir/national_finals/_work/x3_20m/`，不会污染仓库根目录。
