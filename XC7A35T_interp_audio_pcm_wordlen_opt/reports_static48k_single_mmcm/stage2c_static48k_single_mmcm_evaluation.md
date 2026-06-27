# Stage 2c 评估报告：静态 48 kHz 单 MMCM 对照探索

> 工程：`XC7A35T_interp_audio_pcm_wordlen_opt`  
> 探索分支：`exp/static-48k-single-mmcm`  
> 阶段：Stage 2c  
> 优化名称：`static 48 kHz single-MMCM exploration`  
> 基础版本：Stage 3 清理版 / Stage 2 双 MMCM reset gating 主版本  
> 目标平台：Artix-7 XC7A35T-FGG484-2  
> 工具版本：Vivado 2018.3  
> 板级验证方式：AD9708 8-bit DAC + 示波器  
> 定位：低功耗结构对照实验，不作为最终双采样率演示主版本

---

## 1. 本阶段为什么要做

Stage 2b 已经完成了静态 44.1 kHz 单 MMCM 对照实验，证明当系统只保留 `clk_wiz_audio_44k1` 时，Vivado 默认功耗报告会明显下降。

Stage 2c 进一步构建静态 48 kHz 单 MMCM 对照版本，目的是补全单采样率家族对照实验：

```text
Stage 2b：只保留 44.1 kHz 家族 Clock Wizard
Stage 2c：只保留 48 kHz 家族 Clock Wizard
```

这样可以更完整地说明：

1. 双采样率家族主版本的两个 MMCM 是默认功耗报告中的主要动态功耗来源；
2. 若系统只面向固定采样率应用，单 MMCM 结构可以明显降低默认功耗报告；
3. 44.1 kHz 与 48 kHz 两个单 MMCM 版本均可独立正常运行。

---

## 2. 本阶段做了什么改动

Stage 2c 只修改顶层文件：

```text
XC7A35T_interp_audio_pcm_wordlen_opt/
└── XC7A35T_interp.srcs/
    └── sources_1/
        └── new/
            └── board_demo_competition_dac8_top.v
```

核心改动是将双采样率家族时钟结构改成 **静态 48 kHz 单 MMCM 结构**。

### 2.1 保留的部分

保留：

```text
u_clk_wiz_audio_48k
```

对应时钟路径为：

```text
50 MHz 系统时钟
    ↓
clk_wiz_audio_48k
    ↓
6.144 MHz 128× 音频时钟
    ↓
插值链 + DAC 输出
```

### 2.2 删除的部分

删除 / 不再实例化：

```text
u_clk_wiz_audio_44k1
```

同时不再需要：

```text
BUFGMUX 双时钟选择
sw2 采样率家族切换逻辑
44.1 kHz 家族 locked 选择逻辑
```

### 2.3 `sw2` 的处理

为了兼容原来的 XDC 顶层端口约束，`sw2` 端口仍然保留，但在该静态探索版本中不参与功能逻辑。

因此，本版本固定为：

```text
48 kHz 家族
```

`sw2 = 0` 或 `sw2 = 1` 时，输出都应保持为 48 kHz 家族对应频率。

### 2.4 没有改动的部分

Stage 2c 没有修改：

- FIR 系数；
- FIR tap 数；
- 4× polyphase MAC2 前级；
- 后级 2× FIR；
- Stage 1 mode-aware FIR gating；
- DAC 输出选择；
- DAC 8-bit 显示策略；
- ROM 示例音频数据。

因此，该实验的主要变量是：

```text
时钟源数量：双 MMCM → 单 MMCM
固定采样率家族：48 kHz
```

---

## 3. 板级验证结果

本版本固定为 48 kHz 家族，因此理论输出频率为：

| 模式 | 理论频率 |
|---|---:|
| 4× | 192 kHz |
| 8× | 384 kHz |
| 128× | 6.144 MHz |

板级实测结果为：

| 模式 | 理论值 | 实测值 | 结果 |
|---|---:|---:|---|
| 4× | 192 kHz | 192.01 kHz | 正常 |
| 8× | 384 kHz | 384.02 kHz | 正常 |
| 128× | 6.144 MHz | 6.14 MHz | 正常 |

同时用户实测表明：

```text
sw2 = 0 或 sw2 = 1 时，输出均保持为 48 kHz 家族。
```

这符合本静态探索版本的设计预期，因为 `sw2` 在该版本中不参与功能逻辑。

---

## 4. 资源利用率结果

Vivado implementation 后导出的 `utilization_static48k_single_mmcm.txt` 显示：

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

Stage 2c 静态 48 kHz 单 MMCM 版本中：

```text
MMCME2_ADV = 1
```

这说明 44.1 kHz 家族 Clock Wizard 已经被真正移除，不再只是 reset。

### 4.2 Instantiated Netlists 结果

Stage 2c 的 instantiated netlists 中只剩：

```text
clk_wiz_audio_48k = 1
```

不再出现：

```text
clk_wiz_audio_44k1
```

这说明该版本已经从结构上删除了 44.1 kHz 家族 Clock Wizard。

### 4.3 与 Stage 2 主版本资源对比

| 版本 | LUT | FF | DSP | MMCM | 说明 |
|---|---:|---:|---:|---:|---|
| Stage 2 双 MMCM reset gating | 10203 | 4607 | 2 | 2 | 支持 44.1k / 48k 运行中切换 |
| Stage 2c 静态 48k 单 MMCM | 9489 | 4604 | 2 | 1 | 仅支持 48k 家族 |

资源变化：

| 指标 | 变化 |
|---|---:|
| LUT | -714 |
| FF | -3 |
| DSP | 0 |
| MMCM | -1 |

DSP 不变，说明核心 FIR 计算结构没有被破坏。LUT 下降主要来自顶层双时钟选择逻辑、双采样率控制逻辑以及 44.1 kHz Clock Wizard 相关路径被删除后的综合优化。

---

## 5. 时序结果

Vivado `timing_static48k_single_mmcm.txt` 显示：

| 指标 | 数值 |
|---|---:|
| WNS | 17.305 ns |
| TNS | 0.000 ns |
| WHS | 0.039 ns |
| THS | 0.000 ns |
| 结论 | All user specified timing constraints are met |

分时钟域结果：

| 时钟域 | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|
| clk_50M | 17.305 ns | 0 | 0.259 ns | 0 |
| clk_audio_128x_48k | 67.594 ns | 0 | 0.039 ns | 0 |

### 5.1 时钟数量变化

Stage 2c 的 clock summary 中只剩：

```text
clk_50M
clk_audio_128x_48k
clkfb_48k
```

已经没有：

```text
clk_audio_128x_44k1
clkfb_44k1
```

这说明静态 48 kHz 版本的时钟结构更加简单，时序分析只覆盖 48 kHz 家族。

### 5.2 时序结论

Stage 2c 满足所有用户时序约束，并且 WNS = 17.305 ns。删除 44.1 kHz Clock Wizard 后，不会对 48 kHz 插值链造成时序压力。

---

## 6. 功耗结果

Vivado `power_static48k_single_mmcm.txt` 显示：

| 项目 | 数值 |
|---|---:|
| Total On-Chip Power | 0.177 W |
| Dynamic Power | 0.105 W |
| Device Static Power | 0.072 W |
| MMCM Power | 0.103 W |
| u_clk_wiz_audio_48k | 0.103 W |

### 6.1 与 Stage 2 双 MMCM 主版本对比

| 指标 | Stage 2 双 MMCM | Stage 2c 单 MMCM | 变化 |
|---|---:|---:|---:|
| Total On-Chip Power | 0.272 W | 0.177 W | -0.095 W |
| Dynamic Power | 0.200 W | 0.105 W | -0.095 W |
| Static Power | 0.072 W | 0.072 W | 0 W |
| MMCM Power | 0.198 W | 0.103 W | -0.095 W |

可以看到：

```text
总功耗下降 0.095 W；
动态功耗下降 0.095 W；
MMCM 功耗下降 0.095 W。
```

这说明功耗下降基本全部来自移除 44.1 kHz 家族 MMCM。

### 6.2 与 Stage 2b 静态 44.1 kHz 单 MMCM 对比

| 指标 | Stage 2b 44.1k 单 MMCM | Stage 2c 48k 单 MMCM |
|---|---:|---:|
| Total On-Chip Power | 0.168 W | 0.177 W |
| Dynamic Power | 0.097 W | 0.105 W |
| MMCM Power | 0.095 W | 0.103 W |
| MMCME2_ADV | 1 | 1 |

48 kHz 单 MMCM 版本的功耗略高于 44.1 kHz 单 MMCM 版本，主要原因是 48 kHz 家族的 128× 时钟频率为 6.144 MHz，高于 44.1 kHz 家族的 5.6448 MHz，因此对应 MMCM 默认功耗估计略高。

---

## 7. 为什么 Stage 2b / Stage 2c 能证明功耗瓶颈

Stage 2 主版本：

```text
同时实例化 44.1 kHz 与 48 kHz 两个 Clock Wizard；
支持 sw2 运行中切换；
Vivado 默认功耗报告中 MMCM Power = 0.198 W。
```

Stage 2b / 2c 单 MMCM 对照版本：

```text
只实例化一个 Clock Wizard；
不支持双采样率运行中切换；
Vivado 默认功耗报告中 MMCM Power 分别为 0.095 W 和 0.103 W。
```

而：

```text
0.095 W + 0.103 W = 0.198 W
```

这与 Stage 2 双 MMCM 主版本中的 MMCM 功耗完全对应。因此可以明确说明：

```text
双采样率家族中的两个 MMCM 是 Vivado 默认功耗报告中的主要动态功耗来源。
```

同时也解释了为什么 Stage 2 reset gating 没有在默认功耗报告中体现下降：

```text
Stage 2 仍然实例化两个 MMCM；
Stage 2b / Stage 2c 直接删除其中一个 MMCM；
Vivado 默认 report_power 对“资源是否存在”非常敏感，
但对“已实例化资源在某个工作模式下被 reset”不一定敏感。
```

---

## 8. 这一版探索的价值

Stage 2c 与 Stage 2b 一起，构成完整的单 MMCM 对照实验。

| 版本 | 支持采样率家族 | MMCM 数量 | Total Power | 用途 |
|---|---|---:|---:|---|
| Stage 2 主版本 | 44.1k + 48k，可运行中切换 | 2 | 0.272 W | 最终演示主版本 |
| Stage 2b static44k | 仅 44.1k | 1 | 0.168 W | 对照实验 |
| Stage 2c static48k | 仅 48k | 1 | 0.177 W | 对照实验 |

这个对照实验说明：

1. 双采样率家族运行切换能力需要付出额外 MMCM 功耗；
2. 单采样率固定应用可以通过删除未使用 Clock Wizard 显著降低默认功耗报告；
3. 功耗主要差异来自 MMCM，而不是 FIR 计算逻辑；
4. 最终竞赛主版本应保留双 MMCM 以支持功能完整性；
5. 单 MMCM 版本适合作为低功耗结构探索与对照实验保留。

---

## 9. 局限性

Stage 2c 不能直接替代最终主版本，原因是：

1. **不支持 44.1 kHz 家族**  
   该版本只保留 48 kHz 家族，不能输出 176.4 kHz / 352.8 kHz / 5.6448 MHz。

2. **不支持 `sw2` 运行中切换**  
   `sw2` 在该版本中只保留端口，不参与功能逻辑。

3. **牺牲了系统灵活性**  
   单 MMCM 版本功耗更低，但功能覆盖范围比双 MMCM 主版本小。

4. **Vivado 功耗报告不是板级电源实测值**  
   `report_power` 用于版本间估算对比，不等价于板上实际功耗。

因此，Stage 2c 应定位为：

```text
低功耗结构对照实验版本
```

而不是最终竞赛演示主版本。

---

## 10. 建议 Commit 信息

如果需要提交当前 Stage 2c 探索版本，建议 commit：

```text
Add static 48k single-MMCM exploration
```

详细描述：

```text
Add static 48k single-MMCM exploration

- Remove 44.1 kHz Clock Wizard from the top-level design
- Keep only clk_wiz_audio_48k as the 128x audio clock source
- Replace dual-clock BUFGMUX selection with a single BUFG path
- Keep sw2 port only for XDC compatibility
- Verify 4x, 8x and 128x DAC outputs in the 48 kHz family
- Export utilization, timing and power reports for single-MMCM comparison
```

---

## 11. 最终结论

Stage 2c 的最终结论如下：

```text
Stage 2c 构建了静态 48 kHz 单 MMCM 对照版本，仅保留 clk_wiz_audio_48k，删除 44.1 kHz 采样率家族 Clock Wizard。板级验证表明，该版本在 sw2 = 0 或 sw2 = 1 时均固定输出 48 kHz 家族，4×、8×、128× 三档分别为 192.01 kHz、384.02 kHz 和 6.14 MHz，功能正常。实现结果显示，MMCME2_ADV 为 1，总功耗为 0.177 W，动态功耗为 0.105 W，MMCM 功耗为 0.103 W。该结果与 Stage 2b 静态 44.1 kHz 单 MMCM 对照版本共同证明，双采样率家族中的两个 MMCM 是 Vivado 默认功耗报告中的主要动态功耗来源。由于该版本不支持 44.1 kHz 家族和 sw2 运行中切换，因此不作为最终竞赛演示主版本，而作为低功耗结构对照实验版本保留。
```
