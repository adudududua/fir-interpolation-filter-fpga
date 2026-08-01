# P1 TWO24 CIC 3-DSP 候选验证总结

## 结论

P1 用一个 `DSP48E1/USE_SIMD=TWO24/PREG=1` 承担 CIC 两级积分器的 24-bit 低位段，小宽度有符号高位段与进位在 CARRY4 中精确补齐。完整板级实现为 **518 LUT / 498 FF / 197 Slice / 3 DSP / 2 BRAM Tile / 2 MMCM**，并通过 Release 17/17。

相比 P4-D `479 LUT / 468 FF / 4 DSP`，P1 以 **+39 LUT / +30 FF** 换取 **-1 DSP**。它是一个经过完整实现的 3-DSP Pareto 点，但不取代 P4-D 的最低 LUT/FF 默认版。

## 四级 Stop/Go 验证

### P1-A 整数周期模型

- P1-S（低位拆分 + 高位精确重建）：20 个 seed、连续/停顿/复位路径全部 0 mismatch，Go。
- P1-L（纯流水延迟假设）：有限向量末尾少一个输出，除非增加额外积分更新或加宽，因此 No-Go。
- 实际进入 RTL 的只有 P1-S。

### P1-B DSP48E1 UNISIM

- `events=7461`、`commits=7413`、`resets=84`。
- 连续 II=1、stall/resume、低位更新与高位提交之间复位全部通过。
- 实例属性确认为 `USE_SIMD=TWO24`、`USE_MULT=NONE`、`PREG=1`，两个 lane 的 carry 与符号高位对齐正确。

### P1-C CIC 等价与 OOC

- 连续 320 组、随机停顿 480 组、20×256 seed、中途复位：95107 个输出全部 **0 LSB**。
- 同条件 OOC 基线：70 LUT /119 FF /2 DSP，WNS/WHS `+150.805/+0.158 ns`。
- TWO24 OOC：106 LUT /137 FF /1 DSP，WNS/WHS `+158.129/+0.158 ns`。
- OOC 结论是 `-1 DSP / +36 LUT / +18 FF`，与完整板级方向一致；正式资源仍以板级 post-route 为准。

### P1-D 完整板级

- Smoke/Release：**17/17 PASS**。
- 冲激 + 10 seed×4096 + 正/负满幅，4x/8x/128x 逐样本 0 LSB。
- 复位后零输出、8 个中间状态复位场景、10 次动态倍率切换全部通过。

## 板级 post-route 数据

| 版本 | LUT | FF | Slice | DSP | RAMB18 / Tile | MMCM | WNS / WHS | DAC setup / hold | 矢量缺省功耗 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P4-D | 479 | 468 | 198 | 4 | 4 / 2.0 | 2 | +45.734 / +0.121 ns | +76.116 / +78.117 ns | 0.271 W |
| **P1 TWO24** | **518** | **498** | **197** | **3** | **4 / 2.0** | **2** | **+45.933 / +0.114 ns** | **+76.116 / +78.117 ns** | **0.270 W** |

- 设计完全布线，0 routing error，0 timing failing endpoint。
- bundled-data 实测 skew 1.809 ns，50 ns 约束余量 48.191 ns。
- vectorless 功耗为 0.270 W（dynamic 0.198 W / static 0.072 W），Confidence=Medium，只作方向性对比。
- DRC 仅保留 5 条 `DPIP-1` 性能建议，无 Error/Critical Warning。

## 频率响应与 bitstream

P1 只改 CIC 积分器的等价实现，不改系数、字长、舍入、饱和或滤波传递函数；因此沿用 P4-D clean release-v2 六工况数字：

| 输入 | 4x 通带 / 阻带 | 8x 通带 / 阻带 | 128x 通带 / 阻带 |
|---:|---:|---:|---:|
| 44.1 kHz | 0.003011 / 78.670 dB | 0.003470 / 78.565 dB | 0.005146 / 72.335 dB |
| 48 kHz | 0.003011 / 78.670 dB | 0.003033 / 78.565 dB | 0.003477 / 72.335 dB |

- 源码提交：`82a28e44dde1e166ba4f071a1219bfcb5ad52eb5`，构建起始为 clean。
- bit SHA-256：`8AFE9D20990AA1FA000EFFF6E764004B1C48DA087759B2011E079760DAB0CEAD`。
- 实现证据目录：`matlab_fir/national_finals/vivado_results/p4d_p1_two24_3dsp_candidate`。

该 bitstream 已通过软件、RTL 和 Vivado 闭环，但物理板卡下载、DA_CLK 和 DAC 频谱仍需现场执行，不把 bitstream 生成等同于实板测量完成。
