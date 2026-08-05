# P3-M Stage1 DSP 内部寄存器优化执行反馈

## 1. 结论与发布口径

本轮从用户已完成 DAC 与六档采样率板测的 P3-L 正式版继续优化，要求保持 `4 DSP / 2 BRAM Tile / 2 MMCM`，FF 不明显增加，并把完整全国赛板级 LUT 降至 370～385 或更低。最终候选达到：

| 版本 | LUT | FF | Slice | DSP | RAMB18 / Tile | MMCM | WNS/WHS | Vectorless 功耗 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| P3-L 实板通过基线 | 397 | 409 | 161 | 4 | 4 / 2.0 | 2 | +44.408/+0.121 ns | 0.271 W |
| **P3-M DSP-register 正式版** | **368** | **386** | **156** | **4** | **4 / 2.0** | **2** | **+44.836/+0.117 ns** | **0.271 W** |

相对 P3-L 减少 **29 LUT、23 FF、5 Slice**；DSP、BRAM、MMCM 和功耗均不增加。P3-M 已完成 RTL、综合、实现、Timing、DRC/CDC、Bitstream、普通 Vivado GUI 重建和 routed-DCP 六模式 DAC 工具签核。**2026-08-05 用户完成物理板复测，确认各档位采样率均正常且 DAC 输出波形正常，因此 P3-M 正式升级为当前最低 LUT 的实板通过发布；P3-L 保留为前一实板安全回退。**

- 分支：`national-finals-p3m-stage1-dspreg-385target`
- 工具签核标签：`nf-p3m-toolverified-368lut-386ff-156slice-4dsp-2bram`
- 实板签核标签：`nf-p3m-final-368lut-386ff-156slice-4dsp-2bram-boardverified`
- 正式证据目录：`matlab_fir/national_finals/vivado_results/p3m_stage1_dspreg_synth_r1`
- Bitstream SHA-256：`7785D3B3110BC534A546BEAD1F05958DA736B99A46FA1D03800C406FCB5D7D7A`
- Routed DCP SHA-256：`631CDEF481C1DDE7D443C62B781392F467AFF98EEFC1A2ECBF267E6C146B2753`

## 2. 优化原理

P3-L Stage1 用一个 RAMB18E1 串行读取 26 组对称样本。旧调度为 `R0,L1,R1,...,L25,R25`，当前输入 `L0` 绕过 RAM，保存在 24-bit `left_sample` Slice 寄存器中；其他左样本返回时也先写入该寄存器。左右历史有效性又分别通过 24-bit Fabric 选择器把无效样本清零。这部分形成 Stage1 的主要 LUT/FF 热点。

P3-M 改为：

1. Phase-0 仍把当前 PCM 写入现有 Stage1 RAMB18E1，但不再直接送入 `left_sample`；
2. 读取顺序改成 `L0,R0,L1,R1,...,L25,R25`，写入后的 L0 在下一拍从同一个 RAMB18E1 读回；
3. `READ_LEFT` 返回时只使能 DSP48E1 `CEA2`，由 `AREG=1` 保存左操作数；
4. 随后的 `READ_RIGHT` 直接从 RAM 输出接到 DSP48 D 端，A+D 预加后乘系数并累加到 PREG；
5. 左历史无效时用 `INMODE[1]=1` 在 DSP 内部强制 A 为零，右历史无效时用 `INMODE[2]=0` 强制 D 为零；
6. 因而正式 `USE_DSP48_PREADDER=1` 配置可删除 24-bit Fabric 左样本寄存器、旁路 mux 和两侧宽掩码逻辑；
7. 64 个音频时钟的 Stage1 空闲窗口可容纳新增的一次 RAM 读取，MAC 截止时间不变。

该优化不修改 FIR 系数、Q15 舍入、41-bit 累加界、饱和、valid 相位、Stage2/3、CIC、测试音 ROM、按键、时钟或 DAC 接口。

## 3. 资源演进

| 检查点 | Synth LUT/FF | Routed LUT/FF/Slice | DSP | BRAM Tile | 判定 |
|---|---:|---:|---:|---:|---|
| P3-L 正式基线 | 449/420 | 397/409/161 | 4 | 2 | 已板测安全回退 |
| P3-M AREG/INMODE | **395/388** | **368/386/156** | **4** | **2** | Go，达到并超过目标 |
| 普通 GUI 从零重建 | 395/388 | **368/386/156** | **4** | **2** | 与独立单进程构建一致 |

综合减少 54 LUT、32 FF；布局布线后净减少 29 LUT、23 FF。综合与实现降幅不同来自 `opt_design` 的跨层 LUT 合并和物理映射，正式资源只采用 routed/placed 报告口径。

## 4. RTL 验证

### 4.1 Stage1 双模型等价

- 行为 RAM 模型：与签核双读 Stage1 比较 1400 个输出，**0 LSB**；
- `SYNTHESIS` + UNISIM RAMB18E1：同样比较 1400 个输出，**0 LSB**；
- 第二项专门验证“写入 L0 后下一拍读回”的物理 RAM 调度和 DSP48 动态 `INMODE`，避免只在行为数组上通过。

正式回归脚本现同时保留 `stage1_single_bram_equivalence` 和 `stage1_single_bram_primitive_equivalence`，防止后续修改绕过真实 RAMB18 语义。

### 4.2 完整回归

- 基线 Smoke：`_work/rtl_regression/20260804_232001`，16/16 PASS；
- 初次候选 Smoke：`_work/rtl_regression/20260804_232954`，16/16 PASS；
- 初次候选 Release：`_work/rtl_regression/20260804_233536`，16/16 PASS；
- **最终正式 Release**：`_work/rtl_regression/20260805_002145`，新增 RAMB18 原语等价项后 **17/17 PASS**；
- **最终正式 Smoke**：`_work/rtl_regression/20260805_003320`，同一份最终源码 **17/17 PASS**；
- Release 输入覆盖冲激、10 个固定随机 seed×4096、正/负满量程和 997 Hz/−1 dBFS 强信号，共14组；
- 4x、8x、128x 三个节点均逐样本 **0 LSB**；
- 8 类内部复位场景分别比较4096个128x输出；
- 10 次不停机倍率切换无 X、无短脉冲；
- 1200 次模式 CDC 原子事务、双 MMCM 频率/100次切换、键盘、ROM、Stage2/3、CIC 和 DAC offset-binary 单元均通过。

## 5. 频响保持

本轮只改变同一对称样本进入 Stage1 DSP48 的保存位置和调度，不改变任何系数或量化节点，因此沿用已经由 MATLAB 和 RTL impulse 签核的六工况：

| 输入 | 节点 | 通带最大绝对偏差 | 峰峰纹波 | 阻带衰减 | 对称误差 |
|---:|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 0 LSB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB | 0 LSB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB | 0 LSB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 0 LSB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB | 0 LSB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB | 0 LSB |

六工况均满足通带 ±0.05 dB、阻带不低于70 dB和严格线性相位要求。

## 6. 实现、Timing、DRC/CDC 与功耗

- 器件：`XC7A35T-FGG484-2`；
- 实现：368 LUT / 386 FF / 156 Slice / 4 DSP / 4 RAMB18E1 / 2 MMCM；
- WNS/TNS：`+44.836 ns / 0 ns`；
- WHS/THS：`+0.117 ns / 0 ns`；
- AD9708 output setup/hold：`+76.116/+78.117 ns`；
- mode bus skew：实际1.777 ns，要求50 ns，slack 48.223 ns；
- mode absolute datapath：0.792～0.843 ns，要求50 ns，最小 slack 49.066 ns；
- vectorless 总/动态/静态功耗：`0.271/0.199/0.072 W`，Medium confidence；
- DRC：0 Error，保留7条 DSP input pipeline、2条 CIC PREG 建议和1条 advisory；均为已知结构性建议，不阻止 Bitstream；
- CDC：保留 BUFGMUX 专用选择输入 `CDC-13 ×2`、原子模式握手 `CDC-15 ×4` 和同步器 Info；数量与 P3-L 一致，功能由切换仿真覆盖。

## 7. 布局布线后 DAC 与采样率验证

默认 44.1 kHz/128x routed-DCP 功能仿真运行6 ms：

- DAC edges：11290；
- DAC data changes：7461；
- `beep_io=1`；
- 结论：`BOARD POSTROUTE DAC ACTIVITY PASS`。

六模式仿真只根据 DUT 的 `key_kr` 驱动公开输入 `key_kc`，实际经过按键扫描、消抖、family guard、CDC、MMCM/BUFGMUX、ROM、插值链、DAC寄存器和ODDR，不 force 内部模式或时钟：

| 模式 | DAC edges / ms | data changes / ms | 结论 |
|---|---:|---:|---|
| 44.1 kHz / 4x | 177 | 175 | PASS |
| 44.1 kHz / 8x | 353 | 342 | PASS |
| 44.1 kHz / 128x | 5645 | 3709 | PASS |
| 48 kHz / 4x | 192 | 192 | PASS |
| 48 kHz / 8x | 384 | 372 | PASS |
| 48 kHz / 128x | 6144 | 3810 | PASS |

运行目录分别为 `_work/postroute_dac_activity/20260804_234857` 和 `_work/postroute_six_mode_dac/20260804_235012`。

## 8. 普通 Vivado GUI 可复现性

`verify_national_finals_gui_project.tcl rebuild` 使用普通 project flow 重新执行 `synth_1`、`impl_1` 和 `write_bitstream`，得到：

```text
GUI_LUT=368
GUI_FF=386
GUI_DSP=4
GUI_BRAM18=4
GUI_MMCM=2
NATIONAL_FINALS_GUI_IMPLEMENTATION_PASS
```

GUI 工程已核对 `AreaOptimized_high / flatten full / ResourceSharing on / opt_design Default` 及全部全国赛 generic。签核脚本把资源门槛更新为 `LUT <= 385`、`FF <= 420`，避免以后错误复用旧 DCP 仍被当成 P3-M。

## 9. 板测与回退

工具侧覆盖了此前“实现成功但 DAC 无波形”的失效模式，物理板最终门禁也已完成：

1. [x] 下载 P3-M bitstream，确认 DAC 输出波形正常；
2. [x] 切换各个采样率/倍率档位，确认实际采样率正常；
3. [x] 未发现持续静音或固定直流码；
4. [x] 升级为 `boardverified` 正式发布；
5. [x] P3-L `nf-p3l-final-397lut-409ff-161slice-4dsp-2bram-boardverified` 保持不动，作为前一实板安全回退。

用户未提供逐档精确仪器数值，本文只记录已经确认的通过结论，不虚构测量值。1x 档连续采集画面的多轨迹来自 15 kHz 测试音在 44.1/48 kHz 下每周期仅约 2.94/3.2 个采样点，以及示波器没有锁定到完整 ROM 序列起点；Single 采集、采样率和 DAC 连续输出均正常，不作为数字数据通路故障。
