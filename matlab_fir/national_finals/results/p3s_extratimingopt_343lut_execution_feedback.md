# P3-S ExtraTimingOpt 343-LUT 优化执行反馈

## 1. 结论与发布边界

P3-S 从已完成实板验证的 P3-R 标签出发，不修改滤波 RTL、系数、字长、舍入、饱和、
valid 时序、时钟、复位、键盘或 DAC 接口，只继续优化完整板级实现策略。最终结果为：

| 指标 | P3-R 实板基线 | P3-S 工具签核候选 | 变化 |
|---|---:|---:|---:|
| LUT | 348 | **343** | **-5** |
| FF | 386 | **386** | 0 |
| Slice | 154 | **151** | **-3** |
| DSP48E1 | 4 | **4** | 0 |
| RAMB18E1 / BRAM Tile | 4 / 2.0 | **4 / 2.0** | 0 |
| MMCM | 2 | **2** | 0 |
| WNS / WHS | +45.200/+0.121 ns | **+45.025/+0.116 ns** | 仍有充分裕量 |
| AD9708 setup / hold | +76.116/+78.117 ns | **+76.116/+78.117 ns** | 0 |
| 总/动态/静态功耗 | 0.271/0.199/0.072 W | **0.271/0.199/0.072 W** | 0 |

P3-S 已完成 RTL、原语、完整链、复位/CDC、实现、Timing/Power、默认与六模式 routed-DCP
DAC、普通 GUI 从零生成 bitstream 的工具闭环。**当前尚未进行 P3-S 实物板复测，因此它是
新的工具签核候选；P3-R 348-LUT boardverified 标签和 bitstream 仍是正式实板安全回退。**

- 分支：`national-finals-p3s-4dsp-deep-optimization`
- 工具签核标签：`nf-p3s-final-343lut-386ff-151slice-4dsp-2bram-toolverified`
- 正式结果：`vivado_results/p3s_343lut_386ff_4dsp_2bram_signedoff`

## 2. 本轮优化方法

P3-R 已经把算法数据通路压到很低，继续修改 Stage2/3 尾状态、系数或 BRAM 端口会重新
引入板级功能风险。本轮先用同一份 `AreaOptimized_high/full/resource_sharing=on` 综合
网表做两层实现搜索：

1. `opt_design -directive ExploreWithRemap` 保持不变；
2. 把 `place_design` 从默认指令改为 `ExtraTimingOpt`；
3. route 仍使用默认路由器，不增加 `phys_opt_design` 复制或 retiming；
4. 普通 GUI、批处理包装器和单进程低内存实现脚本全部显式锁定同一指令。

`ExtraTimingOpt` 使用不同的时序驱动放置与细节优化路径，使原综合网表中的兼容逻辑得到
更好的 LUT O5/O6 打包和跨层映射。预布局逻辑功能和寄存器数不变，最终已用
`report_utilization` 实测少 5 个 Slice LUT、少 3 个 Slice。这个结果不是删除功能、不是
过期 DCP，也不是用 primitive cell 数冒充 Vivado 利用率。

## 3. 测量口径纠正

第一次临时扫描发现工程 `synth_1` DCP 被后续 GUI/试验覆盖，与 P3-R 正式 bit 的源码状态
不一致。该结果立即作废，并从 P3-R 源码重新综合，确认综合为
`374 LUT / 388 FF / 4 DSP / 4 RAMB18E1`。

第二次检查又确认，直接统计 `get_cells REF_NAME=LUT*` 得到的是逻辑原语数量，不能反映
Vivado 对双输出 LUT 和可打包逻辑的资源利用率。最终扫描统一解析
`report_utilization -return_string`，正式 route 与普通 GUI 报告均复现 343/386。上述两次
纠正都发生在候选发布前，错误数字没有进入发布结论。

## 4. 网表与布局策略扫描

### 4.1 二次网表面积优化

同一份重新综合 DCP 的预布局结果如下：

| 流程 | 预布局 LUT | FF | 结论 |
|---|---:|---:|---|
| ExploreWithRemap 基线 | 365 | 394 | 进入布局比较 |
| EWR 后 `resynth_area` | 429 | 394 | 明显劣化 |
| EWR 后 `resynth_seq_area` | 365 | 394 | 无收益 |
| EWR 后 `aggressive_remap` | 365 | 394 | 无收益 |
| EWR 后等价驱动/控制集合并 | 365 | 394 | 无收益 |
| Sequential/Area 后再 aggressive remap | 365 | 394 | 无收益 |

这里的预布局 FF/LUT 是未放置估算，不作为最终发布资源；最终资源只采用 placed/routed
`report_utilization`。

### 4.2 `place_design` 指令扫描

| place 指令 | LUT | FF | Slice | 布局后 setup slack | 结论 |
|---|---:|---:|---:|---:|---|
| **ExtraTimingOpt** | **343** | **386** | **151** | +44.679 ns | **正式保留** |
| Quick | 345 | 386 | 162 | +45.214 ns | 次优，不发布 |
| RuntimeOptimized | 348 | 386 | 152 | +44.847 ns | LUT无收益 |
| Default | 348 | 386 | 154 | +44.912 ns | P3-R实现基线 |
| Default + no fanout opt | 348 | 386 | 154 | +44.912 ns | 无收益 |
| Explore / Explore+no fanout | 348 | 386 | 154 | +44.912 ns | 无收益 |
| WLDrivenBlockPlacement | 348 | 386 | 154 | +44.912 ns | 无收益 |
| ExtraPostPlacementOpt | 348 | 386 | 154 | +44.912 ns | 无收益 |
| no timing driven | 348 | 386 | 158 | +45.445 ns | Slice变差 |
| EarlyBlockPlacement | 349 | 386 | 151 | +45.345 ns | LUT变差 |

343-LUT候选随后从源码重新综合和完整 route，并非只保存 placed 结果。route 后保持
`343 LUT / 386 FF / 151 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM`，0 routing error。

## 5. 为什么没有继续改 RTL

用户要求“直到比 348 LUT 更优”。`ExtraTimingOpt` 已在不改 RTL、不增 FF/DSP/BRAM 的
情况下达到 343 LUT，并通过全部工具门禁。继续做以下结构改动会扩大风险而不再是必要的
发布步骤，因此按 Stop/Go 规则不执行：

- Stage2/3 尾状态二进制化：P3-R 已实测为综合多 10 LUT、多 1 FF；
- signed-20 Stage3：既有 80,001 个候选不能同时通过频响和强信号峰值门禁；
- 系数/历史 BRAM 空地址复用：统一系数 RAM 两端口在 MAC 调度中使用，历史 RAM 还需
  同拍读写；复用会引入端口仲裁、时钟域或额外延迟，不是无风险 LUT 替换；
- `phys_opt_design` retime/复制：设计无负 slack，工具说明该阶段主要服务关键负裕量路径，
  可能增加复制逻辑，不能作为低 LUT 首选。

因此 P3-S 的数学路径与 P3-R 逐字节一致；本轮只提交可复现的实现策略和验证门槛。

## 6. RTL与定点回归

最终源码分别从零运行 Smoke 和 Release，均为 **17/17 PASS**：

- Smoke：`_work/rtl_regression/20260806_010509`；
- Release：`_work/rtl_regression/20260806_010916`；
- Release 全链共14组：冲激、10个固定seed、正/负满量程、997 Hz/−1 dBFS；
- 4x、8x、128x三个节点逐样本最大误差均为 **0 LSB**；
- 长用例输出数为 `16605 / 33219 / 531584`；
- Stage1行为RAM/真实RAMB18E1、Stage2/3历史、统一系数RAM、CIC连续/随机停顿、
  DAC offset-binary全部通过；
- 8类复位场景、1200次CDC、100次时钟族切换、10次动态倍率切换通过，无X、runt或
  pending覆盖。

正式结果目录保存两次回归的全部36份 XSim 日志，不以“仿真跑完”代替逐样本比较。

## 7. 六工况频响

P3-S 未修改系数和定点语义，严格继承 P3-R 的线性相位频响：

| 输入家族 | 输出 | 最大绝对通带偏差 | 通带峰峰纹波 | 阻带衰减 |
|---|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB |

六工况均满足通带纹波不超过0.05 dB、阻带至少70 dB，并保持严格线性相位。

## 8. 实现、DAC与GUI闭环

- 正式route：WNS/WHS `+45.025/+0.116 ns`，TNS/THS=0；
- AD9708最差setup/hold：`+76.116/+78.117 ns`；
- 功耗：总/动态/静态 `0.271/0.199/0.072 W`（Medium confidence）；
- 默认 routed-DCP 6 ms：11290个DAC边沿、7462次数据变化、终值64、beep无效；
- 六模式公开键盘路径：44.1 kHz为`177/353/5645 edges/ms`，48 kHz为
  `192/384/6144 edges/ms`，六档DAC数据持续变化且无X；
- 普通Vivado工程从零`synth_1 -> impl_1 -> write_bitstream`约113秒，复现
  `343 LUT / 386 FF / 4 DSP / 4 RAMB18E1 / 2 MMCM`并生成bitstream；
- `.xpr` 中 `ExploreWithRemap` 与 `ExtraTimingOpt` 均显式保存，GUI门槛为
  `LUT<=344 / FF<=400 / DSP=4 / RAMB18E1=4 / MMCM=2`。

第一次运行 GUI 配置脚本时，Vivado 在写工程 XML 后报告 `Project 1-202`。随后确认 XML
可解析、目标 `Directive=8` 已写入，并用只读配置检查验证其解析为 `ExtraTimingOpt`；普通
GUI从零重建又完整通过。因此该次是配置脚本写回阶段的非签核失败，不是实现失败，也未被
当作成功结果。

正式bitstream SHA-256：
`DDD4F906967F5E039181A9DB17CE339615AE2A7744173519C471F2316086ED2A`

正式routed DCP SHA-256：
`3338BAA1B0BD7BB33B84341E61CEE3FEB004A55BDDAF05854A81F0BCC7D67C47`

## 9. 复现与板测

```powershell
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1 -Step all -ResultTag p3s_rebuild
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1 -RegressionScale Release
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_postroute_board_dac_activity.ps1 -DcpPath .\matlab_fir\national_finals\vivado_results\p3s_343lut_386ff_4dsp_2bram_signedoff\national_finals_board_routed.dcp
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_postroute_six_mode_dac.ps1 -DcpPath .\matlab_fir\national_finals\vivado_results\p3s_343lut_386ff_4dsp_2bram_signedoff\national_finals_board_routed.dcp
```

板测应下载本目录的正式 bit，逐档检查44.1/48 kHz的4x/8x/128x采样率和DAC波形。完成
实测前不要把P3-S标记为boardverified；若出现任何异常，立即回退P3-R的实板标签。
