# 时钟与功耗进一步优化计划

> 分支建议：`exp/clock-power-optimization`  
> 基础版本：`polyphase_mac2_ntaps29_nodsp_verified`  
> 目标工程：`XC7A35T_interp_audio_pcm_wordlen_opt`  
> 目标平台：Artix-7 XC7A35T-FGG484-2  
> 当前已验证基线：4× / 8× / 128× 三档 DAC 波形正常，44.1 kHz / 48 kHz 两个采样率家族均通过板级测试。

---

## 1. 优化目标

当前最终 verified 版本已经完成：

- 4× 前级 polyphase + 2-lane MAC；
- 后级 2× FIR 使用 29 tap Q12；
- 后级 FIR 强制 no-DSP；
- 128× DAC 显示左移 4 位补偿；
- 实现后资源约为：
  - LUT = 10197
  - FF = 4640
  - DSP = 2
  - Total On-Chip Power ≈ 0.272 W
  - WNS ≈ 17.081 ns

本轮新分支的目标不是继续大改 FIR 算法，而是进一步探索 **clock-aware / mode-aware 低功耗优化**，重点降低未使用模块和未使用时钟源的无效翻转功耗。

---

## 2. 当前功耗瓶颈判断

当前最终版本总功耗约为：

| 项目 | 数值 |
|---|---:|
| Total On-Chip Power | 0.272 W |
| Dynamic Power | 0.201 W |
| Static Power | 0.072 W |

其中两个 Clock Wizard / MMCM 的层级功耗约为：

| 模块 | 功耗 |
|---|---:|
| `u_clk_wiz_audio_44k1` | 约 0.095 W |
| `u_clk_wiz_audio_48k` | 约 0.103 W |
| 合计 | 约 0.198 W |

因此，当前系统的主要功耗不在 FIR 乘加逻辑，而在两个采样率家族时钟源以及对应时钟网络。继续压缩 FIR LUT 对总功耗帮助有限；更值得探索的是：

1. 低倍率模式关闭未使用后级插值链；
2. 当前只使用一个采样率家族时，关闭另一个 Clock Wizard / MMCM；
3. 清理调试网络和不必要的寄存器翻转；
4. 在报告中补充不同模式下功耗对比，突出系统级低功耗优化能力。

---

## 3. 优化路线总览

本轮分为四个阶段，每个阶段单独提交，避免一次改太多导致难以定位。

| 阶段 | 优化内容 | 风险 | 预期收益 | 是否建议合并 main |
|---|---|---|---|---|
| Stage 0 | 保护基线与报告归档 | 低 | 保证可回退 | 是 |
| Stage 1 | Mode-aware 后级 FIR gating | 中低 | 低倍率模式减少无效翻转 | 通过板测后可合并 |
| Stage 2 | 未使用 Clock Wizard reset / power_down | 中 | 总功耗可能明显下降 | 通过板测后可合并 |
| Stage 3 | 清理 debug / keep / 注释 | 低 | 工程更干净，减少冗余保留 | 是 |
| Stage 4 | 单 MMCM + DRP 动态重配置 | 高 | 理论最优时钟结构 | 只建议探索，不建议替换主线 |

---

## 4. Stage 0：基线保护与报告归档

### 4.1 目标

确保当前主分支 verified 版本可以随时恢复。

### 4.2 操作

在当前新分支中，先确认工作区干净：

```bash
git status
```

建议给当前 main 上的 verified 版本打 tag：

```bash
git checkout main
git tag -a v_polyphase_mac2_nodsp_verified -m "Verified polyphase MAC2 no-DSP FIR version"
git push origin v_polyphase_mac2_nodsp_verified
```

再切回新分支：

```bash
git checkout exp/clock-power-optimization
```

### 4.3 需要保存的基线数据

建议保留以下报告作为对比基准：

```text
reports_polyphase_mac2_nodsp_verified/
├── utilization_ad9708_audio_pcm_polyphase_mac2_v2b.txt
├── util_hier_polyphase_mac2_v2b.txt
├── timing_ad9708_audio_pcm_polyphase_mac2_v2b.txt
└── power_ad9708_audio_pcm_polyphase_mac2_v2b.txt
```

---

## 5. Stage 1：Mode-aware 后级 FIR Gating

### 5.1 优化动机

当前系统虽然支持 4× / 8× / 128× 三档输出，但内部 128× 插值链很可能始终全部运行。也就是说：

```text
4× 模式下：
    实际只需要 4× 输出，
    但 8×、16×、32×、64×、128× 后级可能仍在翻转。

8× 模式下：
    实际只需要 8× 输出，
    但 16×、32×、64×、128× 后级可能仍在翻转。
```

这会造成低倍率模式下无效动态功耗。

### 5.2 目标结构

根据拨码 `sw1 sw0` 选择运行级数：

| 模式 | 需要运行的级数 | 关闭的级数 |
|---|---|---|
| 4× | 4× 前级 | 8× / 16× / 32× / 64× / 128× |
| 8× | 4× 前级 + 8× 级 | 16× / 32× / 64× / 128× |
| 128× | 全部级数 | 无 |

### 5.3 RTL 修改思路

给 `interp128_top_ce.v` 增加模式输入：

```verilog
input wire [1:0] mode_sel
```

在内部生成：

```verilog
wire mode_4x   = (mode_sel == 2'b00);
wire mode_8x   = (mode_sel == 2'b01);
wire mode_128x = (mode_sel[1] == 1'b1);

wire run_8x_stage   = mode_8x | mode_128x;
wire run_16x_stage  = mode_128x;
wire run_32x_stage  = mode_128x;
wire run_64x_stage  = mode_128x;
wire run_128x_stage = mode_128x;
```

然后对各级输入 valid 做 gating：

```verilog
wire y4_valid_to_8    = y4_valid_w        & run_8x_stage;
wire y8_valid_to_16   = y8_to_16_valid    & run_16x_stage;
wire y16_valid_to_32  = y16_to_32_valid   & run_32x_stage;
wire y32_valid_to_64  = y32_to_64_valid   & run_64x_stage;
wire y64_valid_to_128 = y64_to_128_valid  & run_128x_stage;
```

同时对各级 `ce_out` 做 gating：

```verilog
wire ce8_use   = ce8_out   & run_8x_stage;
wire ce16_use  = ce16_out  & run_16x_stage;
wire ce32_use  = ce32_out  & run_32x_stage;
wire ce64_use  = ce64_out  & run_64x_stage;
wire ce128_use = ce128_out & run_128x_stage;
```

### 5.4 注意事项

1. 4× 前级不能关，因为 4×、8×、128× 都依赖它；
2. 8× 模式必须保留第一级 2×；
3. 128× 模式必须全链路运行；
4. 不建议一开始给各级模块加 reset 清零，只先 gate valid / ce，降低风险；
5. 如果 4× / 8× 模式显示异常，优先检查对应 debug 输出是否仍然直接来自 `dbg_y4_w` / `dbg_y8_w`。

### 5.5 验证步骤

修改后依次验证：

| sw2 | sw1 sw0 | 预期 |
|---|---|---|
| 0 | 00 | 4× = 176.4 kHz 附近，波形正常 |
| 0 | 01 | 8× = 352.8 kHz 附近，波形正常 |
| 0 | 10 | 128× = 5.6448 MHz 附近，波形正常 |
| 1 | 00 | 4× = 192 kHz 附近，波形正常 |
| 1 | 01 | 8× = 384 kHz 附近，波形正常 |
| 1 | 10 | 128× = 6.144 MHz 附近，波形正常 |

### 5.6 报告写法

```text
在低倍率输出模式下，系统根据当前插值倍率关闭未使用的后级插值链路，使 4× 模式仅保留 4× polyphase 前级，8× 模式仅保留 4× 前级和第一级 2× FIR，从而减少后级 2× FIR 的无效寄存器翻转和组合逻辑切换。该优化属于 mode-aware computation gating，不改变滤波器系数与输出采样率。
```

---

## 6. Stage 2：未使用 Clock Wizard / MMCM 关断

### 6.1 优化动机

当前系统支持 44.1 kHz 和 48 kHz 两个采样率家族。若两个 Clock Wizard 同时常开，即使只选择其中一路输出，另一个时钟源仍然持续工作并消耗动态功耗。

### 6.2 目标结构

| sw2 | 使用时钟 | 关闭时钟 |
|---|---|---|
| 0 | 44.1 kHz 家族 Clock Wizard | 48 kHz 家族 Clock Wizard |
| 1 | 48 kHz 家族 Clock Wizard | 44.1 kHz 家族 Clock Wizard |

### 6.3 推荐优先级

1. 若 Clock Wizard 有 `power_down` 端口，优先使用；
2. 若无 `power_down`，尝试使用 `reset`；
3. 若 reset 后功耗无明显变化，只作为探索结果记录；
4. 不建议一开始做 DRP 动态重配置。

### 6.4 RTL 修改思路

在顶层 `board_demo_competition_dac8_top.v` 或时钟选择逻辑所在文件中同步 `sw2`：

```verilog
reg sw2_d1, sw2_d2;

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
        sw2_d1 <= 1'b0;
        sw2_d2 <= 1'b0;
    end else begin
        sw2_d1 <= sw2;
        sw2_d2 <= sw2_d1;
    end
end

wire use_48k = sw2_d2;
```

若 Clock Wizard 暴露 reset：

```verilog
assign rst_clk_wiz_44k1 = global_reset |  use_48k;
assign rst_clk_wiz_48k  = global_reset | ~use_48k;
```

若 Clock Wizard 暴露 power_down：

```verilog
assign pwr_down_clk_wiz_44k1 =  use_48k;
assign pwr_down_clk_wiz_48k  = ~use_48k;
```

最终音频域 reset 应结合被选中时钟的 locked：

```verilog
wire selected_locked = use_48k ? locked_48k : locked_44k1;
assign rst_audio_n = rst_n & selected_locked;
```

### 6.5 风险点

1. 切换 `sw2` 时，未使用的 MMCM 重新启动需要等待 `locked`；
2. 如果直接使用拨码开关控制 reset，可能因抖动导致时钟域异常；
3. 必须同步 `sw2`，最好切换后按一次复位；
4. 若现场演示需要频繁切换 sw2，需测试切换稳定性；
5. Clock Wizard reset 是否真正降低功耗，需要 Vivado power report 验证。

### 6.6 验证步骤

第一轮板测建议不要在线热切换，采用：

```text
1. 设置 sw2 = 0；
2. 按复位；
3. 测 4× / 8× / 128×；
4. 设置 sw2 = 1；
5. 按复位；
6. 测 4× / 8× / 128×。
```

---

## 7. Stage 3：清理 Debug 网络与工程注释

### 7.1 目标

去除历史调试遗留，避免综合器保留不必要网络，也让最终工程更适合展示。

### 7.2 检查项

搜索以下关键字：

```text
mark_debug
keep
debug
dbg_y32
dbg_y64
final_fir_in
pulse_valid
v1d
halfband
```

### 7.3 处理原则

| 内容 | 处理建议 |
|---|---|
| `dbg_y4_w` / `dbg_y8_w` | 可保留，因为 4× / 8× 模式需要直接输出 |
| `dbg_y32_w` / `dbg_y64_w` | 若不用于最终显示，可不保留 mark_debug |
| `final_fir_in` 临时输出 | 不应在最终版中存在 |
| 旧注释中提到 11 tap | 改为 29 tap |
| 旧注释中提到左移 3 位 | 改为左移 4 位 |
| 被注释掉的大段旧 always | 建议删除或移入历史报告 |

---

## 8. Stage 4：单 MMCM + DRP 动态重配置探索

这是高风险探索项，不建议直接替换主线。

### 8.1 理论目标

把两个 Clock Wizard：

```text
u_clk_wiz_audio_44k1
u_clk_wiz_audio_48k
```

合并为一个可动态重配置 MMCM，根据 `sw2` 切换输出 5.6448 MHz 或 6.144 MHz。

### 8.2 优点

- 永远只有一个 MMCM 工作；
- 时钟结构更极致；
- 报告创新性更强。

### 8.3 缺点

- DRP 配置复杂；
- 切换时要等待 locked；
- Vivado 2018.3 下调试成本较高；
- 不适合临近提交时作为主版本。

---

## 9. 推荐提交节奏

### Commit 1：新增计划文档

```text
Add clock power optimization plan
```

### Commit 2：Stage 1 完成后

```text
Add mode-aware FIR stage gating
```

### Commit 3：Stage 2 完成后

```text
Add clock wizard gating for unused sample family
```

### Commit 4：Stage 3 完成后

```text
Clean debug comments and final RTL annotations
```

若 Stage 2 或 Stage 4 不稳定，不要合并到 main，只保留在探索分支。

---

## 10. 最终期望结果

如果 Stage 1 和 Stage 2 均成功，最终可以形成一个更强的优化故事：

| 优化层级 | 已有版本 | 本轮新增 |
|---|---|---|
| 字长优化 | 后级 Q16 → Q12 | 保留 |
| 累加器优化 | ACC_W 扫描至 49 | 保留 |
| 结构优化 | 4× polyphase MAC2 | 保留 |
| 资源映射优化 | 后级 no-DSP | 保留 |
| 模式级低功耗 | 无 | 低倍率关闭后级 FIR |
| 时钟级低功耗 | 无 | 关闭未使用采样率家族 Clock Wizard |

最终报告可以强调：

```text
本项目不仅完成了滤波器算法和位宽层面的资源优化，还进一步从系统工作模式出发，对未使用的插值级和未使用的采样率时钟源进行门控，体现了从算法、RTL 结构到系统时钟功耗的多层级优化思路。
```

---

## 11. 当前建议先做什么

建议先做 Stage 1，不要一开始改 Clock Wizard。

原因：

1. Stage 1 不涉及时钟 IP，风险更低；
2. 即使 Vivado power report 不明显，也可以作为 mode-aware 低功耗优化写进报告；
3. Stage 1 通过后再做 Stage 2，定位更清楚；
4. 如果 Stage 2 失败，Stage 1 仍可保留。

第一步需要检查和修改的文件主要是：

```text
interp128_top_ce.v
demo_interp_dac8_audio_pcm_common.v
```

其中：

- `interp128_top_ce.v` 增加 `mode_sel` 输入，并对后级 valid / ce 做 gating；
- `demo_interp_dac8_audio_pcm_common.v` 将当前 `mode_sel` 传入 `interp128_top_ce`。
