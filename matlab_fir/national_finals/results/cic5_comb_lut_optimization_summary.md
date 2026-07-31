# 全国赛 CIC 5-DSP comb-LUT 优化签核

## 优化目标与方法

从已验证 Route 1（424 LUT / 471 FF / 188 Slice / 6 DSP）出发，保持 FIR 系数、定点位宽、舍入、饱和、valid 和 burst 协议不变。Route 1 的 DSP 分配为两颗 FIR、一个串行 CIC comb、三个 CIC integrator。本轮仅将低速 comb 的 23-bit 减法定向到 LUT/CARRY4，三个每个 128x 时钟都更新的 integrator 仍显式保留在 DSP48E1。

正式参数：

```text
USE_NATIONAL_FINALS_SERIAL_CIC_COMB = 1
USE_NATIONAL_FINALS_CIC_COMB_DSP   = 0
```

## 实现结果

器件 `XC7A35T-FGG484-2`，顶层 `board_demo_competition_dac8_top`，Vivado 2018.3，`AreaOptimized_high + ResourceSharing=on + opt_design Default`。

| 项目 | Route 1 | 5-DSP comb-LUT | 变化 |
|---|---:|---:|---:|
| Slice LUT | 424 | **436** | +12 |
| Slice register | 471 | **471** | 0 |
| Slice | 188 | **181** | -7 |
| DSP48E1 | 6 | **5** | -1 |
| BRAM tile | 3 | **3** | 0 |
| MMCM | 2 | **2** | 0 |
| WNS / WHS | +45.356 / +0.117 ns | **+45.662 / +0.116 ns** | 均无违例 |
| TNS / THS | 0 / 0 ns | **0 / 0 ns** | 0 |
| Vectorless 功耗 | 0.271 W | **0.271 W** | 报告精度下不变 |

综合阶段为 `448 LUT / 469 FF / 5 DSP / 3 BRAM Tile`；上表资源为最终布局布线后结果。DSP 原语层级清单严格为 Stage1 一颗、Stage2/3 共享一颗、三级 CIC integrator 三颗，comb 不再占 DSP。

## 验证结果

- 全国赛 XSim 回归：**10/10 PASS**；
- CIC 单元等价：连续、停顿、burst 中复位，共 3840 个输出 PASS；
- 全链路：impulse + 固定种子随机 PCM，4x/8x/128x 全部 0 LSB；
- 复位恢复：8/8 场景 PASS；不停机倍率切换：10/10 PASS；
- MATLAB：44.1/48 kHz × 4x/8x/128x 六工况全部满足 ±0.05 dB、阻带不低于 70 dB、严格线性相位；
- Timing：WNS/TNS `+45.662/0 ns`，WHS/THS `+0.116/0 ns`，setup/hold 失败端点 0；
- Route：1329/1329 个可布线网络全部完成，routing error 0；
- DRC：0 Error、0 Critical Warning，65 Warning、1 Advisory；
- bitstream 已生成。

最终目录：`vivado_results/board_dual_rate_cic5_comb_lut_v1_final`。

bitstream SHA-256：`B344EB816AF39F0F0C14DCFCEAF9F0735E94EEDF509116BC68569BB0938C8F17`。

## 结论

该版本不是绝对最低 LUT：若评分首先看 LUT，Route 1 的 424 LUT / 6 DSP 仍最优；若希望在近似相同 LUT 水平下降低 DSP，本版本用 12 LUT 换 1 DSP，同时减少 7 Slice，是新的低 DSP Pareto 候选。物理开发板下载和仪器测量仍需现场完成。
