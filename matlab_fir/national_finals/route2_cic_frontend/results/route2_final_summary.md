# 全国赛创新结构 Route 2 最终签核摘要

## 结论

Route 2B 采用 `FIR2 x3 -> canonical HB2 x2 -> CIC4, N=2`，完整布局布线后为 **570 LUT / 551 FF / 229 Slice / 5 DSP / 3 BRAM Tile / 2 MMCM**。它是当前完成 MATLAB、逐位 RTL、板级集成、布局布线、时序、DRC、功耗和 bitstream 全流程的最低 DSP FIR-CIC 方案，但不是最低 LUT 方案。

最低 LUT 仍为 Route 1 的 **424 LUT / 471 FF / 188 Slice / 6 DSP / 3 BRAM / 2 MMCM**。因此两者构成 Pareto 点：比赛若首先比较 LUT，选 Route 1；若必须把 DSP 从 6 降到 5，选 Route 2B。

## 结构搜索与 Stop/Go

| 候选 | 结构 | 结果 | 决策 |
|---|---|---|---|
| Route 2A | 前置 CIC2/N1 + 177-tap 补偿插值 FIR | 频响通过，但需要 362 个 MAC/控制周期，现有 128 周期预算不足 | NO-GO-TIMING |
| Route 2B | 三个 FIR2 + 两个 canonical HB2 + CIC4/N2 | 六工况频响通过；全链路逐位通过；完整实现和 bitstream 通过 | 保留为 5-DSP Pareto 版 |
| Route 2C | 三个 FIR2 + 一个 canonical HB2 + CIC8/N3 | 六工况频响、三类逐位向量和综合通过；512 LUT / 473 FF / 6 DSP / 3 BRAM（综合） | 被 424-LUT Route 1 在同为 6 DSP 时支配，不进入实现 |

Route 2B 中 Stage1 使用 97-tap Q16 系数；Stage2 保持 Q15；Stage3 使用 11-tap Q14 补偿系数：

```text
[231 14 -1722 -75 9683 16506 9683 -75 -1722 14 231]
```

两个半带级均使用严格对称 canonical 系数 `[-1 0 9 16 9 0 -1]/16`，并共享一套紧凑移位加法数据通路。五颗 DSP 的确切分配为：Stage1 串行 MAC 1 颗、Stage2/3 共享 MAC 1 颗、CIC4 两级 comb 串行共享 1 颗、两级 integrator 2 颗。

Route 2C 的 Stage3 Q14 系数为：

```text
[242 21 -1810 -212 9759 16768 9759 -212 -1810 21 242]
```

## MATLAB 六工况频响

### Route 2B：5 DSP 正式实现候选

| 输入 | 节点 | 通带最大绝对偏差 | 通带峰峰纹波 | 阻带衰减 | 对称误差 | 结果 |
|---:|---:|---:|---:|---:|---:|---|
| 44.1 kHz | 4x | 0.005984828 dB | 0.007584394 dB | 73.418312 dB | 0 | PASS |
| 44.1 kHz | 8x | 0.010568993 dB | 0.010568223 dB | 73.437834 dB | 0 | PASS |
| 44.1 kHz | 128x | 0.005872423 dB | 0.007975631 dB | 71.584977 dB | 2.22e-16 | PASS |
| 48 kHz | 4x | 0.005984828 dB | 0.006860989 dB | 73.418312 dB | 0 | PASS |
| 48 kHz | 8x | 0.009555171 dB | 0.009554523 dB | 73.437834 dB | 0 | PASS |
| 48 kHz | 128x | 0.005872423 dB | 0.006874301 dB | 71.584977 dB | 2.22e-16 | PASS |

### Route 2C：单半带综合候选

| 输入 | 节点 | 通带最大绝对偏差 | 通带峰峰纹波 | 阻带衰减 | 结果 |
|---:|---:|---:|---:|---:|---|
| 44.1 kHz | 4x | 0.005984828 dB | 0.007584394 dB | 73.418312 dB | PASS |
| 44.1 kHz | 8x | 0.036819151 dB | 0.036818373 dB | 73.350793 dB | PASS |
| 44.1 kHz | 128x | 0.005975698 dB | 0.007464385 dB | 73.475560 dB | PASS |
| 48 kHz | 4x | 0.005984828 dB | 0.006860989 dB | 73.418312 dB | PASS |
| 48 kHz | 8x | 0.033682147 dB | 0.033681493 dB | 73.350793 dB | PASS |
| 48 kHz | 128x | 0.005975698 dB | 0.006616127 dB | 73.475560 dB | PASS |

全部工况满足通带最大绝对偏差不超过 0.05 dB、阻带衰减不低于 70 dB。Route 2B 的三节点冲激响应严格对称；Route 2C 使用各级对称 FIR/CIC 结构，数学模型同样保持线性相位。

## RTL 与板级集成回归

- Route 2B 全链路逐位：impulse、固定随机、满量程随机三类输入均通过，4x/8x/128x 全部 **0 LSB mismatch**；输出计数分别为 `1229/2467/39540`、`4301/8611/137844`、`2253/4515/72308`。
- Route 2C 全链路逐位：三类输入均通过，4x/8x/128x 全部 **0 LSB mismatch**；输出计数分别为 `1229/2467/39536`、`4301/8611/137840`、`2253/4515/72304`。
- 全国赛公共回归：**9/9 PASS**，包括 ROM、均衡器、CIC 串行等价、双采样率 MMCM/无毛刺切换、按键、板级集成、旧正式链逐位、8 个复位恢复场景和 10 次不停机倍率切换。

## Route 2B 布局布线签核

| 项目 | 结果 |
|---|---:|
| LUT / FF / Slice | 570 / 551 / 229 |
| DSP48E1 | 5 |
| BRAM Tile | 3（6 个 RAMB18E1） |
| MMCM / IO | 2 / 17 |
| WNS / TNS | +46.258 ns / 0 ns |
| WHS / THS | +0.118 ns / 0 ns |
| Setup / hold failing endpoints | 0 / 0（总端点 1896） |
| Vectorless 功耗 | 0.271 W（Dynamic 0.199 W，Static 0.072 W，Medium confidence） |
| DRC | Error 0；61 条 warning/advisory，均为 DSP 流水建议、动态 OPMODE 和 RAM 异步控制检查 |

bitstream：`matlab_fir/national_finals/vivado_results/board_dual_rate_route2b_5dsp_final/national_finals_dual_rate_4x8x128x_areaopt.bit`

SHA-256：`96F1BEE26BD6EDE53B3F8FB431A38C11F31AFF65549579518AA3CE2D2CA42D3E`

## 版本与边界

- Route 1 分支：`codex/national-finals-unified-fir-engine-v1`
- Route 1 标签：`national-finals-route1-424LUT-471FF-6DSP-3BRAM-2MMCM`
- Route 2 分支：`codex/national-finals-cic-front-end-v1`
- Route 2 标签：`national-finals-route2-570LUT-551FF-5DSP-3BRAM-2MMCM`
- Route 2 物理板下载仍需现场执行；本文的“板级通过”只表示完整板级顶层仿真、布局布线、时序、DRC 和 bitstream 通过，不把 bitstream 成功误写为物理板实测通过。
