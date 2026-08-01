# P4-F：Stage2/3 历史改用 LUTRAM 的 1 BRAM Pareto 方案

## 结论

P4-F 在已验证的 P4-E 共享 PCM/Stage1 RAMB18 基础上，将 Stage2/3 历史存储从一个 RAMB18E1 改为 8 个 RAM32M。最终实现为 **531 LUT / 487 FF / 204 Slice / 4 DSP / 2 RAMB18（1 BRAM Tile）/ 2 MMCM**，实现后 WNS **+45.898 ns**、WHS **+0.105 ns**。

该方案通过完整验证，是当前 **BRAM 最少** 的可用 Pareto 点；但它比默认 P4-D 多 52 LUT、19 FF、6 Slice，也未达到指导文件预估的 500--510 LUT，因此不替代综合资源更均衡的 P4-D 默认版。

## 结构变化

- 保留 P4-E 的 512x36 PCM/Stage1 共享 RAMB18E1：PCM 使用地址 0--162，Stage1 历史使用地址 256--319。
- 保留一个统一 FIR 系数 RAMB18E1。
- Stage2/3 历史不再使用统一 RAMB18E1，改由 `interp2_stage23_lutram_cic_dsp_ce` 中 8 个 RAM32M 保存。
- DSP 数据通路、系数、定点量化、插值倍率及动态模式切换协议均不改变，因此频响与 P4-D/P4-E 相同。

## 实现结果

| 方案 | LUT | FF | Slice | DSP | RAMB18 | BRAM Tile | RAM32M | MMCM | WNS | WHS | 向量无关总/动态/静态功耗 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P4-D 默认 | 479 | 468 | 198 | 4 | 4 | 2.0 | 0 | 2 | +45.734 ns | +0.121 ns | 0.271 / 0.199 / 0.072 W |
| P4-E 共享 PCM/Stage1 | 491 | 487 | 202 | 4 | 3 | 1.5 | 0 | 2 | +46.132 ns | +0.105 ns | 0.271 / 0.199 / 0.072 W |
| **P4-F Stage2/3 LUTRAM** | **531** | **487** | **204** | **4** | **2** | **1.0** | **8** | **2** | **+45.898 ns** | **+0.105 ns** | **0.270 / 0.198 / 0.072 W** |

相对 P4-E，P4-F 用 **+40 LUT / +2 Slice** 换取 **-1 RAMB18（-0.5 BRAM Tile）**；相对 P4-D，则用 **+52 LUT / +19 FF / +6 Slice** 换取 **-2 RAMB18（-1 BRAM Tile）**。

时序约束均满足：TNS/THS 为 0；模式请求 bundled-data 总线的实际布线偏斜为 **1.859 ns**，小于 **50 ns** 约束。AD9708 输出 setup/hold slack 分别为 **+76.116 ns / +78.117 ns**。

## 验证闭环

- Smoke：**16/16 PASS**；冲激 + 1 个随机种子，每组 1024 输入样本，4x/8x/128x 均 0 LSB。
- Release：**16/16 PASS**；冲激 + 10 个随机种子，每组 4096 输入样本，4x/8x/128x 均 0 LSB；复位 8/8、动态切换 10 次全部通过。
- 普通 Vivado GUI 行为仿真：PASS；冲激 + seed01，所有节点 0 LSB。
- 普通 Vivado GUI 综合/实现：PASS；资源守卫确认 531 LUT / 487 FF / 4 DSP / 2 RAMB18 / 8 RAM32M / 2 MMCM。
- 单进程实现、DRC、时序、CDC、bus-skew、功耗报告和 bitstream：全部生成成功。

第一次 Smoke 的动态模式用例曾失败，原因是测试平台错误地用 Stage2/3 BRAM 宏同时控制 Stage1 单 BRAM开关，导致测试配置与板级配置不一致。修正为 Stage1 共享 RAM 独立使能后，Smoke 与 Release 均全通过；该失败不是滤波数据通路缺陷。

## 可复现资产

- 分支：`codex/national-finals-p4f-bram1`
- 标签：`national-finals-p4f-531LUT-487FF-4DSP-1BRAM`
- 结果目录：`matlab_fir/national_finals/vivado_results/p4f_stage23_lutram_2ramb18/`
- bitstream SHA-256：`32CBB432B53B84D6DE71E7751DFAD0A6F9B3668BBBEB6B8C39A3BE78A8AE3A22`

## 使用建议

- 若优先考虑综合资源平衡和最少 LUT/FF：使用 P4-D（479 LUT / 468 FF / 2 BRAM）。
- 若 BRAM 特别紧张且可接受约 11% LUT 增量：使用本 P4-F（531 LUT / 487 FF / 1 BRAM）。
- P4-F 是有效的低 BRAM 备选方案，不是默认板级交付版本。
