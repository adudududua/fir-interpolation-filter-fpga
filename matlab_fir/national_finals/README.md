# 全国总决赛：双采样率可配置插值滤波器

当前 P4-C 候选已完成 MATLAB 建模、24 bit 定点模型、15 项 XSim 回归、Vivado 综合/布局布线/时序/DRC/CDC/功耗评估和 bitstream 生成。默认最低 LUT/FF 档为 **479 LUT / 468 FF / 198 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**；同源 3-DSP、2-DSP 档也均完成实现与 bitstream。所有可在当前环境执行的软件与 FPGA 工具验收均已通过；由于当前环境无法接触实物开发板，物理板下载和仪器测量仍需按本文最后一节执行，不能把 bitstream 成功等同于实板通过。

当前可发布 Pareto 点为 P3 `462 LUT / 447 FF / 5 DSP / 3 BRAM Tile`、P4-A `491 LUT / 444 FF / 4 DSP / 3 BRAM Tile`，以及 P4-C 的 `479 LUT / 4 DSP`、`504 LUT / 3 DSP`、`523 LUT / 2 DSP` 三档（均为 2 BRAM Tile）。这些版本均继承 P1 真 Q15 修复和 P3 的原子 CDC、同步复位、AD9708 输出时序闭环。复核发现旧 Route 1 `424 LUT / 6 DSP` 与低 DSP `436 LUT / 5 DSP` 的 Stage 3 系数实际为 Q14 幅度、MAC 却按 Q15 右移，导致 8x/128x 绝对增益约为 -6.02 dB；这些旧版本只保留为资源演进历史，不再作为发布候选。前一份指导的完整执行记录见 [P0～P4 执行反馈](results/next_stage_optimization_guide_execution.md)，本轮指导的逐项判断和实测见 [P4-B RTL 下一阶段指导执行反馈](results/p4b_rtl_next_optimization_guide_execution.md)。

## 0. P1：Stage 3 真 Q15 与绝对增益闭环

P1 将 11-tap Stage 3 统一为真 Q15 系数 `[404,-148,-3272,522,19250,32016,19250,522,-3272,-148,404]`，同步修正 MATLAB 位真模型、统一 RAMB18E1 初始化、后备系数 ROM 和原语测试，并删除只对旧半幅系数成立的 35-bit 直通捷径。Stage 3 现在保留完整 38-bit MAC 视图和 signed 20-bit 饱和检查。

新增绝对增益门禁先对旧 RTL 输出执行负向验证并正确失败：4x/8x/128x 分别为 `-0.001599/-6.023392/-6.024933 dB`。修复后为 `-0.001599/-0.002709/-0.003480 dB`，最大模式间差 `0.001881 dB`，均满足 `0.01 dB` 门槛。XSim 10/10、完整链冲激/随机三节点 0 LSB、六工况频响与严格线性相位全部通过。

post-route 结果为 **446 LUT / 471 FF / 5 DSP / 3 BRAM Tile / 2 MMCM / 17 IO**，WNS/WHS 为 **+45.104/+0.121 ns**，功耗仍为 0.271 W，bitstream SHA-256 为 `F57419974501552FE670DD711354B244908EA05EC8DE95511719C467D1D74749`。相对旧 436-LUT 故障基线多 10 LUT，原因是恢复可达的 38-bit 饱和逻辑；其余主要资源不增加。

## P3：CDC、同步复位与 AD9708 接口闭环

P3 不改变 P1 的滤波系数、定点舍入和样点值。两位模式总线改为 request/ack 原子握手，FIR/CIC/bridge/键盘状态采用同步复位，MMCM `locked` 和音频复位释放经过同步器；切换期间 DAC 强制中点静音。8 位 `dac_data` 进入 IOB 寄存器，`dac_clk` 由 ODDR 转发，并按 AD9708 setup/hold 加板级裕量建立两个互斥 forwarded clock 约束。

从零 XSim 回归为 **11/11 PASS**：包含 1200 次模式 CDC 全方向压力测试、100 次双 MMCM 家族切换、8 个内部复位恢复场景、10 次动态倍率切换、串行 CIC 对拍、完整链冲激/随机 0 LSB 和统一 RAMB18E1 全地址检查。post-route 为 **462 LUT / 447 FF / 180 Slice / 5 DSP / 3 BRAM Tile / 2 MMCM / 17 IO**，WNS/WHS 为 **+46.140/+0.050 ns**，AD9708 最差输出 setup/hold 为 **+76.116/+78.117 ns**，功耗仍为 **0.271 W**。bitstream SHA-256 为 `A38C6D4F4B3C023DBD22897505B85864990CFC7C5D974A84FA38C5F0ADE21033`。

CDC 报告中专用 `BUFGMUX_CTRL` 选择入口和 bundled-data shadow bus 分别保留书面 waiver；它们没有用 false path 隐藏，详细逐规则说明和板级待办见 [P3 工程闭环签核](results/p3_engineering_closure_summary.md)。

## P4-A：严格等价 N3 Hold，5 DSP 降至 4 DSP

利用插值 CIC 的多速率恒等式，把 `C³ → ↑16 → I³` 严格改写为 `C² → Hold16 → I²`。新实现保留 33-bit 模运算宽度、右移 8 bit 归一化、舍入饱和及输出有效周期；两级低速 comb 使用 LUT/CARRY4，两级高速 integrator 各使用一颗 DSP48E1。因此全机 DSP 分配由 `1 + 1 + 3 = 5` 变成 `1 + 1 + 2 = 4`。

独立等价测试覆盖连续 320 组、随机停顿 480 组、复位中断与 7680 个输出样本；完整 RTL 回归扩展为 **12/12 PASS**，Stage1/2/3/128x 全链路仍为 0 LSB。post-route 为 **491 LUT / 444 FF / 197 Slice / 4 DSP / 3 BRAM Tile / 2 MMCM / 17 IO**，WNS/WHS 为 **+45.738/+0.052 ns**，AD9708 最差输出 setup/hold 仍为 **+76.116/+78.117 ns**，功耗 **0.271 W**。bitstream SHA-256 为 `D262BA94186D992016FE9FACD157E34FDB29EDF0F9A3433A38833A65B101C334`。

这是 DSP 优先 Pareto 点：相对 P3 少 1 DSP、少 3 FF，但增加 29 LUT 和 17 Slice，不能表述为所有资源同时下降。详细验证和 waiver 见 [P4-A N3 Hold 签核](results/p4a_n3_hold_4dsp_summary.md)。

## P4-B：Stage 1/2/3 历史 RAM 时分复用，3 降至 2 BRAM Tile

P4-B 保持 P4-A 的 4-DSP N3 Hold 数值路径，只优化历史存储。Stage 1 把当前输入旁路为第 0 对左样本，单 RAMB18E1 按 `R0,L1,R1,...,L25,R25` 连续读取其余对称样本，约 53 拍完成 26 次 MAC，满足 64 拍截止期。Stage 2/3 用 bank 地址共享一个 32×22-bit RAMB18E1，同拍双写冲突由一项 Stage 3 写队列吸收。两处均使用显式 SDP RAMB18E1，防止 Vivado 回退为 LUTRAM。

完整回归为 **14/14 PASS**：Stage 1 新旧核 1400 输出 0 LSB、Stage 2/3 分别 336/671 输出 0 LSB、N3 Hold 7680 输出 0 LSB，并通过全链随机/冲激、8 种内部状态复位、1200 次原子 CDC、100 次家族切换和 10 次不停机倍率切换。post-route 为 **504 LUT / 493 FF / 202 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM / 17 IO**，WNS/WHS **+45.637/+0.119 ns**，功耗 **0.271 W**，bitstream SHA-256 为 `DA0665E43A8DA5230AB93FC786AB0EED47BD83FE393C9B1416BA3360B8DE5E85`。

相对 P4-A，P4-B 多 13 LUT、49 FF 和 5 Slice，少 1 BRAM Tile；因此 P4-A 与 P4-B 分别作为低 LUT/FF 与低 BRAM 的 4-DSP 回退点保留。详细证据见 [P4-B 单 BRAM 签核](results/p4b_single_bram_4dsp_summary.md)。

## P4-C：固定 CE 精简、DSP48 预加器与 26/29-bit CIC

P4-C 不改变 FIR/CIC 传递函数、系数、舍入、饱和或输出 valid 序列，完成三项严格等价优化。第一，证明全国赛连续 2 的幂 CE 下 Stage2 与 Stage3 的 phase0 历史写集合不相交，仅在板级签核配置删除不可达的 25-bit 待写队列；通用模块默认仍保留队列。第二，在当前 Stage1 单 BRAM 串行核上重新 A/B，DSP48E1 `D+A` 预加器比 LUT 对称加法再减少 7 个综合 LUT。第三，把 N3 Hold CIC 的两个保守 33-bit 状态按解析界收紧为 26/29 bit，并提供全机 4/3/2-DSP 三档。

同时修复了 48 kHz 家族切换后首个 ROM 地址可能错误的问题、`SETTLE_CYCLES>3` 的 CDC 计数器截断问题，并把 GUI `sim_1` 的顶层和宏锁定到签核结构。历史 RAMB18 新增 primitive-vs-behavioral 独立对拍；最终 XSim 为 **15/15 PASS**。

| P4-C 档位 | LUT | FF | Slice | DSP | BRAM Tile | MMCM | WNS/WHS | 功耗估计 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 默认低 LUT/FF | **479** | **468** | **198** | **4** | 2 | 2 | +45.734/+0.121 ns | 0.271 W |
| 低 DSP-A | 504 | 494 | 198 | 3 | 2 | 2 | +45.853/+0.121 ns | 0.271 W |
| 低 DSP-B | 523 | 523 | 197 | 2 | 2 | 2 | +45.802/+0.121 ns | 0.270 W |

相对 P4-B，默认档减少 **25 LUT、25 FF、4 Slice**，DSP/BRAM/MMCM 不变；3-DSP 档以 `+25 LUT/+26 FF` 换 1 DSP，2-DSP 档以 `+44 LUT/+55 FF` 换 2 DSP。功耗是无 SAIF 的 vectorless 估算，0.001 W 差异不能当作实物省电结论。默认 bitstream SHA-256 为 `814465320512830C98D0EDA5352D36797BF5C442CD27E3520B5B89601F1C52D3`。

本轮 MATLAB 直接分析当前 RTL 发布的 impulse CSV，六工况通带、阻带、绝对增益和严格线性相位全部 PASS；详细证明、策略扫描、三档 SHA 和未执行项见 [P4-C 指导执行反馈](results/p4b_rtl_next_optimization_guide_execution.md)。

## 0.1 Route 1：统一双端口系数 RAM（历史资源点）

Route 1保留Stage1和Stage2/3两颗FIR DSP。原因是48 kHz最紧工况下，一个128拍输入超周期内三段FIR最坏需要`27+42+60=129`拍，单DSP没有可靠调度余量。实际优化是把Stage1的26路`case`常量系数网络，与Stage2/3同步系数BRAM合并到一个显式true-dual-port `RAMB18E1`：

- A口地址64～89供Stage1读取26个signed 16-bit对称系数；
- B口地址0～63供Stage2/3读取两相系数；
- 两颗DSP可以同拍读取，不降低吞吐；
- 利用原RAMB18的空闲地址，BRAM Tile仍为3；
- 所有历史存储、MAC、舍入、饱和、均衡器、CIC16和六工况频响不变。

该改动删除了Stage1的常量译码/宽选择网络，综合从452 LUT降到436 LUT，Stage1层级从136 LUT降到120 LUT；布局布线从434 LUT / 469 FF / 190 Slice降到 **424 LUT / 471 FF / 188 Slice**。DSP/BRAM/MMCM/IO和0.271 W功耗不变。

验证包括：统一RAMB18E1的96个地址逐点检查、全国赛回归10/10 PASS、4x/8x/128x冲激和固定随机0 LSB、8个复位恢复场景、10次动态倍率切换、六工况频响、完整布局布线、时序和DRC。WNS/WHS为 **+45.356/+0.117 ns**，TNS/THS为0，bitstream SHA-256为`77D67B9E53FF43A0774A2F0093B5A89F22F27371C8CD9FD59DB018834C757BF4`。

正式提交为`aaac3be`，标签为`national-finals-route1-424LUT-471FF-6DSP-3BRAM-2MMCM`。更完整的Stop/Go过程见 [Route 1 优化记录](results/route1_unified_engine_progress.md)。

### 0.1 第八轮：CIC 串行 comb 从 DSP48 迁移到 LUT CARRY4

Route 1 的 6 个 DSP 分配为：Stage1 1 个、Stage2/3 共享 1 个、CIC 三级串行 comb 1 个、CIC 三级高速 integrator 3 个。本轮保持两个 FIR DSP 和三个每拍更新的积分器 DSP 不变，只把低采样率 comb 的一条 23-bit 减法器迁移到 LUT 进位链。comb 每个 8x 输入有 16 个 128x 主时钟周期可用，原本已经在三个周期内依次完成三级有限差分，因此该映射不增加延迟、不改变 burst 协议，也不改变任何加减法位宽或模运算结果。

为避免 GUI 与脚本再次出现参数不一致，映射选择从板级顶层贯通到 CIC 内核，并在 XPR 中显式固定：

```text
USE_NATIONAL_FINALS_SERIAL_CIC_COMB = 1
USE_NATIONAL_FINALS_CIC_COMB_DSP   = 0
```

综合后为 `448 LUT / 469 FF / 5 DSP / 3 BRAM Tile`；完整布局布线后为 **436 LUT / 471 FF / 181 Slice / 5 DSP / 3 BRAM Tile / 2 MMCM**。与 Route 1 比较：LUT `424 -> 436`（+12），FF 保持 471，Slice `188 -> 181`（-7），DSP `6 -> 5`（-1），BRAM/MMCM 保持 `3/2`，vectorless 功耗仍为 0.271 W。DSP 原语清单严格为两颗 FIR DSP 和三颗 CIC integrator DSP，已确认 comb 不再占 DSP。

验证结果：全国赛 XSim 回归 10/10 PASS；CIC 连续、停顿和 burst 中复位共 3840 点等价；4x/8x/128x impulse 与固定随机逐点 0 LSB；8 个内部状态复位场景与 10 次动态倍率切换通过；六工况 MATLAB 频响和严格线性相位全部 PASS。最终 WNS/TNS 为 **+45.662/0 ns**，WHS/THS 为 **+0.116/0 ns**，setup/hold 失败端点均为 0；1329/1329 个可布线网络全部完成，routing error=0，DRC Error/Critical Warning=0。bitstream SHA-256 为 `B344EB816AF39F0F0C14DCFCEAF9F0735E94EEDF509116BC68569BB0938C8F17`。

本轮之前还实际实现了“Stage1/2/3 三段 FIR 共用一颗 DSP”的原型。总超周期估算曾给出 117/128 拍，但 XSim 和局部截止期复核表明 Stage1 必须在相邻 2x 相位之间的 64 拍内完成；同一窗口最低需要 `Stage1 27 + Stage2 19 + Stage3 26 = 72` 拍，确定超出 8 拍。该路线已作为 No-Go 保留在提交 `354b890`，不能作为板级候选；详情见 [共享 FIR MAC No-Go 记录](results/shared_fir_mac_v1_nogo.md)。

## 1. 完成状态

- [x] 44.1 kHz / 48 kHz、signed 24 bit 输入数据通路
- [x] 4x / 8x / 128x 三档正式输出
- [x] 10 Hz～20 kHz、±0.05 dB、阻带不低于 70 dB、严格线性相位
- [x] MATLAB 浮点搜索和六工况验证
- [x] MATLAB/RTL bit-true 向量生成
- [x] RTL 单元、时钟、键盘、板级集成和全链路仿真
- [x] Vivado 2018.3 综合、布局布线、时序、DRC、功耗与 bitstream
- [ ] 实物 FPGA 下载、DA_CLK 示波器测量和 DAC 频谱验收

## 2. 低资源共享架构

```text
24 bit PCM
   |
   +-> 105 tap 严格半带 2x -> 17 tap 2x -> 11 tap 平坦 2x
                                |              |
                                +-- 4x 输出    +-- 8x 输出
                                               |
                                               +-> [-1,10,-1]/8 移位加减均衡
                                                   -> C² -> Hold16 -> I² -> 128x 输出
```

44.1 kHz 与 48 kHz 共用同一 FIR/CIC 数据通路、DSP 和数据 BRAM，只增加两路 MMCM 与一个 `BUFGMUX_CTRL`。128x 支路的三抽头对称均衡器为

```text
y[n] = x[n-1] + (2*x[n-1] - x[n] - x[n-2]) / 8
```

它仅用加减和算术右移，不增加乘法器；4x/8x 输出保持平坦 FIR 响应。双采样率板级测试正弦也打包在同一个 256×24 bit ROM 中。

第七轮434-LUT基线布局布线后为 **434 LUT / 469 FF / 190 Slice / 6 DSP / 3 BRAM / 2 MMCM**。相对最初指定的573 LUT / 621 FF / 255 Slice / 6 DSP CIC基线，减少139 LUT、152 FF和65 Slice；Route 1和第八轮是后续历史资源点。完成 P1 标度修复和 P3 工程闭环后，P4-A 以 N3 Hold 降至4 DSP，P4-B 再把历史存储从3降至2 BRAM Tile；P4-C 删除板级不可达队列、启用当前结构有效的 DSP48 预加器并收紧 CIC 状态，当前默认 post-route 为 **479 LUT / 468 FF / 198 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**。

### 2.1 第七轮434-LUT基线优化方法

```text
24-bit PCM，44.1/48 kHz
  -> 105-tap 严格半带 FIR 2x
  -> 17-tap FIR 2x
  -> 11-tap 平坦 FIR 2x
  -> [-1,10,-1]/8 移位加减均衡
  -> CIC16，N=3
  -> 4x / 8x / 128x
```

资源压缩方法归纳如下：

1. Stage1 利用严格半带零系数和线性相位对称性，以一颗 DSP 串行完成有效抽头；Stage2/3 再时分复用一颗 DSP。
2. Route 1及此前版本让CIC三级comb在三个空闲周期内复用一颗DSP，三级integrator使用三颗DSP，总量为`1 + 1 + 1 + 3 = 6`；第八轮保持调度不变，仅把comb减法迁入LUT/CARRY4，总量改为`1 + 1 + 0 + 3 = 5`。
3. Stage1 与 Stage2/3 直接使用 DSP48E1 PREG 保存 `M+P` 累加状态，取消外部宽位累加器和结果寄存器。
4. Stage1 的 41-bit 累加宽度由系数绝对值和的最坏界证明；Stage2/3 保持 38-bit 通用累加宽度。
5. 第五轮 Q15 舍入将 DSP C 输入固定为 16383，仅在非负结果时通过 `CARRYIN` 再加 1，精确等价于原来的非负 `+16384`、负数 `+16383`，同时删除宽常数选择器。
6. 平坦 Stage3 的系数绝对值和为 22926，20-bit 输入下 MAC 绝对值满足 `22926 × 2^19 < 2^34`；因此 signed 35-bit 视图足够，Q15 输出必然落在 signed 20-bit 内，可删除不可能触发的饱和比较/选择器。
7. 三级 comb 历史统一为 22 bit 并轮转，让 DSP 输入始终读取固定历史寄存器，删除 23-bit 三选一宽复用器。
8. P4-B 中 Stage1 历史使用单 RAMB18E1 串行双读，Stage2/3 历史按 bank 合并为另一个 RAMB18E1；加上统一系数和测试 ROM，全机使用 4 个 RAMB18E1，即 2 个 BRAM Tile。
9. CIC 前的 `[-1,10,-1]/8` 均衡器只使用加减和算术右移，不增加 DSP；当前版无损保留 21-bit 自然峰值余量，并把 20-bit 饱和统一后移到 CIC 最终输出量化器，避免中间重复削顶逻辑。
10. 正式综合/实现配置为 `AreaOptimized_high + rebuilt + ResourceSharing=on + opt_design Default`，并由 GUI 原生工程和独立脚本两条流程交叉复现。
11. 均衡器单元测试同时实例化 20-bit 兼容输出与 21-bit 余量输出，对 2009 组含正负满量程样本分别检查饱和结果和未削顶精确结果。

Stage1 DSP48 预加器经过 A/B 综合后明确淘汰：开启时为 491 个综合 LUT，关闭并使用织构对称预加时为 469 个综合 LUT。因此当前结构是“织构预加 + DSP 乘法/PREG MAC”，不能再描述为已启用 DSP48 预加器。

### 2.2 第六轮：最终积分状态吸收到 DSP48 内部寄存器

第五轮已经让前两个 CIC 积分状态采用同步复位，但最终积分状态仍和输出/控制一起使用异步复位，因此占用 32 个 Slice FF。第六轮只把这个**内部、不可见**的最终积分状态移入同步复位进程；`y_out`、`y_out_valid`、burst/comb 控制仍保持原异步复位。板级复位会持续多个音频时钟，三组积分状态都能在释放前可靠清零。

Vivado routed checkpoint 的 DSP48 属性核查表明，新增状态实际进入最终积分器 DSP48E1 的 A/B 输入寄存器（`AREG=1, BREG=1`），不是 PREG。综合由 `459 LUT / 464 FF` 变为 `459 LUT / 432 FF`；布局布线后是 `442 LUT / 432 FF / 194 Slice`，相对第五轮 440-LUT 版少 32 FF、多 2 LUT 和 3 Slice；相对第七轮434-LUT版少37 FF、多8 LUT和4 Slice，故将其作为低FF Pareto版本保留。

| 实现策略 | LUT | FF | Slice | DSP | WNS / WHS | 结论 |
|---|---:|---:|---:|---:|---:|---|
| Default | **442** | **432** | 194 | 6 | +45.617 / +0.106 ns | 本分支默认 |
| AddRemap | **442** | **432** | 194 | 6 | +45.617 / +0.106 ns | 与 Default 无面积收益 |
| ExploreArea | 460 | **432** | **180** | 6 | +46.038 / +0.135 ns | 仅 Slice 优先时有意义 |

本轮其余 Stop/Go 候选均未混入正式 RTL：

- 均衡器复用串行 comb DSP：9/9 RTL 通过，但综合为 490 LUT / 453 FF，回退。
- 两处级间算术截位：综合为 454 LUT / 426 FF，但旧 golden 冲激有 1412 点不一致，回退。
- BRAM 上电 scrub：9/9 RTL 通过，但历史存储不再推断为 BRAM，综合恶化为 615 LUT / 517 FF / 1 BRAM Tile，回退。
- 把最终状态拆成独立同步进程：仍为 459 LUT / 432 FF，与合并进程无差别，不继续实现。

因此第六轮没有宣称“全面优于”440-LUT 版；在第七轮完成后，比赛若按 LUT 为第一目标使用 434/469，若总寄存器或 FF 权重更高可使用 442/432。各正式 bitstream 均保留为明确回退点。

### 2.3 第七轮：21-bit 均衡余量后移

对任意 signed 20-bit 的 `x[n]、x[n-1]、x[n-2]`，均衡器
`x[n-1] + (2*x[n-1]-x[n]-x[n-2])/8` 的精确范围可由 signed 21 bit 完整表示。当前版将均衡输出和 CIC 输入加宽为 21 bit，不再在两者之间先做一次 20-bit 饱和；CIC 最终输出仍按原规则舍入、饱和为 20 bit。均衡器由 60 LUT 降到 41 LUT，整机综合为 452 LUT / 469 FF，布局布线为 **434 LUT / 469 FF / 190 Slice**。

本轮 9/9 RTL 回归、六工况 MATLAB 频响、完整实现、时序、DRC 与 bitstream 均通过。`ExploreArea` 可降到 177 Slice，但会增加到 468 LUT，因此最低 LUT 正式流程继续使用 `Default`。

## 3. 正式 RTL 冲激指标

以下数据直接来自 XSim 导出的最终 RTL 冲激响应，不是只分析浮点系数。

| 输入采样率 | 输出 | 通带最大绝对偏差 | 通带峰峰值 | 阻带衰减 | 冲激对称误差 | 判定 |
|---:|---:|---:|---:|---:|---:|---|
| 44.1 kHz | 4x / 176.4 kHz | 0.004610 dB | 0.005703 dB | 78.669 dB | 0 LSB | PASS |
| 44.1 kHz | 8x / 352.8 kHz | 0.005395 dB | 0.006174 dB | 78.562 dB | 0 LSB | PASS |
| 44.1 kHz | 128x / 5.6448 MHz | 0.006116 dB | 0.008056 dB | 72.331 dB | 0 LSB | PASS |
| 48 kHz | 4x / 192 kHz | 0.004610 dB | 0.005703 dB | 78.669 dB | 0 LSB | PASS |
| 48 kHz | 8x / 384 kHz | 0.005395 dB | 0.005719 dB | 78.562 dB | 0 LSB | PASS |
| 48 kHz | 128x / 6.144 MHz | 0.006116 dB | 0.006116 dB | 72.331 dB | 0 LSB | PASS |

所有六工况均满足 ±0.05 dB 和 70 dB 门槛，冲激响应逐点严格对称，拟合相位残差最大约 `1.42e-13 rad`。

![最终 RTL 六工况频响](figures/nf_rtl_impulse_response.png)

详细数值见 [nf_rtl_impulse_summary.txt](results/nf_rtl_impulse_summary.txt)。

## 4. RTL 回归结果

| 测试 | 覆盖内容 | 结果 |
|---|---|---|
| ROM | 双采样率数据、回卷、同步复位 | PASS |
| 统一系数 RAMB18E1 原语 | A/B 双端口共 96 个地址逐点核对 | PASS |
| Stage 1 单 BRAM 等价 | 新旧核 1400 个输出、valid 和数据逐拍比较 | PASS，0 LSB |
| Stage 2/3 统一历史 | Stage 2/3 分别比较 336/671 个输出 | PASS，0 LSB |
| 移位加减均衡器 | 2009 个定向样本 | PASS |
| 串行 comb CIC 等价性 | 连续、停顿、burst 中复位和 3840 个输出 | PASS |
| N3 Hold CIC 等价性 | 连续320、停顿480、复位中断，共7680输出 | PASS，0 LSB |
| MMCM/BUFGMUX | 双频率、往返切换、无 runt 高脉冲 | PASS |
| 模式 CDC 握手 | 1200 次全方向事务，原子提交和逐次 ACK | PASS |
| 矩阵键盘 | SW1～SW8 家族/倍率映射 | PASS |
| 板级顶层 | 上电复位、共享扫描、SW2、SW6、保护切换 | PASS |
| 全链路 bit-true | impulse + 固定种子随机 PCM；4x/8x/128x | PASS，0 LSB |
| 全链路复位恢复 | 8 个内部状态场景，每场景比较 4096 个 128x 输出 | PASS，8/8 |
| 动态倍率切换 | 不复位连续切换 10 次；检查 runt、X、锁死和冻结 | PASS，10/10 |

P4-B 最终发布回归目录为 `_work/rtl_regression/20260801_022831`。十四项测试全部通过；所有逐点比较节点无 X、无丢样、无数值失配。P4-B 详细证据见 [单 BRAM 签核](results/p4b_single_bram_4dsp_summary.md)，历史证据摘要见 [nf_rtl_regression_summary.txt](results/nf_rtl_regression_summary.txt)。

一键重跑：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1 `
  -PublishImpulseOutputs
```

脚本每次使用新的 `matlab_fir/national_finals/_work/rtl_regression/<时间戳>` 空编译目录，任一 PASS 标志缺失或工具退出码非零都会终止。Vivado/XSim 的 `.Xil`、`xsim.dir`、journal 和 log 均留在 `_work` 内，不会写入项目根目录。

## 5. Vivado 实现签核

器件：`XC7A35T-FGG484-2`，顶层：`board_demo_competition_dac8_top`。

| 项目 | 结果 |
|---|---:|
| Slice | 202 / 8150（2.48%） |
| Slice LUT | 504 / 20800（2.42%） |
| Slice register | 493 / 41600（1.19%） |
| BRAM tile | 2 / 50（4.00%，4 RAMB18E1） |
| DSP48E1 | 4 / 90（4.44%） |
| BUFGCTRL / MMCM | 2 / 2 |
| WNS / TNS | +45.637 ns / 0 ns |
| WHS / THS | +0.119 ns / 0 ns |
| setup / hold 失败端点 | 0 / 0（总端点各 1715） |
| 路由错误 | 0，1285 个可布线网络，Fully Routed |
| DRC Error | 0 |
| Vectorless 功耗 | 0.271 W（动态 0.199 W，静态 0.072 W，Medium confidence） |

Vivado DRC 报告共有 7 条 Warning 和 1 条 Advisory，均为面积优先 DSP 未加输入/输出流水的性能建议；Error 为 0。当前时序余量很大、路由完整且 bitstream 已成功生成；这些警告不是“已物理验证”的替代品，首次上板仍要重点检查复位和采样率切换。

本轮签核摘要见 [p4b_single_bram_4dsp_summary.md](results/p4b_single_bram_4dsp_summary.md)，完整原始报告见 [board_dual_rate_p4b2_bram2_v1](vivado_results/board_dual_rate_p4b2_bram2_v1)。

bitstream：

```text
matlab_fir/national_finals/vivado_results/board_dual_rate_p4b2_bram2_v1/
national_finals_dual_rate_4x8x128x_areaopt.bit
```

SHA-256：`DA0665E43A8DA5230AB93FC786AB0EED47BD83FE393C9B1416BA3360B8DE5E85`

### 5.1 P4-B 单 BRAM / 4-DSP Pareto 版签核

综合阶段为 `525 LUT / 499 FF / 4 DSP / 4 RAMB18E1`；布局布线后收敛为 `504 LUT / 493 FF / 202 Slice`。4 个 RAMB18E1 的原语层级严格对应测试 ROM、Stage 1 历史、Stage 2/3 统一历史和统一 FIR 系数，证明 BRAM Tile 的下降不是统计或 GUI 参数差异。相对 P4-A，LUT/FF/Slice 分别增加 13/49/5，BRAM Tile 减少 1，WNS/WHS 仍为正，功耗报告精度下不变。

该结构已经通过 Stage 1、Stage 2/3 和 CIC 三层独立等价测试，再通过完整链、复位和动态模式回归；不是仅凭频响近似接受。P4-A 与 P4-B 的详细对照和现场待办见 [P4-B 签核](results/p4b_single_bram_4dsp_summary.md)。

### 5.2 第八轮 5-DSP comb-LUT Pareto 版签核（历史标度缺陷版本）

Route 1 的 6 个 DSP 为 `Stage1 1 + Stage2/3 共享 1 + CIC comb 1 + CIC integrator 3`。本轮把每个 8x 输入仅执行三次、并且相邻事务之间有 16 个主时钟余量的 23-bit comb 减法放回 LUT/CARRY4；三个在 128x 输出阶段每拍更新的宽积分器仍放在 DSP48E1，形成 `1 + 1 + 0 + 3 = 5 DSP`。

与 Route 1 的最终实现相比，新版为 **436 LUT / 471 FF / 181 Slice / 5 DSP**：增加 12 LUT、FF 不变、减少 7 Slice和1 DSP；BRAM/MMCM/IO与0.271 W功耗不变。该版本保持全部滤波系数和数值路径，故六工况频响与 Route 1 完全相同。完整 Stop/Go、RTL、Timing、DRC 和 bitstream 证据见 [5-DSP 优化签核](results/cic5_comb_lut_optimization_summary.md)。

### 5.3 五轮 6-DSP CIC 优化结果

第一轮固定同一个综合 DCP 对五个 `opt_design` 指令进行了完整实现扫描；第二轮继续压缩宽位复用器、字长和调度状态；第三轮消除 Stage2/3 DSP C 输入前的零/累加器宽复用器；第四轮让 Stage1 和 Stage2/3 的 DSP48E1 PREG 直接保存累加结果，并利用空闲提交周期完成精确 Q15 舍入。每个最终候选均完成布局布线、时序和 DRC，选中的 Default 版本另外生成并校验 bitstream：

| 候选 | LUT | FF | Slice | DSP | WNS / WHS | 结论 |
|---|---:|---:|---:|---:|---:|---|
| 原 6-DSP 基线，ExploreArea | 573 | 621 | 255 | 6 | +46.339 / +0.072 ns | 对照 |
| 基线 RTL，Default | **556** | 621 | 229 | 6 | +45.294 / +0.092 ns | 策略最低 LUT |
| DSP PREG，Default | **556** | 557 | 231 | 6 | +45.936 / +0.106 ns | 最低 LUT 候选 |
| DSP PREG + 组合交接，Default | 557 | 536 | 228 | 6 | +45.614 / +0.105 ns | 上一轮正式版 |
| 第二轮 RTL，Explore | **528** | **532** | **229** | **6** | **+45.075 / +0.078 ns** | 与 Default 同资源 |
| 第二轮 RTL，AddRemap | **528** | **532** | **229** | **6** | **+45.075 / +0.078 ns** | 与 Default 同资源 |
| 第二轮 RTL，Default | 528 | 532 | 229 | 6 | +45.075 / +0.078 ns | 上一正式版本 |
| 第三轮 RTL，Explore | **487** | **532** | **205** | **6** | **+46.420 / +0.105 ns** | 与 Default 同资源 |
| 第三轮 RTL，AddRemap | **487** | **532** | **205** | **6** | **+46.420 / +0.105 ns** | 与 Default 同资源 |
| 第三轮 RTL，Default | **487** | **532** | **205** | **6** | **+46.420 / +0.105 ns** | 上一正式版本 |
| 第四轮 RTL，ExploreArea | 472 | **464** | **194** | **6** | **+46.367 / +0.152 ns** | Slice 最低 |
| 第四轮 RTL，AddRemap | **461** | **464** | 199 | **6** | **+45.405 / +0.114 ns** | 与 Default 同资源 |
| 第四轮 RTL，Default | **461** | **464** | **199** | **6** | **+45.405 / +0.114 ns** | 上一正式版本 |
| 第五轮 `CARRYIN`，Default | 451 | 464 | - | 6 | +45.647 / +0.140 ns | 中间候选 |
| 第五轮 `CARRYIN`，AddRemap | 451 | 464 | - | 6 | +45.647 / +0.140 ns | 与 Default 同 LUT |
| 第五轮 `CARRYIN`，ExploreArea | 475 | 464 | - | 6 | +46.154 / +0.099 ns | No-Go |
| 第五轮 Stage3 证明字长，Default | 440 | 464 | 191 | 6 | +46.046 / +0.127 ns | 440-LUT 锚点 |
| **第七轮 21-bit 余量，Default** | **434** | **469** | **190** | **6** | **+45.539 / +0.108 ns** | **Route 1之前的最低LUT回退版本** |
| 第七轮 21-bit 余量，ExploreArea | 468 | 469 | **177** | 6 | +46.357 / +0.095 ns | Slice 更低但 LUT 增加，不采用 |

第七轮版本综合后为452 LUT / 469 FF，`opt_design`后布局布线结果进一步收敛到434 LUT / 469 FF。第五轮的`CARRYIN`中间候选上，Default与AddRemap均为451 LUT，ExploreArea为475 LUT；第七轮同一DCP的ExploreArea为468 LUT，因此当时选择LUT最低且流程最简单的`Default`。累计保留的结构优化是：

1. 两个隐藏 CIC 积分状态采用 DSP48E1 PREG 原生同步复位；所有外部可见控制、最终状态、valid 和输出仍保持异步复位，并已通过 8 个复位恢复场景。
2. 仅在串行 CIC 模式下取消均衡器冗余输出寄存器，由 CIC 输入事务直接捕获组合结果；均衡器默认的寄存输出兼容接口没有改变。
3. 串行 CIC 的三级 comb 历史统一为 22 bit，并在三个 comb 周期中轮转，使 DSP 输入固定读取第 0 级历史，消除了原 23 bit 三选一宽位复用器。该模块由 44 LUT / 136 FF 降到 18 LUT / 138 FF；增加 2 个 FF，换得 26 个 LUT。
4. CIC 的 16 拍 burst 剩余计数由 5 bit 收窄为 4 bit，`burst_pending` 继续单独表示首拍，因此 16 个输出的协议没有改变。
5. Stage1 累加器由 42 bit 收窄到 41 bit。26 个非零系数绝对值之和为 44756，最坏界 `2^24 × 44756 = 750881079296`，小于 signed 41 bit 正上限 `2^40-1 = 1099511627775`，因此不会溢出；默认兼容配置仍保留 42 bit。
6. Stage2/3 调度状态由 2 bit 的级号压成 1 bit `job_stage3`，固定 MAC 次数改为由级号和相位组合生成，不再保存 4 bit `job_mac_count`。
7. 每个 Stage2/3 MAC 任务开始时调度器已经清零 `acc_reg`，所以首抽头无需再以 `job_mac_index==0` 选择常数 0。DSP48E1 C 输入恒接累加器、OPMODE 恒为 M+C，消除了 ACC_W 级零/累加器复用器；独立 Stage2/3 等价测试分别比较 336/671 个输出，误差均为 0 LSB。
8. Stage1 和共享 Stage2/3 取消外部宽位累加器与结果寄存器，直接用 DSP48E1 PREG 通过 `M+P` 保存串行 MAC 状态。正式最低 LUT 配置由织构完成对称样本预加；显式 DSP48 预加器候选综合为 491 LUT，劣于关闭时的 469 LUT，因此不采用。
9. MAC 结束后的空闲提交周期在 DSP 内加入精确 Q15 舍入偏置：C 端恒为 16383，非负结果再通过 `CARRYIN` 加 1。移位、饱和和输出协议不变，同时删除符号驱动的宽常数选择器。
10. 新时延会与下一次 Stage3 写入重叠，因此任务启动时锁存环形历史 `head/fill`；完整链回归曾真实捕获这一问题。修正后进一步把 Stage2/3 两组读头选择器合并为共享 `history_read_head`，9/9 回归恢复 0 LSB。
11. 全国赛平坦 Stage3 的最大系数绝对值和为 22926；20-bit 输入下 MAC 绝对值小于 `22926 × 2^19 = 12019810304 < 2^34`，带符号 35-bit 视图足够，Q15 舍入结果必然落在 signed 20-bit 范围内。由此删除不可能触发的 Stage3 饱和比较/选择器，最终再减少 11 LUT。
12. 均衡器将 21-bit 精确结果直接交给 21-bit CIC 输入，删除中间 20-bit 饱和选择器；CIC 最终 `OUTPUT_W=20` 量化器仍保留原舍入和饱和语义。该变化由 2009 组宽/窄双输出单元测试、整链 0 LSB 回归和六工况频响共同验证。

淘汰项也进行了真实综合或仿真：均衡运算融合进串行 comb DSP 为 581 LUT / 622 FF；改为共享 Stage2/3 DSP 的版本在修正 signed 系数扩展后虽 0 LSB 通过，但综合为 592 LUT / 558 FF；早期只替换 Stage1 预加器、未让 PREG 保存累加状态的方案为 586 LUT / 578 FF；本轮在现有 PREG 结构上再次开启 DSP48 预加器，综合仍由 469 增至 491 LUT；把 pending 合并进 burst 计数则在第 16 个样点破坏等价性。其余 Stage2/3 BRAM 微码、Stage1 直接舍入、24 bit 结果寄存器和均衡器位宽收窄也均按 Stop/Go 淘汰。完整策略数据见 [cic6_implementation_strategy_scan.csv](results/cic6_implementation_strategy_scan.csv)，优化记录见 [cic6_further_optimization_summary.txt](results/cic6_further_optimization_summary.txt)。

### 5.4 第六轮低 FF Pareto 版签核

以下数据来自 `board_dual_rate_cic6_round6_preg_opt` 的最终 routed 报告，不是综合估算：

| 项目 | 第五轮最低 LUT 版 | 第六轮低 FF 版 | 变化 |
|---|---:|---:|---:|
| Slice LUT | 440 | **442** | +2 |
| Slice register | 464 | **432** | **-32** |
| Slice | 191 | **194** | +3 |
| DSP48E1 | 6 | **6** | 0 |
| BRAM tile | 3 | **3** | 0 |
| MMCM | 2 | **2** | 0 |
| WNS / WHS | +46.046 / +0.127 ns | **+45.617 / +0.106 ns** | 均无违例 |
| TNS / THS | 0 / 0 ns | **0 / 0 ns** | 0 |
| Vectorless 功耗 | 0.271 W | **0.271 W** | 报告精度下不变 |

最终实现 1300/1300 个网络全部完成，routing error 为 0；DRC 为 34 条 Warning、1 条 Advisory、**0 Error**。这些提示仍是面积优先 DSP 未加输入/输出流水、动态 OPMODE 以及 BRAM 异步控制检查，不影响 bitstream 生成，但首次上板仍须执行本文的复位和家族切换检查。

bitstream：

```text
matlab_fir/national_finals/vivado_results/board_dual_rate_cic6_round6_preg_opt/
national_finals_dual_rate_4x8x128x_areaopt.bit
```

SHA-256：`49DF03B71C6D73A73EE282A5D1EEE0D9F5EB91ADDB96879ACBA381F0D999D47C`

本版本已通过最终 9/9 XSim、六组 MATLAB RTL 冲激验收、从头综合、布局布线、时序、DRC、功耗报告和 bitstream 生成；**尚未在实物板下载复测**。

详细记录见 [cic6_round6_ff_optimization_summary.txt](results/cic6_round6_ff_optimization_summary.txt) 和 [cic6_round6_strategy_scan.csv](results/cic6_round6_strategy_scan.csv)。

### 5.5 GUI 资源不一致问题与修复

此前 GUI 显示 **482 LUT / 542 FF / 8 DSP**，不是 461-LUT 报告测错，而是 `.xpr` 只启用了 `USE_NATIONAL_FINALS_DATAPATH=1`，没有启用串行 comb CIC、全国赛 Stage2/3 窄系数和综合资源共享；GUI 因而综合了旧的 8-DSP 并行 CIC。工程文件现已显式登记串行 CIC 源文件并固定以下配置：

- `USE_NATIONAL_FINALS_SERIAL_CIC_COMB=1`
- `USE_NATIONAL_FINALS_N3_HOLD_EQUIV=1`
- `USE_NATIONAL_FINALS_CIC_COMB_DSP=0`
- `USE_NATIONAL_FINALS_NARROW_STAGE23=1`
- `USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1=1`
- `USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY=1`
- `USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER=0`
- `ResourceSharing=on`
- `opt_design Directive=Default`

第五轮用普通工程 `synth_1/impl_1` 从头重建得到 440 LUT / 464 FF；第七轮在同一工程配置和更新后的 RTL 上从头重建为 **434 LUT / 469 FF / 6 DSP / 3 BRAM Tile / 2 MMCM**。随后 comb-LUT 历史版为 **436 LUT / 471 FF / 5 DSP / 3 BRAM Tile / 2 MMCM**。当前 XPR 已进一步固定 N3 Hold、Stage 1 单 RAM、Stage 2/3 统一历史、Stage1 DSP48 预加器和 CIC 4-DSP 默认映射，正式签核为 **479 LUT / 468 FF / 4 DSP / 2 BRAM Tile / 2 MMCM**。可用以下命令检查配置并重建：

```powershell
vivado.bat -mode batch -source `
  .\matlab_fir\national_finals\vivado\verify_national_finals_gui_project.tcl `
  -tclargs rebuild
```

## 6. MATLAB 与 Vivado 复现

MATLAB：

```matlab
cd('D:/FpgaProject/XilinxProject/XC7A35T/fir_interpolation/matlab_fir/national_finals');
run('nf_01_search_shared_cic_equalizer.m');
run('nf_02_generate_dual_rate_rom.m');
run('nf_03_generate_bittrue_vectors.m');
% 先运行 RTL 回归并发布 impulse CSV，再执行：
run('nf_04_analyze_rtl_impulse.m');
```

Vivado 2018.3 一键综合、实现和 bitstream：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1 `
  -Step all
```

包装脚本先执行面积优化综合，再以低内存单进程完成布局布线、报告和 bitstream。默认实现指令是本轮复核后的 `Default`；P4-C 三个正式目录为 `vivado_results/p4c_signed_479lut_468ff_4dsp_2bram`、`p4c_signed_3dsp_2bram` 和 `p4c_signed_2dsp_2bram`，P4-B、P4-A、P3、Route 1及此前回退结果仍保留。日志与 `.Xil` 均写入 `matlab_fir/national_finals/_work/<tool>/<时间戳>`，不会污染项目根目录。

需要使用 Vivado GUI 时，不要从仓库根目录直接运行 `vivado.bat`，也不要依赖双击 `.xpr` 的当前工作目录。使用以下入口可把 GUI 的 `.Xil`、journal 和 log 隔离到 `national_finals/_work/vivado_gui/<时间戳>`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\vivado\open_national_finals_gui_clean.ps1
```

## 7. SW1～SW8 与预期 DA_CLK

板载 15 kHz、0.5FS、signed 24 bit 测试音用于直观验收。1x 是保留的诊断档，正式赛题输出为 4x/8x/128x。

| 按键 | 家族 | 模式 | 理论/实现 DA_CLK |
|---|---:|---:|---:|
| SW1 | 44.1 kHz | 1x 诊断 | 44,099.972 Hz |
| SW2 | 44.1 kHz | 4x | 176,399.887 Hz |
| SW3 | 44.1 kHz | 8x | 352,799.774 Hz |
| SW4 | 44.1 kHz | 128x | 5,644,796.380 Hz |
| SW5 | 48 kHz | 1x 诊断 | 48,000.530 Hz |
| SW6 | 48 kHz | 4x | 192,002.119 Hz |
| SW7 | 48 kHz | 8x | 384,004.237 Hz |
| SW8 | 48 kHz | 128x | 6,144,067.797 Hz |

## 8. 实板验收清单

1. 用 Vivado Hardware Manager 下载上述 `.bit`，记录器件 ID、下载时间和 DONE 状态。
2. 上电默认应为 44.1 kHz / 128x；确认 DAC 静态中点正常，无持续满量程。
3. 依次按 SW2、SW3、SW4、SW6、SW7、SW8，用频率计或示波器测 `DA_CLK`，与上表比较；建议允许 ±0.02%。
4. 在 44.1↔48 kHz 家族切换时同时观察 `DA_CLK` 和 DAC 输出。允许受控静音/复位窗口，不允许持续毛刺时钟、锁死或满量程直流。
5. 用示波器确认 `dac_data` 在 `DA_CLK` 上升沿前稳定；当前 RTL 在音频主时钟下降沿更新 DAC 数据。
6. 用频谱仪检查六个正式档均有约 15 kHz 主音；记录主音幅度、首镜像频带和噪声底。重点验证 128x 首镜像抑制不低于 70 dB。
7. 每档至少切换 20 次并进行 10 分钟连续运行，检查无失锁、无异常啸叫、无输出冻结。
8. 如需 ILA，优先观察 `family_active`、`rst_audio_n`、`mode_state`、`selected_valid`、`dac_clk`；ILA 会改变资源与布局，最终提交仍应使用无 ILA bitstream。
9. 将六档 DA_CLK 实测值、频谱截图、板卡照片和供电电流回填到本文；全部满足后再把“实物 FPGA 验证”复选框改为 `[x]`。
