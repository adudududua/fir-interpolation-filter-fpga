# P4-A N3 Hold 4-DSP 签核

## 结论

P4-A 已完成软件与 FPGA 工具侧闭环。结构使用严格多速率恒等式：

```text
C^3 -> upsample-by-16 -> I^3
  ==
C^2 -> hold each sample for 16 output enables -> I^2
```

两级 comb 映射到 LUT/CARRY4，两级高速积分器映射到 DSP48E1。33-bit modulo 宽度、最终右移 8 bit、舍入饱和、输出样点序列和 valid 周期均保持不变。

## 验证

- N3 Hold 与旧 N3 串行 comb CIC：连续 320 事务、随机停顿 480 事务、复位中断，共比较 7680 个输出，0 LSB。
- 全国赛 XSim：12/12 PASS；包含统一系数 RAM、CDC 1200 次事务、全链冲激/随机、8 个复位内部状态、动态模式切换。
- 全链 Stage1、Stage2、Stage3 与 128x 输出：0 LSB。
- 频响、Q15 系数和绝对增益不变，沿用 P1 已通过的六工况门禁。
- bitstream 成功生成；物理开发板下载、示波器和音频仪器仍是现场门禁。

## 同口径 post-route 结果

| 指标 | P3 | P4-A | 变化 |
|---|---:|---:|---:|
| LUT | 462 | 491 | +29 |
| FF | 447 | 444 | -3 |
| Slice | 180 | 197 | +17 |
| DSP48E1 | 5 | 4 | -1 |
| BRAM Tile / RAMB18E1 | 3 / 6 | 3 / 6 | 0 |
| MMCM | 2 | 2 | 0 |
| WNS / WHS | +46.140 / +0.050 ns | +45.738 / +0.052 ns | 全部通过 |
| 功耗 | 0.271 W | 0.271 W | 0 |

AD9708 的 44.1 kHz 家族最差 setup/hold 为 `+84.287/+86.288 ns`，48 kHz 家族为 `+76.116/+78.117 ns`。DRC 中旧 P3 的 `DPREG-4` 已消失；剩余两条 `DPOP-1` 是面积优先积分器未启用 PREG 的性能建议，在 45.738 ns WNS 下书面 waiver。CDC-13 为专用 BUFGMUX 选择入口，CDC-15 为已通过 1200 次原子握手测试的 bundled-data 总线，均沿用 P3 说明且未通过降级或 false path 隐藏。

bitstream：`vivado_results/board_dual_rate_p4a_n3_hold_v1/national_finals_dual_rate_4x8x128x_areaopt.bit`

SHA-256：`D262BA94186D992016FE9FACD157E34FDB29EDF0F9A3433A38833A65B101C334`

P4-A 是 DSP 优先 Pareto 点：真实减少 1 DSP，但增加 29 LUT 和 17 Slice。P3 与 P4-A 均需保留，后续 P4-B 只从本标签继续做 BRAM 调度，不覆盖此回退点。
