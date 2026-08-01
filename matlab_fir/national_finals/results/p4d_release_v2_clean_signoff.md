# P4-D Release V2 干净发布签核

## 结论

P4-D Release V2 已从独立 detached worktree 的干净提交 `e55dca0f2f2f32e6be70706dffb964b9f64cfe2c` 完成 MATLAB、RTL、综合、布局布线和 bitstream 闭环。它不改变 P4-D 的滤波拓扑与样点序列，主要修复旧导出包的 20/21-bit golden 不一致、证据哈希不闭合和 CDC 绝对延迟约束被宽泛异步时钟组覆盖的问题。

正式配置 ID 为 `NF-P4D-R2-479LUT-468FF-4DSP-2BRAM-2MMCM`。正式 bitstream 位于 `vivado_results/p4d_release_v2_clean_signedoff/national_finals_dual_rate_4x8x128x_areaopt.bit`，SHA-256 为 `8630210663629357237AAA3F076348FBE65610EAAB61ADA4706E81F75AAF02A6`。

## 关键修复

- 均衡器的权威模型改为 signed-20 输入、signed-21 无损输出；正负满量程用例各产生一次越过 signed-20 边界的结果，旧模型会出现 5 次错误削顶。
- CIC 权威模型固定为 `C² → Hold16 → I²`，21-bit 输入、26/29-bit 模运算状态，与旧 `C³ → ↑16 → I³` 参考比较 8240 个样点，0 LSB。
- Release 向量扩展为 impulse、10 个固定 seed 和正/负满量程，共 13 组；三个正式节点都检查 reset-zero prefix 和逐样本 0 LSB。
- 频响检查不再使用 `freqz`，会先验证 config ID、系数/Q 格式、59 个资产哈希、RTL impulse 与 golden 前缀以及 golden 零尾，再计算绝对和归一化指标。
- CDC 从宽泛 ctrl/audio 异步时钟组改为精确同步器/BUFGMUX false path；两位 mode bundled-data 同时施加 50 ns bus skew 与 50 ns absolute datapath max-delay，并在 Tcl 内断言四条路径都存在且约束未被覆盖。
- 构建包装器在调用 Vivado 前保存 Git 源状态，并在结束时按字节恢复 Vivado 自动改写的 XPR；manifest 分开记录源码状态和生成物状态。

## 验证结果

| 项目 | 结果 |
|---|---|
| MATLAB 21-bit 边界模型 | PASS；新模型峰值 786432，旧 signed-20 模型削顶 5 次 |
| CIC 等价 | PASS；8240 样点，0 LSB |
| Smoke RTL | 15/15 PASS；impulse + seed01，4x/8x/128x 0 LSB |
| Release RTL | 15/15 PASS；13 组全链向量，reset-zero prefix 与三节点 0 LSB |
| 六工况频响 | 6/6 PASS；最差绝对通带误差 0.005146 dB，最差阻带 72.335 dB |
| post-route 资源 | 479 LUT / 468 FF / 198 Slice / 4 DSP / 4 RAMB18E1（2 Tile）/ 2 MMCM |
| 全局时序 | WNS +45.734 ns / WHS +0.121 ns |
| AD9708 输出时序 | setup +76.116 ns / hold +78.117 ns |
| mode CDC | bus skew 1.813/50 ns；最大绝对数据延迟 0.912/50 ns；ignored exception 为空 |
| 功耗估计 | 0.271 W total / 0.199 W dynamic / 0.072 W static；vectorless、Medium confidence |
| bitstream | PASS；SHA-256 `8630210663629357237AAA3F076348FBE65610EAAB61ADA4706E81F75AAF02A6` |

## 六工况正式指标

| 输入族 | 输出 | shape 最大偏差 | shape 通带纹波 | 绝对通带最大误差 | 绝对阻带衰减 |
|---|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.004610 dB | 0.005703 dB | 0.003011 dB | 78.670 dB |
| 44.1 kHz | 8x | 0.005395 dB | 0.006155 dB | 0.003470 dB | 78.565 dB |
| 44.1 kHz | 128x | 0.006116 dB | 0.007783 dB | 0.005146 dB | 72.335 dB |
| 48 kHz | 4x | 0.004610 dB | 0.005703 dB | 0.003011 dB | 78.670 dB |
| 48 kHz | 8x | 0.005395 dB | 0.005719 dB | 0.003033 dB | 78.565 dB |
| 48 kHz | 128x | 0.006116 dB | 0.006114 dB | 0.003477 dB | 72.335 dB |

## 证据位置与限制

原始 DCP、bit、utilization/timing/power/CDC/DRC/methodology/exception 报告、综合源清单、Smoke/Release 全链日志及 93 项 SHA-256 记录都在 `matlab_fir/national_finals/vivado_results/p4d_release_v2_clean_signedoff/`。`source_state_at_build_start.json` 与 `release_manifest_p4d_v2.json` 均确认源工作区无改动。

当前功耗仍是 vectorless 估计，不能替代同激励 SAIF 或板上电流实测；工具通过 bitstream 生成也不能替代最终下载后的六档输出时钟、DAC 波形与频谱验证。
