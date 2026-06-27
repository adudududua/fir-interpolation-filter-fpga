# Stage 2 评估报告：MMCM Reset Gating 与采样率家族运行切换验证

> 工程：`XC7A35T_interp_audio_pcm_wordlen_opt`  
> 分支：`exp/clock-power-optimization`  
> 阶段：Stage 2  
> 优化名称：`MMCM reset gating for sample-family switching`  
> 基础版本：Stage 1 `mode-aware FIR stage gating`  
> 目标平台：Artix-7 XC7A35T-FGG484-2  
> 工具版本：Vivado 2018.3  
> 板级验证方式：AD9708 8-bit DAC + 示波器

---

## 1. 本阶段的目的

在前一阶段 Stage 1 中，系统已经实现了 **mode-aware 后级 FIR gating**：

- 4× 模式下关闭未使用的 2× 后级插值链；
- 8× 模式下只保留第一级 2× FIR；
- 128× 模式下运行完整插值链。

Stage 2 进一步从 **采样率家族时钟源** 角度进行低功耗结构探索。原设计支持两类音频采样率家族：

| `sw2` | 采样率家族 | 128× 时钟 |
|---|---|---:|
| 0 | 44.1 kHz 家族 | 5.6448 MHz |
| 1 | 48 kHz 家族 | 6.144 MHz |

原系统中同时实例化了两个 Clock Wizard：

```text
u_clk_wiz_audio_44k1
u_clk_wiz_audio_48k
```

虽然最终只通过 `BUFGMUX` 选择其中一个时钟送入插值链，但未被选择的 Clock Wizard 在结构上仍然存在。因此，本阶段尝试让未使用的采样率家族 Clock Wizard 保持复位，从系统结构上减少未使用时钟源的无效工作。

本阶段的核心目标不是改变 FIR 算法，而是探索：

```text
当前只使用一个采样率家族时，另一个采样率家族的 Clock Wizard 是否可以被安全复位。
```

---

## 2. 本阶段修改了哪些文件

本阶段主要修改：

```text
XC7A35T_interp_audio_pcm_wordlen_opt/
└── XC7A35T_interp.srcs/
    └── sources_1/
        └── new/
            └── board_demo_competition_dac8_top.v
```

没有修改 FIR 系数、FIR tap 数、插值链数据通路、DAC 数据截位策略，也没有修改 Stage 1 已经验证通过的 `interp128_top_ce.v` 和 `demo_interp_dac8_audio_pcm_common.v` 的核心逻辑。

---

## 3. 具体 RTL 改动

### 3.1 对 `sw2` 做 50 MHz 系统时钟域同步

原设计中，`sw2_ibuf` 直接用于选择 44.1 kHz / 48 kHz 家族时钟。Stage 2 中新增两级同步寄存器：

```verilog
reg sw2_meta = 1'b0;
reg sw2_sync = 1'b0;

always @(posedge clk_sys_bufg) begin
    sw2_meta <= sw2_ibuf;
    sw2_sync <= sw2_meta;
end

wire use_48k;
assign use_48k = sw2_sync;
```

其中：

| 信号 | 含义 |
|---|---|
| `use_48k = 0` | 选择 44.1 kHz 家族 |
| `use_48k = 1` | 选择 48 kHz 家族 |

这样做的目的是避免拨码开关信号直接控制 MMCM reset 和 BUFGMUX select，降低异步输入对时钟切换逻辑的影响。

---

### 3.2 对两个 Clock Wizard 增加互斥 reset gating

Stage 2 中新增两个 reset 控制信号：

```verilog
assign rst_mmcm_48k  = (~rst_n_int) | (~use_48k);
assign rst_mmcm_44k1 = (~rst_n_int) | use_48k;
```

对应行为如下：

| `use_48k` | 44.1 kHz Clock Wizard | 48 kHz Clock Wizard |
|---|---|---|
| 0 | 工作 | reset |
| 1 | reset | 工作 |

也就是说：

```text
sw2 = 0：
    44.1 kHz 家族工作；
    48 kHz 家族 Clock Wizard 保持 reset。

sw2 = 1：
    48 kHz 家族工作；
    44.1 kHz 家族 Clock Wizard 保持 reset。
```

这个设计属于 **sample-family-aware clock source gating / reset gating**。它不是改变输出采样率，而是让系统根据当前采样率选择状态，隔离未使用的时钟源。

---

### 3.3 `BUFGMUX` 选择信号改为同步后的 `use_48k`

原设计中 `BUFGMUX` 的选择信号来自 `sw2_ibuf`。Stage 2 中改为：

```verilog
.S(use_48k)
```

这样 `BUFGMUX` 的选择信号与两个 Clock Wizard 的 reset 控制信号使用同一个同步后的采样率家族选择信号，避免出现选择信号和 reset 控制不一致的情况。

---

### 3.4 音频域复位绑定当前选中 MMCM 的 `locked`

Stage 2 中，当前选中 MMCM 的锁定信号为：

```verilog
assign mmcm_locked_sel = use_48k ? mmcm_locked_48k : mmcm_locked_44k1;
```

随后将音频域复位与当前选中 MMCM 的 `locked` 信号绑定：

```verilog
assign rst_audio_async_n = rst_n_int & mmcm_locked_sel;
```

音频域复位采用“异步拉低、同步释放”方式：

```verilog
always @(posedge clk_audio_128x_sel or negedge rst_audio_async_n) begin
    if (!rst_audio_async_n) begin
        rst_audio_sync <= 3'b000;
    end
    else begin
        rst_audio_sync <= {rst_audio_sync[1:0], 1'b1};
    end
end

assign rst_audio_n = rst_audio_sync[2];
```

这样做的意义是：

1. 当 `sw2` 切换到另一个采样率家族时，原来工作的 MMCM 被 reset，新选择的 MMCM 需要重新 locked；
2. 在新 MMCM 没有 locked 之前，插值链保持复位；
3. 新时钟稳定后，再在当前音频时钟域内同步释放复位；
4. 避免插值链在时钟未稳定时误运行。

---

## 4. 板级验证结果

Stage 2 通过了板级 DAC 输出验证，并且 `sw2` 可以在运行中正常切换。

### 4.1 `sw2 = 0`：44.1 kHz 家族

| 输出倍率 | 理论值 | 实测值 | 结果 |
|---|---:|---:|---|
| 4× | 176.4 kHz | 176.3 kHz | 正常 |
| 8× | 352.8 kHz | 352.61 kHz | 正常 |
| 128× | 5.6448 MHz | 5.65 MHz | 正常 |

### 4.2 `sw2 = 1`：48 kHz 家族

| 输出倍率 | 理论值 | 实测值 | 结果 |
|---|---:|---:|---|
| 4× | 192 kHz | 192.01 kHz | 正常 |
| 8× | 384 kHz | 384.02 kHz | 正常 |
| 128× | 6.144 MHz | 6.15 MHz | 正常 |

### 4.3 运行中切换结果

实测结果表明：

```text
sw2 可以在系统运行中切换；
切换后对应采样率家族下的 4× / 8× / 128× 三档输出均能恢复正常；
DAC 波形正常。
```

这说明 Stage 2 中的 MMCM reset gating、BUFGMUX 时钟选择、当前 MMCM locked 绑定音频域复位这三部分配合是可行的。

---

## 5. 资源利用率结果

### 5.1 Stage 2 实现后资源

Vivado implementation 后导出的 `utilization_stage2_mmcm_reset_gating.txt` 显示：

| 资源 | 使用量 | 可用量 | 利用率 |
|---|---:|---:|---:|
| Slice LUTs | 10203 | 20800 | 49.05% |
| LUT as Logic | 10083 | 20800 | 48.48% |
| LUT as Shift Register | 120 | 9600 | 1.25% |
| Slice Registers | 4607 | 41600 | 11.07% |
| DSP48E1 | 2 | 90 | 2.22% |
| Bonded IOB | 13 | 250 | 5.20% |
| BUFGCTRL | 2 | 32 | 6.25% |
| MMCME2_ADV | 2 | 5 | 40.00% |

### 5.2 与前几个版本对比

| 版本 | LUT | FF | DSP | MMCM | 说明 |
|---|---:|---:|---:|---:|---|
| polyphase MAC2 no-DSP verified | 10197 | 4640 | 2 | 2 | 最终 verified 基线 |
| Stage 1 mode gating | 10204 | 4641 | 2 | 2 | 低倍率关闭未使用后级 FIR |
| Stage 2 MMCM reset gating | 10203 | 4607 | 2 | 2 | 未使用采样率家族 Clock Wizard reset |

可以看到，Stage 2 没有明显增加资源。LUT 相比 Stage 1 少 1 个，FF 相比 Stage 1 少 34 个，DSP 仍为 2 个，MMCM 仍为 2 个。

需要注意的是，FF 数量下降并不代表 Stage 2 做了显式的寄存器资源压缩，而更可能来自综合与实现过程中对控制逻辑、复位逻辑和无用寄存器的重新优化。这个变化可以记录，但不应作为主要优化点重点宣传。

### 5.3 资源结论

Stage 2 的资源结果说明：

```text
MMCM reset gating 没有破坏原来的低资源结构；
没有引入额外 DSP；
没有增加 MMCM 数量；
整体 LUT / FF 仍然保持在安全范围内。
```

---

## 6. 时序结果

Vivado `timing_stage2_mmcm_reset_gating.txt` 显示：

| 指标 | 数值 |
|---|---:|
| WNS | 16.978 ns |
| TNS | 0.000 ns |
| WHS | 0.065 ns |
| THS | 0.000 ns |
| 结论 | All user specified timing constraints are met |

分时钟域结果：

| 时钟域 | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|
| clk_50M | 16.978 ns | 0 | 0.065 ns | 0 |
| clk_audio_128x_44k1 | 75.134 ns | 0 | 0.074 ns | 0 |
| clk_audio_128x_48k | 68.122 ns | 0 | 0.074 ns | 0 |

### 6.1 时序分析

Stage 2 新增的逻辑主要在 50 MHz 系统时钟域和复位控制路径上，包括：

- `sw2` 两级同步；
- 两个 MMCM reset 控制；
- 当前 MMCM locked 选择；
- 音频域复位同步释放。

这些逻辑没有进入 FIR 的长乘加路径，也没有改变 4× polyphase MAC2 或后级 2× FIR 的关键数据路径。因此，Stage 2 对时序影响很小。

### 6.2 时序结论

Stage 2 满足所有用户时序约束，且 WNS 仍有较大余量。该优化不会对系统最高工作频率构成压力。

---

## 7. 功耗结果

Vivado `power_stage2_mmcm_reset_gating.txt` 显示：

| 项目 | 数值 |
|---|---:|
| Total On-Chip Power | 0.272 W |
| Dynamic Power | 0.200 W |
| Device Static Power | 0.072 W |
| MMCM Power | 0.198 W |
| u_clk_wiz_audio_44k1 | 0.095 W |
| u_clk_wiz_audio_48k | 0.103 W |

### 7.1 与 Stage 1 对比

Stage 1 与 Stage 2 的默认 Vivado power report 基本相同：

| 版本 | Total Power | Dynamic | Static | MMCM |
|---|---:|---:|---:|---:|
| Stage 1 mode gating | 0.272 W | 0.200 W | 0.072 W | 0.198 W |
| Stage 2 MMCM reset gating | 0.272 W | 0.200 W | 0.072 W | 0.198 W |

这说明：

```text
从 Vivado 默认功耗报告来看，Stage 2 没有体现出总功耗下降。
```

### 7.2 为什么功耗报告没有下降

Stage 2 的 RTL 结构确实把未使用的 Clock Wizard reset 了，但 Vivado 默认 `report_power` 没有体现功耗下降，主要原因可能包括：

1. `report_power` 没有导入具体运行模式下的仿真活动文件  
   报告中 `Simulation Activity File = ---`，说明功耗分析没有使用 `sw2=0` 或 `sw2=1` 的实际切换活动数据。

2. 设计中仍然实例化两个 Clock Wizard / MMCM  
   资源报告中 `MMCME2_ADV = 2`，因此 Vivado 仍然把两个 MMCM 作为已使用时钟资源统计。

3. Clock Wizard 只有 `reset` 端口，不是显式 `power_down` 端口  
   reset 可以让输出和 locked 行为受控，但 Vivado 默认功耗模型未必把 reset 状态等效为完全低功耗关闭。

4. 两个时钟约束仍然存在  
   timing / power 报告仍然看到 `clk_audio_128x_44k1` 和 `clk_audio_128x_48k` 两个时钟，因此默认估算中两个 MMCM 仍然被纳入功耗模型。

因此，在竞赛报告中不应写：

```text
Stage 2 使 Vivado 报告功耗降低。
```

更严谨的写法应该是：

```text
Stage 2 实现了采样率家族感知的 Clock Wizard reset gating。板级测试表明该结构支持运行中采样率家族切换，功能正确；但 Vivado 默认功耗估计未反映该模式级 reset gating 带来的活动差异，报告总功耗仍为 0.272 W。
```

### 7.3 功耗结论

Stage 2 的功耗优化属于 **结构探索有效、报告未量化体现** 的类型。

它说明设计者已经从系统级角度考虑了未使用时钟源的问题，但在当前 Vivado 默认功耗估计条件下，不能把它作为“定量降低功耗”的结论。若要进一步定量证明，需要补充分模式活动文件、实际板级电流测量，或使用带 `power_down` 的 MMCM/Clock Wizard 配置。

---

## 8. 这一优化的价值

### 8.1 优点

Stage 2 的优点主要有：

1. **功能通过板级验证**  
   44.1 kHz / 48 kHz 两个采样率家族下，4× / 8× / 128× 三档输出均正常。

2. **支持运行中切换 `sw2`**  
   说明时钟选择、MMCM reset、locked 复位同步配合正确。

3. **资源几乎不增加**  
   LUT、FF、DSP 都保持在原有水平附近，DSP 仍为 2。

4. **时序完全满足约束**  
   WNS = 16.978 ns，TNS = 0，时序余量充足。

5. **形成更完整的竞赛优化思路**  
   设计不只停留在 FIR 系数、字长和 polyphase 结构层面，还进一步考虑到双采样率家族系统中的时钟源管理。

6. **提高系统切换可靠性**  
   音频域复位与当前选中 MMCM 的 locked 信号绑定，有助于避免时钟切换过程中的错误输出。

### 8.2 局限性

Stage 2 也有需要谨慎说明的地方：

1. **Vivado 默认功耗报告没有下降**  
   不能声称已经通过报告证明功耗降低。

2. **仍然占用两个 MMCM**  
   因为系统仍然实例化两个 Clock Wizard，资源上 `MMCME2_ADV` 仍为 2。

3. **reset gating 不等价于 power-down gating**  
   reset 只是控制 MMCM 复位，未必在工具功耗模型中等效为低功耗关断。

4. **如果要进一步优化，需要更复杂方案**  
   例如 Clock Wizard 暴露 `power_down` 端口、手动例化 `MMCME2_ADV` 并控制 `PWRDWN`，或使用单 MMCM + DRP 动态重配置。但这些方案风险更高，不适合作为当前竞赛主线的立即替换方案。

---

## 9. 这一版优化应如何评价

综合功能、资源、时序和功耗报告，可以把 Stage 2 评价为：

```text
Stage 2 是一次成功的系统级时钟结构优化探索。
```

更具体地说：

| 评价维度 | 结论 |
|---|---|
| 功能正确性 | 成功，板级三档输出均正常 |
| 运行中切换 | 成功，sw2 可运行中切换 |
| 资源影响 | 很小，DSP 不变，LUT/FF 保持稳定 |
| 时序影响 | 很小，所有约束满足 |
| 功耗报告 | 未体现下降 |
| 竞赛展示价值 | 有价值，但应保守表述 |
| 是否建议保留 | 建议保留在低功耗探索分支；若长期板测稳定，可作为最终工程的一部分 |

---

## 10. 竞赛报告中的推荐表述

建议在竞赛报告中写：

```text
在完成 FIR 结构和字长优化后，进一步针对双采样率家族时钟结构进行了低功耗探索。系统通过同步后的 sw2 信号选择当前采样率家族，并将未使用的 Clock Wizard 置于 reset 状态，同时将音频域复位与当前选中 MMCM 的 locked 信号绑定，保证采样率家族切换时插值链只在时钟稳定后运行。板级测试表明，该结构支持运行中切换 44.1 kHz / 48 kHz 采样率家族，且 4×、8×、128× 输出均正常。实现结果显示，Stage 2 版本 LUT = 10203，FF = 4607，DSP = 2，WNS = 16.978 ns，时序满足约束。Vivado 默认功耗报告中总功耗仍为 0.272 W，说明默认估计未直接反映该模式级 reset gating 的活动差异，因此本阶段作为系统级时钟管理与低功耗结构探索保留。
```

不建议写：

```text
本阶段显著降低了功耗。
```

可以写：

```text
本阶段实现了面向采样率家族的时钟源复位管理，并通过板级验证证明该结构可行。
```

---

## 11. 是否建议继续优化

对于当前竞赛进度，建议如下：

### 11.1 建议保留

Stage 2 已经通过板测，且没有破坏时序和资源，建议保留在当前优化分支中。

### 11.2 不建议继续大改主结构

不建议马上做以下高风险修改：

- 单 MMCM + DRP 动态重配置；
- 手动重写 Clock Wizard；
- 改成完全自定义 `MMCME2_ADV`；
- 大规模修改时钟拓扑；
- 重新设计所有 clock enable。

原因是当前版本已经能很好支撑竞赛展示，再继续大改可能引入时钟切换不稳定、复位异常或现场演示风险。

### 11.3 后续可以做的安全收尾

建议后续重点转向：

1. 清理注释和调试残留；
2. 更新 README；
3. 更新 DEMO_RESULTS；
4. 整理优化对比表；
5. 整理最终竞赛答辩说明。

---

## 12. 建议 Commit 信息

建议提交：

```text
Add MMCM reset gating for sample-family switching
```

详细描述：

```text
Add MMCM reset gating for sample-family switching

- Synchronize sw2 as the sample-family selection signal
- Reset unused 44.1 kHz or 48 kHz Clock Wizard according to sw2
- Use selected MMCM locked signal to control audio-domain reset release
- Verify runtime sw2 switching on board
- Verify 4x, 8x and 128x DAC outputs for both sample-rate families
- Export utilization, timing and power reports for Stage 2
```

---

## 13. 最终结论

Stage 2 的最终结论如下：

```text
Stage 2 在 Stage 1 的 mode-aware FIR gating 基础上，进一步实现了 sample-family-aware MMCM reset gating。该版本通过同步后的 sw2 信号控制两个采样率家族 Clock Wizard 的互斥复位，并将音频域复位与当前选中 MMCM 的 locked 信号绑定。板级验证表明，系统支持运行中切换 44.1 kHz / 48 kHz 采样率家族，4× / 8× / 128× 三档 DAC 输出均正常。实现后 LUT = 10203，FF = 4607，DSP = 2，WNS = 16.978 ns，时序满足约束。Vivado 默认功耗报告中总功耗仍为 0.272 W，说明当前报告未量化体现 reset gating 的功耗收益。因此，该阶段应定位为一次成功的系统级时钟管理与低功耗结构探索，而不是已被工具报告定量证明的功耗降低版本。
```
