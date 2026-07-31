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

- XSim 全国赛回归：10/10 PASS；
- 额外强制走 `RAMB18E1` 原语分支，逐地址核对 32 个 Stage1
  地址和 64 个 Stage2/3 地址：PASS；
- 4x/8x/128x 冲激与随机向量：逐点 0 LSB；
- 8 种内部状态复位恢复：PASS；
- 10 次无复位动态倍率切换：PASS；
- 综合：436 LUT / 469 FF / 6 DSP / 3 BRAM Tile；
- 相对同口径基线综合减少 16 LUT；
- Stage1 层级由 136 LUT 降至 120 LUT。

原始综合报告：
`vivado_results/board_dual_rate_route1_unified_coeff_ramb18_synth/`

原语级验证首次运行时发现 `INIT_05` 末尾漏写一个十六进制 `D`，
导致 Stage1 地址 80～89 在 bitstream 分支中发生半字节错位。行为
模型不会暴露这一错误。修复后原语 96 个地址全部通过，随后重新生成
了正式 bitstream；中间标签
`national-finals-route1-r1.1-436synth-6DSP-3BRAM` 仅作为结构回退点，
不应直接用于上板。

最终布局布线结果：

- 424 LUT / 471 FF / 188 Slice；
- 6 DSP / 3 BRAM Tile（6 个 RAMB18E1）/ 2 MMCM / 17 IO；
- WNS +45.356 ns，TNS 0，WHS +0.117 ns，THS 0；
- 0 个未布线网络、0 个 routing error；
- DRC：0 Error / 0 Critical Warning；其余 69 条 Warning 和 1 条
  Advisory 均为未加 DSP 流水及异步复位驱动 BRAM 地址的结构提示；
- vectorless 功耗 0.271 W（动态 0.199 W、静态 0.072 W，
  Confidence=Medium）；
- bitstream 生成成功。

相对 434 LUT / 469 FF / 190 Slice 的已实现基线，Route 1 最终减少
10 LUT 和 2 Slice，增加 2 FF；DSP、BRAM、MMCM、IO、功耗均不变。

正式实现目录：
`vivado_results/board_dual_rate_route1_unified_coeff_ramb18_final/`

## R1.2：Stage2 单次量化候选（验证通过，资源否决）

尝试把 Stage2 的 Q15→22 bit 和级间 22→20 bit 两次量化合并为
Stage2 DSP 提交周期内的一次 Q17→20 bit 量化，同时保留下一级偶相
CE 所需的两状态 valid-only 桥。

验证过程与结果：

- 重新生成融合舍入规则的 MATLAB 位真参考；
- XSim 全国赛回归 9/9 PASS；
- 4x/8x/128x 冲激与随机向量逐点 0 LSB；
- 8 种复位恢复和 10 次动态切换全部 PASS；
- 六工况 MATLAB 频响与严格线性相位全部 PASS；
- 综合：437 LUT / 467 FF / 6 DSP / 3 BRAM Tile。

与 R1.1 相比，该候选仅减少 2 FF，却增加 1 LUT。原因是被删除的
22→20 bit Slice 舍入器转移成了 Stage2 DSP 输出端的可变 Q15/Q17
选择与 20 bit 饱和逻辑，净面积没有下降。因此 R1.2 不进入最终
实现，路线 1 回到已标记的 R1.1。

原始实验综合报告保留在：
`vivado_results/board_dual_rate_route1_unified_coeff_fused_q17_synth/`
