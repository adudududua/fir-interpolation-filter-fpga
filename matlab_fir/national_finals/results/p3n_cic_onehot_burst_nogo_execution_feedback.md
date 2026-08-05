# P3-N CIC one-hot burst 状态优化执行反馈（No-Go）

## 1. 结论

本轮从已经实板验证通过的 P3-M `368 LUT / 386 FF / 156 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM` 正式版继续尝试 LUT-only 优化。候选把 N3 Hold CIC 的 4-bit 递减 burst 计数器改为 15-bit thermometer/shift window，希望用少量 FF 消除减一器、零比较和末样点比较逻辑。

最终有效综合结果为：

| 版本 | 综合 LUT | 综合 FF | DSP | RAMB18E1 / Tile | MMCM | 结论 |
|---|---:|---:|---:|---:|---:|---|
| P3-M 正式基线 | 395 | 388 | 4 | 4 / 2.0 | 2 | 保留，post-route 为368/386/156 |
| P3-N 第一次综合 R1 | 395 | 388 | 4 | 4 / 2.0 | 2 | 无效：板级参数仍绑定为0 |
| **P3-N 有效综合 R2** | **403** | **399** | **4** | **4 / 2.0** | **2** | **比基线多8 LUT、11 FF，No-Go** |

候选确实保持 DSP、BRAM 和 MMCM 不变，但 LUT 和 FF 同时变差，因此按预先约定的 Stop/Go 门槛停止在综合阶段，没有继续布局布线、Timing、功耗、bitstream 或板测。当前正式发布仍是 P3-M；本实验不能替代 P3-M，也没有生成可上板 bitstream。

## 2. 先做结构审计，而不是重复已有优化

原计划先检查“两级 CIC comb 是否仍能共享一个减法器”。审计当前 P3-M RTL 与 routed DCP 后确认：

- P3-M 已采用严格恒等变换 `C^3 -> up16 -> I^3 == C^2 -> Hold16 -> I^2`；
- 两级低速 comb 已在 `cic_interp16_n3_hold2_dsp_ce.v` 内按不同拍串行执行；
- 两级运算已经共享同一个 23-bit LUT/CARRY 减法数据通路；
- 因而“再共享一次 comb 减法器”没有新的硬件可删除。

本轮没有盲目重复该建议，转而审计同模块剩余的 burst 控制热点。P3-M 的二进制 burst 状态包含4个计数 FF及减一/零/末样点判断；这是一个规模很小但仍可独立验证的 LUT-only 候选。

## 3. 候选结构

P3-N 增加参数 `BURST_COUNTER_ONEHOT_FF`：

- 旧结构：首个输出后装入 `15`，每个 `ce_out` 递减，比较 `!=0` 与 `==1`；
- 新结构：首个输出后装入 `15'h7fff`，每个 `ce_out` 右移一位，`bit0` 直接表示 burst 仍活动；
- 允许任意 `ce_out` 停顿，停顿期间状态保持；
- `burst_pending`、16个输出的顺序、`y_out_valid` 相位、数值通路、舍入和饱和均不变；
- 通用模块默认值保持0；仅 P3-N 板级顶层和 signed-off 验证包装启用1。

参数已经贯通以下实际板级路径：

`board_demo_competition_dac8_top -> demo_interp_dac8_audio_pcm_common -> interp128_all2x_v7_folded_fir_cic_top_ce -> cic_interp16_n3_hold2_dsp_ce`

板级集成测试的公共模块 stub 同步增加断言，要求 P3-N 路径传入值必须为1，避免出现“验证包装启用、板级综合未启用”的假阳性。

## 4. RTL 验证

### 4.1 CIC 单元逐周期等价

新增第五个 one-hot DUT，与原二进制 N3 Hold DUT逐周期比较 `valid/data`，覆盖：

- 连续 `ce_out`；
- 随机 `ce_out` 停顿；
- burst 中途复位；
- 10个随机种子；
- 4096个输出样点。

结果：

```text
N3 HOLD CIC EQUIVALENCE PASS: ... binary/onehot burst,
continuous=320 stalled=480 seeds=10x256 reset-mid-burst=PASS outputs=4096
```

工作目录：`matlab_fir/national_finals/_work/p3n_onehot_unit`。

### 4.2 完整 Smoke

板级参数链修正并加入启用断言后，最终 Smoke 为 **17/17 PASS**：

```text
NATIONAL FINALS RTL REGRESSION PASS (17/17)
Run directory: matlab_fir/national_finals/_work/rtl_regression/20260805_164213
```

其中包含 ROM、DAC offset-binary、真实 RAMB18E1、Stage1 行为/原语等价、Stage2/3、两种 CIC 等价、双时钟家族、CDC、键盘、板级集成、全链路、8类复位恢复和10次动态切档。

### 4.3 Release 0-LSB 回归

Release 连续回归为 **17/17 PASS**：

```text
NATIONAL FINALS RTL REGRESSION PASS (17/17)
Run directory: matlab_fir/national_finals/_work/rtl_regression/20260805_161605
```

全链路覆盖冲激、10个固定随机种子、正满量程、负满量程和强 `-1 dBFS` 信号，共14组输入；4x、8x、128x全部逐样本 **0 LSB**。同时通过8类内部状态复位恢复与10次无复位动态切档，无窄脉冲和未知态。

第一次 Release 外层命令设置为15分钟，命令在全链路结束附近返回退出码124。检查 `xsim.log` 发现14组数据实际已全部 PASS，单个全链路用例耗时12分43秒，问题是外层上限不足，不是 RTL 死锁。将上限修正为30分钟后，连续17/17正式通过；该问题和处理过程均保留在本反馈中。

## 5. 综合审计与一次假结果的纠正

综合配置与 P3-M 完全相同：

- Vivado 2018.3，`xc7a35tfgg484-2`；
- `AreaOptimized_high`；
- `flatten_hierarchy=full`；
- `resource_sharing=on`；
- Stage1 DSP48预加器=1；
- CIC DSP积分器=2；
- Stage1单BRAM与Stage2/3统一BRAM均=1。

第一次 R1 得到395 LUT/388 FF，看似与P3-M相同。但 elaboration 日志明确显示：

```text
Parameter CIC_BURST_COUNTER_ONEHOT_FF bound to: 0
Parameter BURST_COUNTER_ONEHOT_FF bound to: 0
Unused sequential element burst_window_reg was removed
```

根因是全链路验证通过 `nf_signedoff_filter_core` 启用候选，而板级综合走 `demo_interp_dac8_audio_pcm_common`，新参数尚未沿该路径传递。因此 R1 被判为无效，不作为资源结论。

补齐板级参数并用 stub 断言回归后，R2 日志确认：

```text
Parameter CIC_BURST_COUNTER_ONEHOT_FF bound to: 1
Parameter BURST_COUNTER_ONEHOT_FF bound to: 1
Unused sequential element burst_remaining_reg was removed
```

有效 R2 为403 LUT/399 FF/4 DSP/2 BRAM Tile/2 MMCM。它删除了旧4-bit计数状态，却引入15-bit状态和相应选择/移位控制，净结果是 `+8 LUT/+11 FF`。这说明在当前 Vivado 2018.3、同步复位和可停顿 CE 语义下，thermometer状态没有推断成更便宜的 SRL，也没有优于原二进制计数器的 CARRY/比较合并。

正式综合证据目录：`vivado_results/p3n_onehot_burst_synth_r2`。

## 6. 为什么没有继续实现、Timing和功耗

本轮目标是保持 `4 DSP / 2 BRAM Tile / 2 MMCM`，以少量 FF 换 LUT。预先门槛是：综合 LUT 至少不得高于 P3-M 的395，才进入完整实现。有效候选已经高出8 LUT且多11 FF，不是可能由一次布局随机性解释的1 LUT边界。

因此：

- P3-N 没有 routed LUT/FF/Slice 数字；
- P3-N 没有新的 WNS/WHS、AD9708 setup/hold 或功耗数字；
- P3-N 没有 bitstream、post-route DAC 或实板结论；
- 表中 P3-M 的368/386/156、`+44.836/+0.117 ns`和0.271 W只属于正式基线，不能写成P3-N结果。

这遵循 Stop/Go 规则，也避免为一个综合已明显劣化的候选浪费实现时间或制造“跑通即可用”的误导。

## 7. 频响继承

P3-N 不改变任何滤波系数、字长、舍入、饱和、输出样点或valid序列，Release又证明三节点0 LSB，因此数学频响严格继承P3-M：

| 输入家族 | 节点 | 通带最大绝对偏差 | 峰峰纹波 | 阻带衰减 | 相位/对称性 |
|---|---|---:|---:|---:|---|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 严格线性相位，0 LSB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB | 严格线性相位，0 LSB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB | 严格线性相位，0 LSB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 严格线性相位，0 LSB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB | 严格线性相位，0 LSB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB | 严格线性相位，0 LSB |

六工况继续满足通带 `±0.05 dB`、阻带不低于70 dB和严格线性相位要求。

## 8. Git与回退

- 实验分支：`national-finals-p3n-cic-onehot-burst`；
- 候选源码提交：`18b7fc2 experiment: evaluate CIC one-hot burst state`；
- 分支和提交信息均不含 `codex`；
- P3-M 正式标签 `nf-p3m-final-368lut-386ff-156slice-4dsp-2bram-boardverified` 不移动；
- 最终工作版本恢复并停留在 P3-M 正式结构，P3-N 分支仅用于复查失败路线。

本轮最有价值的结果不是资源下降，而是增加了板级参数启用断言和“综合后核对 elaboration 参数”的验证纪律，防止以后再次把未真正启用的候选资源表误判为优化结果。
