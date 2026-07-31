# 全国总决赛：双采样率可配置插值滤波器

当前版本已完成 MATLAB 建模、24 bit 定点模型、RTL、9 项 XSim 回归、Vivado 综合/布局布线/时序/DRC/功耗评估和 bitstream 生成。所有软件与 FPGA 工具验收均已通过；由于当前环境无法接触实物开发板，物理板下载和仪器测量仍需按本文最后一节执行，不能把 bitstream 成功等同于实板通过。

当前最低 LUT 正式版：`434 LUT / 469 FF / 190 Slice`，位于分支 `codex/national-finals-cic6-round7-lut-opt`；`442 LUT / 432 FF / 194 Slice` 的第六轮版本继续作为低 FF Pareto 回退点。两者均保持 6 DSP / 3 BRAM / 2 MMCM，频响和正式 RTL 逐点输出完全一致。

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
                                                   -> CIC16, N=3 -> 128x 输出
```

44.1 kHz 与 48 kHz 共用同一 FIR/CIC 数据通路、DSP 和数据 BRAM，只增加两路 MMCM 与一个 `BUFGMUX_CTRL`。128x 支路的三抽头对称均衡器为

```text
y[n] = x[n-1] + (2*x[n-1] - x[n] - x[n-2]) / 8
```

它仅用加减和算术右移，不增加乘法器；4x/8x 输出保持平坦 FIR 响应。双采样率板级测试正弦也打包在同一个 256×24 bit ROM 中。

当前正式版布局布线后为 **434 LUT / 469 FF / 190 Slice / 6 DSP / 3 BRAM / 2 MMCM**。相对最初指定的 573 LUT / 621 FF / 255 Slice / 6 DSP CIC 基线，减少 139 LUT、152 FF 和 65 Slice；相对第五轮 440 LUT / 464 FF 版再减少 6 LUT 和 1 Slice，增加 5 FF。DSP、BRAM、MMCM 以及 0.271 W Vectorless 功耗均不增加。

### 2.1 当前正式版优化方法

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
2. CIC 三级 comb 在三个空闲周期内复用一颗 DSP，三级 integrator 使用三颗 DSP，总 DSP 固定为 `1 + 1 + 1 + 3 = 6`。
3. Stage1 与 Stage2/3 直接使用 DSP48E1 PREG 保存 `M+P` 累加状态，取消外部宽位累加器和结果寄存器。
4. Stage1 的 41-bit 累加宽度由系数绝对值和的最坏界证明；Stage2/3 保持 38-bit 通用累加宽度。
5. 第五轮 Q15 舍入将 DSP C 输入固定为 16383，仅在非负结果时通过 `CARRYIN` 再加 1，精确等价于原来的非负 `+16384`、负数 `+16383`，同时删除宽常数选择器。
6. 平坦 Stage3 的系数绝对值和为 22926，20-bit 输入下 MAC 绝对值满足 `22926 × 2^19 < 2^34`；因此 signed 35-bit 视图足够，Q15 输出必然落在 signed 20-bit 内，可删除不可能触发的饱和比较/选择器。
7. 三级 comb 历史统一为 22 bit 并轮转，让 DSP 输入始终读取固定历史寄存器，删除 23-bit 三选一宽复用器。
8. Stage1 历史、Stage2/3 历史/系数以及双采样率测试 ROM 使用 6 个 RAMB18E1，即 3 个 BRAM Tile。
9. CIC 前的 `[-1,10,-1]/8` 均衡器只使用加减和算术右移，不增加 DSP；当前版无损保留 21-bit 自然峰值余量，并把 20-bit 饱和统一后移到 CIC 最终输出量化器，避免中间重复削顶逻辑。
10. 正式综合/实现配置为 `AreaOptimized_high + rebuilt + ResourceSharing=on + opt_design Default`，并由 GUI 原生工程和独立脚本两条流程交叉复现。
11. 均衡器单元测试同时实例化 20-bit 兼容输出与 21-bit 余量输出，对 2009 组含正负满量程样本分别检查饱和结果和未削顶精确结果。

Stage1 DSP48 预加器经过 A/B 综合后明确淘汰：开启时为 491 个综合 LUT，关闭并使用织构对称预加时为 469 个综合 LUT。因此当前结构是“织构预加 + DSP 乘法/PREG MAC”，不能再描述为已启用 DSP48 预加器。

### 2.2 第六轮：最终积分状态吸收到 DSP48 内部寄存器

第五轮已经让前两个 CIC 积分状态采用同步复位，但最终积分状态仍和输出/控制一起使用异步复位，因此占用 32 个 Slice FF。第六轮只把这个**内部、不可见**的最终积分状态移入同步复位进程；`y_out`、`y_out_valid`、burst/comb 控制仍保持原异步复位。板级复位会持续多个音频时钟，三组积分状态都能在释放前可靠清零。

Vivado routed checkpoint 的 DSP48 属性核查表明，新增状态实际进入最终积分器 DSP48E1 的 A/B 输入寄存器（`AREG=1, BREG=1`），不是 PREG。综合由 `459 LUT / 464 FF` 变为 `459 LUT / 432 FF`；布局布线后是 `442 LUT / 432 FF / 194 Slice`，相对第五轮 440-LUT 版少 32 FF、多 2 LUT 和 3 Slice；相对当前 434-LUT 版少 37 FF、多 8 LUT 和 4 Slice，故将其作为低 FF Pareto 版本保留。

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
| 44.1 kHz | 8x / 352.8 kHz | 0.005495 dB | 0.006274 dB | 78.161 dB | 0 LSB | PASS |
| 44.1 kHz | 128x / 5.6448 MHz | 0.006918 dB | 0.008111 dB | 72.348 dB | 0 LSB | PASS |
| 48 kHz | 4x / 192 kHz | 0.004610 dB | 0.005703 dB | 78.669 dB | 0 LSB | PASS |
| 48 kHz | 8x / 384 kHz | 0.005495 dB | 0.005738 dB | 78.161 dB | 0 LSB | PASS |
| 48 kHz | 128x / 6.144 MHz | 0.006918 dB | 0.006917 dB | 72.348 dB | 0 LSB | PASS |

所有六工况均满足 ±0.05 dB 和 70 dB 门槛，冲激响应逐点严格对称，拟合相位残差最大约 `1.42e-13 rad`。

![最终 RTL 六工况频响](figures/nf_rtl_impulse_response.png)

详细数值见 [nf_rtl_impulse_summary.txt](results/nf_rtl_impulse_summary.txt)。

## 4. RTL 回归结果

| 测试 | 覆盖内容 | 结果 |
|---|---|---|
| ROM | 双采样率数据、回卷、同步复位 | PASS |
| 移位加减均衡器 | 2009 个定向样本 | PASS |
| 串行 comb CIC 等价性 | 连续、停顿、burst 中复位和 3840 个输出 | PASS |
| MMCM/BUFGMUX | 双频率、往返切换、无 runt 高脉冲 | PASS |
| 矩阵键盘 | SW1～SW8 家族/倍率映射 | PASS |
| 板级顶层 | 上电复位、共享扫描、SW2、SW6、保护切换 | PASS |
| 全链路 bit-true | impulse + 固定种子随机 PCM；4x/8x/128x | PASS，0 LSB |
| 全链路复位恢复 | 8 个内部状态场景，每场景比较 4096 个 128x 输出 | PASS，8/8 |
| 动态倍率切换 | 不复位连续切换 10 次；检查 runt、X、锁死和冻结 | PASS，10/10 |

第六轮最终一次发布回归目录为 `_work/rtl_regression/20260731_140213`。九项测试全部通过；所有逐点比较节点无 X、无丢样、无数值失配。证据摘要见 [nf_rtl_regression_summary.txt](results/nf_rtl_regression_summary.txt)。

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
| Slice | 190 / 8150（2.33%） |
| Slice LUT | 434 / 20800（2.09%） |
| Slice register | 469 / 41600（1.13%） |
| BRAM tile | 3 / 50（6.00%） |
| DSP48E1 | 6 / 90（6.67%） |
| BUFGCTRL / MMCM | 2 / 2 |
| WNS / TNS | +45.539 ns / 0 ns |
| WHS / THS | +0.108 ns / 0 ns |
| 路由错误 | 0，1348/1348 可布线网络全部完成 |
| DRC Error | 0 |
| Vectorless 功耗 | 0.271 W（动态 0.199 W，静态 0.072 W，Medium confidence） |

Vivado DRC 报告共有 69 条 Warning 和 1 条 Advisory，主要是面积优先结构中未加流水的 DSP 性能建议，以及 DSP/BRAM 异步控制检查。当前时序余量很大、路由完整、DRC Error 为 0 且 bitstream 已成功生成；这些警告不是“已物理验证”的替代品，首次上板仍要重点检查复位和采样率切换。

签核摘要见 [nf_hardware_signoff_summary.txt](results/nf_hardware_signoff_summary.txt)。

bitstream：

```text
matlab_fir/national_finals/vivado_results/board_dual_rate_cic6_round7_headroom_opt/
national_finals_dual_rate_4x8x128x_areaopt.bit
```

SHA-256：`8AA618986749BFDFF8A5FDBD8CF125E34F529DA1449356717B739B1E4545A0D4`

### 5.1 五轮 6-DSP CIC 优化结果

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
| **第七轮 21-bit 余量，Default** | **434** | **469** | **190** | **6** | **+45.539 / +0.108 ns** | **当前最低 LUT 正式版本** |
| 第七轮 21-bit 余量，ExploreArea | 468 | 469 | **177** | 6 | +46.357 / +0.095 ns | Slice 更低但 LUT 增加，不采用 |

当前正式版综合后为 452 LUT / 469 FF，`opt_design` 后布局布线结果进一步收敛到 434 LUT / 469 FF。第五轮的 `CARRYIN` 中间候选上，Default 与 AddRemap 均为 451 LUT，ExploreArea 为 475 LUT；第七轮同一 DCP 的 ExploreArea 为 468 LUT，因此继续选择 LUT 最低且流程最简单的 `Default`。累计保留的结构优化是：

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

### 5.2 第六轮低 FF Pareto 版签核

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

### 5.3 GUI 资源不一致问题与修复

此前 GUI 显示 **482 LUT / 542 FF / 8 DSP**，不是 461-LUT 报告测错，而是 `.xpr` 只启用了 `USE_NATIONAL_FINALS_DATAPATH=1`，没有启用串行 comb CIC、全国赛 Stage2/3 窄系数和综合资源共享；GUI 因而综合了旧的 8-DSP 并行 CIC。工程文件现已显式登记串行 CIC 源文件并固定以下配置：

- `USE_NATIONAL_FINALS_SERIAL_CIC_COMB=1`
- `USE_NATIONAL_FINALS_NARROW_STAGE23=1`
- `USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER=0`
- `ResourceSharing=on`
- `opt_design Directive=Default`

第五轮用普通工程 `synth_1/impl_1` 从头重建得到 440 LUT / 464 FF；第七轮在同一工程配置和更新后的 RTL 上从头重建为 **434 LUT / 469 FF / 6 DSP / 3 BRAM Tile / 2 MMCM**，与独立签核流程一致。可用以下命令检查配置并重建：

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

包装脚本先执行面积优化综合，再以低内存单进程完成布局布线、报告和 bitstream。默认实现指令是本轮扫描选出的 `Default`；当前分支默认结果目录为 `vivado_results/board_dual_rate_cic6_round7_headroom_opt`，第五轮 440-LUT 与第六轮低 FF 回退结果仍分别保留在原结果目录。日志与 `.Xil` 均写入 `matlab_fir/national_finals/_work/vivado/<时间戳>`，不会污染项目根目录。

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
