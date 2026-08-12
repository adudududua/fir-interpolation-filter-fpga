# 高阶数字插值滤波器设计与 FPGA 验证

### 2026-08-12：当前工程切换至 268 LUT / 2 DSP 候选

在为 239 LUT / 388 FF / 3 DSP 实板通过版创建归档提交和标签后，当前工程
`XC7A35T_interp_opt_2025.2` 已切换为 CIC 积分器 DSP 模式 0。新配置的完整板级实现为
**268 LUT / 417 FF / 2 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM**，定点规格仍为
Stage1/Stage2/Stage3=`24/20/20 bit`。RTL Smoke **17/17 PASS**；Vivado 2025.2 完整
综合、实现和 bitstream 均通过，WNS/WHS=`+44.389/+0.078 ns`，DRC Error=0。

独立构建归档位于
[active_268lut_2dsp](XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/active_268lut_2dsp)，
独立构建 bitstream SHA-256 为
`1F6DCF4A9CD81D4301AA18E6789B751873E9CA367739346F4E7E8F70E301E50B`；标准 GUI
`synth_1/impl_1` 也已从零重建为相同资源、时序和 DRC 结果，其 bitstream SHA-256 为
`7A8542EA469EB9312B0AD87F4832455337C0616575C12A4860A3D9A26C6DF92A`。该版本当前状态为
**tool-verified，待物理板验证**。

### 2026-08-12：239 LUT / 3 DSP 版本物理板验证通过

用户已确认当前 Vivado 2025.2、CIC 积分器 DSP 模式 1 的版本完成物理板验证，板级结果为
**239 LUT / 388 FF / 3 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM**，定点规格保持
Stage1/Stage2/Stage3=`24/20/20 bit`。该版本已通过 RTL Smoke **17/17**、完整综合与实现、
正时序和 0 DRC Error，并已生成可追溯 bitstream；该状态已用下述标签归档，随后当前工程
已切换至 2-DSP 候选。原 218 LUT / 365 FF / 4 DSP 实板版本保留在
`XC7A35T_interp_LUTmin_2025.2`，作为 LUT 优先的独立回退。

板测对应 bitstream 的 SHA-256 为
`796844A59E439744082A11CDBD75C4BBAA4538D598B2793310E24E6B2F0401EA`，routed DCP 的
SHA-256 为 `89F075A53ADCEC418F9E25531F6C9CE9ED12409436E4599D35666A5EF0E9E188`。归档与板测记录见
[active_239lut_3dsp](XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/active_239lut_3dsp/BOARD_PASS.md)。
正式标签为 `nf-vivado2025.2-239lut-388ff-3dsp-2bram-24-20-20-board-pass`。
本记录仅陈述用户明确确认的“239-LUT 版本板测成功”，不推定未提供的逐档仪器读数。

### 2026-08-12：3-DSP / 4-RAMB18E1 固定资源下的 LUT 压缩复测

针对 239 LUT / 388 FF / 3 DSP / 4 RAMB18E1 候选继续做了公平 A/B。综合/实现策略扫描、
两种 DSP48E1 TWO24 结构和一项共享 CARRY 结构均已实际验证；没有候选低于 239 LUT。
最接近的 `AreaOptimized_medium` 为 **241 LUT / 388 FF / 3 DSP / 4 RAMB18E1**；
TWO24 的 comb+一级积分器候选为 **260/417**，双积分器候选为 **262/393**，二者均
时序通过、DRC Error=0 且数值 0 LSB，但 LUT 更高。共享 CARRY 会在连续帧下发生吞吐冲突，
不满足每 16 个 `ce_out` 接收一帧的接口语义。

因此复测结论保留 **239 LUT / 388 FF / 3 DSP / 4 RAMB18E1**。复测阶段未改动正式
RTL/工程泛型，也未生成板测 bitstream；其后该配置已写入当前正式工程、完成完整构建，
并于 2026-08-12 经用户确认物理板验证通过。完整资源矩阵、失败原因和复现入口见
[3-DSP LUT 压缩执行反馈](matlab_fir/national_finals/results/vivado2025_2_3dsp_lut_optimization_execution_feedback.md)。
本轮生成的 Vivado 临时工程、仿真目录和时间戳原始运行目录已清理；仓库仅保留
[固定资源复测精简汇总](XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/structure_experiments/results/3dsp_lut_optimization_20260812/summary.txt)、
分析报告及复现脚本，原始运行目录需要时由脚本重新生成。

### 2026-08-12：技术报告补充实验 E0～E4

依据技术报告补充实验指导，对 218-LUT、24/20/20、4-DSP 板测基线补跑数字域证据链。
MATLAB 软件门禁通过：固定模型/稳定 RTL 向量 6/6、0 LSB；六工况频响 6/6，最差通带
绝对偏差 **0.007844 dB**、最差阻带 **72.355 dB**；997 Hz、10 kHz、19 kHz 的六工况
相干频谱 18/18，最差镜像抑制 **74.546 dBc**。当前 RTL Smoke 重新运行得到 **17/17 PASS**。

冲激非零支撑区对称误差为 0 LSB，相位拟合残差小于 `1e-13 rad`，因此严格线性相位同时具有
结构和数值证据。报告明确区分了启动瞬态、满幅边界、稳态音频、归档消融和未完成的 SAIF、
正式 Fmax、配对 seed、仪器音频项目。完整目的、过程图、结果、局限和复现入口见
[技术报告补充测试报告](submit/finally/reports/test_report.md)。

### 2026-08-11：218 板测基线后的 4/3/2-DSP Pareto 复验

218-LUT 24/20/20 版本已由用户确认物理板测成功，并归档为不可变标签
`nf-vivado2025.2-218lut-365ff-4dsp-2bram-24-20-20-board-pass`。随后先完成发布
配置闭环：MATLAB 模型、稳定 Smoke 金标准、默认 RTL 回归、GUI 仿真文件集、
Stage2=20 显式泛型和 Vivado 构建指纹现在指向同一数值配置。默认 Smoke
**17/17 PASS**，完整 Vivado 2025.2 再次得到 **218 LUT / 365 FF / 4 DSP**、
WNS/WHS=`+45.279/+0.079 ns`、0 DRC Error 和正式 bitstream。

在不改动正式 `.xpr` 和 board-pass 基线的前提下，用只读工程和综合命令行泛型覆盖
重新实测 CIC 积分器 DSP 模式 2/1/0：

| CIC DSP 模式 | 综合 LUT / FF | 布局布线 LUT / FF | DSP | RAMB18E1 | MMCM | WNS/WHS | RTL Smoke | 状态 |
|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 2 | 280 / 373 | **218 / 365** | **4** | 4 | 2 | +45.279/+0.079 ns | 17/17 PASS | **正式板测版** |
| 1 | 301 / 396 | **239 / 388** | **3** | 4 | 2 | +44.703/+0.079 ns | 17/17 PASS | **正式板测 Pareto 版** |
| 0 | 329 / 425 | **268 / 417** | **2** | 4 | 2 | +44.389/+0.078 ns | 17/17 PASS | 工具验证 Pareto，待板测 |

3-DSP 点相对正式基线节省 1 DSP，代价是 `+21 LUT / +23 FF`；2-DSP 点再节省
1 DSP，相对 3-DSP 再增加 `+29 LUT / +29 FF`。因此，若评分中一个 DSP 的权重高于
`21×LUT权重 + 23×FF权重`，3-DSP 点优于 4-DSP；2-DSP 相对 3-DSP 的对应临界为
`29×LUT权重 + 29×FF权重`。当前正式工程使用已板测的 239/3-DSP 版，已板测的
218/4-DSP 版保留为 LUT 优先回退；268/2-DSP 仍仅作为可切换 Pareto。三点无 SAIF 功耗估算均为
`0.271 W`，该结果被两颗 MMCM 主导，不用于宣称实测功耗改善。

3-DSP/2-DSP 的资源、时序、DRC 和回归结论已固化在完整执行记录中；对应的时间戳
Vivado 原始运行目录属于可重复生成的本地中间产物，清理后可通过记录中的命令重建。详见
[218 基线 CIC DSP Pareto 执行反馈](matlab_fir/national_finals/results/vivado2025_2_218_cic_dsp_pareto_execution_feedback.md)。

### 2026-08-11：24/20/20 GUI 综合内存失败修复

用户手动运行正式 Vivado 2025.2 工程时，`synth_1` 在 `Start Technology Mapping` 阶段失败。
实际 `runme.log` 没有 RTL、约束或器件资源错误，而是明确记录
`out of memory allocating 8388640 bytes`：当时 15.73 GB 物理内存仅余约 2.71 GB，Windows
提交内存余量约 3.37 GB，Vivado 又默认启动两个内部综合 worker；综合主进程峰值约1.64 GB后，
系统已无法再承诺约8 MB内存。D盘当时也只余约1.24 GB，虽不是本次第一故障点，但已是后续
实现和报告保存的风险项。

正式工程现已为 `synth_1` 持久安装
`tools/vivado_2025_2/synth_low_memory_pre.tcl`，把内部综合线程固定为1；GUI run和完整构建均使用
单job。通过 `repair_gui_synth_2025_2.tcl` 原生 `reset_run` 后重新运行，日志确认
`maximum of 1 processes`，综合以0 Error/0 Critical Warning完成，资源为
**280 LUT / 373 FF / 4 DSP / 4 RAMB18E1 / 2 MMCM**，峰值约1.92 GB。随后从同一个GUI
`synth_1` 继续完成 `impl_1 -> write_bitstream`，再次得到
**218 LUT / 365 FF / 4 DSP / 4 RAMB18E1 / 2 MMCM**，WNS/WHS=`+45.279/+0.079 ns`，
DRC Error=0。修复证据分别位于
`tools/vivado_2025_2/results/synth_repair_20260811_195841` 和
`tools/vivado_2025_2/results/gui_impl_verify_20260811_200228`。该修复只改变Vivado运行并发，
没有修改滤波RTL、字长、系数、量化、时序或DAC接口。

## 当前最低 LUT 正式实板版：Vivado 2025.2 218 LUT / 4 DSP（24/20/20，2026-08-11 板测成功）

在已板测 221-LUT 安全基线上，本轮按建议把 Stage1/Stage2/Stage3 的有效数据宽度从
`24/22/20 bit` 改为 `24/20/20 bit`。Stage1 输出直接右移4 bit并饱和到20 bit送入 Stage2；
Stage2 到 Stage3 的第二级 bridge 变为同宽 `SHIFT_N=0` 传输，只保留原 valid/phase 握手；
Stage2 历史数据、共享 DSP 数据口和 DSP48E1 `PATTERNDETECT` 符号扩展判据同步收窄。
4x 公开节点左移4 bit恢复24-bit PCM标度，Stage3、CIC、系数、采样率和 DAC 接口保持不变。

这是一套新的有限字长规格，不宣称与 221-LUT 版逐样本相同。独立 MATLAB 模型先完成六模式
频响 6/6 和定向数值测试 9/9，再为 RTL 生成配置标识
`NF-P3-STAGE123-24-20-20-CANDIDATE-R1` 的金标准。最差频响如下：

| 输出 | 最大绝对通带偏差 | 峰峰纹波 | 阻带衰减 | 相位 |
|---|---:|---:|---:|---|
| 4x | 0.003022 dB | 0.005714 dB | 78.277 dB | 严格线性 |
| 8x | 0.003447 dB | 0.006162 dB | 78.359 dB | 严格线性 |
| 128x | 0.007605 dB | 0.005733 dB | 72.355 dB | 严格线性 |

正式 Vivado 2025.2 从头综合、实现并生成 bitstream：

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 280 | 0 | 373 | 4 | 4 | 2 | 17 | 2 |
| **布局布线后** | **218** | **0** | **365** | **4** | **4** | **2** | **17** | **2** |

相对 221-LUT 实板基线减少 **3 LUT（1.36%）和 2 FF（0.54%）**，DSP、BRAM、IO、MMCM
不变。整板 WNS/WHS=`+45.279/+0.079 ns`，TNS/THS=0，DRC Error=0；bus-skew 实际
0.444 ns、50 ns 约束余量 `+49.556 ns (MET)`；vectorless 总/动态/静态功耗仍为
`0.271/0.199/0.072 W`，置信度 Medium。

| 统计对象 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM | WNS/WHS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **完整板级系统正式实现** | **218** | **0** | **365** | **4** | **4** | **2** | **17** | **2** | **+45.279/+0.079 ns** |
| **插值滤波器核心 OOC 独立实现** | **190** | **0** | **279** | **4** | **3** | **1.5** | **0** | **0** | **内部 +150.943/+0.069 ns** |

最终源树的 Smoke 为 **17/17 PASS**；Release 也为 **17/17 PASS**，覆盖冲激、10个固定随机
seed、正负满幅和 −1 dBFS 强音频共14组输入，4x/8x/128x 对24/20/20 MATLAB金标准逐样本
0 LSB，并通过8类复位恢复、10次不停机动态切档、RAMB18原语、CDC、双时钟族和板级顶层。
最终 routed DCP 的六模式门级回归得到44.1 kHz `177/353/5645 edges/ms`、48 kHz
`192/384/6144 edges/ms`，六档 DAC 数据持续变化且无 X，日志以
`BOARD POSTROUTE SIX-MODE DAC PASS` 结束。

正式工具产物位于
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260811_190839`；bitstream SHA-256 为
`1834675AB971FFA8BD6C03BF1B596D6F5D65C8A36A6B8D0182EEA6C5D408D110`，routed DCP SHA-256 为
`FC26756258EF14A60872D55CBDDAC928D536727937876788D180E2D3BE35A462`。2026-08-11 用户明确确认
218-LUT 版本物理板测成功，当前状态正式升级为 **board-verified**；正式标签为
`nf-vivado2025.2-218lut-365ff-4dsp-2bram-24-20-20-board-pass`，221-LUT board-pass 保留为前一
安全回退。未提供的逐档仪器原始读数不作推测。完整设计、验证、No-Go和复现记录见
[218-LUT 24/20/20 字长优化执行反馈](matlab_fir/national_finals/results/vivado2025_2_stage123_24_20_20_218lut_execution_feedback.md)。

## 前一最低 LUT 正式实板版：Vivado 2025.2 221 LUT / 4 DSP（2026-08-10 板测确认）

本轮从已由用户物理板验证的 234-LUT 安全基线建立分支
`national-finals-v2025.2-post234-lut-optimization`，对 routed 网表逐个 LUT 审计后保留三项可证明
等价的状态复用：模式 CDC 用本地 `ack_toggle` 兼任已接收 request token，删除重复 `req_seen`；
Stage2/3 在一次 Stage3 任务完成前直接使用稳定的 pending 补偿模式，删除第二份 job 快照；全国赛
ROM、历史 RAM 和数据通路均同步复位为零，因此把全国赛活动路径的输入 valid 明确为常量 1，
删除 Stage1 RAM 前 24 位“输入/零”门控，而区域赛兼容路径仍保留原一拍 valid 行为。滤波器系数、
定点字长、舍入/饱和、4x/8x/128x 相位、双采样率时钟、DSP、BRAM 和 MMCM 均未改变。

正式 Vivado 2025.2 从头综合、布局布线并生成 bitstream：

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 285 | 0 | 375 | 4 | 4 | 2 | 17 | 2 |
| **布局布线后** | **221** | **0** | **367** | **4** | **4** | **2** | **17** | **2** |

相对已板测 234-LUT 基线减少 **13 LUT（5.56%）和 2 FF（0.54%）**，DSP、BRAM、IO、MMCM
不变。整板 WNS/WHS=`+44.556/+0.079 ns`，TNS/THS=0，失败端点 0，路由失败网络 0，
DRC Error=0；CDC 双位模式总线 bus-skew 实际 0.433 ns、约束 50.000 ns、余量
`+49.567 ns (MET)`；vectorless 总/动态/静态功耗为 `0.271/0.199/0.072 W`，置信度 Medium。

| 统计对象 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM | WNS/WHS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **完整板级系统正式实现** | **221** | **0** | **367** | **4** | **4** | **2** | **17** | **2** | **+44.556/+0.079 ns** |
| **插值滤波器核心 OOC 独立实现** | **193** | **0** | **281** | **4** | **3** | **1.5** | **0** | **0** | **内部 +151.232/+0.166 ns** |

同一 RTL 先后通过 Smoke 与 Release **17/17 PASS**；Release 覆盖 CIC 定向等价、冲激、10 个
固定 seed、正负满量程、强 −1 dBFS、4x/8x/128x 三节点逐样本 0 LSB、RAMB18 原语、8 类
复位、1200 次 CDC、100 次时钟族切换和 10 次不停机动态切档。正式 routed DCP 的默认 DAC
活动测试得到 11290 个边沿和 7462 次数据变化；六模式门级回归得到 44.1 kHz
`177/353/5645 edges/ms`、48 kHz `192/384/6144 edges/ms`，六档 DAC 数据持续变化且无 X。
这里 177 是 1 ms 观察窗中的整数边沿计数，对应目标 176.4 kHz，不是把标称采样率改成 177 kHz。

正式工具产物位于
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260810_181833`；bitstream SHA-256 为
`08B2DE6DB8DF1FBC9E59EA78808C57BD007E414243B5F6FF9C7FF1B2797D91A7`，routed DCP SHA-256 为
`BFE4A9A25958C232E24091A08EE7A2F0E564AB3DF8C45EEFEB9CCA3CF1DC943F`。2026-08-10 用户完成
物理板验证，确认 44.1/48 kHz 两个采样率族下各倍率档位的输出采样率均正确，DAC 波形均正常；
当前状态正式升级为 **board-verified**，标签为
`nf-vivado2025.2-221lut-367ff-4dsp-2bram-board-pass`。234-LUT board-pass 继续作为前一安全回退。
详细候选矩阵、No-Go
原因和复现命令见
[221-LUT routed 网表不变量优化执行反馈](matlab_fir/national_finals/results/vivado2025_2_post234_221lut_execution_feedback.md)。

### 221-LUT 板测版后的结构重构试验（No-Go，2026-08-10）

以 221-LUT board-pass 标签为不可变回退点，本轮在独立分支
`national-finals-v2025.2-global-fir-scheduler` 试验了 256× 双采样率族计算时钟、全局单 DSP
三级 FIR 调度、固定时隙 Stage2/3，以及把两级 bridge 量化搬入共享 DSP48 空闲拍。正式板级
RTL 和 `.xpr` 未接入这些 No-Go 候选。

时钟可行性候选已完成布局布线：两个 MMCM 产生 11.2896/12.288 MHz，经
`BUFGMUX_CTRL` 选择 256× 计算时钟，再由 `BUFR /2` 恢复 128× 音频时钟；DRC Error=0，
WNS/WHS=`+79.928/+0.248 ns`。这证明时钟结构能在 XC7A35T 上实现，但并不代表调度器面积更低。

结构 A/B 使用同一 FIR 前三节点 OOC 边界；它不含 CIC、PCM ROM、按键、CDC、DAC、IO 和
MMCM，不能与 221-LUT 整板数字直接相减：

| FIR 前端候选 | LUT | FF | DSP48E1 | RAMB18E1 | RTL 等价 | 结论 |
|---|---:|---:|---:|---:|---|---|
| **221-LUT 正式版 FIR 前端参考** | **187** | **159** | **2** | **3** | 正式核心来源 | 基线 |
| 全局单 DSP FIR 调度 | 316 | 276 | 1 | 3 | 64k 周期，三节点逐拍一致 | 少1 DSP但多129 LUT，No-Go |
| 固定时隙 Stage2/3 | **186** | 165 | 2 | 3 | 64k 周期，三节点逐拍一致 | 仅少1 LUT、多6 FF，无法覆盖新增时钟集成 |
| DSP 内折叠两级量化 | 197 | 159 | 2 | 3 | 26k 周期，三节点逐拍一致 | 多10 LUT，No-Go |
| 固定时隙并折叠两级量化 | 254 | 211 | 2 | 3 | 64k 周期，三节点逐拍一致 | 多67 LUT，No-Go |

固定时隙方案对 `AreaOptimized_high/medium`、`FewerCarryChains` 和 `Default` 的 LUT/FF 扫描为
`186/165、186/165、188/165、188/165`；删除返回流水 FF 后变成 `194/159`，同样恶化。所有
候选均带 pending 覆盖、历史写冲突和截止期断言。量化折叠还专门修复并复验了正满量程舍入
边界。由于没有候选形成可信的整板净收益，本轮按停止线不生成候选 bitstream、不运行完整
Release 17/17，也不改变 221-LUT 正式推荐。

完整调度思路、资源矩阵、失败原因、验证数量和一键复现入口见
[221-LUT 后结构重构试验执行反馈](matlab_fir/national_finals/results/vivado2025_2_post221_structure_redesign_execution_feedback.md)。

## 当前正式实板安全回退：Vivado 2025.2 234 LUT / 4 DSP（2026-08-10 板测确认）

在已经完成用户物理板验证并创建 board-pass 标签的 239-LUT 版本上，分支
`national-finals-v2025.2-230to234-lut-challenge` 继续挑战 230～234 LUT。最终保留三项严格
等价的控制结构优化：Stage1 合并调度/发射索引；Stage2/3 bridge 复用滤波核内部权威 phase
状态，删除两套 `phase_mirror`；模式切换在 `force_mute` 有效期间于 DAC 分频负边沿原子提交，
从全国赛活动路径的 DAC 静音条件中删除不会在非静音周期出现的重复 mode mismatch 比较。
滤波器系数、字长、舍入/饱和、valid 相位、双采样率时钟、4 DSP 和 2 BRAM Tile 均未改变。

正式 Vivado 2025.2 从头综合、布局布线并生成 bitstream：

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 310 | 0 | 377 | 4 | 4 | 2 | 17 | 2 |
| **布局布线后** | **234** | **0** | **369** | **4** | **4** | **2** | **17** | **2** |

相对 239-LUT 板测基线减少 **5 LUT（2.09%）和 8 FF（2.12%）**，DSP、BRAM、IO、MMCM
不变。整板 WNS/WHS=`+44.925/+0.060 ns`，TNS/THS=0，失败端点 0，路由失败网络 0，
DRC Error=0；CDC 双位模式总线 bus-skew 要求 50.000 ns、实际 0.533 ns、余量
`+49.467 ns (MET)`；总/动态/静态功耗为 `0.271/0.199/0.072 W`，置信度 Medium。

同一核心 RTL 的独立 OOC post-route 结果为：

| 统计对象 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM | WNS/WHS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **完整板级系统正式实现** | **234** | **0** | **369** | **4** | **4** | **2** | **17** | **2** | **+44.925/+0.060 ns** |
| **插值滤波器核心 OOC 独立实现** | **194** | **0** | **282** | **4** | **3** | **1.5** | **0** | **0** | **内部 +151.280/+0.089 ns** |

最终候选先后通过 Smoke 与 Release **17/17 PASS**；Release 覆盖 CIC 定向等价、全链三节点
逐样本对拍、BRAM 原语、复位恢复、10 次不停机动态切档、CDC、ROM、DAC、按键和双时钟族。
正式 routed DCP 六模式门级回归得到 44.1 kHz `177/353/5645 edges/ms`、48 kHz
`192/384/6144 edges/ms`，六档 DAC 数据持续变化、无 X，日志以
`BOARD POSTROUTE SIX-MODE DAC PASS` 结束。频响参数不变：4x/8x/128x 峰峰纹波为
`0.005709/0.006192/0.005848 dB`，阻带衰减为 `78.568/78.609/72.371 dB`，严格线性相位。

工具签核归档目录为
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260810_160858`。用户随后使用标准 GUI
工程重新综合、实现并下载 bitstream，确认 44.1/48 kHz 两个输入采样率族下所有档位的实际输出
采样率均正确，DAC 输出波形均正常，因此当前版本正式升级为 **board-verified**。本次实际板测
产物归档在 `XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260810_170616_board_pass`：
bitstream SHA-256 为 `F9DB8E33C3959C448FDE316A51BA9A13ABC83D5AE1F69655CD5D0B698A871E85`，
routed DCP SHA-256 为 `47CDCA8E43C2DA817D028828564862EC56C64F0E791C6F845DE05A3E03DA3162`。
正式实板标签为 `nf-vivado2025.2-234lut-369ff-4dsp-2bram-board-pass`；239-LUT board-pass
继续作为前一安全回退。完整候选矩阵、失败原因、
复现路径和验证证据见
[234-LUT 共享相位与原子切档执行反馈](matlab_fir/national_finals/results/vivado2025_2_shared_phase_atomic_mode_234lut_execution_feedback.md)。

## 前一最低 LUT 正式实板回退：Vivado 2025.2 239 LUT / 4 DSP（2026-08-10 板测确认）

在已经完成实板验证的 249-LUT 安全基线上，分支
`national-finals-v2025.2-post249-lut-optimization` 继续审计实现后物理网表。审计发现 Stage1
中心延迟样本寄存器原来使用 `read_mask ? read_data : 24'b0`，在 Fabric 中生成了 24 位
BRAM 数据/零选择器。该中心抽头的历史有效性在一次复位周期内单调变化：复位后
`delay_result=0`，无效启动期保持旧值与反复写零严格等价；中心抽头第一次有效后，在下次复位
之前后续读取始终有效。因此本轮把条件数据选择改写为寄存器时钟使能：只有
`read_coeff_index == DELAY_INDEX && read_mask` 时才更新 `delay_result`。这不是近似删逻辑，
而是把已经存在的状态不变量明确表达给综合器。

标准 Vivado 2025.2 正式 `.xpr` 工程从 `reset_run` 开始重新综合、实现并生成 bitstream：

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 314 | 0 | 385 | 4 | 4 | 2 | 17 | 2 |
| **布局布线后** | **239** | **0** | **377** | **4** | **4** | **2** | **17** | **2** |

相对 249-LUT 实板版减少 **10 LUT（4.02%）**，FF、DSP、BRAM、IO、MMCM 均不变；与该优化
之前同一源码树的综合结果相比，综合 LUT 从 325 降至 314（−11）。整板 WNS/TNS 为
`+45.306/0 ns`，WHS/THS 为 `+0.082/0 ns`，失败端点 0，路由错误 0，DRC Error 0。
总/动态/静态功耗仍为 `0.271/0.199/0.072 W`，功耗报告置信度为 Medium。

本轮同时重新执行了独立插值核心 OOC（Out-of-Context）实现，不能把整板 239 LUT 全部称为
滤波器核心资源：

| 统计对象 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM | WNS/WHS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **完整板级系统正式实现** | **239** | **0** | **377** | **4** | **4** | **2** | **17** | **2** | **+45.306/+0.082 ns** |
| **插值滤波器核心 OOC 独立实现** | **197** | **0** | **290** | **4** | **3** | **1.5** | **0** | **0** | **内部 +151.665/+0.054 ns** |

OOC 统计顶层为 `interp128_all2x_v7_folded_fir_cic_top_ce`，核心实现路由错误和 DRC Error 均为
0。3 个 RAMB18E1 等于 1.5 BRAM Tile；整板额外包含 1 个外围 ROM RAMB18E1，所以整板为
4 个 RAMB18E1，即 2 Tile。两套数据具有不同综合边界，不能用 `239-197` 声称外围精确占用
42 LUT。

完整验证结果如下：

- Smoke 与 Release RTL 回归均为 **17/17 PASS**；Release 全链冲激、10 个随机 seed、正/负
  满量程和强 −1 dBFS 共 14 组输入，在 4x/8x/128x 三节点均为 **0 LSB**；
- Stage1 行为 RAM 与 RAMB18E1 原语各比较 1400 个输出，均为 0 LSB；8 类复位恢复、10 次
  不停机动态切档、ROM、DAC、BRAM、CDC、按键和双时钟族检查全部通过；
- 239-LUT routed DCP 的六模式门级后仿真得到 44.1 kHz
  `177/353/5645 edges/ms`、48 kHz `192/384/6144 edges/ms`，六档 DAC 数据均持续变化、无 X，
  最终日志为 `BOARD POSTROUTE SIX-MODE DAC PASS`；
- 频响不变：4x/8x/128x 最差通带最大绝对偏差为
  `0.003022/0.003521/0.007730 dB`，峰峰纹波为
  `0.005709/0.006192/0.005848 dB`，阻带衰减为 `78.568/78.609/72.371 dB`，严格线性相位。

正式结果目录为
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260809_173232`。bitstream SHA-256 为
`56248A6FFD013B020012B397ED32E9FA9F2285644978E5016CEB2F5506911EEA`，routed DCP SHA-256 为
`0AFBDAFA7D6ECAED9D7DEF72A53F7ECBB7DF0FFC29823071B4A8D43A31B38729`。用户随后完成物理板
验证，确认各档采样率与 DAC 输出波形均正常，因此该版本已升级为 **board-verified**；正式
回退标签为 `nf-vivado2025.2-239lut-377ff-4dsp-2bram-board-pass`。详细原理、验证日志、
手动复现和回退方法见
[239-LUT Stage1 延迟使能执行反馈](matlab_fir/national_finals/results/vivado2025_2_stage1_delay_enable_239lut_execution_feedback.md)。

## 前一最低 LUT 正式实板版：Vivado 2025.2 249 LUT / 4 DSP（2026-08-09 确认）

在 258-LUT 实板通过版已经由独立提交和标签保留后，分支
`national-finals-v2025.2-245to249-lut-challenge` 挑战 245～249 LUT。最终没有改滤波器系数、
定点字长、舍入/饱和、valid 时序、4x/8x/128x 接口或双采样率时钟；主要把 CIC 的三级
串行 comb 减法映射到一个显式 DSP48E1 P 寄存器，把原来占用 DSP 的第一级 26-bit 积分器
交换到 CARRY4，并复用 comb 阶段索引承担一拍对齐状态。整机 DSP 数仍为 4，BRAM 仍为
4 个 RAMB18E1（2 BRAM Tile），但删除了 Fabric 中的宽减法器及一组独立状态寄存器。

标准 Vivado 2025.2 从头综合、实现并生成 bitstream 的结果为：

**249 LUT / 0 LUTRAM / 377 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**。综合为 **325 LUT / 385 FF**；相对已板测 258-LUT 基线再减少
**9 LUT（3.49%）**，增加 1 FF，DSP、BRAM、IO、MMCM 与功耗均不变。WNS/TNS 为
`+43.997/0 ns`，WHS/THS 为 `+0.085/0 ns`，失败端点 0，DRC Error 0；总/动态/静态功耗为
`0.271/0.199/0.072 W`。

### 249-LUT 版本的整板与插值核心双口径资源报告

为避免把整板的 249 LUT 误写成“插值滤波器核心资源”，本版本按论文中常用的方法补做了
一次独立 OOC（Out-of-Context）实现。OOC 顶层固定为
`interp128_all2x_v7_folded_fir_cic_top_ce`，器件为 `xc7a35tfgg484-2`，核心时钟按最坏公开
采样率配置为 6.144 MHz；系数、字长、Stage1/Stage2/3、CIC 阶数以及 249-LUT 整板版本的
全部结构参数保持一致。综合采用 `AreaOptimized_high + flatten_hierarchy=full +
resource_sharing=on + shreg_min_size=5`，实现采用 `opt_design ExploreArea + place_design Explore +
route_design`。以下均为 **Vivado 2025.2 post-route 报告值**：

| 统计对象 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | IO | MMCM | WNS/WHS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **完整板级系统正式实现** | **249** | **0** | **377** | **4** | **4** | **2** | **17** | **2** | **+43.997/+0.085 ns** |
| **插值滤波器核心 OOC 独立实现** | **210** | **0** | **290** | **4** | **3** | **1.5** | **0** | **0** | **内部 +150.963/+0.128 ns** |

核心 OOC 的路由错误数为 0，在 OOC 可执行的 DRC 范围内为 0 Error；4 个 DSP48E1 和
3 个 RAMB18E1 均由实现后原语网表直接计数，并非估算。核心的 3 个 RAMB18E1 等于
1.5 BRAM Tile；完整板级系统另有 1 个外围 RAMB18E1，因此整板显示 4 个 RAMB18E1，折算为
2 BRAM Tile。OOC 顶层不包含板级 ROM/激励源、按键/模式控制、双采样率时钟生成、DAC 包装、
IO 和 MMCM。

OOC 面积实现保留零延迟顶层边界，以复现签核的 210-LUT 放置结果；脚本另外从 routed 网表中
筛选“内部寄存器→内部寄存器”路径，得到内部 WNS/WHS=`+150.963/+0.128 ns`。原始 OOC 边界
报告中的 -0.860 ns hold 起点是独立输入 `stage3_compensated_mode`：即使把时钟入口设为整板
routed DCP 实际使用的 `BUFGCTRL_X0Y16`，独立边界仍没有整板里的同源启动寄存器和相应时钟
插入延迟，因此该数字不是核心内部违例。**OOC 数据用于核心资源与内部路径统计**，完整接口
时序签核必须采用完整系统的
`WNS/WHS=+43.997/+0.085 ns`。论文或答辩中应分别称为“核心独立实现资源”和“完整系统实现
资源”，不能用 `249-210` 直接声称外围逻辑精确占用 39 LUT，因为跨层级综合会改变逻辑合并
与打包结果。

参赛现场关闭 Vivado GUI 后，在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\core_ooc\run_core_ooc_2025_2.ps1
```

约 3 分钟后终端必须出现 `CORE_OOC_2025_2_DEMO_PASS`。向评委展示最新
`core_ooc/results/<时间戳>/core_ooc_summary.txt`、`utilization_post_route.rpt`，或在 Vivado GUI/Tcl
Console 中执行 `open_checkpoint {<结果目录>/core_post_route.dcp}` 后运行 `report_utilization`。
脚本、非默认安装路径参数、报告清单和统计边界详见
[核心 OOC 现场复现说明](XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/core_ooc/README.md)。

验证不是以“跑通综合”为通过条件：CIC 定向等价测试覆盖连续/停顿输入、10 个随机 seed、
中途复位并逐样本比较 **4096 个输出**；Smoke 与 Vivado 2025.2 Release 回归均为
**17/17 PASS**，14 组全链输入的 4x/8x/128x 三节点全部 **0 LSB**；正式 routed DCP 的
六档检查得到 44.1 kHz `177/353/5645 edges/ms`、48 kHz `192/384/6144 edges/ms`，六档
DAC 数据均持续变化且无 X。2026-08-09 用户完成物理板复测，确认各档输出采样率与 DAC
输出波形均正常，因此该版本已升级为 **board-verified**，并作为 239-LUT 候选的正式实板
安全回退。工具签核标签为 `nf-vivado2025.2-249lut-377ff-4dsp-2bram-toolverified`，实板标签为
`nf-vivado2025.2-249lut-377ff-4dsp-2bram-board-pass`。

频响严格继承已经签核的正确标度路径：4x/8x/128x 最差通带最大绝对偏差分别为
`0.003022/0.003521/0.007730 dB`，最差峰峰纹波为
`0.005709/0.006192/0.005848 dB`，阻带衰减为 `78.568/78.609/72.371 dB`，均满足
±0.05 dB、≥70 dB 和严格线性相位要求。详细 A/B 尝试、失败原因、完整验证矩阵、报告路径、
bitstream 哈希和回退方法见
[249-LUT CIC DSP 角色交换执行反馈](matlab_fir/national_finals/results/vivado2025_2_cic_dsp_role_exchange_249lut_execution_feedback.md)。

## 当前最低 LUT 正式实板版：Vivado 2025.2 258 LUT / 4 DSP（2026-08-08）

在 276-LUT 正式板测版已经由提交、标签和独立分支完整保留后，分支
`national-finals-v2025.2-post276-lut-optimization` 进行了存储/控制架构重构。Stage1 不再按
`Lk/Rk` 两地址读取后做对称预加，而是把 26 个对称系数展开为 52 个顺序系数，放入现有统一
系数 RAMB18E1 的空闲地址 128--179；控制器从新到旧单地址扫描历史，每拍直接 MAC，并在扫描
中同时捕获中心延迟样本。由此删除左右抽头状态、两套有效掩码、第二地址公式和独立延迟预取，
不新增 DSP 或 BRAM。

标准 Vivado 2025.2 GUI 工程从零重建结果为：

**258 LUT / 0 LUTRAM / 376 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**。相对 276-LUT 板测基线减少 **18 LUT（6.52%）**、减少 3 FF，DSP、BRAM、
IO、MMCM 和功耗均不变。综合为 **319 LUT / 384 FF**；WNS/TNS=`+45.222/0 ns`，
WHS/THS=`+0.077/0 ns`，DRC Error=0，总/动态/静态功耗=`0.271/0.199/0.072 W`。

该候选已完成 Smoke/Release 各 **17/17 PASS**；Release 的 17 份独立日志均有 PASS 且无
ERROR/FATAL/FAIL，14 组全链输入的 4x/8x/128x 全部 0 LSB。标准 GUI 工程成功完成综合、实现
和 bitstream；routed-DCP 六档又得到 44.1 kHz `177/353/5645 edges/ms`、48 kHz
`192/384/6144 edges/ms`，六档 DAC 数据均持续变化且无 X。

系数、定点字长、舍入/饱和和输出 valid 时序均未改变，因此频响严格继承 P3-J 以后正式正确
标度路径：最差通带最大绝对偏差 0.007730 dB、最差峰峰纹波 0.006192 dB、最差阻带衰减
72.371 dB，严格线性相位。2026-08-08 用户已完成物理板复测，确认 44.1/48 kHz 各倍率档位
采样率以及 DAC 输出波形均正常，因此当前状态正式升级为 **board-verified**；下方 276-LUT
版本保留为前一实板安全回退。工具签核标签为
`nf-vivado2025.2-258lut-376ff-4dsp-2bram-toolverified`，实板标签为
`nf-vivado2025.2-258lut-376ff-4dsp-2bram-board-pass`。完整执行、失败处理、日志路径、
bitstream 哈希和回退说明见
[258-LUT Stage1 顺序抽头执行反馈](matlab_fir/national_finals/results/vivado2025_2_stage1_sequential_258lut_execution_feedback.md)。

## 当前最低 LUT 正式实板版：Vivado 2025.2 276 LUT / 4 DSP（2026-08-08）

当前优化分支为 `national-finals-v2025.2-4dsp-2bram-lut-opt`。本轮从已经完成实板验证的
Vivado 2025.2 292-LUT 版本继续优化，保持滤波系数、各级定点字长、舍入/饱和、valid
时序、44.1/48 kHz 双时钟族、4x/8x/128x 档位、DAC 接口以及 **4 DSP / 2 BRAM Tile**
不变。最终正式布局布线结果为：

**276 LUT / 0 LUTRAM / 379 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**。相对已板测 292-LUT 基线减少 **16 LUT（5.48%）**，增加 3 FF，DSP、
BRAM、IO 和 MMCM 均不变。该版本已经完成工具侧完整签核；2026-08-08 用户又完成物理板
复测，确认 44.1/48 kHz 两个输入采样率族下各公开插值档位的输出采样率均正确，DAC 输出
波形均正常，因此正式升级为 **board-verified 发布版**。292-LUT 标签保留为前一板测回退。

### 292 → 276 LUT 的演进

| 版本/检查点 | 主要变化 | Routed LUT | LUTRAM | FF | DSP | BRAM Tile | WNS/WHS | 功耗 | 状态 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 2025.2 板测基线 | 同一 FIR-CIC RTL 迁移并升级 IP | 292 | 1 | 376 | 4 | 2 | +44.234/+0.112 ns | 0.271 W | **板测通过** |
| 策略检查点 | `AreaOptimized_high/full/on`，物理优化采用 `ExploreArea + Explore` | 285 | 1 | 376 | 4 | 2 | +44.695/+0.062 ns | 0.271 W | 工具通过，提交 `5faa60b` |
| SHREG 检查点 | `SHREG_MIN_SIZE=5`，短复位链保留为 FF | 284 | 0 | 379 | 4 | 2 | +45.025/+0.091 ns | 0.271 W | 工具通过，提交 `22b9b55` |
| **DSP 抽头门控正式版** | **Stage2/3 无效历史抽头改用 DSP PREG CE 门控，删除两个宽数据选择器** | **276** | **0** | **379** | **4** | **2** | **+44.885/+0.112 ns** | **0.271 W** | **工具与用户实板均通过** |

### 276-LUT 优化原理

Stage2/3 原实现先根据历史有效位，在 Fabric 中把 22-bit/20-bit 历史样本选择为“真实样本或
全零”，再送入共享 DSP48E1。新实现让 BRAM 原始样本直接进入 DSP，并在任务启动时锁存
`job_history_valid`：历史无效时关闭该抽头的 DSP PREG 更新，历史有效时才累加。由于关闭
PREG 更新与“向当前累加值加零”在该串行 MAC 调度中严格等价，所以删除了两个宽零值选择器，
同时没有改变系数、算术结果或周期边界。这是在现有
`Stage1 FIR -> 共享 Stage2/3 FIR（CIC 补偿已折叠进 Stage3）-> CIC16` 结构内的控制/映射
优化，不是重新增加一套独立补偿器。

另一个候选曾尝试用 Stage1 DSP PREG 保存尾部延迟，虽然 Smoke **17/17** 通过并减少 24 FF，
但综合从当前候选的 **341 LUT / 387 FF** 恶化为 **363 LUT / 363 FF**，多 22 LUT；原因是
48-bit C 端口和控制选择逻辑代价超过被删除的寄存器，因此按 LUT 优先门槛回退，没有进入实现。

### 276-LUT 正式签核结果

- Vivado 2025.2 综合：**341 LUT / 0 LUTRAM / 387 FF / 4 DSP / 2 BRAM Tile**；
- 布局布线：**276 LUT / 0 LUTRAM / 379 FF / 4 DSP / 2 BRAM Tile / 17 IO / 2 MMCM**；
- Timing：WNS/TNS=`+44.885/0 ns`，WHS/THS=`+0.112/0 ns`，setup/hold 失败端点均为 0；
- DRC：0 Error；仅保留 DSP 输入/输出流水线建议和 1 条 RAMB18 advisory；
- 功耗：总/动态/静态=`0.271/0.199/0.072 W`，Medium confidence；
- Release RTL 回归 **17/17 PASS**：14 组全链输入（冲激、10 seeds、正/负满量程、强
  −1 dBFS）在 4x/8x/128x 三节点全部 **0 LSB**；Stage1 行为 RAM 与 RAMB18E1 原语各
  1400 个输出 0 LSB；8 类内部复位恢复、10 次无复位动态切档、ROM、DAC offset、
  系数/历史 BRAM、CDC、按键和时钟族测试全部通过。总回归封装器在最后一个动态切档用例
  elaboration 时达到 603 s 外层时限；该用例随后在同一生成目录单独完成并 PASS，最终逐项
  审计 17 份 `xsim.log` 均有 PASS/finish 且无 ERROR/FATAL；
- routed-DCP 六档功能仿真全部通过：44.1 kHz 族为 `177/353/5645 edges/ms`，48 kHz 族为
  `192/384/6144 edges/ms`，六档 DAC 数据均持续变化、无 X；前三个整数是 1 ms 窗口计数，
  分别对应理论 176.4/352.8/5644.8 kHz；
- bitstream：
  `XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260808_012650/board_demo_competition_dac8_top_2025_2.bit`；
  SHA-256=`1A6CDA833627AA197AB111EB426E6CA70405E69D657B3528C3B6D9CF1A0BCB2F`。
- 物理板：2026-08-08 用户确认所有公开档位输出采样率正确，DAC 输出波形正常；正式标签为
  `nf-vivado2025.2-276lut-379ff-4dsp-2bram-17io-2mmcm-board-pass`。

完整的 2025.2 构建、验证和手动 GUI 复现说明见
[Vivado 2025.2 迁移与优化记录](XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/README.md)。

### 276-LUT 板测后进一步优化审计（2026-08-08）

在用户确认 276-LUT 版本六档采样率和 DAC 波形均正常后，另建
`national-finals-v2025.2-post276-lut-optimization` 分支继续试验，正式板测 RTL 不动。
重新综合精确复现 **341 LUT / 387 FF / 4 DSP / 2 BRAM Tile**；从同一综合 DCP 扫描 7 组
`opt/place` 策略，最低仍为 **276 LUT / 379 FF**，没有策略优于正式结果。

首个 RTL 候选把 Stage2/3 历史有效比较改为粘滞状态，完整 Smoke 回归 **17/17 PASS**，但
综合变为 **345 LUT / 388 FF**，相对基线多 4 LUT、1 FF，故判定 No-Go 并完整回退。本轮没有
用较差候选生成 bitstream，正式推荐仍为板测通过的 276-LUT R5。结构审计、七组策略数据、
失败原因和下一步风险边界见
[276-LUT 板测后优化审计与执行反馈](matlab_fir/national_finals/results/post276_lut_optimization_audit_execution_feedback.md)。

## 前一 Vivado 2025.2 板测回退：292 LUT / 4 DSP（2026-08-07）

`XC7A35T_interp_opt_2025.2` 的综合失败已修复。根因不是 RTL 语法，而是 Windows 提交内存
余量一度只有约 3.04 GB（GUI 与综合子进程峰值叠加会超过余量），同时用户 Tcl Store 缺失
`::tclapp::support::appinit 1.2`，复制工程还带有 Vivado 2018.3 的旧 IP/运行缓存。现已重建
Tcl Store、把 Clocking Wizard 升级到 2025.2 Rev17、重新生成 IP target，并通过 Vivado
原生 `reset_run` 重置综合与实现。用户关闭无关软件后，提交内存余量已提高到约 8.67 GB。

Vivado 2025.2 完整构建已通过：综合 361 LUT / 1 LUTRAM / 384 FF，布局布线后为
**292 LUT / 1 LUTRAM / 376 FF / 4 DSP / 4 RAMB18E1（2 BRAM Tile）/ 17 IO / 2 MMCM**，WNS/WHS 为
**+44.234/+0.112 ns**，TNS/THS 均为 0，DRC 0 Error，vectorless 总功耗 0.271 W，并成功
生成 bitstream。直接针对新工程源码运行的全国赛 RTL Smoke 回归为 **17/17 PASS**；2025.2
routed DCP 的六档网表仿真也通过，44.1 kHz 族为 `177/353/5645 edges/ms`，48 kHz 族为
`192/384/6144 edges/ms`，六档 DAC 数据均持续变化。

用户随后使用该 2025.2 bitstream 完成实板验证：44.1 kHz/48 kHz 两个输入族及所有公开插值
档位的实测采样率均正确，DAC 输出波形全部正常，因此本版本已由 tool-verified 更新为
**board-verified 正式版本**。292 LUT 是同一 RTL 经 Vivado 2025.2 新版综合/实现得到的工具
结果，不能与 2018.3 数字混为一次新的 RTL 优化；原 P3-U/P3-T 仍保留为旧工具链安全回退。
修复脚本、手动复现步骤、资源/时序/功耗报告及验证路径见
[Vivado 2025.2 迁移记录](XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/README.md)。

## 当前最低 LUT 工具签核候选：333 LUT / 4 DSP P3-U 控制路径深度优化版（2026-08-07）

P3-U 在已实板通过的 P3-T 上保持全部滤波系数、定点运算和板级接口不变，以两项周期
精确的控制路径编码继续降低面积：正式参数的键盘消抖由二进制加一器改为六状态 Johnson
序列；模式 CDC 的 pending flag 加倒计数器改为 one-hot settle token。最终综合为
**365 LUT / 384 FF**，布局布线为
**333 LUT / 382 FF / 152 Slice / 4 DSP / 4 RAMB18E1（2 Tile）/ 2 MMCM**；相对 P3-T
减少 8 LUT 和 11 Slice，仅增加 1 FF。WNS/WHS 为 **+45.704/+0.079 ns**，AD9708
setup/hold 为 **+76.116/+78.117 ns**，总/动态/静态功耗仍为
**0.271/0.199/0.072 W**。

Smoke/Release 均为 **17/17 PASS**；Release 的 14 组全链输入在 4x/8x/128x 所有节点
均为 0 LSB，并覆盖 8 类复位、1200 次 CDC、100 次切族和 10 次动态切档。正式 routed
DCP 的默认 DAC 活性为 11290 个边沿/7462 次数据变化；六档为 44.1 kHz
`177/353/5645 edges/ms`、48 kHz `192/384/6144 edges/ms`，六档 DAC 数据均持续变化。
普通 GUI 工程从零综合、实现和 Generate Bitstream 也复现 333/382/152/4-DSP/4-RAMB18。

**P3-U 当前为 tool-verified，尚待用户物理板复测，因此不能标为 boardverified；P3-T
341-LUT 版仍是正式实板安全回退。**完整证据见
[P3-U执行反馈](matlab_fir/national_finals/results/p3u_333lut_control_optimization_execution_feedback.md)和
[`p3u_333lut_382ff_4dsp_2bram_signedoff`](matlab_fir/national_finals/vivado_results/p3u_333lut_382ff_4dsp_2bram_signedoff)。

## 当前正式实板通过安全回退：341 LUT / 4 DSP P3-T Stage1 DSP尾周期版（2026-08-06）

P3-T从已板测的P3-S继续优化，在 **4 DSP / 2 BRAM Tile / 2 MMCM** 不变的前提下，把
Stage1串行MAC后的空闲周期用于精确Q15舍入、`PATTERNDETECT/PATTERNBDETECT`符号扩展
检查和DSP PREG直接饱和钳位；同时由计算期间稳定的写指针派生历史基址，删除独立6-bit
基址寄存器。最终综合为 **367 LUT / 383 FF**，布局布线为
**341 LUT / 381 FF / 163 Slice / 4 DSP / 4 RAMB18E1（2 Tile）/ 2 MMCM**。相对P3-S少
2 LUT、5 FF，但多12 Slice，因此是LUT/FF优先的新Pareto点，不是所有资源同时下降。

最终源码Smoke/Release均为 **17/17 PASS**；Stage1行为RAM与真实RAMB18E1各1400输出
0 LSB，全链14组4x/8x/128x均0 LSB，8类复位、1200次CDC、100次切族和10次动态切档
全部通过。341-LUT routed DCP又通过默认DAC活动和六档网表仿真：44.1 kHz为
`177/353/5645 edges/ms`，48 kHz为`192/384/6144 edges/ms`；GUI重实现成功生成bitstream。
WNS/WHS为 **+45.270/+0.107 ns**，功耗仍为 **0.271 W**。Vivado 2018.3可能在外部实现
进程仍运行时提前返回`wait_on_run`的问题也已修复，GUI脚本会持续等待到真实终态。

**用户已完成P3-T物理板复测：44.1/48 kHz两族的4x/8x/128x六档采样率均正确，DAC输出波形正常。P3-T现提升为正式实板发布；P3-S 343-LUT保留为前一实板安全回退。**
详细候选矩阵、完整RTL/Timing/Power/DAC/GUI证据、哈希和板测步骤见
[P3-T执行反馈](matlab_fir/national_finals/results/p3t_stage1_dsp_tail_saturation_341lut_execution_feedback.md)和
[`p3t_341lut_381ff_4dsp_2bram_signedoff`](matlab_fir/national_finals/vivado_results/p3t_341lut_381ff_4dsp_2bram_signedoff)。

## 前一正式实板通过回退：343 LUT / 4 DSP P3-S ExtraTimingOpt 版（2026-08-06）

P3-S 从已完成实板验证的 P3-R 348-LUT 标签继续优化，**不修改滤波RTL、系数、字长、
舍入、饱和、valid时序、复位、时钟、键盘或DAC接口**。同一份
`374 LUT / 388 FF / 4 DSP / 4 RAMB18E1`综合网表继续使用`ExploreWithRemap`，只把
`place_design`显式改为`ExtraTimingOpt`，最终得到
**343 LUT / 386 FF / 151 Slice / 4 DSP / 4 RAMB18E1（2 Tile）/ 2 MMCM**。相对P3-R再少
5 LUT和3 Slice，FF/DSP/BRAM/MMCM不变；WNS/WHS为 **+45.025/+0.116 ns**，AD9708
setup/hold为 **+76.116/+78.117 ns**，总/动态/静态功耗仍为
**0.271/0.199/0.072 W**。

本轮先纠正了被后续GUI覆盖的旧综合DCP和“primitive数量不等于Vivado资源利用率”两处
测量风险，再完成11种布局指令及多种二次网表优化的公平扫描。最终源码Smoke/Release均为
**17/17 PASS**，14组全链4x/8x/128x全部0 LSB；8类复位、1200次CDC、100次切族和10次
动态切档全部通过。343-LUT正式routed DCP又通过默认DAC活动与六档公开键盘网表仿真：
44.1 kHz为`177/353/5645 edges/ms`，48 kHz为`192/384/6144 edges/ms`，六档DAC均持续
变化。普通Vivado工程从零约113秒复现343/386/4-DSP/4-RAMB18并生成bitstream。

2026-08-06 对一次手动GUI重跑得到348 LUT的问题完成闭环：该次`impl_1/runme.log`实际执行
的是无参数`place_design`，同时Vivado把工程中的`ExtraTimingOpt`写回为Default，因此它
复现的是P3-R而不是P3-S。常见触发方式是在工程配置或Git分支切换前已经打开Vivado，旧的
内存工程在保存时覆盖新`.xpr`。关闭全部Vivado进程、重新写入P3-S profile并Reset
`synth_1/impl_1`后，普通project flow再次得到343 LUT、386 FF和151 Slice，WNS/WHS仍为
`+45.025/+0.116 ns`。以后请使用
`matlab_fir/national_finals/vivado/open_national_finals_gui_clean.ps1`打开工程；该入口会拒绝
已有Vivado进程，并在发现策略漂移时自动清除陈旧run。

**2026-08-06 用户已完成P3-S物理板验证，确认44.1/48 kHz两个输入家族下
4x/8x/128x各档采样率均正确，DAC输出波形正常；P3-S曾据此升级为正式实板发布，现由
P3-T取代并保留为前一实板安全回退。**正式bit SHA-256为
`DDD4F906967F5E039181A9DB17CE339615AE2A7744173519C471F2316086ED2A`。完整策略矩阵、
测量纠正、RTL/Timing/Power/DAC/GUI证据与复现步骤见
[P3-S执行反馈](matlab_fir/national_finals/results/p3s_extratimingopt_343lut_execution_feedback.md)和
[`p3s_343lut_386ff_4dsp_2bram_signedoff`](matlab_fir/national_finals/vivado_results/p3s_343lut_386ff_4dsp_2bram_signedoff)。

## 前一正式实板通过回退：348 LUT / 4 DSP P3-R DSP空闲拍舍入饱和版（2026-08-06）

P3-R在保持 **4 DSP / 2 BRAM Tile / 2 MMCM** 不变的前提下，复用Stage2/3共享
DSP48E1的MAC后空闲周期：第一尾拍在DSP内部完成精确Q15舍入，下一拍用
`PATTERNDETECT/PATTERNBDETECT`检查目标位宽的符号扩展，溢出时再由同一DSP把最大值或
最小值直接装入PREG。与P3-Q“只输出Pattern标志、仍保留Fabric饱和mux”的失败结构不同，
P3-R把宽比较器和宽饱和mux一起从Fabric移除。最终综合为374 LUT/388 FF，布局布线为
**348 LUT / 386 FF / 154 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**；相对P3-O再少13 LUT，
相对已实板通过的P3-M少20 LUT，FF/DSP/BRAM/MMCM和0.271 W功耗均不增加。WNS/WHS为
**+45.200/+0.121 ns**，AD9708 setup/hold为 **+76.116/+78.117 ns**。

最终同源码Smoke/Release均为 **17/17 PASS**；14组完整链输入在4x/8x/128x全部0 LSB，
覆盖真实RAMB18、正负饱和、8类复位、1200次CDC、100次家族切换及10次动态倍率切换。
正式routed DCP又通过默认DAC活动和44.1/48 kHz六档公开按键级网表仿真；普通Vivado GUI
工程从零完成综合、实现和bitstream并复现348/386/4-DSP/4-RAMB18。**2026-08-06用户完成
物理板验证，确认44.1/48 kHz两个家族下4x/8x/128x各档输出采样率均正确，DAC输出波形
正常；P3-R据此升级为当前正式实板通过发布。**P3-M 368-LUT仍保留为前一实板安全回退。完整试验矩阵、失败候选、
频响、Timing/Power、哈希和复现步骤见 [P3-R执行反馈](matlab_fir/national_finals/results/p3r_4dsp_dsp_sequential_saturation_execution_feedback.md)。

## P3-Q 4-DSP Pattern 饱和优化：No-Go，保留361-LUT P3-O（2026-08-05）

本轮在DSP固定为4、BRAM固定为2 Tile的前提下，把Stage1与Stage2/3的宽位符号扩展/
饱和判断尝试迁入现有DSP48E1的`PATTERNDETECT/PATTERNBDETECT`。候选先通过Smoke
**17/17**：Stage1行为/真实RAMB18各1400输出、Stage2 336输出、Stage3 671输出和全链
4x/8x/128x均为0 LSB，复位、CDC、时钟族及动态切档全部通过。但公平四组综合为
**395（基线）/396（仅Stage1）/414（仅Stage2/3）/415（组合）LUT**，FF均388、DSP均4、
BRAM均2 Tile。固定宽比较器原本能与饱和mux联合折叠，改用Pattern标志后反而增加LUT5，
因此按Stop/Go规则不进入实现，不虚构候选Timing、功耗或bitstream结果。

失败试验RTL和构建参数已逐项撤销，该阶段正式工程恢复P3-O；当时推荐为
**361 LUT / 386 FF / 158 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**，P3-M 368-LUT实板版仍是
安全回退。完整原理、逐项验证、原语计数、资源矩阵、停止理由和回退路线见
[P3-Q 4-DSP Pattern饱和优化执行反馈](matlab_fir/national_finals/results/p3q_4dsp_pattern_saturation_execution_feedback.md)。

## P3-P 近期论文驱动优化审计：No-Go，继续保留361-LUT P3-O（2026-08-05）

本轮查阅并筛选了2022～2026年的BLMAC、有限字长最优FIR、MCM/ILP、乘累加联合优化、
adder-mux联合优化和时分复用常数乘论文，并对P3-O做rebuilt层次热点审计。实际完成
BRAM输出直连、Stage2/3级联饱和及四种实现策略扫描、DSP PREG直出、窄valid屏蔽宽
复位、显式RAMB18测试音ROM五类候选。进入实现的候选LUT分别为367、最低369、370和
368，均未优于P3-O的361 LUT；直接PREG输出虽少43 FF，却使综合LUT增至416，按停止线
未实现。因此该轮不改正式滤波RTL，当时继续保留P3-O工具候选和P3-M实板安全回退。

完整论文链接、适用性分析、层次热点、原语仿真问题与修复、Synth/Route/Timing/Power
对比和No-Go依据见 [P3-P近期论文驱动优化执行反馈](matlab_fir/national_finals/results/p3p_recent_paper_driven_optimization_execution_feedback.md)。

## 前一工具签核候选：361 LUT / 4 DSP P3-O ExploreWithRemap版（2026-08-05）

P3-O 从已物理板通过的 P3-M 正式标签逐文件核对源码后建立，**不修改滤波 RTL、系数、字长、舍入、饱和、valid时序、时钟或DAC接口**，只把完整板级 `opt_design` 从 `Default` 改为 `ExploreWithRemap`。同一395-LUT/388-FF综合网表从P3-M的368 LUT收敛到 **361 LUT / 386 FF / 158 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**；WNS/WHS为 **+44.989/+0.103 ns**，AD9708 setup/hold为 **+76.116/+78.117 ns**，功耗仍为 **0.271/0.199/0.072 W**。

本轮Release RTL为 **17/17 PASS**：冲激、10个固定seed、正/负满量程和−1 dBFS强信号在4x/8x/128x均逐样本0 LSB；8类复位恢复、1200次CDC、100次时钟族切换和10次动态倍率切换均通过。361-LUT routed DCP默认启动6 ms得到11290个DAC边沿和7461次数据变化；公开按键级六模式得到44.1 kHz的`177/353/5645 edges/ms`与48 kHz的`192/384/6144 edges/ms`，六档数据均持续变化。

普通GUI工程、包装脚本和实现Tcl在该阶段统一固定`ExploreWithRemap`，GUI发布门槛收紧为`LUT<=362 / FF<=400 / DSP=4 / RAMB18E1=4 / MMCM=2`，避免手动实现静默回到368-LUT Default或错误参数。普通GUI工程从零执行`synth_1 -> impl_1 -> write_bitstream`约127秒，再次复现361/386/4-DSP/4-RAMB18并成功生成bitstream。P3-O是前一工具完整签核候选；其后已由348-LUT P3-R取代，P3-M仍是物理板安全回退。完整方法、超时重跑、Timing/功耗、哈希、正式证据目录和复现步骤见 [P3-O 361-LUT执行反馈](matlab_fir/national_finals/results/p3o_explorewithremap_361lut_execution_feedback.md)。

## 前一实板通过回退：368 LUT / 4 DSP P3-M Stage1 DSP-register 版（2026-08-05）

当前正式分支为 `national-finals-p3m-stage1-dspreg-385target`，从已板测的 P3-L 正式版继续把 Stage1 对称左操作数移入 DSP48E1 `AREG`，并用动态 `INMODE` 在 DSP 内部屏蔽未初始化的 A/D 历史样本；当前样本先写入已有单 RAMB18，再按 `L0,R0,L1,R1,...,L25,R25` 读回，删除原 24-bit Fabric 左样本寄存器、旁路 mux 和宽掩码逻辑。滤波系数、字长、Q15 舍入、饱和、valid 相位、Stage2/3、CIC、ROM、时钟、按键与 DAC 接口均不变。

最终布局布线为 **368 LUT / 386 FF / 156 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**，相对 P3-L 减少 **29 LUT / 23 FF / 5 Slice**，WNS/WHS 为 **+44.836/+0.117 ns**，AD9708 setup/hold 为 **+76.116/+78.117 ns**，vectorless 功耗仍为 **0.271 W**。Bitstream SHA-256 为 `7785D3B3110BC534A546BEAD1F05958DA736B99A46FA1D03800C406FCB5D7D7A`。

本版已完成 Stage1 行为 RAM 与真实 UNISIM RAMB18E1 两套1400输出0-LSB对比、最终同源码 Smoke/Release 各 **17/17**、14组全链冲激/10 seed/满量程/强信号4x/8x/128x 0 LSB、8类复位恢复、10次动态倍率切换、普通Vivado GUI从零综合/实现/Bitstream，以及routed-DCP默认DAC活动和六模式公开按键路径测试。六档得到44.1 kHz `177/353/5645 edges/ms`、48 kHz `192/384/6144 edges/ms`，DAC数据均持续变化。**2026-08-05 用户完成物理板复测，确认各档位采样率均正确且 DAC 输出波形正常，因此 P3-M 正式升级为当前最低 LUT 的实板通过发布；P3-L 397-LUT 标签保留为前一实板安全回退。**完整方法和证据见 [P3-M Stage1 DSP 内部寄存器优化执行反馈](matlab_fir/national_finals/results/p3m_stage1_dspreg_368lut_execution_feedback.md) 与 [`p3m_stage1_dspreg_synth_r1`](matlab_fir/national_finals/vivado_results/p3m_stage1_dspreg_synth_r1)。

## P3-N 后续实验：CIC one-hot burst 状态（No-Go，2026-08-05）

在 P3-M 上继续审计后确认：N3 Hold CIC 的两级低速 comb 已经串行共享同一个 LUT/CARRY 减法数据通路，没有第二次共享空间。随后把4-bit递减 burst计数器改为15-bit thermometer/shift window，以少量FF换取减一器和比较LUT。候选通过CIC单元连续/随机停顿/突发中复位逐周期等价、最终Smoke/Release各 **17/17**，Release的冲激、10个随机种子、正负满量程和强−1 dBFS在4x/8x/128x均为 **0 LSB**。

第一次综合虽然仍为395 LUT/388 FF，但网表审计发现板级参数实际绑定为0，因此立即作废；补齐 `board -> common -> filter -> CIC` 参数链并加入板级启用断言后，有效同策略综合为 **403 LUT / 399 FF / 4 DSP / 2 BRAM Tile / 2 MMCM**，相对P3-M综合基线增加 **8 LUT和11 FF**。本路线按Stop/Go规则停止在综合阶段，没有实现、Timing、功耗、bitstream或板测结果；正式工作版本仍为P3-M 368-LUT实板通过版。滤波器数值路径未改变，六工况频响严格继承P3-M。完整过程、首次假结果纠正、验证路径和资源表见 [P3-N CIC one-hot burst 执行反馈](matlab_fir/national_finals/results/p3n_cic_onehot_burst_nogo_execution_feedback.md)。

## 前一正式实板通过回退：397 LUT / 4 DSP P3-L 共享保护时基版（2026-08-04）

当前正式分支为 `national-finals-p3l-safe-packedrom-395target`，最终布局布线资源为 **397 LUT / 409 FF / 161 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**，WNS/WHS 为 **+44.408/+0.121 ns**，AD9708 setup/hold slack 为 **+76.116/+78.117 ns**，vectorless 功耗为 **0.271 W（Medium confidence）**。正式 bitstream SHA-256 为 `AC8735BAD24450FA038C79B104072DA70CEFA6FEF7B599C52CE16ECA5F091440`。

本版已完成 Smoke/Release **16/16 PASS**、完整链冲激/随机/满量程/强信号的 4x/8x/128x **0 LSB** 对拍、8 类复位恢复、10 次动态倍率切换、默认档和六模式 routed-DCP DAC 活动测试、RAMB18 INIT、Timing、DRC/CDC、功耗及 bitstream 闭环。**2026-08-04 用户完成物理板复测，确认 DAC 输出正常，44.1/48 kHz 两个家族下各倍率档位的实际采样频率均正确**。因此 P3-L 已从工具候选正式提升为板级验证通过版本；P3-K 427-LUT 版降为安全历史回退。

正式标签为 `nf-p3l-final-397lut-409ff-161slice-4dsp-2bram-boardverified`。完整优化、验证与板测记录见 [P3-L 395～405 LUT 目标优化执行反馈](matlab_fir/national_finals/results/p3l_395lut_target_optimization_execution_feedback.md)，发布证据见 [`p3l_safe_packedrom_sharedguard`](matlab_fir/national_finals/vivado_results/p3l_safe_packedrom_sharedguard)。

## 前一实板通过回退：427 LUT / 4 DSP DAC-ROM 安全版（2026-08-03）

用户在实物板上发现此前 412-LUT bitstream 的 `DA_CLK` 存在，但 `dac_data` 固定为中点码 128，DAC 不出波。使用同一个已布线 DCP 做完整板级功能仿真后精确复现：2 ms 内有 11,290 个 DAC 时钟边沿，但数据跳变为 0；复位、静音、模式、valid 与各级历史填充均正常，测试音 ROM 的采样值却始终为 0。

根因是 424-LUT Packed-ROM 优化把“下一地址”写进推断 BRAM 的空闲高 8 bit，并在 `$readmemh` 后用第二个 procedural `for` 循环补写高位。RTL 仿真接受这种二次初始化，但 Vivado 2018.3 没有把补写后的高位可靠固化进 RAMB18 INIT；地址 0 的高位保持 0，硬件因而永久自循环在首个零样点。该问题同时影响 424-LUT Packed-ROM 与继承它的 412-LUT 指针推导版本，两个旧 bitstream/tag 均已撤销上板推荐资格，不能再作为稳定回退。

当前分支 `national-finals-p3k-4dsp-dac-rom-fix` 恢复 24-bit 纯同步 ROM 和普通时序地址计数。修复版 post-route 为 **427 LUT / 416 FF / 177 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**，WNS/WHS **+44.983/+0.105 ns**，AD9708 setup/hold **+76.116/+78.117 ns**，vectorless 总/动态/静态功耗 **0.271/0.199/0.072 W**。修复版 routed DCP 在相同完整板级测试中达到 **11,290 个时钟边沿、7,461 次 DAC 数据跳变、88 次 ROM 样点更新**，Stage1/Stage2/CIC 均持续变化；bitstream SHA-256 为 `0FFEC2DC929AE3A16E2CB08B32F5B056F378902416E1E191B9D7D08CC6B0EA7D`。

修复版相对失效的 412-LUT 版本增加 15 LUT，并不是滤波器数据通路退化。旧 Packed-ROM 在综合后的 BRAM 高 8 bit 实际成为常量 0，使“下一地址”反馈、地址递增、范围比较与回绕选择等逻辑被常量传播或合并；较低 LUT 数包含了功能失效带来的虚假收益。修复后恢复真实的 8-bit 地址递增器、44.1/48 kHz 地址范围比较和回绕/家族选择逻辑，综合由 449/420 LUT/FF 变为 456/422，post-route 由 412/418 变为 427/416。综合只增加 7 LUT、布线后增加 15 LUT，是 `opt_design` 跨层合并与映射变化所致；DSP、BRAM、MMCM、滤波系数、频响和功耗均不变。

本轮新增了可重复的布局布线后板级门禁：`run_postroute_board_dac_activity.ps1` 从 routed DCP 导出 functional netlist，完整运行真实双 MMCM、65535 拍上电复位、ROM、插值链和 DAC ODDR，并要求 DAC 时钟与数据活动同时达标。详细定位、修复和证据见 [P3-K DAC-ROM 修复执行反馈](matlab_fir/national_finals/results/p3k_dac_rom_hardware_fix_execution_feedback.md)，bit、DCP、报告和回归日志见 [`p3k_final_427lut_416ff_177slice_4dsp_2bram_dacromfix`](matlab_fir/national_finals/vivado_results/p3k_final_427lut_416ff_177slice_4dsp_2bram_dacromfix)。**2026-08-03 用户已完成修复 bitstream 实板复测，确认 DAC 输出正常、采样率正常**；至此 MATLAB、RTL、综合实现、post-route、bitstream 与实板 DAC/采样率验证形成闭环。当前未提供逐档实测频率和频谱数据，因此本文不虚构这些测量值。

## 已撤销发布：412 LUT / 4 DSP 指针推导历史状态版（2026-08-03）

当前工具侧默认为 `national-finals-p3k-4dsp-pointer-fill` 分支的 **412 LUT / 418 FF / 168 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM** 版本。正式实现没有采用会延迟首样点的“复位后 64 拍清 RAM”，而是复用现有环形写指针推导历史填充深度：Stage1 的两组 6-bit fill 状态压缩为 1 个满标志，Stage2/3 的三组 4-bit fill/任务快照压缩为 3 个满标志。短复位读掩码、任务头快照、滤波系数、字长、舍入、饱和、valid 时序和板级接口均保持不变。

正式 post-route 的 WNS/WHS 为 **+45.083/+0.056 ns**，TNS/THS=0，AD9708 setup/hold 为 **+76.116/+78.117 ns**，vectorless 总/动态/静态功耗为 **0.271/0.199/0.072 W**。Release RTL **15/15 PASS**：14 组全链输入的 4x/8x/128x 全部 0 LSB，8 个短复位场景各比较 4096 个 128x 输出，10 次动态切换通过。bitstream SHA-256 为 `E7512D603231276CDCED13C5FEA3A7284558B941CF4102FA1E3339CD5F5EF1CF`。

相对前一 424-LUT Packed-ROM 签核版，本版净减 **12 LUT、13 FF、1 Slice**，DSP、BRAM、MMCM 和功耗不变。滤波传递函数不变，MATLAB 六工况最差绝对通带偏差/峰峰纹波/阻带仍为 **0.007730/0.006192/72.371 dB**，严格线性相位。Default/AddRemap/Explore 均为 412/418/168，ExploreWithRemap 为 415/418/169，因此保留 Default。完整方法、首轮失败原因、RTL/实现证据和回退路线见 [P3-K 指针推导执行反馈](matlab_fir/national_finals/results/p3k_pointer_derived_fill_execution_feedback.md)。物理板下载和仪器测量尚未在当前环境执行，不能写成实板已通过。

## 前一发布结论：424 LUT / 4 DSP Packed-ROM 版（2026-08-03）

该轮工具侧默认由 P3-J 430-LUT 基线更新为 `national-finals-p3j-4dsp-bram-microengine` 分支的 **424 LUT / 431 FF / 169 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM** 版本。它不改变 FIR/CIC 系数、字长、舍入、饱和或输出序列，而是把测试音 ROM 的空闲高 8 bit用于保存下一地址，删除 fabric 地址递增/范围比较/回绕 mux，并用 4-bit `{valid,family,mode}` 压缩矩阵键盘扫描上下文。相对前一 430-LUT 签核基线减少 **6 LUT/7 Slice**，DSP、BRAM、MMCM、FF和功耗不增加。

正式 clean-source 结果的 WNS/WHS 为 **+45.042/+0.080 ns**，TNS/THS=0，AD9708 setup/hold 为 **+76.116/+78.117 ns**，vectorless 总/动态/静态功耗为 **0.271/0.199/0.072 W**。MATLAB 六工况最差绝对通带偏差/峰峰纹波/阻带为 **0.007730/0.006192/72.371 dB**，严格线性相位；Release RTL 为 **15/15 PASS**，14 组全链输入的 4x/8x/128x 全部 0 LSB。普通 Vivado GUI 工程从零重建也复现 424/431/4-DSP/4-RAMB18/2-MMCM 并生成 bitstream。物理板下载和仪器测量尚未在当前环境执行，不能写成实板已通过。

本轮同时实测了 5-RAMB18 的 Stage1/Stage2/3 拆分、两相共享 CIC、高/中/默认综合和 Default/AddRemap 实现。增加到 5 个 RAMB18E1 分别得到 478 或 477 LUT，没有出现 BRAM 换入 200 多 LUT 的收益；最终保留点仍只用 4 个 RAMB18E1。完整逐项数据、失败原因、超时处理和复现命令见 [P3-J 4-DSP BRAM/微引擎执行反馈](matlab_fir/national_finals/results/p3j_4dsp_bram_microengine_execution_feedback.md)，正式报告/bitstream/Release/GUI 日志见 [`p3j_final_424lut_431ff_169slice_4dsp_2bram_packedrom`](matlab_fir/national_finals/vivado_results/p3j_final_424lut_431ff_169slice_4dsp_2bram_packedrom)。bitstream SHA-256 为 `2BA97CCE337638D57268EE04CCE0D09D2FDF6637B1A4A25D35E57BCB49C3ED4B`。

## 424-LUT 后续 LUT-only / FF 换 LUT 审计（2026-08-03）

在 DSP=4、BRAM Tile=2、MMCM=2 不变且允许 FF 小幅增加（目标不超过440、上限448）的条件下，已继续实测系数 BRAM 终止标志、键盘移位去抖、CIC 15-bit 移位尾状态、共享启动/扫描计数以及五种 `opt_design` 策略。所有完成 RTL 的候选均通过对应 XSim；组合候选另通过完整 Smoke **15/15**。但最终布局布线均未低于当前 424-LUT 版本：

| 后续候选 | Synth LUT/FF | Placed LUT/FF/Slice | DSP | BRAM Tile | WNS/WHS | 结论 |
|---|---:|---:|---:|---:|---:|---|
| 当前 Packed-ROM 基线 | 453/433 | **424/431/169** | 4 | 2 | **+45.042/+0.080 ns** | 保留 |
| 系数 BRAM 终止标志 | 453/428 | 430/426/177 | 4 | 2 | +45.674/+0.096 ns | 少5 FF但多6 LUT，No-Go |
| 系数标志+共享启动计数 | 451/428 | 429/426/182 | 4 | 2 | +45.156/+0.056 ns | 综合下降、实现反升，No-Go |
| 仅共享启动计数 | 452/433 | 427/431/173 | 4 | 2 | +44.926/+0.096 ns | 多3 LUT，No-Go |
| 原始 RTL 同环境重跑 | 453/433 | **424/431/169** | 4 | 2 | **+45.042/+0.080 ns** | 精确复现 |

固定451-LUT综合 DCP 的实现策略结果为：Default/Explore/AddRemap/ExploreWithRemap 均为429 LUT，ExploreArea 为495 LUT。CIC 移位状态则在综合阶段已增至457 LUT/439 FF；键盘移位去抖在全局综合中净收益为0，二者均按停止线未进入实现。这说明当前424版的优势来自 Vivado 对原结构的跨层合并，局部 RTL 数量下降不能直接等价为 post-route LUT 下降。

当前推荐版本、资源、Timing、功耗、bitstream 和频响指标均保持不变；本轮没有实物板，不能把工具侧验证写成新候选已通过板测。完整逐项方法、失败原因、验证证据、分支、提交和标签见 [P3-J LUT-only / FF 换 LUT 执行反馈](matlab_fir/national_finals/results/p3j_lut_only_ff_tradeoff_execution_feedback.md)。

## 424-LUT 后续结构优化：环形指针推导填充深度（2026-08-03）

前一轮局部逻辑替换没有降低 post-route LUT；本轮改为删除冗余状态本身。Stage1 在首次回绕前可直接把 `wr_ptr` 解释为已写深度，Stage2/3 则用 `-job_history_head` 推导任务启动时的深度；达到 52/9/6 点后各用一位粘滞满标志。由此把 24 bit fill 状态压缩为 4 bit 满状态，保持未写地址屏蔽和 8 拍短复位语义。

| 候选 | Synth LUT/FF | Routed LUT/FF/Slice | DSP | BRAM Tile | WNS/WHS | 结论 |
|---|---:|---:|---:|---:|---:|---|
| **DAC-ROM 安全修复版** | **456/422** | **427/416/177** | **4** | **2** | **+44.983/+0.105 ns** | **当前可上板候选** |
| Packed-ROM 旧签核版 | 453/433 | 424/431/169 | 4 | 2 | +45.042/+0.080 ns | ROM 地址锁死，禁止上板 |
| 指针推导旧版 | 449/420 | 412/418/168 | 4 | 2 | +45.083/+0.056 ns | ROM 地址锁死，禁止上板 |
| AddRemap / Explore | 同一 DCP | 412/418/168 | 4 | 2 | +45.083/+0.056 ns | 与 Default 同资源 |
| ExploreWithRemap | 同一 DCP | 415/418/169 | 4 | 2 | +45.387/+0.121 ns | 多3 LUT/1 Slice，No-Go |

首个“复位后 64 拍主动清 RAM”候选因丢失短复位后的首批输入而在全链位真门禁失败，已在综合前撤销；最终指针推导版不增加启动延迟，并通过 Smoke/Release 15/15、14 组全链 0 LSB、8 组复位恢复、10 次动态切换、布局布线、时序、DRC/CDC、功耗评估和 bitstream 生成。该结果仍待物理板复测。

## 优化演进总览（建议先读）

本节按时间顺序统一整理“最初4x+2x、区域赛全2x、FIR-CIC、全国赛全2x对照、6-DSP CIC、440/442/434-LUT、Route 1、P1/P3/P4工程闭环、P3-J～P3-M RTL演进、P3-O实现重映射、P3-P近期论文驱动审计、P3-Q Pattern饱和审计，以及P3-R/P3-T DSP空闲拍优化与P3-S布局打包”。重要纠错：旧424-LUT/6-DSP与436-LUT/5-DSP版本有8x/128x约−6.02 dB标度缺陷；412-LUT/4-DSP与424-LUT/4-DSP又有测试音ROM地址锁死缺陷。当前正式实板通过发布为P3-T `341 LUT / 381 FF / 163 Slice / 4 DSP / 2 BRAM Tile`；P3-S `343 LUT / 386 FF / 151 Slice / 4 DSP / 2 BRAM Tile`降为前一实板安全回退。

### 统计与比较口径

不同阶段曾使用不同顶层和输入采样率。为避免把模块级结果、完整板级结果和 MATLAB 候选混为一谈，本文统一使用以下标记：

| 口径 | 含义 | 可以比较什么 |
|---|---|---|
| **独立链** | 只综合插值数据通路，不含 PCM ROM、按键、DAC 包装、双采样率时钟等板级功能 | 适合判断滤波结构本身的面积变化 |
| **单采样率板级** | 44.1 kHz 完整演示顶层，通常含 PCM ROM、模式控制和 DAC 接口 | 区域赛各版本可以纵向比较 |
| **全国赛板级** | 44.1/48 kHz 双采样率、4x/8x/128x 完整顶层，含 2 个 MMCM | 全国赛 FIR-CIC 与全国赛全 2x 可以直接比较 |
| **MATLAB 候选** | 只完成数学或定点搜索，未进入完整 RTL/实现 | 只能比较频响，不能填写 FPGA 资源 |

下文的 LUT、FF、DSP、BRAM 和 MMCM 均取 Vivado 布局布线后结果；明确标为“独立链”的早期数据除外。BRAM 按 BRAM Tile 计数，两个 RAMB18E1 等于一个 BRAM Tile。功耗均为 Vivado vectorless 估计，不是实测值；`0.168/0.169 W` 来自早期单采样率顶层且为 Low confidence，`0.271 W` 来自全国赛双采样率顶层且为 Medium confidence，因此两组数值不能用于推导滤波器本身的功耗增量。

### P3-J 前一签核基线：Stage3 吸收 128x CIC 均衡器

P3-J 把 P4-D 独立的 11-tap shift-add CIC 均衡器折叠进第三级 FIR：4x/8x 使用原 flat Stage3 系数，128x 使用联合设计的 compensated Stage3 系数，然后直接进入 N3 Hold CIC16。两组系数占用统一 RAMB18E1 的空闲地址，signed-18 高两位存入 parity；模式在 Stage3 job 边界快照，补偿输出保留经满量程证明所需的 signed-21。独立均衡器不再进入板级网表，DSP、BRAM、MMCM不增加。

Release 从零回归 **15/15 PASS**：冲激、10 个固定 seed×4096、正/负满量程和新增 997 Hz/−1 dBFS 强信号共 14 组全链输入，4x/8x/128x 逐样本 **0 LSB**；另通过 8 个内部状态复位场景、10 次不停机倍率切换、1200 次原子 CDC 切换和 RAMB18 parity 原语测试。最终从 clean source 复现的板级 post-route 为 **430 LUT / 431 FF / 176 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**，相对 P4-D R2 减少 **49 LUT / 37 FF / 22 Slice**；WNS/WHS **+45.636/+0.119 ns**，AD9708 setup/hold **+76.116/+78.117 ns**，功耗 **0.271 W**。详细结构见 [P3-J RTL 签核](matlab_fir/national_finals/results/p3_joint_stage3_rtl_signoff.md)，后续正交扫描、失败原因和可复现性修复见 [P3-J 后续优化指导执行反馈](matlab_fir/national_finals/results/p3j_next_optimization_execution_guide_execution_feedback.md)。

### P3-J 后续指导执行：DSP/BRAM Pareto、有限字长与可复现构建

指导中的 P1/P2/P3/P5 已按停止线执行。默认 4-DSP、低 DSP、低 BRAM和交叉点的实测结果如下；所有保留点均已完成 post-route、正时序和 bitstream，默认版另于 2026-08-03 重跑 MATLAB 与 Release RTL 15/15。

| P3-J 候选 | LUT | FF | Slice | DSP | RAMB18 / BRAM Tile | WNS/WHS | 结论 |
|---|---:|---:|---:|---:|---:|---:|---|
| **DAC-ROM 修复候选** | **427** | **416** | **177** | **4** | **4 / 2.0** | **+44.983/+0.105 ns** | 当前可上板候选 |
| 指针推导旧版 | 412 | 418 | 168 | 4 | 4 / 2.0 | +45.083/+0.056 ns | ROM 地址锁死，禁止上板 |
| Packed-ROM 旧版 | 424 | 431 | 169 | 4 | 4 / 2.0 | +45.042/+0.080 ns | ROM 地址锁死，禁止上板 |
| P3-J Packed-ROM 前基线 | 430 | 431 | 176 | 4 | 4 / 2.0 | +45.636/+0.119 ns | 安全历史回退 |
| 3-DSP | 466 | 457 | 188 | 3 | 4 / 2.0 | +45.785/+0.121 ns | 低 DSP Pareto |
| 2-DSP | 488 | 486 | 191 | 2 | 4 / 2.0 | +45.736/+0.060 ns | 最低 DSP Pareto |
| 1.5-BRAM | 456 | 450 | 181 | 4 | 3 / 1.5 | +46.033/+0.116 ns | 低 BRAM Pareto |
| 3-DSP + 1.5-BRAM | 478 | 476 | 191 | 3 | 3 / 1.5 | +45.610/+0.115 ns | 交叉 Pareto |
| 1-BRAM | 495 | 480 | 186 | 4 | 2 / 1.0 | +45.807/+0.108 ns | 超过 490-LUT 停止线，No-Go |
| 9-tap Stage3 | 441 | 431 | 177 | 4 | 4 / 2.0 | +46.190/+0.121 ns | 比 430 基线多 11 LUT，No-Go |

历史“430 报告但手动重跑 436”的原因也已闭环：430 实际来自 `AreaOptimized_high/full/on`，旧包装器却默认 `rebuilt` 并可复用未标记来源的 DCP。现在批处理默认和 GUI 都统一为 `full`，综合写 `national_finals_synth_provenance.txt`，实现前强制校验指纹；本机默认 `-Step all` 约 102 秒完成。`-jobs` 固定为 4，避免 GUI 曾以 19 jobs 触发内存不足或 route 假死。

### P1 正确性修复：Stage 3 真 Q15 与绝对增益门禁

独立复核冲激直流和发现：旧 Stage 3 整数系数只有 Q14 幅度，共享 MAC 却固定右移 15 bit。4x 不经过 Stage 3，绝对增益为 -0.001599 dB；8x/128x 则分别为 -6.023392/-6.024933 dB。旧频响脚本对每个节点分别除以自身冲激和，因此只证明了频响形状，没有证明模式间幅度一致。

P1 将 Stage 3 统一为真 Q15，修正 MATLAB、RTL 系数 ROM、统一 RAMB18E1 INIT 与原语测试，恢复完整 38-bit signed 饱和路径，并新增 `±0.01 dB` 绝对增益和 `0.01 dB` 模式间增益差门禁。修复后 4x/8x/128x 为 -0.001599/-0.002709/-0.003480 dB，最大差 0.001881 dB；RTL 10/10 和全链路 0 LSB 回归通过。

修复版 post-route 为 **446 LUT / 471 FF / 5 DSP / 3 BRAM Tile / 2 MMCM**，WNS/WHS **+45.104/+0.121 ns**，功耗 0.271 W。多出的 10 LUT 是恢复 38-bit 饱和检查的正确性成本。完整证据见 [P1 Stage 3 Q 格式修复签核](matlab_fir/national_finals/results/p1_stage3_qformat_fix_summary.md)。

### P3 工程闭环：原子 CDC、同步复位与 AD9708 STA

P3 保持 P1 的系数和位真样点不变，把两位模式选择改成 request/ack 原子握手，数据通路改为同步复位，并加入 MMCM 锁定同步、安全静音、IOB 数据寄存器和 ODDR DAC 时钟转发。XSim 从零重跑为 **11/11 PASS**，其中模式 CDC 覆盖 1200 次全方向事务，双 MMCM 家族切换压力测试 100 次，动态倍率切换的边沿数为 32/128/256/4096 且无 runt/X。

post-route 为 **462 LUT / 447 FF / 180 Slice / 5 DSP / 3 BRAM Tile / 2 MMCM**，WNS/WHS **+46.140/+0.050 ns**，功耗 **0.271 W**。AD9708 约束包含 2.0 ns setup、1.5 ns hold 和 0.5 ns 附加裕量，最差输出 setup/hold 为 **+76.116/+78.117 ns**。bitstream SHA-256 为 `A38C6D4F4B3C023DBD22897505B85864990CFC7C5D974A84FA38C5F0ADE21033`。详细证据和 CDC/DRC waiver 见 [P3 工程闭环签核](matlab_fir/national_finals/results/p3_engineering_closure_summary.md)，指导合理性与后续 P4/P5 分工见 [下一阶段优化指导执行记录](matlab_fir/national_finals/results/next_stage_optimization_guide_execution.md)。

### P4-A 4-DSP Pareto 版：N3 Hold 严格等价改写

P4-A 将三级 CIC 的 `C³ → ↑16 → I³` 按多速率恒等式改写为 `C² → Hold16 → I²`，保持 33-bit 模运算、输出归一化、valid 周期和所有滤波系数不变。新增测试与旧 CIC 比较 7680 个输出样本，连续输入、随机停顿和中途复位均为 0 LSB；完整 XSim 为 **12/12 PASS**。

同一全国赛板级顶层 post-route 为 **491 LUT / 444 FF / 197 Slice / 4 DSP / 3 BRAM Tile / 2 MMCM**，WNS/WHS **+45.738/+0.052 ns**，功耗 **0.271 W**，bitstream SHA-256 为 `D262BA94186D992016FE9FACD157E34FDB29EDF0F9A3433A38833A65B101C334`。相对 P3 的变化为 `+29 LUT / -3 FF / +17 Slice / -1 DSP`，因此它是最低 DSP 的 Pareto 候选，不替代最低 LUT 的 P3 版本。完整证据见 [P4-A N3 Hold 签核](matlab_fir/national_finals/results/p4a_n3_hold_4dsp_summary.md)。

### P4-B 2-BRAM-Tile Pareto 版：历史存储单端口时分复用

P4-B 保持 P4-A 的所有系数、位宽、舍入、饱和、valid 和输出样点不变，只重排历史 RAM。Stage 1 将当前输入旁路为第 0 对左样本，其余 51 次历史读在相邻 64 拍 `ce2_out` 窗口内串行完成，使双读历史从 2 个 RAMB18E1 降为 1 个；Stage 2/3 用 bank 地址把两组浅历史合并到另一个 RAMB18E1，并用一项写队列解决同拍更新。两处都使用显式 RAMB18E1，避免综合回退到 LUTRAM。

新增 Stage 1 新旧核对拍 1400 个输出、Stage 2/3 对拍 336/671 个输出，均为 0 LSB；完整 XSim 为 **14/14 PASS**。最终 post-route 为 **504 LUT / 493 FF / 202 Slice / 4 DSP / 2 BRAM Tile（4 RAMB18E1）/ 2 MMCM**，WNS/WHS **+45.637/+0.119 ns**，功耗 **0.271 W**。相对 P4-A 用 `+13 LUT / +49 FF / +5 Slice` 换掉 `1 个 BRAM Tile`；因此 P4-A 适合优先 LUT/FF，P4-B 适合优先 BRAM。bitstream SHA-256 为 `DA0665E43A8DA5230AB93FC786AB0EED47BD83FE393C9B1416BA3360B8DE5E85`，完整证据见 [P4-B 单 BRAM签核](matlab_fir/national_finals/results/p4b_single_bram_4dsp_summary.md)。

### P4-C 当前默认版：固定 CE 精简、DSP48 预加器和 CIC 4/3/2-DSP Pareto

P4-C 在 P4-B 的正确标度和 2-BRAM-Tile 结构上继续做严格等价优化：只在板级连续 2 的幂 CE 配置删除不可达的 Stage2/3 25-bit 写队列；在当前 Stage1 单 BRAM 核上重新实测并启用 DSP48E1 `D+A` 预加器；把 N3 Hold CIC 的两个保守 33-bit 状态按解析界收紧为 26/29 bit。通用模块仍保留写队列，CIC 也保留 4/3/2-DSP 可配置映射。

本轮还修复了 48 kHz 切换后首 ROM 地址、CDC `SETTLE_CYCLES>3` 截断和 GUI 仿真宏漂移，并增加历史 RAMB18 原语独立对拍。最终 RTL 为 **15/15 PASS**，MATLAB 重新分析当前 RTL impulse 的六工况频响和严格线性相位全部 PASS。

| P4-C 档位 | LUT | FF | Slice | DSP | BRAM | MMCM | WNS/WHS | 功耗估计 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **默认低 LUT/FF** | **479** | **468** | **198** | **4** | **2** | **2** | **+45.734/+0.121 ns** | **0.271 W** |
| 低 DSP-A | 504 | 494 | 198 | 3 | 2 | 2 | +45.853/+0.121 ns | 0.271 W |
| 低 DSP-B | 523 | 523 | 197 | 2 | 2 | 2 | +45.802/+0.121 ns | 0.270 W |

相对 P4-B，默认档减少 25 LUT、25 FF、4 Slice；3-DSP 和 2-DSP 档分别以 `+25 LUT/+26 FF`、`+44 LUT/+55 FF` 交换 1/2 个 DSP。三档均为同一最终 RTL 从头综合、布局布线和 bitstream 结果。默认 SHA-256 为 `814465320512830C98D0EDA5352D36797BF5C442CD27E3520B5B89601F1C52D3`；逐项指导判断、数学证明、策略扫描和未执行项见 [P4-C 执行反馈](matlab_fir/national_finals/results/p4b_rtl_next_optimization_guide_execution.md)。

### P4-D 当前发布闭环：固定签核配置、10-seed Release 与 CDC 物理约束

P4-D 不改变 P4-C 的滤波系数、定点路径、吞吐或资源拓扑，而是修复“脚本通过但 GUI/资产/回归规模可能漂移”的发布风险。新增固定参数的 `nf_signedoff_filter_core`，把算法配置与 Smoke/Release 规模完全解耦；GUI `sim_1` 显式登记 8 个日常 `.mem`，全链 testbench 在 `$readmemh` 前逐一预检资产。故意移走输入文件的负向测试已确认会立即报 `NF_ASSET_MISSING`。

发布级 MATLAB 生成冲激和 10 个固定 seed×4096 输入，共 44 个 `.mem`、41,293,728 字节；完整 Release XSim 为 **15/15 PASS**，每个 seed 的 4x/8x/128x 输出数分别为 `16605/33219/531584`，三个节点逐样本 **0 LSB**。旧 TB/指导中的 `531552` 少 32 点，已按 `138368+(4096-1024)×128=531584` 和十组实际 golden 行数修正。

request/ack bundled-data CDC 新增 `50.000 ns` bus-skew 约束，post-route 实测 `1.816 ns`、裕量 `48.184 ns`。重新实现仍为 **479 LUT / 468 FF / 198 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM**，WNS/WHS **+45.734/+0.121 ns**，AD9708 setup/hold **+76.116/+78.117 ns**，vectorless 功耗 **0.271 W**；独立 Tcl 和普通 GUI `impl_1 -> write_bitstream` 均通过。新 bitstream SHA-256 为 `44879C48B2A15481A2B7DE598EAA83DE02CD1DABBD9C9BD5D26F0E8399E3E378`。完整 TIMING-18/CDC 证据、发布清单和物理板待办见 [P4-D 发布闭环签核](matlab_fir/national_finals/results/p4d_release_closure_summary.md)。

P4-D Release V2 又完成了导出包深度审计：修正 20/21-bit golden，增加正负满量程边界用例和 reset-zero prefix 断言，将 CDC 改为精确 false path 加 50 ns bus-skew/absolute max-delay，并从干净提交 `e55dca0` 重建。Release/Smoke 均为 **15/15 PASS**，13 组 Release 向量的 4x/8x/128x 全部 **0 LSB**；post-route 仍为 **479 LUT / 468 FF / 4 DSP / 2 BRAM Tile / 2 MMCM**，WNS/WHS **+45.734/+0.121 ns**，mode bus skew **1.813 ns**、最大绝对延迟 **0.912 ns**，bit SHA-256 为 `8630210663629357237AAA3F076348FBE65610EAAB61ADA4706E81F75AAF02A6`。完整干净构建清单和六工况数值见 [P4-D Release V2 签核](matlab_fir/national_finals/results/p4d_release_v2_clean_signoff.md)。

### P4-E/P4-F：按深度审计指导验证低 BRAM Pareto

P4-E 将板级 PCM ROM 与 Stage1 历史映射到同一个 512×36 RAMB18E1：Stage1 读优先，PCM 请求保持到已证明的空闲窗口，RAM 输出寄存器同时作为 PCM 预取缓冲。P4-F 再把 Stage2/3 历史从 RAMB18E1 改为 8 个 RAM32M。两版都不改变系数、DSP 数据通路、定点舍入、饱和或 valid 序列，Release 对拍证明 4x/8x/128x 与 P4-D 逐样本 0 LSB，因此继承相同六工况频响。

| 版本 | LUT | FF | Slice | DSP | RAMB18 / BRAM Tile | MMCM | WNS/WHS | 功耗（总/动态/静态） | 验证与定位 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| **P4-D 默认** | **479** | **468** | **198** | **4** | **4 / 2.0** | **2** | **+45.734/+0.121 ns** | **0.271/0.199/0.072 W** | 默认最低 LUT/FF；15/15 |
| P4-E PCM/Stage1 共享 | 491 | 487 | 202 | 4 | 3 / 1.5 | 2 | +46.132/+0.105 ns | 0.271/0.199/0.072 W | 低 BRAM Pareto；16/16 |
| P4-F Stage2/3 LUTRAM | 531 | 487 | 204 | 4 | 2 / 1.0 | 2 | +45.898/+0.105 ns | 0.270/0.198/0.072 W | 最低 BRAM Pareto；16/16 |

P4-F 没有达到指导预估的约 500～510 LUT，而是用相对 P4-D 的 `+52 LUT/+19 FF/+6 Slice` 换掉 1 BRAM Tile，所以不能称为综合资源更优。补偿器与 CIC C² 共享串行 ALU 也实际实现并通过 Smoke，但为 504 LUT / 488 FF，面积反升，已按 No-Go 独立保留。完整的执行/问题/取舍见 [P4-C 深度审计指导执行反馈](matlab_fir/national_finals/results/p4c_rtl_deep_audit_and_next_optimization_guide_execution.md)。

### X3：20 MHz 统一三级 FIR 创新结构（功能 Go，资源 No-Go）

最新指导中尚未尝试的创新点也已在独立分支落地：把 Stage1/2/3 全部搬到 20 MHz 域，用 4-deep Gray FIFO 接收输入、用 y2/y4/y8 ping-pong bank 返回音频域，三级 FIR 共用一颗 DSP48E1；补偿器和 N3 Hold CIC 保持原音频域结构。160 个 sys clock 完成一帧，低于 48 kHz 的约 416.67-clock 最坏输入间隔。冲激加 10 个固定 seed×4096 的 Release 回归 **11/11 PASS**，三节点逐样本 **0 LSB**，因此六工况频响与 P4-D 完全相同。

| 滤波核心口径 | LUT | FF | DSP | RAMB18 / BRAM Tile | 结论 |
|---|---:|---:|---:|---:|---|
| P4-D 已布线滤波层级 | 377 | 361 | 4 | 3 / 1.5 | 当前基准 |
| X3 20 MHz 统一 FIR OOC post-route | 910 | 692 | 3 | 5 / 2.5 | 功能通过，资源 No-Go |
| X3 增量 | **+533** | **+331** | **-1** | **+2 / +1.0** | 1 DSP 的收益不足以抵消控制与 CDC 存储 |

X3 两个时钟域 WNS/WHS 分别为 20 MHz `+34.839/+0.072 ns`、6.144 MHz `+149.833/+0.081 ns`。OOC vectorless 功耗为 `0.076 W`，因不含双 MMCM 与板级包装，不能与 P4-D 的完整板级 `0.271 W` 直接比较。核心资源已明显越过停止线，所以没有污染 P4-D 工程，也没有继续生成 X3 板级 bitstream；默认推荐保持 P4-D。架构、修复、RTL 回归、CDC/DRC 和停止理由见 [X3 20 MHz 统一 FIR 执行报告](matlab_fir/national_finals/results/x3_20m_unified_fir_nogo.md)。

通带指标也统一区分两种定义：

- **通带最大绝对偏差**：通带内相对 0 dB 的最大偏离，直接对应赛题“±0.05 dB”门槛。
- **通带峰峰纹波**：通带最大值减最小值。早期报告未保存该值时以“—”表示，不用最大绝对偏差代替。

整体演进路线如下：

```text
最初 4x + 5×2x
  -> 七级全 2x：先统一结构和提高频响余量
  -> 全 2x Phase 1～6：canonical、多相、严格半带、BRAM、DSP 共享、混合字长
  -> FIR-CIC：用 CIC16 替换高采样率四级 2x FIR
  -> 区域赛低 LUT CIC：2-DSP / 9-DSP / 8-DSP Pareto 收敛到 472 LUT
  -> 全国赛双采样率：补齐 44.1/48 kHz 与 4x/8x/128x 正式节点
  -> 全国赛全 2x 回退对照：714 LUT/3 DSP 与 728 LUT/2 DSP
  -> 全国赛 6-DSP CIC：573 LUT 基线连续优化到 440 LUT
  -> 第六轮复位映射：442 LUT / 432 FF，形成低 FF Pareto 点
  -> 第七轮余量后移：均衡器保留 21-bit 无损余量，CIC 末端统一量化，降至 434 LUT
  -> Route 1：统一 Stage1/Stage2/3 系数 RAM，降至 424 LUT / 6 DSP
  -> 第八轮：低速 CIC comb 迁移到 LUT/CARRY4，形成 436 LUT / 5 DSP Pareto 点
  -> P1/P3：修复真 Q15 绝对增益，并闭合 CDC、复位和 AD9708 STA
  -> P4-A：N3 Hold 严格等价改写，形成 491 LUT / 4 DSP Pareto 点
  -> P4-B：Stage1 与 Stage2/3 历史 RAM 时分复用，形成 504 LUT / 4 DSP / 2 BRAM Tile Pareto 点
  -> P4-C：固定 CE 删除死队列、Stage1 预加器、26/29-bit CIC，形成 479 LUT / 4 DSP 默认版及 3/2-DSP Pareto
  -> P4-D：固定签核 wrapper、Release 长回归、CDC bus-skew 与 bitstream 清单闭环
  -> P4-E：PCM/Stage1 共享 RAMB18，形成 491 LUT / 4 DSP / 1.5 BRAM Tile Pareto
  -> P4-F：Stage2/3 历史改 RAM32M，形成 531 LUT / 4 DSP / 1 BRAM Tile Pareto
  -> X3：20 MHz 三级 FIR 共用 1 DSP，Release 0 LSB，但核心为 910 LUT / 692 FF / 3 DSP / 2.5 BRAM，资源 No-Go
  -> P3-J：按模式将128x均衡响应折叠进Stage3，删除独立均衡器，形成430 LUT / 431 FF / 4 DSP新默认版
  -> P3-J 后续：形成466-LUT/3-DSP、488-LUT/2-DSP、456-LUT/1.5-BRAM Pareto；signed-20与9-tap均No-Go
```

### Route 1：历史 424-LUT 资源点做了什么

Route 1 的优化对象不是滤波器系数、CIC 阶数或定点字长，而是两条 FIR DSP 通道之间重复的**系数存储和地址译码**。名称中的“统一引擎”也不表示把 Stage1、Stage2、Stage3 强行合并为一颗 DSP：48 kHz 最紧工况下，一个 128 拍输入超周期内，Stage1、Stage2、Stage3 最坏分别需要 27、42、60 拍，单 DSP 合计 **129 拍**，已经超过可用预算。因此正式版本继续保留 Stage1 和 Stage2/3 两颗 FIR DSP。

434-LUT 基线的系数路径为：

```text
Stage1：26 路 case 常量系数网络 -> FIR DSP 1
Stage2/3：独立同步系数 BRAM    -> FIR DSP 2
```

Route 1 将其改为一个显式 true-dual-port `RAMB18E1`：

```text
统一系数 RAMB18E1
  A口地址 64..89 -> Stage1 的 26 个 signed 16-bit 对称系数 -> FIR DSP 1
  B口地址  0..63 -> Stage2/3 两相系数                 -> FIR DSP 2
```

两个端口可以在同一拍分别供数，因此不会引入 DSP 互斥或吞吐下降；同时复用原系数 RAMB18 的空闲地址，不增加 BRAM。Stage1/Stage2/Stage3 历史存储、MAC 调度、Q15 舍入、饱和、均衡器和 CIC16 全部不变，频响与 434-LUT 版逐点一致。

资源下降的直接原因是删除 Stage1 的26路常量译码和宽系数选择网络：综合由 **452 LUT / 469 FF** 降到 **436 LUT / 469 FF**，Stage1 层级从136 LUT降到120 LUT；布局布线由 **434 LUT / 469 FF / 190 Slice** 降到 **424 LUT / 471 FF / 188 Slice**。最终少10 LUT和2 Slice，多2 FF，仍为 **6 DSP / 3 BRAM / 2 MMCM / 17 IO**，Vectorless功耗仍为0.271 W。

为避免行为模型掩盖RAM初始化错误，Route 1还增加了原语级验证，逐地址核对32个Stage1地址和64个Stage2/3地址，并发现、修复了`INIT_05`漏写一个十六进制数字导致的半字节错位。最终验证为：XSim回归10/10 PASS、4x/8x/128x冲激和固定随机全部0 LSB、8种复位恢复与10次动态切档通过、六工况频响/线性相位通过、WNS/WHS为 **+45.356/+0.117 ns**、TNS/THS为0、DRC Error=0，并成功生成bitstream。

曾尝试把Stage2两次量化融合为一次Q17→20-bit量化，结果为437 LUT / 467 FF：虽然少2 FF，却比正式Route 1多1 LUT，因此按最低LUT目标否决。正式提交为`aaac3be`，标签为`national-finals-route1-424LUT-471FF-6DSP-3BRAM-2MMCM`，bitstream SHA-256为`77D67B9E53FF43A0774A2F0093B5A89F22F27371C8CD9FD59DB018834C757BF4`。完整实验记录见 [Route 1 优化记录](matlab_fir/national_finals/results/route1_unified_engine_progress.md)。

### 第八轮：436-LUT / 5-DSP comb-LUT Pareto 版

Route 1 的 6 个 DSP 分配为 Stage1 一颗、Stage2/3 共享一颗、三级串行 CIC comb 一颗、三级高速 integrator 三颗。本轮只把低采样率 comb 的 23-bit 减法迁移到 LUT/CARRY4；comb 每个 8x 输入有 16 个 128x 主时钟周期可用，原三周期串行差分调度、位宽和模运算语义均不改变。三个每拍更新的 integrator 继续定向映射到 DSP48E1，因此总量变为 `1 + 1 + 0 + 3 = 5 DSP`。

最终布局布线为 **436 LUT / 471 FF / 181 Slice / 5 DSP / 3 BRAM / 2 MMCM**。相对 Route 1 多 12 LUT、FF 不变、少 7 Slice和1 DSP，功耗报告仍为0.271 W；这是“近最低 LUT 下进一步节省 DSP”的新 Pareto 点，而不是替代424-LUT Route 1 的绝对最低 LUT 地位。完整 XSim 回归10/10 PASS，六工况频响不变，WNS/WHS为 **+45.662/+0.116 ns**，TNS/THS为0，DRC Error/Critical Warning为0，bitstream SHA-256为`B344EB816AF39F0F0C14DCFCEAF9F0735E94EEDF509116BC68569BB0938C8F17`。签核记录见 [5-DSP comb-LUT 优化摘要](matlab_fir/national_finals/results/cic5_comb_lut_optimization_summary.md)。

同时实现过三段 FIR 共用一颗 DSP 的原型，但局部64拍截止期内最低需要72拍，XSim捕获Stage1未按时完成，故作为 No-Go 保留而未进入正式板级路径。证明见 [共享 FIR MAC No-Go 记录](matlab_fir/national_finals/results/shared_fir_mac_v1_nogo.md)。

### 第一阶段：最初 4x+2x 基线与全 2x 重构

最初版本采用“前级 4x FIR + 后续 5 级 2x FIR”。它首先完成了 44.1 kHz 到 5.6448 MHz 的 128 倍插值功能，但有两个明显问题：前级 4x 多相滤波器控制和并行数据通路较重；最终阻带只有 70.339 dB，距离 70 dB 门槛仅 0.339 dB，系数量化或字长继续缩减的余量很小。

因此第一步不是立刻追求最低 LUT，而是把结构统一成七级 2x：

1. 每级只处理偶相/奇相，结构和 valid 时序更规则；
2. 半带零系数与对称系数可以在所有级重复利用；
3. 最终通带最大绝对偏差由约 0.01727 dB 降到 0.00730 dB，阻带由 70.339 dB 提高到 77.679 dB；
4. 直接并行写法一度达到 38 DSP，说明“数学结构更规整”并不自动等于“RTL 更省资源”，后续必须依靠串行 MAC 和时分复用。

早期独立链结果如下。该表只反映插值核，不应与后面的完整板级 440/472 LUT 直接相减。

| 版本 | 结构/优化方法 | LUT | FF | DSP | BRAM | 通带最大绝对偏差 | 最终阻带 |
|---|---|---:|---:|---:|---:|---:|---:|
| 最初版本 | `4x + 5×2x`，功能基线 | 9002 | 4497 | 2 | 0 | 约 0.01727 dB | 70.339 dB |
| 全 2x 并行基线 | 七级直接并行，尚未做硬件复用 | 9376 | 4118 | 38 | 0 | 0.00730 dB | 77.679 dB |
| 全 2x 首个稳定串行版 | Stage1 串行 DSP MAC，其余级移位加法 | 5912 | 4218 | 1 | 0 | 0.00730 dB | 77.679 dB |

这一阶段的关键认识是：全 2x 的主要价值是提供规则、可分解的优化载体；真正节省资源的是随后对零系数、对称性、存储、字长和运算时间的系统性利用。

### 第二阶段：全 2x Phase 1～6 的逐轮优化

全 2x 路线没有用一次“大改”完成，而是逐步消除综合报告中的主要热点：

1. **Phase 1，canonical 半带尾级**：Stage4～7 的小整数系数改成移位加减，删除通用乘法器及其宽加法树。
2. **Phase 2，Stage2/3 真多相**：不再对插零样点执行无效 MAC；只计算当前相位需要的非零系数，并缩短 valid 管线。
3. **Phase 3，Stage1 严格半带与 BRAM 历史**：重新设计 105 tap 严格半带滤波器，利用中心抽头、零抽头和对称抽头；把长历史从 FF 移入双读 BRAM，重点降低寄存器数量。
4. **Phase 4，Stage2/3 共享 DSP**：用 48 MHz 系统时钟相对音频采样使能的巨大周期余量，让两个 FIR 级时分复用一颗 DSP48E1。这里主动增加 1 个 DSP，换来大幅 LUT 下降，是第一次明确采用 Pareto 思路。
5. **Phase 5，Q15 单次舍入与紧凑饱和**：把多个级间宽舍入器合并为边界处一次舍入，ACC40 保留足够动态范围，同时移除重复符号扩展和比较逻辑。
6. **Phase 6，逐级混合字长**：通过定点搜索把七级数据宽度收敛为 `24/22/20/18/18/18/18 bit`，共享 DSP 累加器收窄到 ACC38；3-DSP 候选资源反而增加，因此最终保留 2 DSP。

完整单采样率板级结果如下，`Δ` 均相对上一行：

| 版本 | LUT | LUT Δ | FF | FF Δ | DSP | BRAM | 功耗估计 | 主要收益 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 全 2x 初始板级 | 6426 | — | 4416 | — | 1 | 0 | — | 建立可实现基线 |
| Phase 2 板级 | 4428 | -1998 | 3279 | -1137 | 1 | 0 | — | canonical 尾级 + 真多相 |
| Phase 3 板级 | 3676 | -752 | 1106 | -2173 | 1 | 1 | — | 严格半带 + BRAM 历史 |
| Phase 4 共享 DSP | 2122 | -1554 | 1198 | +92 | 2 | 1 | — | 用 1 DSP 换 1554 LUT |
| Phase 4 四档正式版 | 1817 | -305 | 1182 | -16 | 2 | 1 | — | 板级控制与数据通路继续合并 |
| Phase 5 | 1536 | -281 | 1181 | -1 | 2 | 1 | — | 单舍入、紧凑饱和、ACC40 |
| **Phase 6** | **1395** | **-141** | **1040** | **-141** | **2** | **1** | **0.168 W** | 混合字长、ACC38；完成实板验证 |

Phase 6 相对全 2x 初始板级累计减少 **5031 LUT（78.29%）** 和 **3376 FF（76.45%）**，代价是增加 1 DSP 和 1 BRAM Tile。最终 128x 的通带最大绝对偏差为 **0.00523192 dB**，阻带衰减为 **78.61965812 dB**；RTL 冲激与随机 PCM 均为 0 LSB，四档仿真、实现、bitstream 和物理板测均通过。完整过程见 [Phase 6 执行报告](matlab_fir/all2x_phase6_execution_report.md)。

### 第三阶段：FIR-CIC 替换与区域赛低 LUT 优化

Phase 6 已经把全 2x 做到 1395 LUT，但 Stage4～7 位于 352.8 kHz～5.6448 MHz 的高采样率区间，而有效音频带宽始终只有 20 kHz。继续压缩四套高倍率 FIR 的收益开始变小，因此改用：

```text
Stage1 2x -> Stage2 2x -> Stage3 2x + CIC 逆下垂补偿 -> CIC16(N=3)
```

设计思路分为两步：

1. **算法级替换**：用三级 CIC16 的 comb/integrator 加减累加替代四级 2x FIR，并把补偿折叠进原 11 tap Stage3，不增加 Stage3 抽头数、历史深度或 DSP 数。
2. **实现级 Pareto 优化**：先保留 2-DSP 低 DSP 版本，再把 CIC 的宽位加减定向映射到空闲 DSP48E1，以 DSP 换 LUT；随后把历史/系数/PCM ROM 移入 BRAM，压缩键盘扫描、舍入器和控制计数器，并扫描 Vivado 面积策略。

主要完整单采样率板级里程碑如下：

| 版本 | LUT | LUT Δ | FF | FF Δ | DSP | BRAM | 功耗估计 | 主要优化 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Phase 6 全 2x | 1395 | — | 1040 | — | 2 | 1 | 0.168 W | 对照基线 |
| FIR-CIC 折叠补偿 | 1128 | -267 | 964 | -76 | 2 | 1 | — | 四级 FIR 换 CIC16，补偿折入 Stage3 |
| PCM ROM + 紧凑舍入 | 941 | -187 | 940 | -24 | 2 | 1.5 | 0.168 W | ROM 入 BRAM，删除 42-bit 宽偏置加法 |
| CIC 映射 DSP | 729 | -212 | 920 | -20 | 9 | 1.5 | 0.168 W | 7 个 CIC 宽位加减器用 DSP 换 LUT |
| Stage2/3 串行 LUTRAM | 578 | -151 | 619 | -301 | 9 | 1.5 | 0.168 W | 环形历史 + 单 DSP 串行 MAC |
| 紧凑键盘扫描 | 557 | -21 | 579 | -40 | 9 | 1.5 | — | 合并板级控制逻辑 |
| Stage2/3 历史入 BRAM | 521 | -36 | 579 | 0 | 9 | 2.5 | — | 用 1 BRAM Tile 换 LUTRAM |
| 系数同步 BRAM | 506 | -15 | 579 | 0 | 9 | 3 | — | 删除组合系数选择网络 |
| 共享扫描使能 | 496 | -10 | 565 | -14 | 9 | 3 | — | 复用上电计数器/扫描时基 |
| `ExploreArea` 候选 | 478 | -18 | 565 | 0 | 9 | 3 | — | 实测实现策略收敛 |
| **区域赛最终实板版** | **472** | **-6** | **564** | **-1** | **8** | **3** | **0.169 W** | 禁止 5-bit burst 计数器误占 DSP |

这条路线形成了清晰的 Pareto 前沿：

- **941 LUT / 2 DSP**：DSP 最省；
- **729～478 LUT / 9 DSP**：逐步用 DSP/BRAM 换通用逻辑；
- **472 LUT / 8 DSP**：把误映射的控制减法放回 CARRY 链，保留六个真正有价值的 CIC DSP 运算。

FIR-CIC 正式 128x RTL 冲激的通带最大绝对偏差为 **0.00303062 dB**，阻带衰减为 **72.34929 dB**；4x 为 **0.00301125 dB / 78.67042 dB**。8x 是带 CIC 预加重的内部节点，当时不是区域赛正式验收输出，因此没有把它包装成“±0.05 dB 的 8x 正式指标”。472-LUT 版本完成冲激/随机 bit-true、复位、动态切档、实现、bitstream 和物理板测，四档 `DA_CLK` 及 DA 正弦输出均正常。

### 第四阶段：全国赛全 2x 回退与公平对照

全国赛增加 48 kHz 输入家族，并把 4x、8x、128x 都定义为正式输出。为了回答“保留七级全 2x 是否比 CIC 更省资源”，在提交 `648fd94` 上重新对全 2x 做了专门优化，而不是直接拿早期 1395-LUT Phase 6 与 CIC 比较：

1. Stage1 保留严格半带和串行 DSP MAC；
2. Stage2/3 继续共享一个 DSP、BRAM 历史和逐级窄字长；
3. Stage4～7 不再实例化四套独立内核，而是合并为共享的 7-tap 半带尾级引擎；
4. 对尾级分别实现 `shift-add` 和 DSP48 两个 Pareto 点；
5. 与 FIR-CIC 使用完全相同的双采样率板级顶层、器件、约束和实现流程。

同口径布局布线结果如下：

| 全国赛完整板级架构 | LUT | FF | DSP | BRAM | MMCM | WNS/WHS | 功耗估计 | 相对 573-LUT CIC |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| FIR-CIC 串行 comb | 573 | 621 | 6 | 3 | 2 | +46.339/+0.072 ns | 0.271 W | 基线 |
| 全 2x 共享尾级，DSP48 | 714 | 662 | 3 | 3 | 2 | +46.438/+0.105 ns | 0.271 W | +141 LUT、+41 FF、-3 DSP |
| 全 2x 共享尾级，shift-add | 728 | 662 | 2 | 3 | 2 | +46.441/+0.105 ns | 0.271 W | +155 LUT、+41 FF、-4 DSP |

三种实现均完整布局布线、满足 setup/hold、DRC Error=0 并生成 bitstream。全国赛全 2x 独立回归为 4/4 PASS，冲激和随机 PCM 的 4x/8x/128x 全部 0 LSB，共享尾级还与四套独立尾级对拍 33949 个样点无误差；但这两个全 2x 全国赛 bitstream **尚未完成物理板测**。

结论不是“全 2x 不可用”，而是目标不同：

- 若优先节省 DSP，`728 LUT / 2 DSP` 全 2x 是更合适的 Pareto 点；
- 若优先节省 LUT 和总体通用逻辑，`573 LUT / 6 DSP` FIR-CIC 比最优全 2x 少 141～155 LUT；
- 全 2x 的 128x 阻带约 78.45～78.88 dB，优于 CIC 的约 72.35 dB；CIC 用仍满足赛题的频响余量换取更低 LUT。

### 第五阶段：全国赛 6-DSP CIC 从 573 LUT 优化到 434 LUT，并形成 432-FF Pareto 点

全国赛最初功能基线为 **602 LUT / 616 FF / 8 DSP / 3 BRAM / 2 MMCM**。第一轮先把三级 CIC comb 改为单 DSP 三周期串行差分，并禁止无价值的控制运算占用 DSP，形成用户指定的 **573 LUT / 621 FF / 6 DSP** 回退基线。随后每一轮都保持滤波系数、节点输出和定点舍入语义不变，并以完整 RTL 零误差回归为准入条件。

| 全国赛 6-DSP CIC 版本 | LUT | LUT Δ | FF | FF Δ | Slice | DSP | BRAM | MMCM | WNS/WHS | 功耗估计 | 主要方法 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 双采样率功能基线 | 602 | — | 616 | — | — | 8 | 3 | 2 | +46.309/+0.103 ns | 0.271 W | 44.1/48 kHz、三正式节点 |
| 6-DSP 回退基线 | 573 | -29 | 621 | +5 | 255 | 6 | 3 | 2 | +46.339/+0.072 ns | 0.271 W | comb 三周期串行化，8 DSP 降到 6 DSP |
| 实现策略改为 `Default` | 556 | -17 | 621 | 0 | 229 | 6 | 3 | 2 | +45.294/+0.092 ns | — | 同一综合 DCP 小范围策略实扫 |
| DSP PREG 状态复用 | 556 | 0 | 557 | -64 | 231 | 6 | 3 | 2 | +45.936/+0.106 ns | — | CIC 内部状态留在原生 PREG |
| 组合均衡直交 CIC | 557 | +1 | 536 | -21 | 228 | 6 | 3 | 2 | +45.614/+0.105 ns | — | 删除冗余寄存边界 |
| comb 历史轮转/字长压缩 | 528 | -29 | 532 | -4 | 229 | 6 | 3 | 2 | +45.075/+0.078 ns | — | 22-bit 轮转历史、Stage1 41-bit |
| Stage2/3 累加器复用器消除 | 487 | -41 | 532 | 0 | 205 | 6 | 3 | 2 | +46.420/+0.105 ns | — | 首抽头直接使用已清零 PREG |
| FIR PREG 累加与提交 | 461 | -26 | 464 | -68 | 199 | 6 | 3 | 2 | +45.405/+0.114 ns | — | Stage1、Stage2/3 删除外部宽累加寄存器 |
| DSP `CARRYIN` 精确舍入 | 451 | -10 | 464 | 0 | — | 6 | 3 | 2 | +45.647/+0.140 ns | — | 空闲提交周期实现正负对称 Q15 舍入 |
| **第五轮最低 LUT 正式版** | **440** | **-11** | **464** | **0** | **191** | **6** | **3** | **2** | **+46.046/+0.127 ns** | **0.271 W** | Stage3 最坏界证明后删除不可能触发的饱和逻辑 |
| **第六轮低 FF Pareto 版** | **442** | **+2** | **432** | **-32** | **194** | **6** | **3** | **2** | **+45.617/+0.106 ns** | **0.271 W** | 最终 CIC 积分状态改用同步复位并吸收到 DSP48 内部 A/B 寄存器 |
| **第七轮最低 LUT 正式版** | **434** | **-8** | **469** | **+37** | **190** | **6** | **3** | **2** | **+45.539/+0.108 ns** | **0.271 W** | 均衡器 21-bit 无损余量直交 CIC，删除中间 20-bit 饱和选择器 |

573-LUT 基线到第七轮最低 LUT 版的总变化为：

- LUT：`573 -> 434`，减少 **139（24.26%）**；
- FF：`621 -> 469`，减少 **152（24.48%）**；
- Slice：`255 -> 190`，减少 **65（25.49%）**；
- DSP / BRAM / MMCM：保持 **6 / 3 / 2**；
- Vectorless 功耗：报告精度下保持 **0.271 W**。

这一阶段的核心思路不是继续改变滤波算法，而是让 RTL 更贴合 DSP48E1 的实际数据通路：

1. 用 PREG 保存累加状态，删除 DSP 外侧同宽寄存器和反馈复用器；
2. 利用已知的清零/提交周期固定 OPMODE，删除运行时宽选择器；
3. 用 `CARRYIN` 完成正负数不对称的精确舍入偏置；
4. 在数学最坏界证明安全后才裁剪字长或饱和逻辑；
5. 任何微优化都重新跑 impulse、随机 PCM、复位、动态切档和完整实现；综合报告下降但 bit-true 不通过的候选不进入正式版；
6. Stage1 DSP48 预加器也做了实测 A/B：显式 A/B 预加器为 491 LUT，织构预加加 DSP PREG 为 469 LUT，因此当前正式版保持预加器关闭，选择真实结果而不是结构直觉。

第六轮继续检查 CIC 状态寄存器的物理映射。第五轮中两个内部积分状态已经采用同步复位，但最终积分状态仍因异步复位占用 32 个 Slice FF。把该内部状态移入同步复位进程后，Vivado 将它吸收到最终积分器 DSP48E1 的 A/B 输入寄存器，综合结果由 `459 LUT / 464 FF` 变为 `459 LUT / 432 FF`。完整布局布线为 `442 LUT / 432 FF / 194 Slice`：相对 440-LUT 版增加 2 LUT 和 3 Slice，但减少 32 FF；DSP/BRAM/MMCM 和 0.271 W 功耗不变。因此它继续作为**低 FF Pareto 版本**保留，而最低 LUT 正式版本已在第七轮更新为 434 LUT。

第七轮转而检查补偿均衡器与 CIC 之间的量化边界。对任意 signed 20-bit 的当前样本和两级历史，`[-1,10,-1]/8` 均衡器精确结果的范围只需要 **21 bit**；旧结构却先饱和回 20 bit，再进入具有 32-bit 内部动态范围的 CIC，形成一套可后移的中间饱和选择器。当前版让均衡器无损输出 21 bit、CIC 输入相应加宽 1 bit，并仍由 CIC 最终量化器输出 20 bit。均衡器由 60 LUT 降到 41 LUT，CIC 增加少量宽度开销后，整机综合由 459 LUT 降到 452 LUT，布局布线由 440 LUT 降到 **434 LUT**。这不是删除削顶保护：最终 20-bit 输出仍执行相同舍入和饱和，只是把量化边界移动到具有完整累加余量的位置。

本轮的 Stop/Go 结果如下：

| 第七轮候选 | 综合/实现结果 | 验证 | 结论 |
|---|---|---|---|
| 仅收紧均衡器内部理论位宽 | 459 LUT / 464 FF | 9/9 RTL PASS | Vivado 已自动裁掉冗余符号位，资源不变，回退 |
| 单 LUT 加法器分时均衡 | 465 LUT / 510 FF | 2009 点单元逐位 PASS | 操作数复用和状态控制抵消收益，回退 |
| 21-bit 余量后移 | 452 LUT / 469 FF；布局布线 434 LUT / 190 Slice | 9/9 RTL、六工况 MATLAB、实现/bitstream PASS | **保留为最低 LUT 正式版** |
| `ExploreArea` 实现 | 468 LUT / 469 FF / 177 Slice | timing/DRC/bitstream PASS | Slice 更少但多 34 LUT，不采用 |

这一轮还执行了三项 Stop/Go 候选和实现策略复扫：

| 第六轮候选 | 综合资源/验证 | 结论 |
|---|---|---|
| 最终 CIC 状态同步复位 | 459 LUT / 432 FF / 6 DSP；9/9 RTL PASS | 保留；布局布线 442 LUT / 432 FF |
| 均衡器复用串行 comb DSP | 490 LUT / 453 FF / 6 DSP；9/9 RTL PASS | 功能正确但面积变差，回退 |
| 级间算术截位 | 454 LUT / 426 FF / 6 DSP；冲激出现 1412 点失配 | 资源下降但 bit-true 失败，回退 |
| BRAM 上电 scrub | 615 LUT / 517 FF / 6 DSP / 1 BRAM Tile；9/9 RTL PASS | 破坏历史 BRAM 推断，回退 |

同一综合 DCP 的 `Default / AddRemap / ExploreArea` 完整实现结果分别为 `442/432/194`、`442/432/194` 和 `460/432/180`（LUT/FF/Slice）。`ExploreArea` 只适合 Slice 优先场景；本分支继续选择 LUT 更低、流程更简单的 `Default`。

第六轮完整取舍与签核见 [低 FF 优化摘要](matlab_fir/national_finals/results/cic6_round6_ff_optimization_summary.txt)，策略原始汇总见 [第六轮实现策略表](matlab_fir/national_finals/results/cic6_round6_strategy_scan.csv)。

### 各结构频响汇总

早期版本只归档最终 128x 指标；全国赛版本才对 44.1/48 kHz 下的 4x、8x、128x 六工况全部签核。所有“—”都表示原报告未保存该口径，不表示测试失败。

| 架构/版本 | 输入采样率 | 节点 | 通带最大绝对偏差 | 通带峰峰纹波 | 阻带衰减 | 说明 |
|---|---:|---:|---:|---:|---:|---|
| 最初 `4x+5×2x` | 44.1 kHz | 128x | 约 0.01727 dB | — | 70.339 dB | 早期 MATLAB/RTL 最终节点 |
| 全 2x 初始 | 44.1 kHz | 128x | 0.007298 dB | — | 77.679 dB | 初始全 2x 数学基线 |
| Phase 6 全 2x | 44.1 kHz | 128x | 0.005232 dB | — | 78.620 dB | 混合字长正式结果 |
| Phase 7 FIR-CIC | 44.1 kHz | 4x | 0.003011 dB | — | 78.670 dB | 区域赛 RTL 冲激 |
| Phase 7 FIR-CIC | 44.1 kHz | 128x | 0.003031 dB | — | 72.349 dB | 区域赛 RTL 冲激 |
| 全国赛全 2x | 44.1 kHz | 4x | 0.004610 dB | 0.005703 dB | 78.669 dB | RTL 冲激，0 LSB |
| 全国赛全 2x | 44.1 kHz | 8x | 0.005395 dB | 0.006183 dB | 78.562 dB | RTL 冲激，0 LSB |
| 全国赛全 2x | 44.1 kHz | 128x | 0.005444 dB | 0.007823 dB | 78.447 dB | RTL 冲激，0 LSB |
| 全国赛全 2x | 48 kHz | 4x | 0.004610 dB | 0.005703 dB | 78.669 dB | RTL 冲激，0 LSB |
| 全国赛全 2x | 48 kHz | 8x | 0.005395 dB | 0.005719 dB | 78.562 dB | RTL 冲激，0 LSB |
| 全国赛全 2x | 48 kHz | 128x | 0.005444 dB | 0.005909 dB | 78.881 dB | RTL 冲激，0 LSB |
| **434基线 / Route 1 / 5-DSP** | **44.1 kHz** | **4x** | **0.004610 dB** | **0.005703 dB** | **78.669 dB** | **三版系数与定点输出不变，RTL冲激0 LSB** |
| **434基线 / Route 1 / 5-DSP** | **44.1 kHz** | **8x** | **0.005495 dB** | **0.006274 dB** | **78.161 dB** | **三版系数与定点输出不变，RTL冲激0 LSB** |
| **434基线 / Route 1 / 5-DSP** | **44.1 kHz** | **128x** | **0.006918 dB** | **0.008111 dB** | **72.348 dB** | **三版系数与定点输出不变，RTL冲激0 LSB** |
| **434基线 / Route 1 / 5-DSP** | **48 kHz** | **4x** | **0.004610 dB** | **0.005703 dB** | **78.669 dB** | **三版系数与定点输出不变，RTL冲激0 LSB** |
| **434基线 / Route 1 / 5-DSP** | **48 kHz** | **8x** | **0.005495 dB** | **0.005738 dB** | **78.161 dB** | **三版系数与定点输出不变，RTL冲激0 LSB** |
| **434基线 / Route 1 / 5-DSP** | **48 kHz** | **128x** | **0.006918 dB** | **0.006917 dB** | **72.348 dB** | **三版系数与定点输出不变，RTL冲激0 LSB** |
| **P1 / P3 / P4-A / P4-B / P4-C / P4-D 正确标度版** | **44.1 kHz** | **4x** | **0.004610 dB** | **0.005703 dB** | **78.669 dB** | **各版逐点位真一致；绝对增益 -0.001599 dB** |
| **P1 / P3 / P4-A / P4-B / P4-C / P4-D 正确标度版** | **44.1 kHz** | **8x** | **0.005395 dB** | **0.006174 dB** | **78.562 dB** | **各版逐点位真一致；绝对增益 -0.002709 dB** |
| **P1 / P3 / P4-A / P4-B / P4-C / P4-D 正确标度版** | **44.1 kHz** | **128x** | **0.006116 dB** | **0.008056 dB** | **72.331 dB** | **各版逐点位真一致；绝对增益 -0.003480 dB** |
| **P1 / P3 / P4-A / P4-B / P4-C / P4-D 正确标度版** | **48 kHz** | **4x** | **0.004610 dB** | **0.005703 dB** | **78.669 dB** | **各版逐点位真一致；绝对增益 -0.001599 dB** |
| **P1 / P3 / P4-A / P4-B / P4-C / P4-D 正确标度版** | **48 kHz** | **8x** | **0.005395 dB** | **0.005719 dB** | **78.562 dB** | **各版逐点位真一致；绝对增益 -0.002709 dB** |
| **P1 / P3 / P4-A / P4-B / P4-C / P4-D 正确标度版** | **48 kHz** | **128x** | **0.006116 dB** | **0.006116 dB** | **72.331 dB** | **各版逐点位真一致；绝对增益 -0.003480 dB** |
| **P3-J Stage3/均衡器联合版** | **44.1 kHz** | **4x** | **0.003022 dB** | **0.005709 dB** | **78.568 dB** | **flat Stage3；Release 0 LSB** |
| **P3-J Stage3/均衡器联合版** | **44.1 kHz** | **8x** | **0.003521 dB** | **0.006192 dB** | **78.609 dB** | **flat Stage3；Release 0 LSB** |
| **P3-J Stage3/均衡器联合版** | **44.1 kHz** | **128x** | **0.007730 dB** | **0.005848 dB** | **72.371 dB** | **compensated Stage3；Release 0 LSB** |
| **P3-J Stage3/均衡器联合版** | **48 kHz** | **4x** | **0.003022 dB** | **0.005709 dB** | **78.568 dB** | **flat Stage3；Release 0 LSB** |
| **P3-J Stage3/均衡器联合版** | **48 kHz** | **8x** | **0.003007 dB** | **0.005678 dB** | **78.609 dB** | **flat Stage3；Release 0 LSB** |
| **P3-J Stage3/均衡器联合版** | **48 kHz** | **128x** | **0.007606 dB** | **0.005724 dB** | **72.371 dB** | **compensated Stage3；Release 0 LSB** |

### 时序 Timing 统一结算

Timing 以 Vivado 完成布局布线后的 timing summary 为准，不使用综合前估算。验收规则为：

| 指标 | 含义 | PASS 条件 | 当前结果 |
|---|---|---:|---:|
| WNS | 最差建立时间余量 | `>= 0 ns` | **+45.662 ns** |
| TNS | 所有建立违例的负余量总和 | `= 0 ns` | **0 ns** |
| setup failing endpoints | 建立时间失败端点数 | `= 0` | **0** |
| WHS | 最差保持时间余量 | `>= 0 ns` | **+0.116 ns** |
| THS | 所有保持违例的负余量总和 | `= 0 ns` | **0 ns** |
| hold failing endpoints | 保持时间失败端点数 | `= 0` | **0** |
| 路由完整性 | 可布线网络与 routing error | 全部完成且 error=0 | **1329/1329，error=0** |

需要注意：WNS/WHS 只有在使用相同顶层、相同 XDC 和相同实现阶段时才能公平横向比较。早期独立链使用模块级测试时钟，区域赛板级是 44.1 kHz 单家族顶层，全国赛板级则包含 44.1/48 kHz 两套 MMCM 和异步时钟组；因此下面按三种口径分别结算。

#### 独立插值链 Timing

早期全 2x 独立链报告主要归档 WNS，WHS/TNS/THS 未统一保留；这些数据用于证明结构优化没有引入建立时间违例，不与全国赛板级的约 46 ns WNS 直接比较。

| 独立链版本 | 时钟/约束口径 | WNS | WHS | TNS/THS | 结果 |
|---|---|---:|---:|---:|---|
| 最初 `4x+5×2x` | 早期 OOC 约束 | +165.584 ns | — | — | setup PASS |
| 全 2x 并行基线 | 早期 OOC 约束 | +134.988 ns | — | — | setup PASS |
| 全 2x 稳定基线 | 早期 OOC 约束 | +165.930 ns | — | — | setup PASS |
| Phase 3 BRAM | 早期 OOC 约束 | +159.809 ns | — | — | setup PASS |
| Phase 4 共享 DSP | 早期 OOC 约束 | +161.944 ns | — | — | setup PASS |
| Phase 6 混合字长 | 早期 OOC 约束 | +165.427 ns | — | — | setup PASS |
| Phase 6 48 MHz 对照 | 48 MHz OOC | +9.107 ns | +0.127 ns | 0/0 ns | PASS |
| Phase 7 折叠 FIR-CIC | 48 MHz OOC | +9.107 ns | +0.063 ns | 0/0 ns | PASS |

在相同 48 MHz OOC 约束下，Phase 6 全 2x 改为 Phase 7 折叠 FIR-CIC 后 WNS 保持 **+9.107 ns**，WHS 从 +0.127 ns 变为 +0.063 ns，仍有正保持余量且 THS=0。也就是说，CIC 替换取得面积下降时没有牺牲 setup 收敛。

#### 区域赛单采样率板级 Timing

| 版本 | WNS | 相对上一行 | WHS | TNS/THS | 结论 |
|---|---:|---:|---:|---:|---|
| Phase 6 全 2x | +45.145 ns | — | +0.121 ns | 0/0 ns | PASS |
| Phase 7 FIR-CIC 首版 | +45.113 ns | -0.032 ns | +0.142 ns | 0/0 ns | PASS |
| 941 LUT / 2 DSP | +44.839 ns | -0.274 ns | +0.050 ns | 0/0 ns | PASS |
| 729 LUT / 9 DSP | +44.853 ns | +0.014 ns | +0.077 ns | 0/0 ns | PASS |
| 578 LUT / 9 DSP | +44.153 ns | -0.700 ns | +0.095 ns | 0/0 ns | PASS |
| 472 LUT / 8 DSP | +46.446 ns | +2.293 ns | +0.093 ns | 0/0 ns | PASS |

区域赛从 Phase 6 的 1395 LUT 收敛到 472 LUT 后，WNS 反而由 +45.145 ns 增加到 **+46.446 ns**，提高 **1.301 ns**；WHS 由 +0.121 ns 变为 **+0.093 ns**，减少 0.028 ns，但仍为正，TNS/THS 始终为 0。面积优化没有造成时序违例。

#### 全国赛双采样率板级 Timing

全国赛各结构使用同一器件、板级顶层和时钟约束，可以直接比较：

| 全国赛架构 | WNS | 相对 573-LUT CIC | WHS | 相对 573-LUT CIC | TNS/THS | 结果 |
|---|---:|---:|---:|---:|---:|---|
| 602 LUT / 8 DSP 功能基线 | +46.309 ns | -0.030 ns | +0.103 ns | +0.031 ns | 0/0 ns | PASS |
| 573 LUT / 6 DSP CIC 基线 | +46.339 ns | 基线 | +0.072 ns | 基线 | 0/0 ns | PASS |
| 714 LUT / 3 DSP 全 2x | +46.438 ns | +0.099 ns | +0.105 ns | +0.033 ns | 0/0 ns | PASS |
| 728 LUT / 2 DSP 全 2x | +46.441 ns | +0.102 ns | +0.105 ns | +0.033 ns | 0/0 ns | PASS |
| **440 LUT / 6 DSP 第五轮锚点** | **+46.046 ns** | **-0.293 ns** | **+0.127 ns** | **+0.055 ns** | **0/0 ns** | **PASS** |
| **442 LUT / 432 FF 低 FF CIC** | **+45.617 ns** | **-0.722 ns** | **+0.106 ns** | **+0.034 ns** | **0/0 ns** | **PASS** |
| **434 LUT / 6 DSP 第七轮基线** | **+45.539 ns** | **-0.800 ns** | **+0.108 ns** | **+0.036 ns** | **0/0 ns** | **PASS** |
| **Route 1：424 LUT / 6 DSP** | **+45.356 ns** | **-0.983 ns** | **+0.117 ns** | **+0.045 ns** | **0/0 ns** | **PASS** |
| **第八轮：436 LUT / 5 DSP** | **+45.662 ns** | **-0.677 ns** | **+0.116 ns** | **+0.044 ns** | **0/0 ns** | **PASS** |
| **P1：真 Q15 修复** | **+45.104 ns** | **-1.235 ns** | **+0.121 ns** | **+0.049 ns** | **0/0 ns** | **PASS** |
| **P3：工程闭环** | **+46.140 ns** | **-0.199 ns** | **+0.050 ns** | **-0.022 ns** | **0/0 ns** | **PASS** |
| **P4-A：4 DSP / 3 BRAM Tile** | **+45.738 ns** | **-0.601 ns** | **+0.052 ns** | **-0.020 ns** | **0/0 ns** | **PASS** |
| **P4-B：4 DSP / 2 BRAM Tile** | **+45.637 ns** | **-0.702 ns** | **+0.119 ns** | **+0.047 ns** | **0/0 ns** | **PASS** |
| **P4-D 默认：479 LUT / 4 DSP** | **+45.734 ns** | **-0.605 ns** | **+0.121 ns** | **+0.049 ns** | **0/0 ns** | **PASS；另有50 ns bus-skew，实际1.816 ns** |
| **P3-K DAC-ROM 修复候选：427 LUT / 4 DSP** | **+44.983 ns** | **-1.356 ns** | **+0.105 ns** | **+0.033 ns** | **0/0 ns** | **Timing PASS；AD9708 setup/hold +76.116/+78.117 ns** |
| P3-K 指针推导旧版：412 LUT / 4 DSP | +45.083 ns | -1.256 ns | +0.056 ns | -0.016 ns | 0/0 ns | Timing PASS，但 ROM 功能失败 |
| P3-J Packed-ROM 旧版：424 LUT / 4 DSP | +45.042 ns | -1.297 ns | +0.080 ns | +0.008 ns | 0/0 ns | Timing PASS，但 ROM 功能失败 |
| P3-J Packed-ROM 前基线：430 LUT / 4 DSP | +45.636 ns | -0.703 ns | +0.119 ns | +0.047 ns | 0/0 ns | 安全历史回退 |
| **P4-E：491 LUT / 4 DSP / 1.5 BRAM** | **+46.132 ns** | **-0.207 ns** | **+0.105 ns** | **+0.033 ns** | **0/0 ns** | **PASS；50 ns bus-skew实际2.023 ns** |
| **P4-F：531 LUT / 4 DSP / 1 BRAM** | **+45.898 ns** | **-0.441 ns** | **+0.105 ns** | **+0.033 ns** | **0/0 ns** | **PASS；50 ns bus-skew实际1.859 ns** |
| **P4-C 低 DSP-A：504 LUT / 3 DSP** | **+45.853 ns** | **-0.486 ns** | **+0.121 ns** | **+0.049 ns** | **0/0 ns** | **PASS** |
| **P4-C 低 DSP-B：523 LUT / 2 DSP** | **+45.802 ns** | **-0.537 ns** | **+0.121 ns** | **+0.049 ns** | **0/0 ns** | **PASS** |
| **Vivado 2025.2 24/20/20：218 LUT / 4 DSP** | **+45.279 ns** | **-1.060 ns** | **+0.079 ns** | **+0.007 ns** | **0/0 ns** | **PASS；DRC 0，待物理板测** |

Route 1相对573-LUT基线减少149 LUT和150 FF，WNS减少 **0.983 ns**，WHS增加 **0.045 ns**。第八轮5-DSP版相对同一基线减少137 LUT、150 FF和1 DSP，WNS减少0.677 ns、WHS增加0.044 ns。所有版本均为正WNS/WHS、零TNS/THS、零失败端点；按LUT最低选择424-LUT Route 1，按近最低LUT且节省DSP选择436-LUT/5-DSP版。

需要结合 P1 纠错理解上段历史结论：424/436-LUT 两版因 Stage 3 标度错误不再是发布候选。正确标度并完成工程闭环后，P4-C 默认档在 2 BRAM Tile 下把 P4-B 的 LUT/FF 分别减少 25/25；3-DSP、2-DSP 档也都保持约 +45.8 ns WNS、+0.121 ns WHS 和零失败端点，说明 26/29-bit CARRY 积分器没有造成时序风险。

第五轮实现策略也体现了面积与时序的取舍：`CARRYIN Default` 为 451 LUT、WNS/WHS `+45.647/+0.140 ns`，`ExploreArea` 为 475 LUT、`+46.154/+0.099 ns`。后者多用 24 LUT，只换得 0.507 ns setup 余量且 hold 余量更小；在当前已经没有任何时序违例的情况下不值得，因此选择 `Default`。随后 Stage3 证明字长版本达到 440 LUT，WNS/WHS 回到 **+46.046/+0.127 ns**。

第六轮低 FF 版的 WNS/WHS 为 **+45.617/+0.106 ns**，相对 440-LUT 版分别减少 0.429 ns 和 0.021 ns，但仍然没有 setup/hold 失败端点。`ExploreArea` 可把 Slice 从 194 降到 180，却把 LUT 提高到 460；`AddRemap` 与 `Default` 均为 442 LUT / 432 FF / 194 Slice，故保留 `Default`。

第七轮 21-bit 余量版在 `Default` 下为 **434 LUT / 469 FF / 190 Slice**，WNS/WHS 为 **+45.539/+0.108 ns**；同一综合 DCP 的 `ExploreArea` 为 **468 LUT / 469 FF / 177 Slice**，WNS/WHS 为 `+46.357/+0.095 ns`。后者只减少13 Slice，却增加34 LUT，故该轮正式流程选择`Default`；Route 1与第八轮也继续使用这一实现指令。

由于全国赛顶层包含多个时钟和异步时钟组，不能只用“时钟周期减 WNS”推导一个全局 Fmax；输出采样率 6.144 MHz 也不等同于所有内部路径的约束频率。正式结论应写为“在完整 XDC 下 setup/hold 全部满足”，而不是从全局 WNS 反算一个可能误导的最高频率。当前原始数据见 [5-DSP硬件签核摘要](matlab_fir/national_finals/results/cic5_comb_lut_optimization_summary.md)，历史策略数据见 [实现策略扫描表](matlab_fir/national_finals/results/cic6_implementation_strategy_scan.csv)。

### 最终资源与验证状态汇总

下表选择能代表结构转折点的版本。“变化”按同一比较口径内的前一个关键版本说明；从单采样率切到全国赛双采样率时明确标为范围变化，不做虚假的百分比比较。

| 版本 | 口径 | LUT | FF | DSP | BRAM | MMCM | WNS/WHS | 功耗估计 | 相对关键基线的变化 | RTL/实现/物理板 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| 最初 `4x+5×2x` | 独立链 | 9002 | 4497 | 2 | 0 | — | +165.584/— ns | — | 最初功能基线 | MATLAB/RTL；早期资料未统一板级口径 |
| 全 2x 首个稳定版 | 独立链 | 5912 | 4218 | 1 | 0 | — | +165.930/— ns | — | 比最初独立链少 3090 LUT、279 FF、1 DSP | RTL/综合通过 |
| Phase 6 全 2x | 单采样率板级 | 1395 | 1040 | 2 | 1 | 1 | +45.145/+0.121 ns | 0.168 W | 比全 2x 初始板级少 5031 LUT、3376 FF | RTL/实现/bitstream/物理板均通过 |
| FIR-CIC 首版 | 单采样率板级 | 1128 | 964 | 2 | 1 | 1 | +45.113/+0.142 ns | — | 比 Phase 6 少 267 LUT、76 FF | RTL/实现通过 |
| FIR-CIC 低 DSP | 单采样率板级 | 941 | 940 | 2 | 1.5 | 1 | +44.839/+0.050 ns | 0.168 W | 用 0.5 BRAM 再减 187 LUT、24 FF | RTL/实现/bitstream |
| FIR-CIC 低 LUT 中间版 | 单采样率板级 | 578 | 619 | 9 | 1.5 | 1 | +44.153/+0.095 ns | 0.168 W | 比 941-LUT 版少 363 LUT、321 FF，增加 7 DSP | 完整 RTL/实现/bitstream |
| 区域赛 FIR-CIC 最终版 | 单采样率板级 | 472 | 564 | 8 | 3 | 1 | +46.446/+0.093 ns | 0.169 W | 比 578-LUT 版少 106 LUT、55 FF、1 DSP，增加 1.5 BRAM | **RTL/实现/bitstream/物理板均通过** |
| 全国赛功能基线 | 全国赛板级 | 602 | 616 | 8 | 3 | 2 | +46.309/+0.103 ns | 0.271 W | 新增双采样率与三正式节点，范围发生变化 | RTL/实现/bitstream |
| 全国赛全 2x，最低 LUT | 全国赛板级 | 714 | 662 | 3 | 3 | 2 | +46.438/+0.105 ns | 0.271 W | 比 573-LUT CIC 多 141 LUT、41 FF，少 3 DSP | RTL/实现/bitstream；未物理板测 |
| 全国赛全 2x，最低 DSP | 全国赛板级 | 728 | 662 | 2 | 3 | 2 | +46.441/+0.105 ns | 0.271 W | 比 573-LUT CIC 多 155 LUT、41 FF，少 4 DSP | RTL/实现/bitstream；未物理板测 |
| 全国赛 6-DSP CIC 基线 | 全国赛板级 | 573 | 621 | 6 | 3 | 2 | +46.339/+0.072 ns | 0.271 W | 比 602-LUT/8-DSP 基线少 29 LUT、2 DSP | 9/9 RTL、实现、bitstream；未物理板测 |
| **全国赛第五轮 440-LUT 锚点** | **全国赛板级** | **440** | **464** | **6** | **3** | **2** | **+46.046/+0.127 ns** | **0.271 W** | **比 573 基线少 133 LUT、157 FF，DSP/BRAM/MMCM 不变** | **9/9 RTL、GUI/脚本实现、bitstream；待物理板测** |
| **全国赛低 FF Pareto 版** | **全国赛板级** | **442** | **432** | **6** | **3** | **2** | **+45.617/+0.106 ns** | **0.271 W** | **比 440-LUT 版少 32 FF，多 2 LUT/3 Slice** | **9/9 RTL、MATLAB 六工况、实现、bitstream；待物理板测** |
| **全国赛第七轮基线** | **全国赛板级** | **434** | **469** | **6** | **3** | **2** | **+45.539/+0.108 ns** | **0.271 W** | **比 440-LUT 版少 6 LUT/1 Slice，多 5 FF；比 573 基线少 139 LUT/152 FF** | **9/9 RTL、MATLAB 六工况、实现、DRC、bitstream；待物理板测** |
| **Route 1 历史最低 LUT（标度缺陷）** | **全国赛板级** | **424** | **471** | **6** | **3** | **2** | **+45.356/+0.117 ns** | **0.271 W** | **比434基线少10 LUT/2 Slice，多2 FF；统一双端口系数RAM** | **存在8x/128x约-6.02 dB缺陷，不可发布** |
| **第八轮低 DSP Pareto 版** | **全国赛板级** | **436** | **471** | **5** | **3** | **2** | **+45.662/+0.116 ns** | **0.271 W** | **比Route 1多12 LUT、少7 Slice和1 DSP；comb迁入LUT/CARRY4** | **10/10 RTL、六工况、实现、DRC、bitstream；待物理板测** |
| **P1 真 Q15 修复版** | **全国赛板级** | **446** | **471** | **5** | **3** | **2** | **+45.104/+0.121 ns** | **0.271 W** | **修复旧 8x/128x -6.02 dB 标度错误，恢复绝对增益门禁** | **10/10 RTL、六工况、实现、DRC、bitstream；待物理板测** |
| **P3 工程闭环版** | **全国赛板级** | **462** | **447** | **5** | **3** | **2** | **+46.140/+0.050 ns** | **0.271 W** | **原子 CDC、同步复位、MMCM 安全切换、AD9708 ODDR/IOB STA** | **11/11 RTL、实现、DRC/CDC、bitstream；待物理板测** |
| **P4-A 4-DSP Pareto 版** | **全国赛板级** | **491** | **444** | **4** | **3** | **2** | **+45.738/+0.052 ns** | **0.271 W** | **N3 Hold 严格等价，较 P3 少1 DSP、多29 LUT** | **12/12 RTL、实现、DRC/CDC、bitstream；待物理板测** |
| **P4-B 2-BRAM-Tile Pareto 版** | **全国赛板级** | **504** | **493** | **4** | **2** | **2** | **+45.637/+0.119 ns** | **0.271 W** | **较 P4-A 多13 LUT/49 FF，少1 BRAM Tile** | **14/14 RTL、实现、DRC/CDC、bitstream；待物理板测** |
| **P4-D 默认发布闭环版** | **全国赛板级** | **479** | **468** | **4** | **2** | **2** | **+45.734/+0.121 ns** | **0.271 W** | **继承P4-C资源结构；固定签核wrapper、Release长回归、CDC bus-skew** | **Smoke/Release 15/15、GUI行为/实现、双路径bitstream；待物理板测** |
| **Vivado 2025.2 板测基线** | **全国赛板级** | **292** | **376** | **4** | **2** | **2** | **+44.234/+0.112 ns** | **0.271 W** | **同一正式RTL迁移至2025.2并升级IP；含1 LUTRAM** | **RTL 17/17、routed六档、bitstream及用户实板DAC/六档采样率通过** |
| **2025.2 策略检查点** | **全国赛板级** | **285** | **376** | **4** | **2** | **2** | **+44.695/+0.062 ns** | **0.271 W** | **AreaOptimized_high/full/on + ExploreArea/Explore；含1 LUTRAM** | **完整实现/时序/DRC/bitstream；可回退提交 `5faa60b`** |
| **2025.2 SHREG检查点** | **全国赛板级** | **284** | **379** | **4** | **2** | **2** | **+45.025/+0.091 ns** | **0.271 W** | **SHREG_MIN_SIZE=5，短复位链由1 LUTRAM改为3 FF** | **完整实现/时序/DRC/bitstream；可回退提交 `22b9b55`** |
| **2025.2 DSP抽头门控正式实板版** | **全国赛板级** | **276** | **379** | **4** | **2** | **2** | **+44.885/+0.112 ns** | **0.271 W** | **Stage2/3用DSP PREG CE表达无效历史抽头，删除22/20-bit零值mux；较292少16 LUT** | **Release 17/17、三节点0-LSB、实现/DRC/bitstream、routed六档及用户实板DAC/各档采样率通过** |
| **2025.2 Stage1顺序抽头正式实板版** | **全国赛板级** | **258** | **376** | **4** | **2** | **2** | **+45.222/+0.077 ns** | **0.271 W** | **26个对称系数展开进原系数BRAM空闲区，单地址52拍顺序MAC；较276少18 LUT/3 FF** | **Smoke/Release 17/17、三节点0-LSB、GUI从零重建、DRC/bitstream、routed六档及用户实板DAC/各档采样率通过** |
| **2025.2 CIC DSP角色交换正式实板版** | **全国赛板级** | **249** | **377** | **4** | **2** | **2** | **+43.997/+0.085 ns** | **0.271 W** | **三级comb串行减法进入DSP PREG，第一级26-bit积分器换至CARRY4，并复用comb索引作对齐状态；较258少9 LUT/多1 FF** | **CIC 4096输出定向等价、Smoke/Release 17/17、三节点0-LSB、实现/DRC/bitstream、routed六档及用户实板DAC/各档采样率通过** |
| **249-LUT版本插值核心 OOC** | **核心独立实现** | **210** | **290** | **4** | **1.5** | **0** | **内部 +150.963/+0.128 ns** | **—** | **顶层固定为 `interp128_all2x_v7_folded_fir_cic_top_ce`；3个RAMB18E1，不含板级ROM/控制/时钟/DAC/IO** | **现场入口从零复现、post-route、0路由错误、OOC范围0 DRC Error；完整接口时序由整板签核** |
| **2025.2 Stage1延迟使能正式实板版** | **全国赛板级** | **239** | **377** | **4** | **2** | **2** | **+45.306/+0.082 ns** | **0.271 W** | **用中心抽头有效性的单调不变量，将24-bit数据/零mux改写为寄存器使能；较249少10 LUT，其他列举资源不变** | **Smoke/Release 17/17、三节点0-LSB、正式GUI工程全流程、DRC/bitstream、routed六档及用户物理板通过** |
| **239-LUT版本插值核心 OOC** | **核心独立实现** | **197** | **290** | **4** | **1.5** | **0** | **内部 +151.665/+0.054 ns** | **—** | **与239-LUT整板同一核心RTL和参数；3个RAMB18E1，不含板级ROM/控制/时钟/DAC/IO** | **现场入口从零复现并精确门禁、post-route、0路由错误、OOC范围0 DRC Error；完整接口时序由整板签核** |
| **2025.2 Stage1索引合并+共享phase+原子切档正式实板版** | **全国赛板级** | **234** | **369** | **4** | **2** | **2** | **+44.925/+0.060 ns** | **0.271 W** | **Stage1合并调度/发射索引；Stage2/3复用权威phase；force_mute内负边沿原子提交模式并删除重复mismatch静音项；较239少5 LUT/8 FF** | **Smoke/Release 17/17、正式综合/实现/DRC/bitstream、routed六档及用户实板各档采样率/DAC波形通过** |
| **234-LUT版本插值核心 OOC** | **核心独立实现** | **194** | **282** | **4** | **1.5** | **0** | **内部 +151.280/+0.089 ns** | **—** | **与234-LUT整板同一核心RTL和参数；3个RAMB18E1，不含板级ROM/控制/时钟/DAC/IO** | **现场入口从零复现并精确门禁、post-route、0路由错误、OOC范围0 DRC Error；完整接口时序由整板签核** |
| **2025.2 routed不变量复用正式实板版** | **全国赛板级** | **221** | **367** | **4** | **2** | **2** | **+44.556/+0.079 ns** | **0.271 W** | **CDC ack兼任seen、Stage3直接复用稳定pending模式、全国赛同步复位零路径常量valid删除24-bit输入/零门控；较234少13 LUT/2 FF** | **Smoke/Release 17/17、正式实现/DRC/bitstream、默认DAC、routed六档及用户物理板六档采样率/DAC波形全部通过** |
| **221-LUT版本插值核心 OOC** | **核心独立实现** | **193** | **281** | **4** | **1.5** | **0** | **内部 +151.232/+0.166 ns** | **—** | **与221-LUT整板同一核心RTL和参数；3个RAMB18E1，不含板级ROM/控制/时钟/DAC/IO** | **从空结果目录连续两次复现，精确门禁PASS、post-route、0路由错误、OOC范围0 DRC Error** |
| **2025.2 Stage1/2/3=24/20/20 LUT优先实板版** | **全国赛板级** | **218** | **365** | **4** | **2** | **2** | **+45.279/+0.079 ns** | **0.271 W** | **Stage1后直接量化到20 bit，Stage2数据/历史/DSP判据收窄，第二级bridge改同宽握手；较221少3 LUT/2 FF** | **MATLAB 6/6+9/9、Smoke/Release 17/17、14组全链0-LSB、正式实现/DRC/bitstream、routed六档及用户物理板通过** |
| **218-LUT版本插值核心 OOC** | **核心独立实现** | **190** | **279** | **4** | **1.5** | **0** | **内部 +150.943/+0.069 ns** | **—** | **与218-LUT整板同一24/20/20核心参数；3个RAMB18E1，不含板级ROM/控制/时钟/DAC/IO** | **post-route、0路由错误、OOC范围0 DRC Error；完整接口时序由218-LUT整板签核** |
| **2025.2 24/20/20 低DSP正式实板版** | **全国赛板级** | **239** | **388** | **3** | **2** | **2** | **+44.703/+0.079 ns** | **0.271 W** | **CIC积分器DSP模式1；相对218-LUT版增加21 LUT/23 FF并减少1 DSP，其他列举资源不变** | **Smoke 17/17、正式实现/正时序/0 DRC Error、bitstream及用户物理板通过** |
| **P3-U 控制路径深度优化候选** | **全国赛板级** | **333** | **382** | **4** | **2** | **2** | **+45.704/+0.079 ns** | **0.271 W** | **精确Johnson键盘消抖 + CDC one-hot settle token；相对P3-T少8 LUT/11 Slice，仅多1 FF** | **Smoke/Release 17/17、三节点0-LSB、GUI从零重建、routed DAC/六档与bitstream通过；待物理板测** |
| **P3-T Stage1 DSP尾周期正式实板版** | **全国赛板级** | **341** | **381** | **4** | **2** | **2** | **+45.270/+0.107 ns** | **0.271 W** | **Stage1 DSP接管舍入/Pattern溢出检测/PREG钳位，并由稳定写指针派生历史基址；相对P3-S少2 LUT/5 FF，但多12 Slice** | **Smoke/Release 17/17、三节点0-LSB、GUI、routed DAC/六档、bitstream及用户实板DAC/六档采样率通过** |
| **P3-S ExtraTimingOpt正式实板版** | **全国赛板级** | **343** | **386** | **4** | **2** | **2** | **+45.025/+0.116 ns** | **0.271 W** | **不改P3-R RTL；以ExtraTimingOpt改善LUT打包，相对P3-R少5 LUT/3 Slice** | **Smoke/Release 17/17、0-LSB、GUI、routed DAC/六档、bitstream及用户实板DAC/各档采样率通过** |
| **P3-R DSP空闲拍舍入饱和正式版** | **全国赛板级** | **348** | **386** | **4** | **2** | **2** | **+45.200/+0.121 ns** | **0.271 W** | **Stage2/3共享DSP在MAC后完成舍入、Pattern符号扩展检查和PREG直接钳位，移除Fabric宽比较器与饱和mux** | **Smoke/Release 17/17、0-LSB、GUI、routed DAC/六档、bitstream及用户实板DAC/各档采样率通过** |
| **P3-O ExploreWithRemap候选** | **全国赛板级** | **361** | **386** | **4** | **2** | **2** | **+44.989/+0.103 ns** | **0.271 W** | **RTL与P3-M相同；同一综合网表重映射再少7 LUT，DSP/BRAM/FF不变** | **前一工具候选；Release 17/17、routed DAC/六档通过** |
| P3-P论文驱动审计 | 全国赛板级 | 361（保留P3-O） | 386 | 4 | 2 | 2 | +44.989/+0.103 ns（保留） | 0.271 W | 五类候选最佳为367/369/370/368 LUT，均No-Go，正式RTL恢复P3-O | 论文、原语、综合、实现审计完成；无新板测 |
| P3-Q DSP Pattern饱和审计 | 全国赛板级 | 361（保留P3-O） | 386 | 4 | 2 | 2 | +44.989/+0.103 ns（保留） | 0.271 W | 四组综合395/396/414/415 LUT；Pattern标志破坏比较器与饱和mux折叠，No-Go | 候选Smoke 17/17；停止在综合，正式RTL恢复P3-O |
| **P3-M DSP-register 正式版** | **全国赛板级** | **368** | **386** | **4** | **2** | **2** | **+44.836/+0.117 ns** | **0.271 W** | **Stage1 左操作数进入 DSP48 AREG，INMODE 屏蔽 A/D，无额外 DSP/BRAM** | **Smoke/Release 17/17、RTL/UNISIM、GUI、post-route、bitstream及用户实板 DAC/各档采样率通过** |
| **P3-L 共享保护时基正式版** | **全国赛板级** | **397** | **409** | **4** | **2** | **2** | **+44.408/+0.121 ns** | **0.271 W** | **相对实板通过 P3-K 少30 LUT、7 FF、16 Slice；离线单镜像 Packed-ROM + 复用键盘计数器低10位** | **Smoke/Release 16/16、默认及六模式 post-route、DRC/CDC、bitstream、实板 DAC 与六档采样频率通过** |
| **P3-K DAC-ROM 实板通过版** | **全国赛板级** | **427** | **416** | **4** | **2** | **2** | **+44.983/+0.105 ns** | **0.271 W** | **显式ROM地址计数；保留指针推导历史优化** | **Smoke/Release 15/15、post-route、DRC/CDC、bitstream、实板 DAC/采样率正常** |
| P3-K 指针推导旧版 | 全国赛板级 | 412 | 418 | 4 | 2 | 2 | +45.083/+0.056 ns | 0.271 W | 环形指针推导填充深度 | **RAMB18下一地址为0，禁止上板** |
| P3-J Packed-ROM 旧版 | 全国赛板级 | 424 | 431 | 4 | 2 | 2 | +45.042/+0.080 ns | 0.271 W | ROM高位保存下一地址 | **RAMB18下一地址为0，禁止上板** |
| **P3-J Packed-ROM 前可复现基线** | **全国赛板级** | **430** | **431** | **4** | **2** | **2** | **+45.636/+0.119 ns** | **0.271 W** | **128x均衡响应折叠进Stage3** | **安全历史回退；待实板测** |
| **P3-J 3-DSP Pareto** | **全国赛板级** | **466** | **457** | **3** | **2** | **2** | **+45.785/+0.121 ns** | **0.271 W** | **较默认多36 LUT/26 FF，少1 DSP** | **Release 15/15、实现、bitstream；待物理板测** |
| **P3-J 2-DSP Pareto** | **全国赛板级** | **488** | **486** | **2** | **2** | **2** | **+45.736/+0.060 ns** | **0.270 W** | **较默认多58 LUT/55 FF，少2 DSP** | **Release 15/15、实现、bitstream；待物理板测** |
| **P3-J 1.5-BRAM Pareto** | **全国赛板级** | **456** | **450** | **4** | **1.5** | **2** | **+46.033/+0.116 ns** | **0.271 W** | **较默认多26 LUT/19 FF，少0.5 BRAM Tile** | **RTL、实现、bitstream；待物理板测** |
| **P4-E 1.5-BRAM Pareto** | **全国赛板级** | **491** | **487** | **4** | **1.5** | **2** | **+46.132/+0.105 ns** | **0.271 W** | **PCM ROM与Stage1历史共享RAMB18；较P4-D少0.5 BRAM、多12 LUT/19 FF** | **Smoke/Release 16/16、GUI行为/实现、bitstream；待物理板测** |
| **P4-F 1-BRAM Pareto** | **全国赛板级** | **531** | **487** | **4** | **1** | **2** | **+45.898/+0.105 ns** | **0.270 W** | **Stage2/3历史改8个RAM32M；较P4-D少1 BRAM、多52 LUT/19 FF** | **Smoke/Release 16/16、GUI行为/实现、bitstream；待物理板测** |
| **P4-C 3-DSP Pareto 版** | **全国赛板级** | **504** | **494** | **3** | **2** | **2** | **+45.853/+0.121 ns** | **0.271 W** | **较默认版多25 LUT/26 FF，少1 DSP** | **CIC三映射0 LSB、实现、bitstream；待物理板测** |
| **P4-C 2-DSP Pareto 版** | **全国赛板级** | **523** | **523** | **2** | **2** | **2** | **+45.802/+0.121 ns** | **0.270 W** | **较默认版多44 LUT/55 FF，少2 DSP** | **CIC三映射0 LSB、实现、bitstream；待物理板测** |

综合结论：

- **当前最低 LUT 且正式实板通过版为 Vivado 2025.2 24/20/20 字长版：218 LUT / 365 FF / 4 DSP / 2 BRAM Tile**；MATLAB频响与定向数值、Smoke/Release 17/17、14组全链逐样本对拍、正式综合/实现/时序/DRC/功耗/bitstream、routed六档及用户物理板均通过；
- **当前正式工程和低 DSP 实板 Pareto 版为 Vivado 2025.2 CIC 模式1：239 LUT / 388 FF / 3 DSP / 2 BRAM Tile**；相对218-LUT版以21 LUT和23 FF换取1 DSP，Smoke 17/17、正式实现、正时序、0 DRC Error、bitstream及用户物理板均通过；
- **221 LUT / 367 FF / 4 DSP / 2 BRAM Tile 版本继续保留为更早实板回退**；Smoke/Release 17/17、正式综合/实现/DRC/时序/功耗/bitstream、默认与 routed 六档门禁及用户物理板六档采样率/DAC波形全部通过；
- **221-LUT 后结构重构试验未形成新正式候选**：256× 全局单 DSP、固定时隙 Stage2/3、DSP 内折叠量化均完成定向逐拍等价和同口径 OOC；最佳候选只在 FIR 前端减少 1 LUT、增加 6 FF，且需要新增 256× 时钟集成，无法形成可信的整板净收益，因此正式版和 board-pass 标签保持不变；
- **前一实板安全回退为 Vivado 2025.2 共享phase与原子切档版：234 LUT / 369 FF / 4 DSP / 2 BRAM Tile**；其 board-pass 标签继续保留；
- **前一实板安全回退为 Vivado 2025.2 Stage1 延迟使能版：239 LUT / 377 FF / 4 DSP / 2 BRAM Tile**；工具闭环与用户物理板均通过，board-pass 标签继续保留；
- **前一 Vivado 2025.2 实板安全回退为249 LUT / 377 FF / 4 DSP / 2 BRAM Tile**；258、276、292 LUT版本继续作为更早实板回退；
- 旧 Route 1 `424 LUT / 6 DSP` 和第八轮 `436 LUT / 5 DSP` 是重要资源演进点，但存在 Stage 3 Q14/Q15 标度缺陷，不再作为发布候选；
- **历史 P3-U 控制路径候选为 333 LUT / 382 FF / 152 Slice / 4 DSP / 2 BRAM Tile**；其工具验证已通过但未物理板复测，现仅保留为结构演进记录，不再作为当前推荐版本；
- **当前最低LUT且正式实板通过版为P3-T：341 LUT / 381 FF / 4 DSP / 2 BRAM Tile**；Stage1 DSP尾周期饱和与派生基址通过两轮17/17、0-LSB、GUI、routed-DCP六档门禁、bitstream，以及用户实板DAC与44.1/48 kHz六档采样率复测；
- **前一实板安全回退为P3-S：343 LUT / 386 FF / 4 DSP / 2 BRAM Tile**；滤波RTL与P3-R相同，完整17/17、GUI、routed-DCP DAC/六档、bitstream以及用户实板DAC/各档采样率均通过；
- **前一实板安全回退为P3-R：348 LUT / 386 FF / 4 DSP / 2 BRAM Tile**；共享Stage2/3 DSP的空闲拍接管舍入和饱和，Release 17/17、GUI重建、routed-DCP DAC/六档以及用户实板DAC/各档采样率均通过；
- **前一实板安全版为P3-M：368 LUT / 386 FF / 4 DSP / 2 BRAM Tile**；已通过真实RAMB18 Stage1对拍、完整Release、GUI重建、六模式布局后DAC门禁以及用户实板DAC/各档采样率复测；
- **P3-L：397 LUT / 409 FF / 4 DSP / 2 BRAM Tile** 保留为前一实板安全回退；
- **P3-K DAC-ROM 修复版 427 LUT / 416 FF / 4 DSP / 2 BRAM Tile 现为安全历史回退**；旧 412-LUT 指针推导版和 424-LUT Packed-ROM 版均因 ROM 地址锁死撤销；
- **P4-D R2：479 LUT / 468 FF / 4 DSP / 2 BRAM Tile 保留为联合 Stage3 之前的稳定回退点**；
- **P4-E 与 P4-F 分别以增加 12/52 LUT 换取 0.5/1 BRAM Tile，是低 BRAM Pareto，不支配 P4-D**；
- **P4-A：491 LUT / 444 FF / 4 DSP / 3 BRAM Tile 仍是最低 FF 的 4-DSP 回退点**；
- **P4-B 已被同为 4 DSP/2 BRAM Tile、但少25 LUT/25 FF的 P4-C 默认档支配，只保留为回退**；
- **当前最低 FF 的全国赛 6-DSP CIC 是 442 LUT / 432 FF 版本；它与 434 LUT / 469 FF 版本互为 Pareto 点**；
- **当前最低 DSP 的已签核 P3-J 方案是 488 LUT / 2 DSP / 2 BRAM Tile；另有 466 LUT / 3 DSP 中间档**；
- 全 2x 最低 DSP 版仍具有更高最终阻带，但在相同2 DSP下比P4-C多205 LUT、139 FF和1 BRAM Tile；FIR-CIC 以仍高于70 dB的阻带余量换取明显更低资源；
- P3、P4-A、P4-B、P4-C、P4-D 和 P3-J 均已完成 MATLAB、RTL、XSim、综合、布局布线、时序、DRC/CDC 和 bitstream 工具侧签核；P3-J 与 P4-D 均完成 10-seed×4096 加正负满量程的发布门槛；仍需实物板下载复测，不能把区域赛472-LUT版本的实板结论直接代替。

## 历史详细资料

主 README 只保留当前 Vivado 2025.2 正式路线、关键资源演进、验证状态和安全回退点。早期 Phase 6、Phase 7、P3/P4 候选的逐轮参数、旧 bitstream 哈希、阶段性板测诊断和已经失效的复现说明不再重复展开，避免与当前工程配置混淆。

需要追溯历史细节时，可查阅：

- [全国赛交付与验证说明](matlab_fir/national_finals/README.md)
- [Phase 7 FIR-CIC 执行报告](matlab_fir/all2x_phase7_fir_cic_execution_report.md)
- [Phase 7 验证汇总](matlab_fir/alt_all2x_v7/verification/reports/phase7_verification_final_summary.md)
- [`matlab_fir/national_finals/results`](matlab_fir/national_finals/results) 中的各轮执行反馈
- Git 分支、提交和标签中的可回退工程版本
