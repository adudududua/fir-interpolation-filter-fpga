# Route 1：统一双 DSP FIR 引擎实验记录

## 基线

- Git 标签：`national-finals-434LUT-469FF-6DSP-3BRAM-2MMCM`
- 综合：452 LUT / 469 FF / 6 DSP / 3 BRAM Tile
- 布局布线：434 LUT / 469 FF / 6 DSP / 3 BRAM Tile

## 周期预算

主时钟是 128x 输出时钟。最紧的 48 kHz 工况仍有固定的
128 拍输入超周期：

| FIR 任务 | 128 拍内最坏计算/提交拍数 |
|---|---:|
| Stage1，26 个对称 MAC 加一次提交 | 27 |
| Stage2，两相 9/8 个 MAC，加提交流水 | 42 |
| Stage3，四个 6/5 MAC 任务，加提交流水 | 60 |
| 如果只使用一颗 DSP 的合计 | 129 |

因此三段 FIR 压到一颗 DSP 没有可靠周期余量。Route 1 保留两条
DSP 计算通道，把共享重点放到系数存储、量化器和跨级调度。

## R1.1：统一双端口系数 RAMB18

Stage1 原来的 26 路系数 case 网络改由 Stage2/3 系数存储器的第二
读端口提供。为避免 Vivado 2018.3 将双读口推断 ROM 复制成两块
RAMB18，正式候选使用显式 `RAMB18E1`：

- A 口地址 64～89：Stage1 的 26 个对称系数；
- B 口地址 0～63：Stage2/3 的两相系数；
- 两条 FIR DSP 可以同拍读系数；
- 所有激活系数均可由 signed 16 bit 精确表示；
- BRAM Tile 和 DSP 数量不增加。

验证结果：

- XSim 全国赛回归：9/9 PASS；
- 4x/8x/128x 冲激与随机向量：逐点 0 LSB；
- 8 种内部状态复位恢复：PASS；
- 10 次无复位动态倍率切换：PASS；
- 综合：436 LUT / 469 FF / 6 DSP / 3 BRAM Tile；
- 相对同口径基线综合减少 16 LUT；
- Stage1 层级由 136 LUT 降至 120 LUT。

原始综合报告：
`vivado_results/board_dual_rate_route1_unified_coeff_ramb18_synth/`

## 后续

R1.2 将尝试把 Stage2 的 Q15→22 bit 和级间 22→20 bit 两次量化
合并为 Stage2 DSP 提交周期内的一次 Q17→20 bit 量化。该候选会
改变少量最低有效位，必须重新生成 RTL 位真参考并重新执行六工况
MATLAB 频响验收，不能用 R1.1 的 0-LSB 结论代替。
