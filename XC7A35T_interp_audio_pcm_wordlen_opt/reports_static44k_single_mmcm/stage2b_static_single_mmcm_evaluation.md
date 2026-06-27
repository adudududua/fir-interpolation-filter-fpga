# Stage 2b 评估报告：静态 44.1 kHz 单 MMCM 对照探索

> 工程：`XC7A35T_interp_audio_pcm_wordlen_opt`  
> 探索分支：`exp/static-44k1-single-mmcm`  
> 阶段：Stage 2b  
> 优化名称：`static 44.1 kHz single-MMCM exploration`  
> 基础版本：Stage 3 清理版 / Stage 2 双 MMCM reset gating 主版本  
> 目标平台：Artix-7 XC7A35T-FGG484-2  
> 工具版本：Vivado 2018.3  
> 板级验证方式：AD9708 8-bit DAC + 示波器  
> 定位：低功耗结构对照实验，不作为最终双采样率演示主版本

---

## 1. 本阶段为什么要做

在 Stage 2 主版本中，系统已经实现了 **sample-family-aware MMCM reset gating**：

```text
sw2 = 0：
    使用 44.1 kHz 家族 Clock Wizard；
    48 kHz 家族 Clock Wizard 保持 reset。

sw2 = 1：
    使用 48 kHz 家族 Clock Wizard；
    44.1 kHz 家族 Clock Wizard 保持 reset。
```

Stage 2 主版本的板级功能已经通过，支持运行中切换 `sw2`，并且 44.1 kHz / 48 kHz 两个采样率家族下 4× / 8× / 128× 三档输出均正常。

但是 Stage 2 的 Vivado 默认功耗报告中，总功耗仍为：

```text
Total On-Chip Power = 0.272 W
Dynamic Power       = 0.200 W
MMCM Power          = 0.198 W
```

其中两个 Clock Wizard / MMCM 的层级功耗约为：

```text
u_clk_wiz_audio_44k1 = 0.095 W
u_clk_wiz_audio_48k  = 0.103 W
```

也就是说，Stage 2 虽然从 RTL 结构上让未使用 Clock Wizard 进入 reset，但 Vivado 默认 `report_power` 并没有体现出功耗下降。

因此，Stage 2b 的目的不是继续修改 FIR 插值算法，而是做一个更直接的结构对照实验：

```text
如果真正删除一个采样率家族的 Clock Wizard，只保留一个 MMCM，
Vivado 默认功耗报告是否会明显下降？
```

这个实验可以回答两个问题：

1. 当前默认功耗报告中的主要功耗是否确实来自两个 MMCM；
2. Stage 2 reset gating 功耗未下降，是不是因为工具没有量化 reset gating 的活动差异，而不是优化方向判断错误。

---

## 2. 本阶段做了什么改动

Stage 2b 只修改顶层文件：

```text
XC7A35T_interp_audio_pcm_wordlen_opt/
└── XC7A35T_interp.srcs/
    └── sources_1/
        └── new/
            └── board_demo_competition_dac8_top.v
```

核心改动是将双采样率家族时钟结构改成 **静态 44.1 kHz 单 MMCM 结构**。

### 2.1 保留的部分

保留：

```text
u_clk_wiz_audio_44k1
```

也就是：

```text
50 MHz 系统时钟
    ↓
clk_wiz_audio_44k1
    ↓
5.6448 MHz 128× 音频时钟
    ↓
插值链 + DAC 输出
```

### 2.2 删除的部分

删除 / 不再实例化：

```text
u_clk_wiz_audio_48k
```

同时不再需要双时钟选择结构：

```text
BUFGMUX 双时钟选择
sw2 采样率家族切换逻辑
48 kHz 家族 locked 选择逻辑
```

### 2.3 `sw2` 的处理

为了兼容原来的 XDC 顶层端口约束，`sw2` 端口仍然保留，但在该静态探索版本中不参与功能逻辑。

因此，本版本固定为：

```text
44.1 kHz 家族
```

`sw2` 如何拨动都不应改变输出频率。

### 2.4 没有改动的部分

Stage 2b 没有修改：

- FIR 系数；
- FIR tap 数；
- 4× polyphase MAC2 前级；
- 后级 2× FIR；
- Stage 1 mode-aware FIR gating；
- DAC 输出选择；
- DAC 8-bit 显示策略；
- ROM 示例音频数据。

因此，Stage 2b 的变量主要集中在：

```text
时钟源数量：双 MMCM → 单 MMCM
```

---

## 3. 板级验证结果

本版本固定为 44.1 kHz 家族，因此理论输出频率为：

| 模式 | 理论频率 |
|---|---:|
| 4× | 176.4 kHz |
| 8× | 352.8 kHz |
| 128× | 5.6448 MHz |

板级实测结果为：

| 模式 | 理论值 | 实测值 | 结果 |
|---|---:|---:|---|
| 4× | 176.4 kHz | 176.43 kHz | 正常 |
| 8× | 352.8 kHz | 352.68 kHz | 正常 |
| 128× | 5.6448 MHz | 5.64 MHz | 正常 |

实测频率与理论频率基本一致，说明删除 48 kHz 家族 Clock Wizard 后，44.1 kHz 家族的 4× / 8× / 128× 插值输出仍然正常。

该结果说明：

```text
单 MMCM 静态 44.1 kHz 结构功能正确；
删除 48 kHz 家族 Clock Wizard 没有破坏 44.1 kHz 插值链。
```

---

## 4. 资源利用率结果

Vivado implementation 后导出的 `utilization_static44k_single_mmcm.txt` 显示：

| 资源 | 使用量 | 可用量 | 利用率 |
|---|---:|---:|---:|
| Slice LUTs | 9489 | 20800 | 45.62% |
| LUT as Logic | 9369 | 20800 | 45.04% |
| LUT as Shift Register | 120 | 9600 | 1.25% |
| Slice Registers | 4604 | 41600 | 11.07% |
| DSP48E1 | 2 | 90 | 2.22% |
| Bonded IOB | 12 | 250 | 4.80% |
| BUFGCTRL | 2 | 32 | 6.25% |
| MMCME2_ADV | 1 | 5 | 20.00% |

### 4.1 Clocking 资源变化

Stage 2 主版本中：

```text
MMCME2_ADV = 2
```

Stage 2b 静态 44.1 kHz 单 MMCM 版本中：

```text
MMCME2_ADV = 1
```

这说明 48 kHz 家族 Clock Wizard 已经被真正移除，不再只是 reset。

### 4.2 Instantiated Netlists 结果

Stage 2b 的 instantiated netlists 中只剩：

```text
clk_wiz_audio_44k1 = 1
```

不再出现：

```text
clk_wiz_audio_48k
```

这进一步说明该版本已经从结构上删除了 48 kHz 家族 Clock Wizard。

### 4.3 与 Stage 2 主版本资源对比

| 版本 | LUT | FF | DSP | MMCM | 说明 |
|---|---:|---:|---:|---:|---|
| Stage 2 双 MMCM reset gating | 10203 | 4607 | 2 | 2 | 支持 44.1k / 48k 运行中切换 |
| Stage 2b 静态 44.1k 单 MMCM | 9489 | 4604 | 2 | 1 | 仅支持 44.1k 家族 |

资源变化：

| 指标 | 变化 |
|---|---:|
| LUT | -714 |
| FF | -3 |
| DSP | 0 |
| MMCM | -1 |

其中 DSP 不变，说明 FIR 核心计算结构没有被破坏。LUT 下降主要来自顶层时钟选择逻辑、双采样率相关控制逻辑以及 48 kHz Clock Wizard 相关路径被删除后的综合优化。

---

## 5. 时序结果

Vivado `timing_static44k_single_mmcm.txt` 显示：

| 指标 | 数值 |
|---|---:|
| WNS | 17.305 ns |
| TNS | 0.000 ns |
| WHS | 0.043 ns |
| THS | 0.000 ns |
| 结论 | All user specified timing constraints are met |

分时钟域结果：

| 时钟域 | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|
| clk_50M | 17.305 ns | 0 | 0.259 ns | 0 |
| clk_audio_128x_44k1 | 74.111 ns | 0 | 0.043 ns | 0 |

### 5.1 时钟数量变化

Stage 2b 的 clock summary 中只剩：

```text
clk_50M
clk_audio_128x_44k1
clkfb_44k1
```

已经没有：

```text
clk_audio_128x_48k
clkfb_48k
```

这说明静态 44.1 kHz 版本的时钟结构更加简单，时序分析也只需要覆盖 44.1 kHz 家族。

### 5.2 时序结论

Stage 2b 满足所有用户时序约束，并且 WNS = 17.305 ns，说明删除 48 kHz Clock Wizard 后不会对现有 44.1 kHz 插值链造成时序压力。

---

## 6. 功耗结果

Vivado `power_static44k_single_mmcm.txt` 显示：

| 项目 | 数值 |
|---|---:|
| Total On-Chip Power | 0.168 W |
| Dynamic Power | 0.097 W |
| Device Static Power | 0.072 W |
| MMCM Power | 0.095 W |
| u_clk_wiz_audio_44k1 | 0.095 W |

### 6.1 与 Stage 2 双 MMCM 主版本对比

| 指标 | Stage 2 双 MMCM | Stage 2b 单 MMCM | 变化 |
|---|---:|---:|---:|
| Total On-Chip Power | 0.272 W | 0.168 W | -0.104 W |
| Dynamic Power | 0.200 W | 0.097 W | -0.103 W |
| Static Power | 0.072 W | 0.072 W | 0 W |
| MMCM Power | 0.198 W | 0.095 W | -0.103 W |

可以看到：

```text
总功耗下降 0.104 W；
动态功耗下降 0.103 W；
MMCM 功耗下降 0.103 W。
```

三者高度一致，说明功耗下降几乎全部来自移除一个 MMCM。

### 6.2 功耗比例变化

Stage 2 主版本中，MMCM 功耗为：

```text
MMCM Power = 0.198 W
```

Stage 2b 中，MMCM 功耗为：

```text
MMCM Power = 0.095 W
```

下降幅度约为：

```text
(0.198 - 0.095) / 0.198 ≈ 52.0%
```

总功耗下降幅度约为：

```text
(0.272 - 0.168) / 0.272 ≈ 38.2%
```

动态功耗下降幅度约为：

```text
(0.200 - 0.097) / 0.200 ≈ 51.5%
```

该结果说明，当前系统在默认 Vivado 功耗报告中，动态功耗主要由 MMCM 贡献。

---

## 7. 为什么 Stage 2b 功耗下降，而 Stage 2 没有下降

这是本阶段最重要的分析点。

### 7.1 Stage 2 的情况

Stage 2 主版本中：

```text
两个 MMCM 都实例化；
通过 sw2 选择当前使用的采样率家族；
未选中的 Clock Wizard 被 reset。
```

从 RTL 功能角度看，这是合理的低功耗时钟结构探索。

但是 Vivado 默认 `report_power` 没有导入分模式仿真活动文件，因此工具仍然把两个已实例化的 MMCM 都计入功耗模型。结果是：

```text
Stage 2 report_power 中仍然显示：
Total On-Chip Power = 0.272 W
MMCM Power          = 0.198 W
```

### 7.2 Stage 2b 的情况

Stage 2b 中：

```text
只实例化一个 MMCM；
48 kHz 家族 Clock Wizard 被彻底删除；
Vivado 资源报告中 MMCME2_ADV 从 2 变为 1。
```

因此默认功耗报告能够直接反映结构变化：

```text
Total On-Chip Power = 0.168 W
MMCM Power          = 0.095 W
```

### 7.3 结论

Stage 2 和 Stage 2b 的差异说明：

```text
Vivado 默认功耗报告对“已实例化但被 reset 的 MMCM”不敏感；
但对“直接删除一个 MMCM”的结构变化非常敏感。
```

因此，Stage 2 功耗未下降并不代表“时钟源是功耗瓶颈”的判断错误。Stage 2b 的结果反而验证了：

```text
双采样率家族中的两个 MMCM 是当前默认功耗报告中的主要动态功耗来源。
```

---

## 8. 这一版优化的价值

### 8.1 工程价值

Stage 2b 的工程价值在于提供了一个清晰的结构对照：

| 结构 | 功能 | 功耗 |
|---|---|---|
| 双 MMCM | 支持 44.1k / 48k 运行中切换 | 较高 |
| 单 MMCM | 固定单采样率家族 | 明显更低 |

这说明在实际系统设计中，功能灵活性和功耗之间存在取舍：

```text
如果需要同时支持 44.1 kHz / 48 kHz 并运行中切换，需要保留双 MMCM；
如果只面向固定采样率应用，单 MMCM 结构更省资源和功耗。
```

### 8.2 竞赛展示价值

Stage 2b 可以作为竞赛答辩中的对照实验，展示设计者不仅完成了功能验证，还进一步分析了功耗来源，并用结构实验验证判断。

推荐表达：

```text
为了验证功耗瓶颈来源，构建了静态 44.1 kHz 单 MMCM 对照版本。该版本移除 48 kHz 家族 Clock Wizard，仅保留 44.1 kHz 家族时钟源。实现结果显示，MMCME2_ADV 由 2 个降为 1 个，总功耗由 0.272 W 降至 0.168 W，动态功耗由 0.200 W 降至 0.097 W，MMCM 功耗由 0.198 W 降至 0.095 W。该结果表明，双采样率家族中的两个 MMCM 是默认功耗报告中的主要动态功耗来源。
```

同时也应该说明：

```text
考虑到最终竞赛演示需要支持 44.1 kHz / 48 kHz 两个采样率家族运行中切换，最终主版本仍保留双 MMCM 结构；单 MMCM 版本作为低功耗结构对照实验。
```

---

## 9. 局限性

Stage 2b 不能直接替代最终主版本，原因是：

1. **不支持 48 kHz 家族**  
   该版本只保留 44.1 kHz 家族，不能输出 192 kHz / 384 kHz / 6.144 MHz。

2. **不支持 `sw2` 运行中切换**  
   `sw2` 在该版本中只保留端口，不参与功能逻辑。

3. **牺牲了系统灵活性**  
   单 MMCM 版本功耗更低，但功能覆盖范围比双 MMCM 主版本小。

4. **默认功耗报告仍不是实测板级功耗**  
   Vivado `report_power` 结果用于综合实现后的估计和版本对比，不等价于板上实际电源功耗。

因此，Stage 2b 应定位为：

```text
低功耗结构对照实验版本
```

而不是最终竞赛演示主版本。

---

## 10. 是否建议继续做 static48k 单 MMCM 版本

建议继续做 `static48k_single_mmcm` 版本。理由是：

1. 当前只验证了 44.1 kHz 单 MMCM；
2. 如果再验证 48 kHz 单 MMCM，就能形成完整对照；
3. 可以进一步确认 48 kHz 家族单独运行时的功耗约为 0.103 W MMCM；
4. 竞赛报告中的功耗结构分析会更完整。

建议下一阶段命名为：

```text
Stage 2c: static 48 kHz single-MMCM exploration
```

预期功能：

| 模式 | 理论频率 |
|---|---:|
| 4× | 192 kHz |
| 8× | 384 kHz |
| 128× | 6.144 MHz |

预期报告：

```text
MMCME2_ADV = 1
Total On-Chip Power 接近 0.17 W
MMCM Power 接近 0.103 W
```

---

## 11. 建议 Commit 信息

如果需要提交当前 Stage 2b 探索版本，建议 commit：

```text
Add static 44k1 single-MMCM exploration
```

详细描述：

```text
Add static 44k1 single-MMCM exploration

- Remove 48 kHz Clock Wizard from the top-level design
- Keep only clk_wiz_audio_44k1 as the 128x audio clock source
- Replace dual-clock BUFGMUX selection with a single BUFG path
- Keep sw2 port only for XDC compatibility
- Verify 4x, 8x and 128x DAC outputs in the 44.1 kHz family
- Export utilization, timing and power reports for single-MMCM comparison
```

---

## 12. 最终结论

Stage 2b 的最终结论如下：

```text
Stage 2b 构建了静态 44.1 kHz 单 MMCM 对照版本，仅保留 clk_wiz_audio_44k1，删除 48 kHz 采样率家族 Clock Wizard。板级验证表明，该版本在 4×、8×、128× 三档下分别输出 176.43 kHz、352.68 kHz 和 5.64 MHz，功能正常。实现结果显示，MMCME2_ADV 从 Stage 2 主版本的 2 个降为 1 个，总功耗由 0.272 W 降至 0.168 W，动态功耗由 0.200 W 降至 0.097 W，MMCM 功耗由 0.198 W 降至 0.095 W。该结果证明双采样率家族中的两个 MMCM 是 Vivado 默认功耗报告中的主要动态功耗来源。由于该版本不支持 48 kHz 家族和 sw2 运行中切换，因此不作为最终竞赛演示主版本，而作为低功耗结构对照实验版本保留。
```
