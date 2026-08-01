# P4-D 导出包深度审计与下一阶段优化指导（V2）

> 审计对象：`guide.zip` 导出的 MATLAB、RTL、验证与 Vivado 2018.3 实现资料  
> 审计日期：2026-08-01  
> 目标器件：XC7A35T-FGG484-2  
> 当前默认基线：P4-D，479 LUT / 468 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）

## 0. 结论先行

这次导出证明了两件不同的事：

1. **P4-D 的算法结果和实现结果总体可信。** 六工况频响全部通过；现有冲激与十组长随机回归在 4x、8x、128x 三个节点均为 0 LSB；post-route 的 479 LUT / 468 FF / 4 DSP / 4 RAMB18、时序、DAC setup/hold 和 bitstream 彼此自洽。
2. **发布来源闭环还没有真正完成。** 导出包不能证明“包内当前源码可精确重建所附 bitstream”：release manifest 标记 `tracked_worktree_dirty=true`，七个关键源码或脚本与 manifest 哈希不一致；MATLAB 全链 golden 生成器还在使用旧的 20-bit 均衡器/CIC 交接模型，而签核 RTL 是无损 21-bit 交接。

因此，下一轮应按以下顺序执行：

| 优先级 | 工作项 | 结论 |
|---:|---|---|
| P0 | 修复 21-bit golden、哈希清单、clean-source-to-bitstream 闭环 | **必须先做** |
| P1 | 用一个 DSP48E1 `TWO24` 加两个小高位段，实现两级 CIC 积分器 | **最值得研究的新 3-DSP 路线** |
| P2 | 从 P4-E 出发，把只读系数 BRAM 改成双端口等效的两组 distributed ROM | **低 BRAM 第二优先** |
| P3 | Stage3 与三抽头均衡器联合设计 | **只先做 MATLAB 可行性，不直接改 RTL** |
| P4 | 关闭当前未选中的 MMCM，或拆成单家族 bitstream | **真正有意义的功耗路线** |

需要正式撤销上一版中的一条建议：

> **“把 CIC 积分状态移入 PREG 可减少约 40～55 个 Slice FF”不成立。** 当前 routed DCP 的两颗 CIC DSP 已经是 `CREG=1, PREG=0, USE_MULT=NONE`，26-bit 和 29-bit 状态已被吸收到 DSP48E1 的 CREG；它们不是 55 个 Slice FF。单纯从 CREG 改到 PREG 可能改变延迟、改善时序或功耗，但没有可预期的面积收益，面积方向应判为 No-Go。

P4-D 继续作为默认稳定版。P4-E/P4-F 是低 BRAM Pareto，不能称为全面更优；串行前端 ALU 和现有 X3 架构可以停止。

---

## 1. 导出包证据审计

### 1.1 P4-D 的权威 post-route 基线

以下数字可由原始 routed 报告、DCP、bitstream 和层级利用率相互印证：

| 项目 | P4-D 结果 |
|---|---:|
| Slice LUT | **479**（478 logic + 1 SRL） |
| Slice FF | **468** |
| Slice | **198** |
| DSP48E1 | **4** |
| RAMB18E1 / BRAM Tile | **4 / 2** |
| MMCM / IO | **2 / 17** |
| WNS / TNS | **+45.734 ns / 0 ns** |
| WHS / THS | **+0.121 ns / 0 ns** |
| DAC setup / hold 最坏裕量 | **+76.116 / +78.117 ns** |
| 路由 | 1159/1159 可布线网络完成，0 routing error |
| bitstream SHA-256 | `44879C48...3E378`，实文件匹配 |

综合口径为 503 LUT / 474 FF，479 / 468 是实现后的 post-route 数字。后续任何候选都必须使用 post-route 与它比较，不能混用综合、OOC core 或板级估算。

层级热点如下：

| 层级 | LUT | FF | RAMB18 | DSP |
|---|---:|---:|---:|---:|
| FIR/CIC 核心 | 377 | 361 | 3 | 4 |
| Stage1 | 144 | 126 | 1 | 1 |
| Stage2/3 | 118 | 82 | 1 | 1 |
| CIC | 64 | 107 | 0 | 2 |
| 三抽头均衡器 | 46 | 40 | 0 | 0 |
| 统一系数存储 | 1 | 2 | 1 | 0 |

四个 RAMB18 的用途明确：PCM ROM、Stage1 history、Stage2/3 history、统一 FIR coefficient。四颗 DSP 分别属于 Stage1、共享 Stage2/3、CIC 第一积分器、CIC 最终积分器。

### 1.2 六工况频响复核

原脚本按实际 DC 对响应归一化，所以下表“形状偏差”不是相对理想 0 dB 的绝对幅度误差；绝对 DC 增益另有门禁。按导出 CSV 复算后，六工况仍全部通过：

| 输入 | 节点 | DC 归一化形状最大偏差 | 峰峰纹波 | 阻带衰减 | 绝对增益 |
|---:|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.004610 dB | 0.005703 dB | 78.668823 dB | -0.001599 dB |
| 44.1 kHz | 8x | 0.005395 dB | 0.006174 dB | 78.561810 dB | -0.002709 dB |
| 44.1 kHz | 128x | 0.006116 dB | 0.008056 dB | **72.331082 dB** | -0.003480 dB |
| 48 kHz | 4x | 0.004610 dB | 0.005703 dB | 78.668823 dB | -0.001599 dB |
| 48 kHz | 8x | 0.005395 dB | 0.005719 dB | 78.561810 dB | -0.002709 dB |
| 48 kHz | 128x | 0.006116 dB | 0.006116 dB | **72.331082 dB** | -0.003480 dB |

相对理想增益直接计算的真实通带最大绝对偏差为：

- 44.1 kHz：4x / 8x / 128x = 0.003011 / 0.003498 / 0.005596 dB；
- 48 kHz：4x / 8x / 128x = 0.003011 / 0.003033 / 0.003479 dB。

连续频率局部寻优得到 128x 最差阻带约 72.331061 dB；44.1/48 kHz 家族的最差峰分别约在 331.985/361.344 kHz。当前对 70 dB 指标只有约 **2.331 dB** 余量，所以任何改系数、剪位或合并舍入边界的候选都必须首先保护 128x 阻带。

冲激对称误差均为 0 LSB，群延迟为 112、229、3702.5 个对应输出采样，最大相位拟合残差约为 \(1.42\times10^{-13}\) rad。

### 1.3 当前 0-LSB 证据的有效范围

下列结论可信：

- RTL 冲激 CSV 的 225 / 459 / 7406 个样点与对应 golden MEM 的有效前缀逐点相同；其后 golden 全为零，没有截掉非零尾部。
- Release 回归覆盖冲激和 10 个固定 seed × 4096 输入；4x / 8x / 128x 每个随机用例分别输出 16605 / 33219 / 531584 点，全部 0 LSB。
- 系数 RAMB18 原语测试覆盖 Stage1 的 32 个地址和 Stage2/3 的 64 个地址。
- 独立均衡器与 21-bit CIC 单元测试覆盖了满量程、停顿和复位场景。

但必须加上边界说明：全链 golden 生成器仍按 20-bit 均衡器输出建模。现有向量的 `EQUALIZER_SAT=0`，所以这个错误被当前激励掩盖；现有回归结果仍成立，但它不能继续作为新的满量程、削顶、SNR 或噪声实验的权威 golden。

全链 TB 还会在正式比较前固定跳过 4x/8x/128x 的 3/7/112 个 valid 事件；这些事件目前只检查“不是 X”，没有逐点核对预期值。新版应把它们纳入明确的 warm-up/latency 契约：要么证明并断言应为哪些数值，要么把完整前缀写进 golden。否则新的流水延迟可能被“固定跳过”意外掩盖。

另外，板级键盘/时钟控制 TB 使用了滤波链桩模型；它能证明按键、复位、时钟切换和静音控制，但不能替代真实 FIR/CIC 数据通路的板级仿真，更不能替代实物 DAC 测试。

### 1.4 完整性与可重建性不是同一件事

两个 SHA 清单首行都含 UTF-8 BOM：

- 局部清单会让标准 `sha256sum -c` 跳过首项 `coefficients.csv`；
- 全局清单会跳过首项 `NATIONAL_FINALS_README.md`；
- 工具仍可能返回 0，只输出一条“格式不正确”警告。

去掉 BOM 后，局部 14/14、全局 209/209 均通过。因此压缩包本身没有因传输损坏，但 release manifest 仍存在另一层问题：

- `tracked_worktree_dirty=true`；
- manifest 的 24 个对象中，包内只有 12 个能按记录逐字节命中。七个同名关键文件与记录哈希不一致：板级顶层、`nf_signedoff_filter_core.v`、RTL 回归 PS1 和四个 Vivado Tcl；daily seed01 的四个文件与 Smoke full-chain 日志也没有按 manifest 记录提供；
- 例如 manifest 中 wrapper 是 2779 bytes，而包内版本是 2862 bytes；
- bitstream、主要 FIR/CIC 顶层、Release TB、向量脚本、冲激 vectors 和最终 Release 日志能够匹配。

所以当前应准确表述为：

> 所附 DCP、bitstream、资源、时序和既有验证证据相互自洽；但包内所附当前源码尚不能证明可精确重建该 bitstream。

### 1.5 CDC、DRC 与 methodology 的真实状态

当前不是“零告警”设计：

- CDC：10 条 CDC-3 Info、2 条 CDC-13 Critical、4 条 CDC-15 Warning；
- DRC：8×DPIP-1、2×DPOP-1、1×AVAL-4，无 Error；
- methodology：8×TIMING-18，指向 `dac_data[7:0]`。

现有书面豁免总体有依据，但新版报告必须把表述收紧：

- 只能说 `dac_data[7:0]` 对两个互斥 forwarded clock 都具备 output delay，不能泛化成“所有端口都没有缺 output delay”；
- `set_bus_skew` 只限制两位模式总线之间的相对到达偏差，不直接限制绝对飞行时间；应再增加与协议捕获窗口一致的点对点 absolute datapath-delay 约束或报告；
- 每次构建都应断言预期 CDC ID、数量和端点集合，出现新类别或端点立即失败，而不是只看总数。

### 1.6 证据等级

| 候选 | 当前包内证据等级 | 可用于什么结论 |
|---|---|---|
| P4-D | 原始报告、DCP、bitstream、日志齐全；源码重建绑定有缺口 | 可作为实现与算法基线；先修 P0 再称完整发布 |
| P4-E / P4-F | 执行总结中有完整数字，但没有各自 raw report/DCP/bitstream 目录 | 可作为已报告 Pareto；下一次实验前应重新导出原始证据 |
| 串行前端 ALU | 总结级资源与回归结论 | 足以判当前结构 No-Go |
| X3 | OOC 核心总结，和完整板级口径不同 | 足以判当前微架构 No-Go，不能正式与 P4-D 做板级数字相减 |
| PREG / coefficient ROM / TWO24 | 尚无实现结果 | 只能写为研究候选，不能写成资源结论 |

---

## 2. 对上一版指导的关键修正

### 2.1 PREG 面积判断必须撤销

RTL 中虽然声明了：

```text
integrator_state       : 26 bit
final_integrator_state : 29 bit
```

但 routed DCP 的 EDIF 对两颗 CIC DSP 都显示：

```text
CREG=1
DREG=1
PREG=0
USE_MULT=NONE
USE_SIMD=ONE48
```

且 netlist 中不存在对应的 `integrator_state_reg` 或 `final_integrator_state_reg` Slice 寄存器实例。P4-C 的低 DSP-A/B 资源变化也提供旁证：每把一层积分器搬回 fabric，才分别增加约 26/55 个 FF。

DPOP-1 的含义是“PREG=0，建议增加输出流水以改善性能或功耗”，不能反推“当前状态在 Slice FF”。AMD 的 DSP48E1 原语说明也明确区分 CREG 与 PREG；PREG 会同时寄存 P 与 CARRYOUT 等输出，但不是免费的额外面积删除手段：[DSP48E1 原语说明](https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/DSP48E1)。

因此：

- **面积目标：单纯 CREG→PREG，No-Go。**
- **时序/功耗实验：可以做，但必须单列，不能预报减少 55 FF。**
- 如果仍做 A/B，门槛应是“post-route 资源不增、SAIF 动态功耗下降或关键时序改善”，而不是 FF 数门槛。

### 2.2 Golden 的 20/21-bit 模型不一致

签核 RTL 与 `q_format_and_scaling.json` 是：

```text
Stage3：20 bit
均衡器：20-bit 输入，23-bit 中间，21-bit 无损输出
CIC：21-bit 输入，26/29-bit 两级积分状态
```

而 `nf_build_bittrue_case.m` 当前调用：

```matlab
cic3_shiftadd_bittrue(..., 20)
cic_interp16_bittrue(..., 20, 20, ...)
```

这会把均衡结果饱和回 signed-20。必须在生成任何新 golden 前修复。

一个应加入的定向边界例是：令中间历史样本接近正满幅、两侧样本接近负满幅，三抽头均衡输出约可达到 786430；它超过 signed-20 的 524287，但安全落在 signed-21 的 1048575 内。负向同理可达到约 -786432。旧模型应在这个负测试中明确失败，新模型应与 RTL 0 LSB。

### 2.3 频响门禁名称与公式需要分开

当前：

```matlab
H_db = 20*log10(abs(H/sum(y)))
```

它衡量相对实际 DC 的“形状偏差”。新版应同时计算：

1. `SHAPE_ERROR_DB`：按实际 DC 归一化，仅用于观察纹波形状；
2. `ABS_PASS_ERROR_DB`：按理想冲激和 `IMPULSE_AMPLITUDE × R` 归一化，并由它执行 ±0.05 dB 正式门禁；
3. `DC_GAIN_DB` 与 `MODE_DELTA_DB`：继续单独报告；
4. `STOP_WORST_FREQ_HZ`：同时输出最差阻带频点。

### 2.4 两个参数化陷阱需要先封住

这两个问题不影响当前固定配置，但会伤害后续探索：

1. `FINAL_PRUNE_LSB>0` 时，当前 `round_sat_shift_compact` 的 `UPPER_W` 会成为负值；当前签核值为 0，所以分支被旁路。后续不要直接扫该参数，应先重新推导输入/输出宽度关系并增加 elaboration 负测试。
2. `STAGE3_FLAT=0` 与当前 16-bit 统一外部系数 BRAM 不兼容。非平坦历史系数含 35604，超出 signed-16；外部统一 BRAM又固定装载平坦 Stage3 系数。当前 `STAGE3_FLAT=1` 安全，但非平坦组合必须被明确禁止，不能依赖 `ifndef SYNTHESIS` 下的仿真 `$fatal`。

还有一个命名风险：签核 wrapper 的 `USE_LUTRAM_STAGE23=1` 只是选择 Stage2/3 这套实现分支，下级 `USE_UNIFIED_BRAM_STAGE23_HISTORY=1` 已把正式 history 映射为 RAMB18。报告和指导中不要因为参数名含 `LUTRAM` 就把 P4-D 的正式 Stage2/3 history 误写成 LUTRAM。

建议把签核 wrapper 允许的参数组合写成唯一机器可读配置，并让综合脚本在 elaborate 后核对，而不是把通用模块的默认值当成合法候选。

---

## 3. 当前 Pareto 图应怎样解释

| 版本 | LUT | FF | Slice | DSP | RAMB18 / Tile | 判断 |
|---|---:|---:|---:|---:|---:|---|
| P4-D | **479** | **468** | 198 | 4 | 4 / 2.0 | 当前最低 LUT/FF 默认版 |
| 串行前端 ALU | 504 | 488 | 204 | 4 | 4 / 2.0 | 被 P4-D 全面支配，No-Go |
| P4-E | 491 | 487 | 202 | 4 | 3 / 1.5 | 合理的低 BRAM Pareto |
| P4-F | 531 | 487 | 204 | 4 | 2 / 1.0 | 最低 BRAM版；不属于全面更优 |
| P4-C 低 DSP-A | 504 | 494 | — | 3 | 4 / 2.0 | 已有 3-DSP 对照点 |
| P4-C 低 DSP-B | 523 | 523 | — | 2 | 4 / 2.0 | 低 DSP 对照点 |
| X3 OOC 核心 | 910 | 692 | 307 | 3 | 5 RAMB18 | 当前架构 No-Go；非板级同口径 |

表中只有 P4-D 在本包中具备 raw report/DCP/bitstream 级证据；其余数字是执行总结级，X3 还是 OOC 口径。

这里的根本规律是：固定的 CARRY4 加减器、DSP 内部寄存器和 RAMB18 原语已经很高效。把它们改成共享 ALU、LUTRAM 或复杂调度器，往往是在用更多 mux、状态、地址和跨时钟控制换掉一小块专用资源。

后续不能再用“操作槽足够”推导“面积更小”。时间预算只证明吞吐可行；面积必须由同口径综合/实现报告决定。

---

## 4. 所有新候选共用的比较规则

### 4.1 固定实现口径

- Vivado 2018.3 build 2405991；
- `xc7a35tfgg484-2`；
- 完整板级 `board_demo_competition_dac8_top`，并同时报告固定滤波核心层级；
- `AreaOptimized_high + rebuilt + ResourceSharing=on + opt_design Default`；
- 从 clean source 重新综合，不复用旧 synth DCP；
- 以 post-route 资源为正式数字；OOC 只作提前筛选。

### 4.2 固定正确性门槛

- Smoke 与 Release 全部 PASS；
- 4x / 8x / 128x 与同一 `config_id` 的 golden 逐样本 0 LSB；
- 如果结构只增加固定延迟，必须用公式和常数定义延迟，并覆盖首样本、连续流、停顿、复位中断和有限尾部；
- 任何改系数、改舍入边界或改字长的候选必须新建 golden，不得借用 P4-D 的 0-LSB 结论；
- 六工况正式门槛为：相对理想增益的绝对通带偏差 ≤0.05 dB、绝对阻带衰减 ≥70 dB、`|DC_GAIN_DB|≤0.01 dB`、`|MODE_DELTA_FROM_4X_DB|≤0.01 dB`、`symmetry_lsb=0`、`phase_residual<1e-9 rad`；进入 RTL 前建议使用更严的研究门槛：绝对通带偏差 ≤0.045 dB、128x 绝对阻带 ≥71 dB。DC 归一化的 shape pass/stop 继续报告，但不代替绝对门禁。

### 4.3 固定物理门槛

- WNS > 0，TNS=0；
- WHS ≥0.05 ns，THS=0；
- DAC setup / hold 各 ≥70 ns；
- route error=0；
- mode bus skew 实测 ≤5 ns，并提供 absolute datapath-delay 证据；
- 不新增 CDC/DRC/methodology 类别；预期 warning ID、数量、端点集合必须脚本化断言；
- manifest 必须 clean、无 BOM、全部依赖随包提供且哈希全命中。

### 4.4 资源判断方式

一个候选只有在以下至少一个维度形成真实新 Pareto 时才保留：

- 同 DSP/BRAM 下 LUT 与 FF 同时不劣且至少一项更低；
- 明确少一个 DSP 或一个 RAMB18/Tile，同时 LUT/FF 增量低于预先设定门槛；
- 功能/功耗确有独立价值，并且使用 SAIF 或实测证明，而不是依靠 vectorless 报告的小数点变化。

---

## 5. P0：发布闭环 V2（必须先完成）

### 5.1 修复 21-bit 位真模型

执行项：

1. 把均衡器模型拆成 `input_w=20`、`output_w=21`，先断言输入确属 signed-20 而不是预先 clip，再保持 Verilog `>>>3` 对负数向下取整的规则；
2. CIC 模型输入改为 21 bit，积分状态保持 26/29 bit，末端右移 8、输出 20 bit；
3. 增加能真实越过 signed-20、但不越过 signed-21 的正负定向序列；
4. 重新生成 impulse、10 seed 长随机和至少一组正/负 full-scale/adversarial vectors；现有半满幅冲激不能代替满幅边界；
5. manifest 输出均衡器与 CIC 每个边界的饱和次数和最大绝对值；
6. 增加负测试：旧 20-bit 模型对 adversarial case 必须失配，新 21-bit 模型与 RTL 必须 0 LSB。
7. 取消不透明的 3/7/112-valid 跳过，或为每个被跳过的样点增加明确期望值、延迟公式和断言。

通过门槛：

- 现有低幅 vectors 仍保持相同 golden；
- adversarial case 中确实出现 `abs(equalizer_output)>524287`；
- RTL 与 21-bit golden 在三个正式节点 0 LSB；
- 不允许用“饱和次数仍为 0”代替边界覆盖证明。

### 5.2 让频响脚本真正闭合一个 release 配置

当前脚本只读三个 RTL CSV，不核对 golden、系数、Q JSON、config ID 或饱和计数；它还使用 `freqz`，与“只需 MATLAB base functions”的说明不一致。

新版脚本应：

1. 读取并核对 `config_id`；
2. 校验 `coefficients.csv`、Q JSON、vector manifest 与三份 RTL CSV 的 SHA-256；
3. 按长度语义比较 impulse：RTL CSV 的 225/459/7406 点必须等于较长 golden MEM 的同长度前缀，并断言 golden 剩余尾部全为零；不能直接把不同长度数组作等长比较；
4. 固定公式：`SHAPE=20log10(|H|/|sum(y)|)` 只观察形状；`ABS=20log10(|H|/(IMPULSE_AMPLITUDE*R))` 执行绝对通带与绝对阻带门禁；同时输出 DC gain、mode delta 及最差阻带频点；
5. 输出所有级间饱和计数；
6. 使用 `fft` 实现基础函数版本，或明确声明 Signal Processing Toolbox 依赖，不再两种说法并存；
7. FFT 只作粗扫；对每个候选的最差峰再用直接 DTFT 做局部细化，避免 bin 恰好漏掉峰值；
8. 全带图覆盖到各节点 Nyquist，另加 128x 最差阻带峰放大图；不能再把“全带”固定在 0～120 kHz。

### 5.3 清理系数 provenance

`source_stage1_stage2_config.mat` 含旧七级 all-2x 的 `best_res`，其中约 78.62 dB、GD=3709 不是当前 P4-D 指标。建议输出一个精简的 `p4d_coefficient_provenance.mat`，只保留：

- Stage1/2 的来源与最终 Q15 整数；
- Stage3 从旧 Q14 数值等比例转为当前真 Q15 的说明；
- 每级 tap 数、相位和、绝对系数和、Q 格式和 SHA；
- `config_id`。

同时把 `nf_build_bittrue_case.m` 依赖的 `interp2_polyphase_bittrue.m`、`round_shift_sat_signed.m`、`cic_interp16_bittrue.m` 和所需 MAT 一并打包，使导出包能独立重建 vectors。

### 5.4 重建 clean source-to-bitstream 链

执行项：

1. 从 clean checkout 构建，要求 `tracked_worktree_dirty=false`；
2. 用 Vivado `get_files -used_in synthesis`、compile order 和递归扫描共同枚举全部 synthesis、constraint、Verilog include、`$readmemh`/初始化文件；MATLAB 侧递归枚举 `addpath`、函数和 `load` 依赖，而不是手写少量关键文件；
3. 把构建 Tcl、回归脚本、MATLAB 生成器、配置 JSON、报告、DCP、bitstream 和 Release 日志全部纳入 manifest；
4. SHA 清单使用无 BOM 的 ASCII/UTF-8 文本；校验脚本把任何 warning、格式错误、缺文件或行数不符都当成失败；manifest 同时绑定 commit、submodule 状态、part、Vivado build、strategy/directive、seed 与 `config_id`；
5. 在新目录从零构建，复现 15/15 Release、479/468/4/4 基线、时序和 bitstream；
6. `git status --porcelain --untracked-files=all` 必须为空，或所有实际参与构建的未跟踪文件先纳入版本与 manifest；`tracked_worktree_dirty=false` 单独一项不够；
7. 若固定工具、seed 和源快照下 bitstream hash 仍不能复现，必须记录原因，并至少证明 routed DCP/逻辑等价、资源和全部签核报告一致。

### 5.5 固化 warning/waiver

- 记录 CDC-13/15 的预期端点、数量、协议说明和测试覆盖；
- 对 bundled-data 总线同时保留 bus skew 与 absolute datapath-delay 约束/报告；
- 导出 `report_exceptions -ignored`，确认新增 max-delay 没有被异步 `set_clock_groups` 覆盖，并核对两位端点与两个音频家族；
- TIMING-18 豁免只绑定 `dac_data[7:0]` 和两个互斥 forwarded clock；
- 分别保存 44.1/48 kHz 家族的 DAC min/max 路径，而不只保存全局最坏摘要；
- 新 warning 类别、数量变化或端点漂移都使构建失败；
- 保留 DPOP-1 时明确注明它是 PREG 性能/功耗建议，不是当前面积错误。

### 5.6 P0 完成定义

只有同时满足以下条件，才允许把 P4-D 称为“可独立重建的发布基线”：

```text
clean git
完整依赖哈希 100% 命中
21-bit golden 正确
频响/绝对增益/饱和/config_id 同一脚本闭合
Release 15/15
post-route 479/468/4DSP/4RAMB18，或有书面解释、可重复且可证明等价的结果
CDC/DRC/methodology 预期集合无漂移
```

---

## 6. P1：单 DSP48E1 的 TWO24 高/低位分段 CIC（最高优先研究）

### 6.1 为什么这条路线比“16-bit 输入后 TWO24”更好

上一版的 TWO24 设想需要先把 CIC 输入从 21 bit 剪到 16 bit，会改变 golden 和音频精度。新的方案保留完整 21-bit 输入和 26/29-bit 状态，只把每个状态拆成 24-bit 低位段（limb）和很小的高位段：

```text
第一积分器 A：26 bit = 2-bit 高位段 + 24-bit 低位段
第二积分器 B：29 bit = 5-bit 高位段 + 24-bit 低位段
```

一个 DSP48E1 在 `USE_SIMD="TWO24"` 下同时执行两个 24-bit 加法；高位段只需要很小的 fabric 加法。这样目标是用少量 LUT/FF 换掉一颗 DSP，而不是把完整 26-bit 积分器重新放回 CARRY4。

AMD 的 DSP48E1 文档确认 `TWO24` 提供两路 24-bit 加法、SIMD 模式必须 `USE_MULT="NONE"`，并提供分段 CARRYOUT；PREG 还会同时寄存 P 和 CARRYOUT：[DSP48E1 原语说明](https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/DSP48E1)、[7 Series DSP48E1 User Guide UG479](https://docs.amd.com/v/u/en-US/ug479_7Series_DSP48E1)。

### 6.2 数学关系

当前递推是：

\[
A_n=A_{n-1}+u_n
\]

\[
B_n=B_{n-1}+A_n
\]

TWO24 两个 lane 在同一事件中无法让第二 lane 直接使用刚产生的 \(A_n\)。定义新状态：

\[
Q_n=B_n-A_n
\]

则可得到：

\[
A_n=A_{n-1}+u_n
\]

\[
Q_n=Q_{n-1}+A_{n-1}
\]

因为 \(Q_{n-1}=B_{n-1}-A_{n-1}\)，所以零初值下：

\[
Q_n=B_{n-1}
\]

因此形成两个可独立 A/B 的版本：

- **P1-S（协议首选，same-sequence）：** 计算 \(B_n=Q_n+A_n\)，保留原来的数据事件序列，但增加一条 29-bit fabric CARRY 加法器。
- **P1-L（低 LUT 研究，latency-tolerant）：** 直接输出 \(Q_n=B_{n-1}\)，避免 29-bit 主加法器，但数值相对原版先有一事件关系；叠加 PREG/carry 流水后，推荐结构预计总计延后两个音频有效事件，必须由 cycle model 最终定值。

两者都不是近似滤波器，也不降低 CIC 输入位宽。P1-L 必须保持“每个低速输入仍产生 16 个状态更新和 16 个输出”，只允许固定流水延迟，不能靠第 17 次积分更新或额外 burst 修补尾部；若现有两个低速尾零不足以排空最后一个非零样点，则 P1-L 直接 No-Go。P1-S 的资源很可能接近已有 fabric 积分器版本，只有实际 post-route 更优才保留。

令分段基数 \(M=2^{24}\)：

\[
A=A_HM+A_L,\qquad Q=Q_HM+Q_L
\]

其中低位段按无符号模 \(M\) 运算，高位段保留二补码符号。DSP 两个 lane 计算：

\[
A_L^+=(A_L+u_L)\bmod M
\]

\[
Q_L^+=(Q_L+A_L)\bmod M
\]

fabric 高位段更新：

\[
A_H^+=A_H+u_H+c_A
\]

\[
Q_H^+=Q_H+\operatorname{sext}(A_H)+c_Q
\]

其中 \(c_A,c_Q\) 是两个 24-bit lane 的无符号低位段进位；它们不是有符号溢出标志。2-bit/5-bit 状态更新分别使用至少 3-bit/6-bit 的显式有符号中间量，再截回状态宽度，并断言被截位只可能是合法符号扩展；表达式必须使用旧 \(A_H\)、与该事件锁存的 \(u_H\) 和同一事件 carry，避免 Verilog 自定宽静默截断。UG479 对 TWO24 的分段进位映射应按 P[23:0] 与 P[47:24] 对应的 CARRYOUT 位连接，但最终实现必须以 Vivado 2018.3 UNISIM 仿真和 routed 属性核验为准，不能只凭手册文字连线。

### 6.3 推荐微架构

```text
DSP48E1:
  USE_SIMD = TWO24
  USE_MULT = NONE
  PREG     = 1
  CREG     = 0
  operation = P + C

P[23:0]   保存 A_L
P[47:24]  保存 Q_L
C[23:0]   输入 u_L
C[47:24]  输入旧 P[23:0]，即 A_L(old)

fabric:
  2-bit A_H
  5-bit Q_H
  pending/carry 对齐控制
  原有 29->20 舍入饱和器
```

签核 CIC 不在 20 MHz 域运行，而在 `clk_audio_128x=5.6448/6.144 MHz` 域运行，且正式配置 `ce128_out=1'b1`。连续 burst 中每个音频时钟都有新事件，所以方案必须支持 **II=1**；不能等待一个空闲 20 MHz 微拍，也不能为此偷偷新增异步 CDC/FIFO。

`PREG=1` 时 CARRYOUT 同样被寄存，推荐使用每拍重叠的流水，而不是停一拍：

1. 在音频事件 \(n\) 的边沿，PREG 启动/捕获低位段 \(n\)；同时锁存该事件的高位增量上下文；
2. 在音频事件 \(n+1\) 到达的同一边沿之前，registered CARRYOUT 与 P 中的低位段 \(n\) 已可用；组合形成事件 \(n\) 的 `high_next`，该边沿同时提交高位段 \(n\)、启动低位段 \(n+1\)，并退休事件 \(n\) 的输出；
3. P1-S 用对齐的 \(Q_n+A_n\) 退休原数据事件 \(n\)，预计 valid 固定延后 1 个音频事件；P1-L 退休 \(Q_n=B_{n-1}\)，预计相对原数据固定延后 2 个音频事件。

上述 `+1/+2` 是推荐流水的预期值，不是未经仿真的承诺。cycle model 必须逐音频边沿写出 P、CARRYOUT、高位上下文、`high_next`、y 与 valid 的表格，并覆盖首个无效前缀和最终流水排空。若显式 DSP48E1 无法在 II=1 下实现，P1 立即 No-Go；迁到 20 MHz 再加 CDC 属于另一套高成本架构，不计入本路线。

### 6.4 四级实验流程

#### P1-A：纯整数 cycle model

先不写 DSP 原语 RTL，只实现事件级模型，验证：

- 完整 signed 26/29-bit 模运算；
- 24-bit 高/低位分段与整宽结果一致；
- 正负低位段 `0xFFFFFE/0xFFFFFF/0x000000/0x000001` 边界；
- `ce_out=1` 的长连续流作为第一测试，再覆盖随机停顿、中途复位和 burst 首尾；
- \(Q_n=B_{n-1}\) 对所有事件成立；
- P1-L 在仍保持每输入 16 次积分更新/16 个输出、且只使用现有有限向量尾零和正常流水排空的条件下，没有丢失最后一个非零样点；P1-S 的数据事件序列与原版一致。

失败即停止，不进入 Vivado。

#### P1-B：Vivado 2018.3 UNISIM 原语单元测试

显式实例化 DSP48E1，覆盖：

- `USE_SIMD=TWO24`、`USE_MULT=NONE`；
- `PREG=1` 与 CEP/RSTP；
- P 自反馈和 C 端口双 lane 打包；
- CARRYOUT 的 lane 与流水对齐；
- 连续每拍事件下，高位段 \(n\) 的提交、输出 \(n\) 的退休和低位段 \(n+1\) 的启动可在同一音频边沿重叠；
- reset 在低位段更新与高位段提交之间到达；
- `ce_out=1` 的长连续流，以及后续 stall/resume。

单元测试必须比较每一拍内部 A/Q 状态及其与原 A/B 状态的映射，而不只是最终音频输出。

#### P1-C：CIC 模块 OOC

与当前 2-DSP CIC 并排实例化，要求：

- 连续 320 组、随机停顿 ≥480 组、至少 20 个随机 seed；
- 中途复位覆盖 idle、comb、首输出、burst 中间、最后输出和 high-limb pending；
- P1-L 所有输出按 cycle model 最终证明的固定关系（推荐流水预期 `+2` 音频事件）0 LSB；现有有限向量末尾的两个低速零是否足以覆盖延迟，必须由非零尾部断言证明，不能只比较固定输出数量，也不得新增积分更新；
- P1-S 应保持原数据事件序列，仅允许固定音频时钟级 valid 延迟（推荐流水预期 `+1`）；
- hierarchy 中只有 1 个 CIC DSP；
- routed/netlist 属性确认为 `TWO24/PREG=1/USE_MULT=NONE`，没有被综合器拆成 fabric 或两颗 DSP。

#### P1-D：完整板级候选

建议目标：

| 指标 | 首选目标 | 继续观察区 | 停止条件 |
|---|---:|---:|---:|
| LUT | ≤495 | 496～503 | 与已有 3-DSP 版相比 LUT、FF 都不占优，或 >520 |
| FF | ≤480 | 481～493 | 与已有 3-DSP 版相比 LUT、FF 都不占优，或 >510 |
| DSP | **3** | — | 仍为 4，或被拆成 >3 |
| RAMB18 | 4 | 4 | >4 |

已有 3-DSP 对照为约 504 LUT / 494 FF。新方案若能做到约 490～500 LUT / 475～485 FF，就形成明显更好的 3-DSP Pareto；若同时不优于 504/494，则停止，不再扫实现策略碰运气。

### 6.5 主要风险

- PREG/CARRYOUT 的流水关系理解错误；
- P 自反馈与 C 端口跨 lane 反馈形成过长组合路径；
- 2/5-bit 高位段在负数符号扩展或 lane carry 上错一位；
- II=1 连续事件下 carry、低位段和高位段上下文错拍；
- 固定流水延迟在 burst 最后样点、模式切换或复位时丢尾；
- Vivado 2018.3 不按预期保留 ONE-DSP SIMD 结构；
- 控制逻辑增量接近现有 26-bit fabric 积分器，失去资源优势。

这条路线应被视为“高价值、需原语验证的精确研究”，不是已经实现的优化结果。

---

## 7. P2：从 P4-E 出发迁移只读系数到 distributed ROM

### 7.1 为什么比 P4-F 更合理

P4-F 把可写、带独立历史地址行为的 Stage2/3 history 搬进 8 个 RAM32M，仅 RAM32M 本体就消耗 32 LUT，再加 bank、地址和选择逻辑，最终从 P4-E 的 491 LUT 增到 531 LUT。

系数则是只读且端口模式固定，更适合 distributed ROM。当前统一系数 RAMB18 的两个端口必须保留并行供数能力：

- Stage1：约 32×16 的地址平面；
- Stage2/3：64×16 的地址平面；
- 两端可能同拍独立访问，不能用一个单端口 ROM 加宽 mux 替代。

理论存储本体约 20～30 LUT，但读时序选择会显著改变 FF：

- 异步 LUTROM 或“地址已寄存、ROM 组合读”的实现可少增 FF，但必须重排/证明与原 RAMB18 同样的系数到达周期；
- 两组显式 registered-output ROM 可能新增约 32 个 Slice FF（两个 16-bit 输出），从 P4-E 的 487 FF 上升到约 519 FF。

所以不能同时假定“同步读完全不变”和“FF 只增加个位数”；只能以 cycle model 和综合数据判断。

### 7.2 实验步骤

1. 先重新导出并复现 P4-E 的 raw baseline：491 LUT / 487 FF / 3 RAMB18 / 4 DSP；
2. 保持 P4-E 的 PCM+Stage1 共享 RAM 和 Stage2/3 history RAM 不变；
3. 把统一 coefficient RAMB18 拆成两组端口等效 ROM，分别服务 Stage1 和 Stage2/3；
4. 分别 A/B 两个实现：异步 LUTROM+既有地址流水，以及 registered-output LUTROM；两者都必须从 MAC 使用拍反推系数地址，保证到达周期与 bit-true 结果一致；
5. 原语/地址测试覆盖所有 96 个有效地址，并增加每个有效地址翻转一位的负测试；
6. 重新跑完整 16/16 或更新后的统一 Release，并导出 raw hierarchy、DCP、bitstream。

### 7.3 资源门槛

| 结果 | 判断 |
|---|---|
| 2 RAMB18、LUT ≤520、FF ≤495 | **Go，优质 1-Tile 候选**，通常要求无额外32-bit输出寄存 |
| 2 RAMB18、LUT ≤525、FF ≤520 | registered-ROM 条件候选；只作为 LUT/BRAM/FF 交换点 |
| LUT 526～530、FF ≤520，且功能/时序全过 | 可保留为低 BRAM 边缘 Pareto |
| LUT ≥531 且 FF ≥487 | 不优于 P4-F，No-Go |
| RAMB18 仍为3，或 ROM 被复制/回推 BRAM | 结构目标失败 |
| 新增端口仲裁、pending 或宽 mux | 立即复核架构，不继续堆控制补丁 |

这条路线的目标不是替代 479-LUT P4-D，而是得到比 P4-F 更合理的 1 BRAM Tile 版本。

---

## 8. P3：Stage3 与三抽头均衡器联合设计

### 8.1 不能直接卷积后宣称严格等价

当前 11-tap Stage3 后接：

\[
g=[-1,10,-1]/8
\]

数学上卷积后是 13-tap；按当前 Q15 Stage3 系数计算，其等效 Q15 数值约为：

```text
[-50.5, 523.5, 173.5, -4136.75, -1344.75, 19995.25,
 35207.5,
 19995.25, -1344.75, -4136.75, 173.5, 523.5, -50.5]
```

这里有三项硬问题：

1. 中心约 35207.5，超出 signed-16 系数范围；
2. 现有链在 Stage3 Q15 后先舍入/饱和到 20 bit，再执行三抽头算术右移；先量化再均衡是非线性的，不能用一次卷积和一次舍入做到逐点严格等价；
3. 8x 正式输出取自平坦 Stage3、位于均衡器之前。若直接把 Stage3 改成补偿响应，8x 频响也会改变。

因此，“机械卷积删均衡器”不是 0-LSB 优化。

### 8.2 只先做 MATLAB 硬件感知搜索

研究两个模式化系数组：

- 4x/8x 模式：保留平坦 Stage3；
- 128x 模式：使用带 CIC 逆下垂目标的 Stage3，尝试删除外部均衡器。

Stage3 job 启动时必须快照已原子提交的 mode，不能在一个 MAC job 中途换系数。卷积中心 35207.5 在数学上需要至少 17 个有符号有效位；物理实现优先使用 DSP/BRAM 方便的 18-bit lane，并重新推导乘积与累加宽度，或给出经过证明的中心抽头分解。当前 signed-16 统一 BRAM不能复用。动态切换应继续经过 mute/settle/warmup，并明确清理/排空旧响应产生的 CIC 积分状态，而不是让新旧系数和旧 CIC 状态直接交叉。

验收必须按所选输出模式分别运行：4x/8x 使用 flat bank，128x 使用 compensation bank；每种模式拥有独立 `config_id` 与 golden。128x 模式内部产生的 y8 不再被声称与正式平坦 8x golden 同时 0 LSB。

优化目标不能只看 tap 数，应直接包含：

```text
非零对称乘积任务数
系数位宽是否跨过 signed-16 边界
共享 Stage2/3 DSP 的最坏 job deadline
系数存储端口与地址开销
模式切换 reset/warmup/mute 成本
预估 LUT/FF 与实际 RTL net saving
```

进入 RTL 前的门槛：

- 六工况绝对通带偏差 ≤0.045 dB；
- 128x 阻带 ≥71 dB；
- 量化后严格线性相位；
- 基于真实 `clk_audio_128x` 与 `ce8` 每 16 个音频周期窗口的 cycle model 证明共享 Stage2/3 deadline，建议至少保留 4 个音频周期余量；
- 预计删除 46 LUT / 40 FF 的均衡器后，扣除双系数、模式控制和舍入逻辑，仍能净省至少 20 LUT 与 20 FF；
- 动态 8x↔128x 切换有明确的原子系数提交、状态清理和静音窗口。

浮点频响通过仍不够。删除“Stage3 20-bit 舍入后再均衡”这个非线性边界后，还必须完成 bit-true 的正/负满幅、-60 dBFS、-90 dBFS、随机/音频误差谱或 SNR，以及全部饱和计数检查。

任一不满足就停止。当前只有 2.33 dB 阻带余量，不建议通过盲目缩位、把 CIC 降到 N=2 或减少补偿强度来换面积。

---

## 9. P4：功耗应从 MMCM 入手

P4-D 的 vectorless 报告约为：

```text
总功耗 0.271 W
动态   0.199 W
静态   0.072 W
其中两颗 MMCM 动态约 0.197 W
```

这意味着几十个 LUT/FF 的变化几乎不可能在当前 vectorless 精度下被可靠分辨。AMD 也建议用仿真活动文件改善 post-route 功耗分析精度：[Vector/SAIF 功耗分析](https://docs.amd.com/r/en-US/ug907-vivado-power-analysis-optimization/Vector-SAIF-Based-Power-Analysis)。

推荐两种路线：

### 9.1 如果不要求运行时切换采样率家族

分别生成 44.1 kHz 与 48 kHz 两个单 MMCM bitstream。这是控制风险最低、最容易证明功耗收益的方案。

### 9.2 如果必须运行时切换

对当前未选中的 MMCM 使用 `PWRDWN`；MMCME2_ADV 原语提供该输入：[MMCME2_ADV 原语说明](https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/MMCME2_ADV)。建议状态机：

```text
MUTE
-> 唤醒目标 MMCM
-> `LOCKED` 连续稳定 N 拍
-> 切换 BUFGMUX
-> 目标时钟 heartbeat 通过
-> 关闭旧 MMCM
-> 滤波链 warmup
-> UNMUTE
```

必须覆盖 LOCK 超时、目标时钟未运行、连续往返切换和复位插入。功耗比较使用同一 post-route 设计、同一音频激励、同一 SAIF 覆盖率和同一温度/电压设置；vectorless 的 0.001 W 差异不作为 Go 依据。

---

## 10. 明确停止的路线

| 路线 | 为什么停止 |
|---|---|
| 单纯把 CIC CREG 状态改到 PREG 以省 FF | 当前状态已经在 DSP 内；没有 55 个 Slice FF 可省 |
| 串行前端共享 ALU | 省便宜 CARRY 链，却增加宽 mux、状态和中间寄存器；504/488 被 P4-D 支配 |
| 继续修当前 X3 异步 FIFO+三双 bank 架构 | 调度、CDC、bank 与上下文成本远大于省下的 DSP；现有 OOC 为 910/692 |
| 只凭 MAC slot 预算判断面积 | slot 只证明吞吐，不证明资源 |
| 把 Stage2/3 可写 history 继续搬 LUTRAM | P4-F 已实证每少一个 BRAM 需约 +40 LUT |
| 盲目 `FINAL_PRUNE_LSB` 扫描 | 当前参数分支存在负宽度问题，且会改变定点边界 |
| CIC 直接降到 N=2 | 128x 阻带余量太小，镜像抑制风险高 |
| 直接卷积 Stage3 与均衡器并声称 0 LSB | 中间舍入/饱和使其非严格线性等价，8x 分支也会变化 |
| 用 vectorless 功耗比较几十个 LUT/FF | 两颗 MMCM 几乎占满动态功耗，报告分辨率不足 |

X3 的“大方向”只有在重新设计后真正达到全链 1 DSP 才值得重启；如果仍停在 3 DSP，就应与更小的现有 3-DSP/TWO24 候选比较并停止。

---

## 11. 推荐执行顺序与分支纪律

### 第一步：冻结 P4-D，不在原分支直接试验

- 保留当前 bitstream、DCP 和报告只读；
- 建立 P0 release-v2 分支，只做证据链与模型修复；
- P0 完成后打新的 clean tag，作为所有候选共同父节点。

### 第二步：P1 TWO24 采用四级 Stop/Go

```text
整数模型
-> UNISIM DSP48E1 单元
-> CIC OOC
-> 完整板级
```

任一级失败都保留 No-Go 记录，不把临时代码混入签核 wrapper。

### 第三步：独立开展 P2 coefficient ROM

- 先复现并导出 P4-E raw baseline；
- 只改变 coefficient memory；
- 不与 TWO24 同时合并，先测出单变量资源增量；
- 两条都成功后才创建组合候选。

### 第四步：MATLAB-only 的 P3

- 先提交搜索脚本、候选 CSV、六工况和定点噪声结果；
- 达不到 RTL 入口门槛就不写 RTL；
- 达标后新建 config ID 与 golden，不能继承 P4-D 0-LSB。

### 第五步：功耗与上板闭环

P4-D/P1/P2 的面积比较完成后，再单独做 MMCM powerdown；避免把面积、功耗和 CDC 三类变量混在一次提交中。

---

## 12. 每个候选必须导出的最小证据包

```text
00_manifest/
  release_manifest.json
  SHA256SUMS（无 BOM）
  git_status.txt
  vivado_version.txt

01_config/
  config.json
  q_format_and_scaling.json
  coefficient_provenance.mat/csv

02_source/
  Vivado get_files 枚举出的全部 RTL/XDC/MEM/include
  构建 Tcl、回归脚本、MATLAB 生成器及全部依赖

03_verification/
  Smoke/Release 原始日志
  vector manifest 与 saturation counts
  RTL impulse CSV、golden MEM、frequency metrics/summary/plots
  reset、stall、mode switch、负测试日志

04_implementation/
  synth/post-route utilization 与 hierarchical utilization
  timing、CDC、DRC、methodology、exceptions、bus skew、max delay
  routed DCP、bitstream、build manifest
  DSP/RAMB18 primitive property audit

05_board/
  44.1/48 kHz × 4x/8x/128x 六工况 DA_CLK
  DAC 波形/频谱
  动态家族与倍率切换记录
  电源实测或测量方法
```

上板前至少核对六个输出时钟目标：176.4 kHz、352.8 kHz、5.6448 MHz、192 kHz、384 kHz、6.144 MHz。既定仿真与实现流程已经完成，但 21-bit golden 和发布来源绑定尚未闭环；实物下载、DA_CLK 和 DAC 频谱也仍是未完成项，不能由 bitstream PASS 代替。

---

## 13. 最终决策树

```text
P0 clean release-v2 是否完成？
  否 -> 先在P0内修正并重建golden/manifest，不进入新优化或发布候选
  是 -> 做 P1 TWO24

P1 是否在固定延迟下 0 LSB，且形成优于已有 504/494 的 3-DSP Pareto？
  是 -> 保留为低 DSP 主候选
  否 -> 记录 No-Go，回退 P4-D/P4-C 3DSP

是否明确需要 1 BRAM Tile？
  是 -> 从 P4-E 做 P2 coefficient ROM
  否 -> 保留 P4-D，不为 BRAM 增加 LUT/FF

是否允许改变 golden？
  是 -> MATLAB 先做 P3 联合设计
  否 -> 不动 Stage3/均衡器/字长

是否以功耗为目标？
  是 -> MMCM PWRDWN 或单家族 bitstream + post-route SAIF/实测
  否 -> 不用 vectorless 小数差异指导面积优化
```

最终推荐仍是：

1. **默认交付：P4-D。**
2. **低 BRAM：P4-E；只有 1 Tile 为硬约束时才用 P4-F，或等待更好的 P2。**
3. **低 DSP 新研究：优先 TWO24 高/低位分段，不再做单纯 PREG 或宽 ALU 共享。**
4. **明显的新面积突破只有在跨过真实原语边界时才可能出现：少一颗 DSP、少一颗 RAMB18/Tile，或删除整个均衡器模块。**

如果项目坚持当前三节点 golden 与严格等价，优先顺序是 P1 TWO24、P2 coefficient ROM；如果允许按模式新建 golden，P3 删除独立均衡器可能带来更大的 LUT/FF 净收益，应与 P1 并行做 MATLAB 可行性筛选。
