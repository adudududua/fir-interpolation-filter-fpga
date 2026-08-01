# P4-D 导出审计与下一阶段优化指导 V2：执行反馈

## 1. 执行结论

本轮没有盲目合并所有建议，而是按指导规定的 P0→P1/P2→P3 Stop/Go 顺序逐项验证。最终结论如下：

1. **P0 已完成并签核。** 21-bit golden、频响绝对门禁、CDC 绝对延迟、无 BOM 哈希和 clean-source-to-bitstream 闭环均已修复；默认发布版仍为 P4-D：**479 LUT / 468 FF / 198 Slice / 4 DSP / 4 RAMB18E1（2 Tile）/ 2 MMCM**。
2. **P1 TWO24 在结构和功能上成功，但没有达到首选资源门槛。** 单颗 DSP48E1 精确承担两级 CIC 积分器，完整工程降到 3 DSP，17/17 Release 通过；代价为 **518 LUT / 498 FF**。它是可回退的 3-DSP 研究 Pareto，但 LUT/FF 还劣于既有 P4-C 3-DSP 的 504/494，因此不替代默认版，也不作为最佳 3-DSP 交付版。
3. **P2 分布式系数 ROM 成功形成 1 BRAM Tile Pareto。** P2-A 为 **513 LUT / 496 FF / 4 DSP / 2 RAMB18E1（1 Tile）**，17/17 Release 通过；它明显优于旧 P4-F 的 531 LUT / 487 FF / 1 Tile（少 18 LUT、多 9 FF），适合 BRAM 比 LUT/FF 更紧张的场景，但不替代 P4-D。
4. **P3 通过 MATLAB RTL 入口门禁。** 11-tap Q15/18-bit 联合 Stage3/均衡器候选满足六工况、线性相位、定点强弱信号和调度余量要求。预计可通过删除独立均衡器净省约 29 LUT / 31 FF，但这只是保守模型，尚无 RTL、post-route 或 bitstream，不能写成实测资源。
5. **PREG 面积路线明确撤销。** routed DCP 已证明现有两颗 CIC DSP 使用 CREG 保存状态，Slice 中不存在可直接删除的 40～55 个状态 FF；单纯 CREG→PREG 不具有指导所要求的面积依据。
6. **P4 MMCM 功耗路线本轮未执行。** 它是独立的低功耗目标，需要 SAIF 或实板电流测量，并会引入时钟启停、LOCK 超时和切换 CDC 验证；不应与本轮面积单变量实验混合。

默认交付仍是 P4-D clean release-v2。P1、P2、P3 均保存在独立 Git 分支和标签中，便于继续研究或回退。

## 2. 指导条目执行矩阵

| 指导项 | 状态 | 结果 | 是否进入默认版 |
|---|---|---|---|
| P0-1：20/21-bit golden 修复 | 已完成 | signed-20 输入、signed-21 均衡输出、21-bit CIC 输入；旧模型定向负测出现 5 次错误削顶，新模型通过 | 是 |
| P0-2：频响与 release 配置闭合 | 已完成 | 59 项输入资产哈希、config ID、RTL/golden 前缀与零尾、绝对/shape 指标、局部 DTFT 均闭合 | 是 |
| P0-3：系数 provenance | 已完成 | Q 格式、最终系数、依赖和配置 ID 进入发布证据 | 是 |
| P0-4：clean source→bitstream | 已完成 | 独立干净 worktree 构建，93 项发布资产哈希命中，构建前源状态 clean | 是 |
| P0-5：CDC/物理门禁 | 已完成 | mode bus skew 与 absolute max-delay 同时存在，ignored exceptions 为空 | 是 |
| P1-A：TWO24 整数周期模型 | 已完成 | P1-S Go；P1-L 因有限尾少一个输出 No-Go | 独立分支 |
| P1-B：DSP48E1 UNISIM | 已完成 | TWO24/PREG=1/USE_MULT=NONE，7461 events、7413 commits、84 resets 通过 | 独立分支 |
| P1-C：CIC OOC | 已完成 | 95107 输出 0 LSB；2 DSP→1 DSP，+36 LUT/+18 FF | 独立分支 |
| P1-D：完整板级 | 已完成 | 518 LUT / 498 FF / 3 DSP，17/17 Release，bitstream 生成 | 保留，不替代默认版 |
| P2：双 distributed coefficient ROM | 已完成 | A/B 均实现；选中 P2-A 513/496/4DSP/1Tile | 低 BRAM 分支 |
| P3：Stage3/均衡器联合设计 | MATLAB 门禁完成 | 11-tap Q15/18-bit 候选通过；尚未进入 RTL | 研究分支 |
| PREG 面积 A/B | 不执行 | 前提被 routed DSP 属性否定，没有可删除的 Slice 状态 FF | 否 |
| P4：MMCM PWRDWN/单家族 bit | 延后 | 需要独立 SAIF/实测和完整时钟切换安全验证 | 否 |
| 实物板卡六档验收 | 环境受限 | bitstream 已生成；下载、DA_CLK、DAC 波形/频谱和电流仍需现场完成 | 待现场 |

## 3. P0：发布闭环 V2

### 3.1 完成的修复

- 将均衡器权威模型固定为 signed-20 输入、signed-21 无损输出；定向满量程序列实际产生 `abs(output)>524287`，证明边界被覆盖。
- CIC 模型固定为 `C² → Hold16 → I²`，21-bit 输入、26/29-bit 状态，并与原数学参考在 8240 个样点上 0 LSB。
- Release 向量扩展为 impulse、10 个固定 seed 及正/负满量程，共 13 组；三个输出节点同时验证 reset-zero prefix 和全序列。
- 频响脚本区分 shape 指标和相对理想增益的绝对指标；粗 FFT 后用直接 DTFT 细化最差阻带峰。
- 用精确同步器/BUFGMUX false path 代替过宽异步时钟组，并同时约束 50 ns bus skew 和 50 ns absolute datapath delay。
- 构建包装器记录源码起始状态并恢复 Vivado 自动改写的 XPR，SHA 清单无 BOM，发布 manifest 能绑定源、报告、DCP 和 bitstream。

### 3.2 签核数据

| 项目 | P4-D Release V2 |
|---|---:|
| 资源 | 479 LUT / 468 FF / 198 Slice / 4 DSP / 4 RAMB18E1（2 Tile）/ 2 MMCM |
| Smoke / Release | 15/15 / 15/15 PASS |
| 全局 WNS / WHS | +45.734 / +0.121 ns |
| DAC setup / hold | +76.116 / +78.117 ns |
| mode CDC | skew 1.813/50 ns；absolute delay 0.912/50 ns |
| 功耗 | 0.271 W total / 0.199 W dynamic / 0.072 W static；vectorless Medium |
| bit SHA-256 | `8630210663629357237AAA3F076348FBE65610EAAB61ADA4706E81F75AAF02A6` |
| 分支 | `codex/national-finals-p0-release-v2` |
| 标签 | `nf-p4d-r2-479lut-468ff-4dsp-2bram-2mmcm-clean` |

六工况正式指标：

| 输入 | 输出 | 绝对通带最大误差 | 绝对阻带衰减 |
|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003011 dB | 78.670 dB |
| 44.1 kHz | 8x | 0.003470 dB | 78.565 dB |
| 44.1 kHz | 128x | 0.005146 dB | 72.335 dB |
| 48 kHz | 4x | 0.003011 dB | 78.670 dB |
| 48 kHz | 8x | 0.003033 dB | 78.565 dB |
| 48 kHz | 128x | 0.003477 dB | 72.335 dB |

## 4. P1：TWO24 双积分器

### 4.1 采用的方法

一个 `DSP48E1` 配置为 `USE_SIMD=TWO24`、`USE_MULT=NONE`、`PREG=1`，两个 24-bit lane 分别保存两级 CIC 积分器的低位段；26-bit 与 29-bit 状态剩余的 2/5-bit 有符号高位及 lane carry 用小型 CARRY4/寄存器精确补齐。该结构跨越了“一颗 DSP”这一真实原语边界，而不是把整个宽积分器搬回 LUT。

### 4.2 遇到的问题与解决

- **P1-L 纯流水方案丢有限尾。** 连续流中看似只增加固定延迟，但有限向量末尾会少一个非零提交；若补一次更新便会改变积分次数。按 Stop/Go 规则判 No-Go，没有用补零掩盖问题。
- **跨 lane 进位与符号扩展容易错拍。** 使用逐拍整数 A/Q 映射模型后再进入 UNISIM，覆盖连续、随机 stall/resume，以及低位更新到高位提交之间的复位。
- **不能只看最终音频样点。** UNISIM 测试比较每次内部提交；随后 CIC OOC 再与基线逐输出对拍，最后才进入完整板级。

### 4.3 实测结果与判定

| 口径 | 基线 | TWO24 | 变化 |
|---|---:|---:|---:|
| CIC OOC | 70 LUT / 119 FF / 2 DSP | 106 LUT / 137 FF / 1 DSP | +36 LUT / +18 FF / -1 DSP |
| 完整板级 | 479 LUT / 468 FF / 4 DSP | 518 LUT / 498 FF / 3 DSP | +39 LUT / +30 FF / -1 DSP |

完整板级 WNS/WHS 为 `+45.933/+0.114 ns`，DAC setup/hold 为 `+76.116/+78.117 ns`，功耗估计为 0.270 W；17/17 Release、95107 个 CIC 输出及三个正式节点均为 0 LSB。bit SHA-256 为 `8AFE9D20990AA1FA000EFFF6E764004B1C48DA087759B2011E079760DAB0CEAD`。

指导的首选目标为 LUT≤495、FF≤480；继续观察区也要求至少不被既有 504/494 3-DSP 点同时压制。P1 为 518/498，所以结论是：**结构验证 Go，首选资源目标 No-Go**。保留分支和位流用于展示新型 DSP48 SIMD 方法，但最佳现有 3-DSP 资源点仍是 P4-C 504/494。

- 分支：`codex/national-finals-p1-two24-cic`
- 标签：`nf-p1-two24-518lut-498ff-3dsp-2bram-2mmcm`

## 5. P2：双分布式系数 ROM

### 5.1 采用的方法

从 P4-E 出发，保持 PCM+Stage1 共享 RAM、Stage2/3 history RAM、滤波系数和调度不变，只将统一 coefficient RAMB18E1 拆成两个独立 distributed ROM 读端口。为避免把时序假设写死，实际实现了：

- P2-A：地址寄存、组合 ROM 输出；
- P2-B：组合寻址、数据输出寄存。

两者对 MAC 都维持一拍读取契约。专用测试穷举 96 个有效地址，并对每个地址做单 bit 故障注入，避免参考模型和 DUT 同错。

### 5.2 遇到的问题与解决

- **直接复用旧回归目录时缺少与本分支绑定的配置资产。** 重新生成同 config ID 的 Release vectors，并将可再生工作目录保持为 Git ignore，不把临时文件混入源码根目录。
- **同步 ROM 可能增加 32 个输出 FF。** 所以没有只实现一种写法；A/B post-route 证明地址寄存方案只增加 9 FF，而数据寄存方案增加 29 FF，选中 P2-A。
- **综合器可能复制 ROM 或重新推回 BRAM。** 实现报告和层级/原语审计确认最终只有 2 个 RAMB18E1，即 1 Tile，结构目标达成。

### 5.3 实测结果与判定

| 方案 | LUT | FF | DSP | RAMB18 / Tile | WNS / WHS | 功耗估计 |
|---|---:|---:|---:|---:|---:|---:|
| P4-D | 479 | 468 | 4 | 4 / 2.0 | +45.734/+0.121 ns | 0.271 W |
| P4-E | 491 | 487 | 4 | 3 / 1.5 | +46.132/+0.105 ns | 0.271 W |
| **P2-A** | **513** | **496** | **4** | **2 / 1.0** | **+45.949/+0.117 ns** | **0.270 W** |
| P2-B | 516 | 516 | 4 | 2 / 1.0 | +45.764/+0.103 ns | 0.270 W |

P2-A 通过 17/17 Release，完整布线且 0 timing failing endpoint；bit SHA-256 为 `A730052ECED485F0BF1A903FBE1525DE4CC1704500BC65654893AA2C3BF021C1`。它满足指导的优质 1-Tile 门槛 LUT≤520、FF≤495 的 LUT 条件，FF 只超 1 个；结合相对 P4-F 少 18 LUT、只多 9 FF，仍判为有效低 BRAM Pareto，但不是默认综合最优。

- 分支：`codex/national-finals-p2-coeff-distributed-rom`
- 标签：`nf-p2-513lut-496ff-4dsp-1bram-2mmcm`

## 6. P3：Stage3 与均衡器联合设计

### 6.1 采用的方法

按指导只做 MATLAB 硬件感知搜索，不直接修改 RTL。4x/8x 继续使用 flat Stage3；128x 使用独立补偿 bank，以 11/13/15/17 tap、不同阻带权重和双采样率目标搜索。最终候选为 11-tap、Q15/18-bit 对称系数：

```text
[561, 137, -4232, -1554, 20046, 35584,
 20046, -1554, -4232, 137, 561]
```

### 6.2 遇到的问题与解决

- **旧候选偏向 44.1 kHz。** 搜索目标改为 44.1/48 kHz 六工况联合门禁。
- **20-bit Stage3 输出在强激励下削顶。** 保留 signed-21 Stage3→CIC 交接，不用缩位换取虚假面积。
- **早期模型少了 Q 格式对应的缩放，造成约 0.56 dB 的假误差。** 对照 RTL 的每一级二进制点重新校准，加入 DC gain 与模式差门禁。
- **原种子在 44.1 kHz/-1 dBFS 比 P4-D 多 2 次 CIC 饱和。** 对称增益精扫后选择 `trim=0.99945`，饱和计数恢复到与 P4-D 相同的 16 次。

### 6.3 MATLAB 门禁结果

| 输入 | 输出 | 绝对通带最大误差 | 绝对阻带衰减 |
|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 78.568 dB |
| 44.1 kHz | 8x | 0.003521 dB | 78.609 dB |
| 44.1 kHz | 128x | 0.007730 dB | 72.371 dB |
| 48 kHz | 4x | 0.003022 dB | 78.568 dB |
| 48 kHz | 8x | 0.003007 dB | 78.609 dB |
| 48 kHz | 128x | 0.007606 dB | 72.371 dB |

对称误差为 0，最大相位拟合残差 `1.42e-13 rad`；10 类定点激励通过，随机噪声 SNR 97.81 dB，-60 dBFS 约 58 dB，-90 dBFS 约 30 dB。11-tap 两相任务仍为 6/5，最坏 9 拍，在 16 拍 `ce8` 窗口中余 7 拍。

删除独立均衡器可去掉其已实现层级的 46 LUT/40 FF；为双 bank 地址、18-bit 系数、模式快照和 21-bit 边界保守预留 17 LUT/9 FF，因此预测净变化约 `-29 LUT/-31 FF`。若从 P4-D 推算约为 450 LUT/437 FF/4 DSP/2 Tile，但**这不是 Vivado 实测数字**，下一步必须独立完成 RTL、golden、17/17 Release、动态切换和完整 post-route 后才可决定是否纳入交付。

- 分支：`codex/national-finals-p3-joint-stage3-equalizer`
- 标签：`nf-p3-matlab-gate-11tap-q15-18bit`

## 7. 未执行项及原因

### 7.1 单纯 CIC CREG→PREG 面积优化

不执行。P4-D routed DCP 显示两颗 CIC DSP 均为 `CREG=1, PREG=0, USE_MULT=NONE`，26/29-bit 状态已经被 DSP 内部寄存器吸收，netlist 中没有对应的 Slice 状态寄存器。DPOP-1 是性能/功耗建议，不是“存在 55 个 Slice FF”的证据。若以后研究 PREG，只能以时序或带 SAIF 的功耗为目标。

### 7.2 MMCM PWRDWN 或双单家族 bitstream

本轮延后。当前 vectorless 动态功耗约 0.199 W，其中两颗 MMCM 约占 0.197 W，说明这是有价值的功耗方向；但它不能用 vectorless 0.001 W 差异验收。运行时 PWRDWN 还需要 MUTE→唤醒→LOCK 稳定→BUFGMUX 切换→heartbeat→关闭旧 MMCM→warmup→UNMUTE 的新状态机及异常测试。建议在面积候选冻结后建立独立功耗分支，使用同一 post-route SAIF 或实板电流测量。

### 7.3 物理板卡

当前环境能完成 MATLAB、XSim、综合、实现、时序、CDC、DRC、功耗估计和 bitstream，但不能接触开发板、示波器或频谱仪。正式交付前仍需实测 176.4/352.8 kHz、5.6448 MHz、192/384 kHz、6.144 MHz 六档 DA_CLK，以及 DAC 波形、频谱和动态切换静音窗口。

## 8. 最终资源与证据等级汇总

| 版本 | 证据等级 | LUT | FF | DSP | RAMB18 / Tile | MMCM | WNS / WHS | 功耗 | 结论 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| **P4-D R2** | clean build + RTL + route + bit | **479** | **468** | **4** | **4 / 2.0** | 2 | +45.734/+0.121 ns | 0.271 W | 默认交付 |
| P4-C 低 DSP-A | 完整实现 | 504 | 494 | 3 | 4 / 2.0 | 2 | +45.853/+0.121 ns | 0.271 W | 当前资源更好的 3-DSP 版 |
| P1 TWO24 | clean build + RTL + route + bit | 518 | 498 | 3 | 4 / 2.0 | 2 | +45.933/+0.114 ns | 0.270 W | 新结构验证成功，未赢过 P4-C 3DSP |
| P4-E | 完整实现 | 491 | 487 | 4 | 3 / 1.5 | 2 | +46.132/+0.105 ns | 0.271 W | 1.5-Tile Pareto |
| **P2-A** | clean build + RTL + route + bit | **513** | **496** | **4** | **2 / 1.0** | 2 | +45.949/+0.117 ns | 0.270 W | 推荐 1-Tile Pareto |
| P2-B | clean build + RTL + route + bit | 516 | 516 | 4 | 2 / 1.0 | 2 | +45.764/+0.103 ns | 0.270 W | A/B 反例 |
| P4-F | 完整实现 | 531 | 487 | 4 | 2 / 1.0 | 2 | +45.898/+0.105 ns | 0.271 W | 被 P2-A 在 LUT 上明显改进 |
| P3 联合设计 | MATLAB 门禁 | 约450* | 约437* | 4* | 4 / 2.0* | 2* | 未实现 | 未实现 | *均为预测，不是实测 |

功耗均为 Vivado vectorless、Medium confidence；不能据 0.001 W 差异宣称实际省电。

## 9. Git 回退路线

| 用途 | 分支 | 标签 |
|---|---|---|
| 默认稳定 P4-D R2 | `codex/national-finals-p0-release-v2` | `nf-p4d-r2-479lut-468ff-4dsp-2bram-2mmcm-clean` |
| TWO24 3-DSP | `codex/national-finals-p1-two24-cic` | `nf-p1-two24-518lut-498ff-3dsp-2bram-2mmcm` |
| distributed ROM 1-Tile | `codex/national-finals-p2-coeff-distributed-rom` | `nf-p2-513lut-496ff-4dsp-1bram-2mmcm` |
| Stage3/均衡器 MATLAB 门禁 | `codex/national-finals-p3-joint-stage3-equalizer` | `nf-p3-matlab-gate-11tap-q15-18bit` |

本轮最终工作分支停留在 P4-D R2；实验分支不合并进默认 RTL，避免破坏 clean release 边界。
