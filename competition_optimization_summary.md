# FPGA 高阶插值滤波器竞赛优化总结

> 工程：`XC7A35T_interp_audio_pcm_wordlen_opt`  
> 仓库：`fir-interpolation-filter-fpga`  
> 目标平台：Artix-7 XC7A35T-FGG484-2  
> 工具版本：Vivado 2018.3  
> 竞赛题目：高阶数字插值滤波器设计与验证  
> 交付重点：FPGA 板级验证、资源/时序/功耗报告、工程优化说明、对照实验分析

---

## 1. 项目总体目标

本项目面向 FPGA 平台实现高阶数字插值滤波器系统。系统以音频 PCM 数据为输入，经过多级插值 FIR 结构后输出至 AD9708 8-bit DAC，并通过示波器进行板级验证。

系统支持两类音频采样率家族：

| 采样率家族 | 基础采样率 | 4× 输出 | 8× 输出 | 128× 输出 |
|---|---:|---:|---:|---:|
| 44.1 kHz 家族 | 44.1 kHz | 176.4 kHz | 352.8 kHz | 5.6448 MHz |
| 48 kHz 家族 | 48 kHz | 192 kHz | 384 kHz | 6.144 MHz |

最终主版本保留：

```text
44.1 kHz / 48 kHz 双采样率家族运行切换能力；
4× / 8× / 128× 三档 DAC 输出能力；
Stage 1 mode-aware FIR stage gating；
Stage 2 sample-family-aware MMCM reset gating；
Stage 3 工程清理后的最终 RTL 注释与接口。
```

同时，为了分析功耗瓶颈，额外建立两个单 MMCM 对照实验分支：

```text
exp/static-44k1-single-mmcm
exp/static-48k-single-mmcm
```

---

## 2. 已完成版本与分支关系

| 阶段 | 分支 / 版本 | 作用 | 是否作为最终主版本 |
|---|---|---|---|
| Baseline | `polyphase_mac2_ntaps29_nodsp_verified` | 已验证功能基线 | 作为对比基准 |
| Stage 0 | `clock_power_optimization_plan.md` | 制定时钟与功耗优化计划 | 文档保留 |
| Stage 1 | `exp/clock-power-optimization` | mode-aware 后级 FIR gating | 保留 |
| Stage 2 | `exp/clock-power-optimization` | 未使用采样率家族 Clock Wizard reset gating | 保留 |
| Stage 3 | `exp/clock-power-optimization` | 清理 debug 端口、旧注释、历史残留 | 保留 |
| Stage 2b | `exp/static-44k1-single-mmcm` | 44.1 kHz 单 MMCM 对照实验 | 不合并主版本 |
| Stage 2c | `exp/static-48k-single-mmcm` | 48 kHz 单 MMCM 对照实验 | 不合并主版本 |

最终推荐演示主版本：

```text
exp/clock-power-optimization
```

原因是该版本功能最完整，支持双采样率家族运行中切换。

---

## 3. 基线设计概况

最终 verified 基线已经完成：

- 4× 前级 polyphase FIR；
- 前级采用 2-lane MAC 结构；
- 后级 2× FIR 使用 29 tap；
- 后级 FIR 强制 no-DSP；
- 4× / 8× / 128× 三档 DAC 输出；
- 44.1 kHz / 48 kHz 两个采样率家族；
- 板级 DAC 波形验证通过。

基线资源与功耗约为：

| 指标 | 数值 |
|---|---:|
| LUT | 10197 |
| FF | 4640 |
| DSP | 2 |
| Total On-Chip Power | 0.272 W |
| WNS | 约 17 ns |

该版本已经具备完整功能，但从功耗报告看，主要功耗并不在 FIR 逻辑本身，而在双采样率家族对应的两个 Clock Wizard / MMCM 上。

---

## 4. Stage 1：Mode-aware 后级 FIR Gating

### 4.1 优化动机

原系统虽然支持 4× / 8× / 128× 三档输出，但低倍率模式下，后级插值链仍可能继续运行，造成无效翻转。例如：

```text
4× 模式下：
    实际只需要 4× 前级输出；
    8× / 16× / 32× / 64× / 128× 后级不需要参与输出。

8× 模式下：
    实际只需要 4× 前级 + 第一级 2×；
    16× / 32× / 64× / 128× 后级不需要参与输出。
```

因此，Stage 1 根据当前输出倍率关闭未使用的后级 FIR stage。

### 4.2 核心 RTL 思路

在 `interp128_top_ce.v` 中加入：

```verilog
input wire [1:0] mode_sel;
```

并根据 `mode_sel` 生成各级运行使能：

```verilog
wire mode_8x_selected   = (mode_sel == 2'b01);
wire mode_128x_selected =  mode_sel[1];

wire run_8x_stage   = mode_8x_selected | mode_128x_selected;
wire run_16x_stage  = mode_128x_selected;
wire run_32x_stage  = mode_128x_selected;
wire run_64x_stage  = mode_128x_selected;
wire run_128x_stage = mode_128x_selected;
```

对应策略：

| 模式 | 运行级数 | 关闭级数 |
|---|---|---|
| 4× | 4× 前级 | 全部 2× 后级 |
| 8× | 4× 前级 + 第一级 2× | 16× / 32× / 64× / 128× |
| 128× | 全部级数 | 无 |

### 4.3 Stage 1 结果

板级验证结果正常：

| sw2 | 采样率家族 | 4× | 8× | 128× |
|---|---|---:|---:|---:|
| 0 | 44.1 kHz | 176.4 kHz | 352.68 kHz | 5.64 MHz |
| 1 | 48 kHz | 192.01 kHz | 384.02 kHz | 6.14 MHz |

实现报告：

| 指标 | Stage 1 |
|---|---:|
| LUT | 10204 |
| FF | 4641 |
| DSP | 2 |
| Total On-Chip Power | 0.272 W |
| WNS | 16.978 ns |

### 4.4 Stage 1 评价

Stage 1 功能正确、资源变化极小、时序通过。Vivado 默认功耗报告未明显体现 FIR gating 收益，主要原因是系统总功耗被 MMCM 主导，FIR 逻辑在默认报告中的功耗占比较小。

Stage 1 可以作为：

```text
mode-aware computation gating
```

写入竞赛优化说明。

---

## 5. Stage 2：Sample-family-aware MMCM Reset Gating

### 5.1 优化动机

系统支持 44.1 kHz 和 48 kHz 两个采样率家族，原设计同时实例化两个 Clock Wizard：

```text
u_clk_wiz_audio_44k1
u_clk_wiz_audio_48k
```

但任意时刻只需要使用其中一个采样率家族。因此 Stage 2 尝试根据 `sw2` 选择当前采样率家族，并将未使用的 Clock Wizard 置于 reset 状态。

### 5.2 核心 RTL 思路

先对 `sw2` 做 50 MHz 系统时钟域同步：

```verilog
reg sw2_meta = 1'b0;
reg sw2_sync = 1'b0;

always @(posedge clk_sys_bufg) begin
    sw2_meta <= sw2_ibuf;
    sw2_sync <= sw2_meta;
end

wire use_48k = sw2_sync;
```

根据当前采样率家族控制两个 Clock Wizard reset：

```verilog
assign rst_mmcm_48k  = (~rst_n_int) | (~use_48k);
assign rst_mmcm_44k1 = (~rst_n_int) | use_48k;
```

当前选中 MMCM 的 locked 信号用于释放音频域复位：

```verilog
assign mmcm_locked_sel = use_48k ? mmcm_locked_48k : mmcm_locked_44k1;
assign rst_audio_async_n = rst_n_int & mmcm_locked_sel;
```

### 5.3 Stage 2 结果

板级验证通过，且支持 `sw2` 运行中切换。

| sw2 | 采样率家族 | 4× | 8× | 128× |
|---|---|---:|---:|---:|
| 0 | 44.1 kHz | 176.3 kHz | 352.61 kHz | 5.65 MHz |
| 1 | 48 kHz | 192.01 kHz | 384.02 kHz | 6.15 MHz |

实现报告：

| 指标 | Stage 2 |
|---|---:|
| LUT | 10203 |
| FF | 4607 |
| DSP | 2 |
| MMCM | 2 |
| Total On-Chip Power | 0.272 W |
| Dynamic Power | 0.200 W |
| MMCM Power | 0.198 W |
| WNS | 16.978 ns |

### 5.4 Stage 2 评价

Stage 2 的功能和时序都是成功的，但默认功耗报告没有下降。原因是：

```text
Stage 2 仍然实例化两个 MMCM；
Vivado 默认 report_power 没有导入具体 sw2 模式下的活动文件；
工具对“已实例化但被 reset 的 MMCM”不一定按低功耗状态估算。
```

因此，Stage 2 应保守表述为：

```text
系统级时钟管理与低功耗结构探索。
```

不应写成：

```text
Vivado 报告证明功耗显著降低。
```

---

## 6. Stage 3：工程清理与最终 RTL 注释整理

### 6.1 清理内容

Stage 3 主要做工程交付清理，不改变核心算法：

1. 移除未使用的 `dbg_y32 / dbg_y64` 外部调试端口；
2. 保留 `dbg_y4 / dbg_y8`，用于 4× / 8× DAC 输出；
3. 清理旧的 DAC 显示补偿注释；
4. 将旧的 11 tap 注释更新为最终 29 tap 后级 FIR；
5. 清理过程性注释，使代码更适合竞赛提交。

### 6.2 Stage 3 结果

Stage 3 综合、实现、bitstream 生成通过，板级验证与 Stage 2 一致：

```text
44.1 kHz / 48 kHz 两个采样率家族均正常；
4× / 8× / 128× 三档输出均正常；
sw2 运行中切换仍正常。
```

Stage 3 是最终主分支中建议保留的工程清理版本。

---

## 7. Stage 2b：静态 44.1 kHz 单 MMCM 对照实验

### 7.1 实验目的

Stage 2b 只保留：

```text
u_clk_wiz_audio_44k1
```

删除：

```text
u_clk_wiz_audio_48k
```

该版本固定为 44.1 kHz 家族，不再支持 `sw2` 切换。目的不是替代最终主版本，而是验证：

```text
如果真正删除一个 MMCM，Vivado 默认功耗报告是否会下降。
```

### 7.2 板级验证结果

| 模式 | 理论值 | 实测值 |
|---|---:|---:|
| 4× | 176.4 kHz | 176.43 kHz |
| 8× | 352.8 kHz | 352.68 kHz |
| 128× | 5.6448 MHz | 5.64 MHz |

### 7.3 报告结果

| 指标 | Stage 2b static44k |
|---|---:|
| LUT | 9489 |
| FF | 4604 |
| DSP | 2 |
| MMCM | 1 |
| Total On-Chip Power | 0.168 W |
| Dynamic Power | 0.097 W |
| MMCM Power | 0.095 W |
| WNS | 17.305 ns |

### 7.4 评价

Stage 2b 证明，删除 48 kHz Clock Wizard 后，默认功耗报告明显下降。该版本适合作为 44.1 kHz 固定采样率应用下的低功耗对照版本。

---

## 8. Stage 2c：静态 48 kHz 单 MMCM 对照实验

### 8.1 实验目的

Stage 2c 只保留：

```text
u_clk_wiz_audio_48k
```

删除：

```text
u_clk_wiz_audio_44k1
```

该版本固定为 48 kHz 家族，不再支持 `sw2` 切换。它与 Stage 2b 共同构成完整的单 MMCM 对照实验。

### 8.2 板级验证结果

| 模式 | 理论值 | 实测值 |
|---|---:|---:|
| 4× | 192 kHz | 192.01 kHz |
| 8× | 384 kHz | 384.02 kHz |
| 128× | 6.144 MHz | 6.14 MHz |

`sw2 = 0` 或 `sw2 = 1` 时输出都保持为 48 kHz 家族，符合静态探索版本预期。

### 8.3 报告结果

| 指标 | Stage 2c static48k |
|---|---:|
| LUT | 9489 |
| FF | 4604 |
| DSP | 2 |
| MMCM | 1 |
| Total On-Chip Power | 0.177 W |
| Dynamic Power | 0.105 W |
| MMCM Power | 0.103 W |
| WNS | 17.305 ns |

### 8.4 评价

48 kHz 单 MMCM 版本功耗略高于 44.1 kHz 单 MMCM 版本，这是合理的，因为 48 kHz 家族的 128× 时钟为 6.144 MHz，高于 44.1 kHz 家族的 5.6448 MHz。

---

## 9. 关键对照结果

### 9.1 主版本与单 MMCM 对照版本

| 版本 | 采样率家族 | MMCM | Total Power | Dynamic | MMCM Power | 作用 |
|---|---|---:|---:|---:|---:|---|
| Stage 2 / Stage 3 主版本 | 44.1k + 48k，可运行中切换 | 2 | 0.272 W | 0.200 W | 0.198 W | 最终演示主版本 |
| Stage 2b static44k | 仅 44.1k | 1 | 0.168 W | 0.097 W | 0.095 W | 对照实验 |
| Stage 2c static48k | 仅 48k | 1 | 0.177 W | 0.105 W | 0.103 W | 对照实验 |

最关键的关系是：

```text
0.095 W + 0.103 W = 0.198 W
```

这正好对应双 MMCM 主版本中的 MMCM 总功耗。

因此可以得出结论：

```text
双采样率家族中的两个 MMCM 是 Vivado 默认功耗报告中的主要动态功耗来源。
```

### 9.2 功能与功耗取舍

| 结构 | 优点 | 缺点 |
|---|---|---|
| 双 MMCM 主版本 | 支持 44.1k / 48k 运行中切换，功能完整 | 默认功耗较高 |
| 单 MMCM 静态版本 | 功耗明显更低，结构更简单 | 只能支持单一采样率家族 |

最终竞赛主版本选择双 MMCM，是为了保证功能完整性和现场演示灵活性。单 MMCM 版本作为对照实验，用于说明低功耗结构潜力和功耗瓶颈来源。

---

## 10. 最终竞赛报告推荐表述

可以在竞赛报告中写：

```text
在完成插值滤波器功能验证后，进一步开展了时钟与功耗优化探索。首先在低倍率输出模式下关闭未使用的后级 2× FIR，形成 mode-aware computation gating；随后针对 44.1 kHz / 48 kHz 双采样率家族结构，加入 sample-family-aware MMCM reset gating，使未使用采样率家族的 Clock Wizard 进入 reset 状态。板级验证表明，系统支持 4×、8×、128× 三档输出，并可在 44.1 kHz 与 48 kHz 家族之间运行中切换。

Vivado 默认功耗报告显示双 MMCM 主版本总功耗为 0.272 W，其中 MMCM 功耗为 0.198 W。为进一步验证功耗来源，构建了两个静态单 MMCM 对照版本：44.1 kHz 单 MMCM 版本总功耗为 0.168 W，MMCM 功耗为 0.095 W；48 kHz 单 MMCM 版本总功耗为 0.177 W，MMCM 功耗为 0.103 W。两个单 MMCM 版本的 MMCM 功耗之和正好对应双 MMCM 主版本中的 MMCM 功耗，说明双采样率家族时钟源是默认功耗报告中的主要动态功耗来源。最终演示主版本保留双 MMCM 结构以支持双采样率运行切换，而单 MMCM 版本作为低功耗结构对照实验保留。
```

---

## 11. 后续不建议继续做的大改

目前项目已经形成完整优化闭环：

```text
算法结构优化；
字长与资源映射优化；
低倍率模式 gating；
采样率家族时钟 reset gating；
单 MMCM 对照实验；
工程清理与报告归档。
```

不建议继续在最终主分支上做高风险修改，例如：

- 单 MMCM + DRP 动态重配置；
- 手动重写 Clock Wizard；
- 修改全局时钟拓扑；
- 大规模改 reset 架构。

这些可以作为后续展望，不建议替换当前已验证主版本。

---

## 12. 建议最终保留内容

建议仓库中保留：

```text
docs/
├── clock_power_optimization_plan.md
├── stage2_evaluation.md
├── stage2b_static_single_mmcm_evaluation.md
├── stage2c_static48k_single_mmcm_evaluation.md
└── competition_optimization_summary.md
```

建议报告目录保留：

```text
reports_baseline/
reports_stage1_mode_gating/
reports_stage2_mmcm_reset_gating/
reports_stage3_clean/
reports_static44k_single_mmcm/
reports_static48k_single_mmcm/
```

建议分支保留：

```text
exp/clock-power-optimization
exp/static-44k1-single-mmcm
exp/static-48k-single-mmcm
```

---

## 13. 最终结论

本项目已经从功能实现、资源优化、时钟管理和功耗对照实验四个层面形成完整闭环。

最终主版本实现了：

```text
44.1 kHz / 48 kHz 双采样率家族；
4× / 8× / 128× 三档插值输出；
mode-aware 后级 FIR gating；
sample-family-aware MMCM reset gating；
板级 DAC 波形验证；
Vivado 资源、时序、功耗报告归档。
```

单 MMCM 对照实验进一步证明：

```text
双采样率家族时钟源是当前默认功耗报告中的主要动态功耗来源；
单采样率应用可以通过删除未使用 Clock Wizard 显著降低功耗；
但最终竞赛演示主版本需要保留双 MMCM，以保证功能完整性和运行切换能力。
```

因此，本项目不仅完成了高阶插值 FIR 的 FPGA 实现与板级验证，也展示了从算法结构、RTL gating、时钟源管理到功耗对照实验的多层级工程优化能力。
