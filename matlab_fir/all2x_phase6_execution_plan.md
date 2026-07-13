# 全 2x 结构 Phase 6 执行计划

## 1. 执行基线

- 分支：`codex/phase6-three-dsp-pareto`
- Phase 5 独立七级链：1379 LUT、1015 FF、2 DSP、1 BRAM
- Phase 5 板级工程：1536 LUT、1181 FF、2 DSP、1 BRAM
- Phase 5 板级时序：WNS = +44.892 ns
- 当前展示模式：1x / 4x / 8x / 128x，15 kHz ROM，单 DAC 输出

## 2. 对指导文件的采纳结论

| 指导项 | 当前状态 | Phase 6 处理 |
|---|---|---|
| A：最新链路接入板级顶层 | 已完成 | Phase6 混合字长核已登记并进入现有稳定板级顶层 |
| B：2 DSP / 3 DSP Pareto | 已完成 | 3 DSP 增加 LUT/FF，判定 No-Go |
| C：Stage3 Q14 改 Q15 | Phase 5 已完成 | 保持 Q15 位真结果 |
| D：DSP48 深度映射 | 已复核 | Stage1 使用 pre-adder；共享 Stage2/3 保持稳定映射 |
| E：级间数据字长优化 | 已完成 | 选择 24/22/20/18/18/18/18bit |
| F：展示模式稳定 | 已完成 | 四档仿真和 Phase6 实板展示均通过 |
| Stage4~7 共用引擎 | 风险较高 | 不进入当前比赛主线 |

## 3. Phase 6-B 验收门槛

3 DSP 候选必须同时满足：

1. Stage2、Stage3、完整 128x 输出相对 Phase 5 均为 0 LSB；
2. 五组随机种子、满幅边界、零、小信号和 valid 空洞全部通过；
3. 独立七级链综合必须准确使用 3 个 DSP；
4. 时序裕量为正；
5. 相对 Phase 5 独立链至少减少 150 LUT；
6. FF 增量不超过 100。

只有全部满足，才把 3 DSP 方案接入板级工程。否则保留 Phase 5 的 2 DSP 版本。

## 4. 进度

| 步骤 | 状态 | 结果 |
|---|---|---|
| 6-A：复核 Phase 5 板级基线 | 已完成 | 1536 LUT / 1181 FF / 2 DSP / 1 BRAM |
| 6-B1：独立 Stage2/3 DSP RTL | 已完成 | 三 DSP 候选 RTL 完成 |
| 6-B2：多激励位真回归 | 已完成 | Stage2/3/链尾均为 0 LSB |
| 6-B3：独立综合与 Pareto 判定 | 已完成 | 1431 LUT / 1052 FF / 3 DSP，No-Go |
| 6-B4：三 DSP 板级实现 | 已跳过 | 未达到 Go 门槛，不污染比赛主线 |
| 6-D：DSP48 深度映射复核 | 已完成 | Stage1 映射 pre-adder，Stage2/3 为 C+A*B |
| 6-E1：MATLAB 字长搜索 | 已完成 | 推荐 24/22/20/18/18/18/18bit |
| 6-E2：混合字长 RTL 对拍 | 已完成 | 冲激/随机分级与链尾全部 0 LSB |
| 6-E3：独立综合 | 已完成 | 1224 LUT / 867 FF / 2 DSP / 1 BRAM |
| 6-E4：板级实现与 bitstream | 已完成 | 1395 LUT / 1040 FF，WNS +45.145 ns |
| 6-F：展示稳定性复核 | 已完成（实板） | 实测 176.37 kHz / 352.86 kHz / 5.64 MHz，四档波形逐级平滑 |

## 5. 最终判定

Phase6 采用 2-DSP 共享结构与混合数据字长，不采用 3-DSP 独立结构。相对 Phase5 板级减少 141 LUT 和 141 FF，DSP/BRAM 不增加，时序保持通过；四档实板输出正常，并能直观看到从 1x 到 128x 逐级变得光滑。详细证据见 `all2x_phase6_execution_report.md`。
