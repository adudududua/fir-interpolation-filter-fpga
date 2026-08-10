# Vivado 2025.2 迁移、修复与验证记录

## 当前状态：221-LUT 工具签核候选，234-LUT 正式板测回退

分支 `national-finals-v2025.2-post234-lut-optimization` 在已板测 234-LUT 版本上完成 routed
网表不变量优化：CDC `ack_toggle` 兼任本地 seen token；Stage2/3 删除重复补偿模式 job 快照；
全国赛同步复位为零的数据路径把输入 valid 明确为常量 1，从而删除 Stage1 RAM 前 24-bit
输入/零门控。区域赛兼容 generate 路径仍保留原一拍 valid 行为，系数、位宽、舍入/饱和、
采样率和输出相位不变。

正式归档目录为 `tools/vivado_2025_2/results/20260810_181833`：

**221 LUT / 0 LUTRAM / 367 FF / 4 DSP / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**；综合为 **285 LUT / 375 FF**，WNS/WHS=`+44.556/+0.079 ns`，
TNS/THS=0，DRC Error=0，路由错误=0，bus-skew 余量 `+49.567 ns (MET)`，
总/动态/静态功耗=`0.271/0.199/0.072 W`。相对 234-LUT 板测版减少 13 LUT、2 FF，
其他列举资源不变。

Smoke/Release 均为 17/17 PASS；正式 routed DCP 默认模式得到 11290 个 DAC 边沿、7462 次
数据变化，六模式后仿真为 44.1 kHz `177/353/5645 edges/ms`、48 kHz
`192/384/6144 edges/ms`，六档 DAC 数据均持续变化且无 X。bitstream SHA-256 为
`08B2DE6DB8DF1FBC9E59EA78808C57BD007E414243B5F6FF9C7FF1B2797D91A7`，routed DCP SHA-256 为
`BFE4A9A25958C232E24091A08EE7A2F0E564AB3DF8C45EEFEB9CCA3CF1DC943F`。当前为
**tool-verified，待用户物理板验证**；正式安全回退标签仍为
`nf-vivado2025.2-234lut-369ff-4dsp-2bram-board-pass`。

独立核心 OOC 从空结果目录复跑并通过精确门禁：
**193 LUT / 0 LUTRAM / 281 FF / 4 DSP / 3 RAMB18E1（1.5 Tile）/ 0 MMCM**，内部
WNS/WHS=`+151.232/+0.166 ns`，DRC Error=0。现场复现见 [`core_ooc/README.md`](core_ooc/README.md)。

批处理入口会把 `XILINX_TCLAPP_REPO` 与 `TCLLIBPATH` 固定到 Vivado 安装目录自带 Tcl Store，
因此用户目录中损坏的 Tcl Store 缓存不会再让 `open_project` 或 post-route 导出在综合前失败。

## 当前正式板测回退：234 LUT，239 LUT 为前一安全回退

分支 `national-finals-v2025.2-230to234-lut-challenge` 在 239-LUT board-pass 版本上完成三项
等价控制优化：Stage1 合并调度/发射索引，Stage2/3 bridge 复用滤波核权威 phase 状态，以及
在 `force_mute` 有效期间于 DAC 分频负边沿原子提交模式并删除活动路径上的冗余 mismatch
静音项。滤波系数、字长、舍入/饱和、valid、双时钟族、DSP 与 BRAM 数均不变。

正式归档目录为 `tools/vivado_2025_2/results/20260810_160858`：

**234 LUT / 0 LUTRAM / 369 FF / 4 DSP / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**；综合为 **310 LUT / 377 FF**，WNS/WHS=`+44.925/+0.060 ns`，
TNS/THS=0，DRC Error=0，路由错误=0，bus-skew 余量 `+49.467 ns (MET)`，
总/动态/静态功耗=`0.271/0.199/0.072 W`。
相对 239-LUT 板测版减少 5 LUT 和 8 FF，其他列举资源不变。

Smoke/Release 均为 17/17 PASS；正式 routed DCP 六模式后仿真为 44.1 kHz
`177/353/5645 edges/ms`、48 kHz `192/384/6144 edges/ms`，六档 DAC 数据均持续变化且无 X。
工具签核 bitstream SHA-256 为
`3076AB46767D4BA6DB058DA73662E074053A4E5E694FF0E6417DE1D7ABDF7025`。用户随后使用标准 GUI
工程重新综合、实现并完成物理板验证，确认 44.1/48 kHz 两个输入采样率族下所有档位的实际
输出采样率均正确，DAC 输出波形均正常。实际板测归档为
`tools/vivado_2025_2/results/20260810_170616_board_pass`，bitstream SHA-256 为
`F9DB8E33C3959C448FDE316A51BA9A13ABC83D5AE1F69655CD5D0B698A871E85`，routed DCP SHA-256 为
`47CDCA8E43C2DA817D028828564862EC56C64F0E791C6F845DE05A3E03DA3162`；当前状态为
**board-verified**，正式标签为 `nf-vivado2025.2-234lut-369ff-4dsp-2bram-board-pass`。

独立核心 OOC 从空结果目录复跑并通过精确门禁：
**194 LUT / 0 LUTRAM / 282 FF / 4 DSP / 3 RAMB18E1（1.5 Tile）/ 0 MMCM**，内部
WNS/WHS=`+151.280/+0.089 ns`，DRC Error=0。现场复现见 [`core_ooc/README.md`](core_ooc/README.md)。

## 前一状态：239-LUT 正式板测版，249-LUT 更早板测回退

分支 `national-finals-v2025.2-post249-lut-optimization` 将 Stage1 中心延迟寄存器的无效启动期
处理由 24-bit `read_data/0` 数据选择改写为寄存器使能。中心抽头的历史有效性在复位周期内
单调增加，且寄存器复位值为零，因此无效期保持零与反复写零严格等价；有效后每次中心抽头读取
都正常更新。该表达删除了综合后物理网表中的宽数据选择器，不改变系数、位宽、valid 时序或输出。

正式工程从 `reset_run` 开始完整重建并生成 bitstream，结果目录为
`tools/vivado_2025_2/results/20260809_173232`：

**239 LUT / 0 LUTRAM / 377 FF / 4 DSP / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**；综合为 **314 LUT / 385 FF**，WNS/WHS=`+45.306/+0.082 ns`，
TNS/THS=0，DRC Error=0，路由错误=0，总/动态/静态功耗=`0.271/0.199/0.072 W`。
相对 249-LUT 实板版减少 10 LUT，其他列举资源不变。

Smoke/Release 均为 17/17 PASS；Release 全链 14 组输入在 4x/8x/128x 三节点全部 0 LSB；
239-LUT routed DCP 的六模式后仿真为 44.1 kHz `177/353/5645 edges/ms`、48 kHz
`192/384/6144 edges/ms`，六档 DAC 数据均持续变化且无 X。bitstream SHA-256 为
`56248A6FFD013B020012B397ED32E9FA9F2285644978E5016CEB2F5506911EEA`。用户随后完成物理板
验证，确认各档采样率和 DAC 输出波形正常，因此该版本已升级为 **board-verified**；标签为
`nf-vivado2025.2-239lut-377ff-4dsp-2bram-board-pass`。

独立核心 OOC 从空结果目录复跑并通过精确门禁：
**197 LUT / 0 LUTRAM / 290 FF / 4 DSP / 3 RAMB18E1（1.5 Tile）/ 0 MMCM**，内部
WNS/WHS=`+151.665/+0.054 ns`，DRC Error=0。现场复现见 [`core_ooc/README.md`](core_ooc/README.md)。

## 前一状态：249-LUT 正式板测版，258-LUT 更早板测回退

挑战分支 `national-finals-v2025.2-245to249-lut-challenge` 已在 258-LUT 实板版上完成 CIC
DSP 角色交换：三级串行 comb 减法使用一个显式 DSP48E1 P 寄存器，第一级 26-bit 积分器
改由 CARRY4 实现，最后一级积分器仍使用 DSP；同时复用 comb 阶段索引作为 DSP 输出的一拍
对齐状态。整机 DSP 数保持 4，BRAM 保持 4 个 RAMB18E1（2 Tile）。正式构建结果为：

**249 LUT / 0 LUTRAM / 377 FF / 4 DSP / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**；综合为 **325 LUT / 385 FF**，WNS/WHS=`+43.997/+0.085 ns`，DRC Error=0，
总/动态/静态功耗=`0.271/0.199/0.072 W`。相对已板测 258-LUT 版减少 9 LUT、增加 1 FF，
其余列举资源不变。

正式结果目录：`tools/vivado_2025_2/results/20260808_233550`；bitstream SHA-256 为
`353308536B12E16CE896236D3754430B372ED1F957CB52B744EA2A8F57B6D1AB`。CIC 定向等价共比较
4096 个输出，并覆盖连续、停顿、10 seed 和中途复位；Smoke 与 Vivado 2025.2 Release 均为
17/17 PASS，14 组全链输入在 4x/8x/128x 三节点全部 0 LSB；routed DCP 六档 DAC/采样率
检查全部通过。2026-08-09 用户完成物理板复测，确认六档采样率和 DAC 波形均正常，因此
该版本已经升级为 **board-verified**，并作为 239-LUT 候选的正式实板回退。工具签核标签为
`nf-vivado2025.2-249lut-377ff-4dsp-2bram-toolverified`，实板标签为
`nf-vivado2025.2-249lut-377ff-4dsp-2bram-board-pass`。完整 A/B 数据与回退说明见
`matlab_fir/national_finals/results/vivado2025_2_cic_dsp_role_exchange_249lut_execution_feedback.md`。

### 249-LUT 版本的历史插值核心 OOC 报告

整板 249 LUT 不能直接称为滤波器核心资源。专用脚本已把
`interp128_all2x_v7_folded_fir_cic_top_ce` 作为独立顶层完成 Vivado 2025.2 post-route：
**210 LUT / 0 LUTRAM / 290 FF / 4 DSP48E1 / 3 RAMB18E1（1.5 BRAM Tile）/ 0 MMCM**，
核心内部 WNS/WHS=`+150.963/+0.128 ns`，0 DRC Error。现场从零运行命令、非默认安装路径参数、
报告文件和 GUI 展示步骤见 [`core_ooc/README.md`](core_ooc/README.md)。

## 前一状态：258-LUT 正式板测版，276-LUT 更早板测回退

分支 `national-finals-v2025.2-post276-lut-optimization` 已完成 Stage1 存储/控制架构重构：
把 26 个对称系数展开为 52 个顺序系数并写入现有统一系数 RAMB18E1 的空闲地址，Stage1 以
单地址历史扫描每拍直接 MAC，同时捕获中心延迟样本。标准工程完整重建为
**258 LUT / 0 LUTRAM / 376 FF / 4 DSP / 4 RAMB18E1（2 BRAM Tile）/ 17 IO / 2 MMCM**；
WNS/WHS=`+45.222/+0.077 ns`，DRC Error=0，功耗 0.271 W。Smoke/Release 17/17、三节点
0 LSB、routed 六档和 bitstream 全部通过；用户随后完成物理板复测，确认六档采样率与 DAC
波形正常，因此该版本已经升级为 board-verified。

GUI 完整构建结果目录：`tools/vivado_2025_2/results/20260808_161249`；bitstream SHA-256 为
`A9BD34D4770434330B199E1AADC23B71C2DF76B3B4EFEB8DAC4F15498526B491`。详细结构、数值证明、
验证矩阵和回退方法见
`matlab_fir/national_finals/results/vivado2025_2_stage1_sequential_258lut_execution_feedback.md`。
工具签核标签为 `nf-vivado2025.2-258lut-376ff-4dsp-2bram-toolverified`，实板标签为
`nf-vivado2025.2-258lut-376ff-4dsp-2bram-board-pass`。

276-LUT 版本也已完成用户实板验证，作为更早安全回退；其提交、标签和分支均未改写。

## 276-LUT 正式板测版，292-LUT 前一安全回退

当前分支 `national-finals-v2025.2-4dsp-2bram-lut-opt` 在已板测 292-LUT 版本上继续完成
策略与 RTL 优化。最新候选在 Vivado 2025.2 下布局布线为
**276 LUT / 0 LUTRAM / 379 FF / 4 DSP / 4 RAMB18E1（2 BRAM Tile）/ 17 IO / 2 MMCM**，
比 292-LUT 基线减少 16 LUT、增加 3 FF，DSP/BRAM/IO/MMCM 不变。它已通过完整工具签核；
2026-08-08 用户完成物理板验证，确认 44.1/48 kHz 两个输入采样率族下各公开插值档位的
输出采样率均正确，AD9708 DAC 输出波形均正常。正式标签为
`nf-vivado2025.2-276lut-379ff-4dsp-2bram-17io-2mmcm-board-pass`；292-LUT board-pass 标签
继续作为前一实板安全回退。

### 优化演进与方法

| 检查点 | Routed LUT | LUTRAM | FF | DSP | BRAM Tile | 方法 | 状态 |
|---|---:|---:|---:|---:|---:|---|---|
| 板测基线 | 292 | 1 | 376 | 4 | 2 | 2025.2 迁移及 IP 升级 | 板测通过 |
| `5faa60b` | 285 | 1 | 376 | 4 | 2 | `AreaOptimized_high/full/on + ExploreArea/Explore` | 工具通过 |
| `22b9b55` | 284 | 0 | 379 | 4 | 2 | `SHREG_MIN_SIZE=5`，短复位链保留为 FF | 工具通过 |
| `099390e` | **276** | **0** | **379** | **4** | **2** | Stage2/3 DSP PREG 抽头有效位门控 | **工具与用户实板均通过** |
| Stage1 顺序抽头正式版 | **258** | **0** | **376** | **4** | **2** | 系数展开进原 BRAM 空闲区，单地址 52 拍直接 MAC | **工具与用户实板均通过** |
| CIC DSP角色交换正式版 | **249** | **0** | **377** | **4** | **2** | comb进DSP、第一级积分器进CARRY4、对齐状态复用 | **工具与用户实板均通过** |
| Stage1 延迟寄存器使能正式版 | **239** | **0** | **377** | **4** | **2** | 利用中心抽头有效性单调不变量，删除24-bit数据/零mux | **工具与用户实板均通过** |
| Stage1索引合并+共享phase+原子切档正式版 | **234** | **0** | **369** | **4** | **2** | 合并Stage1索引、复用Stage2/3权威phase、force_mute内负边沿原子提交模式 | **工具与用户实板均通过** |

Stage2/3 原实现根据历史有效位，在 Fabric 中将 22-bit/20-bit 样本选择为真实值或零，再送入
共享 DSP。当前实现让 BRAM 原始样本直接进入 DSP，并用任务启动时锁存的
`job_history_valid` 控制 DSP PREG 的更新；无效抽头保持当前累加值，严格等价于累加零。由此
删除两个宽数据选择器，不改变系数、位宽、舍入/饱和、valid 时序、时钟和 DAC 接口。
当前架构仍为补偿已经折叠进 Stage3 的三级 FIR 加 CIC16，不是“独立补偿器 + CIC comb”。

Stage1 DSP PREG 延迟复用也完成了实际 A/B：Smoke 17/17 通过，FF 从 387 降到 363，但综合
LUT 从 341 增至 363（+22），所以按 LUT 优先门槛停止并回退，没有进入正式实现。

### 276-LUT 正式构建结果

结果目录：`tools/vivado_2025_2/results/20260808_012650`

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | BRAM Tile | RAMB18E1 | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 341 | 0 | 387 | 4 | 2 | 4 | 17 | 2 |
| 布局布线后 | **276** | **0** | **379** | **4** | **2** | **4** | **17** | **2** |

| 检查项 | 结果 |
|---|---:|
| WNS / TNS | +44.885 ns / 0 ns |
| WHS / THS | +0.112 ns / 0 ns |
| setup / hold 失败端点 | 0 / 0 |
| DRC Error | 0 |
| 总片上功耗 | 0.271 W |
| 动态 / 静态功耗 | 0.199 W / 0.072 W |
| 功耗置信度 | Medium（无 SAIF 的 vectorless 估算） |

生成文件：

- `tools/vivado_2025_2/results/20260808_012650/board_demo_competition_dac8_top_2025_2.bit`
- `tools/vivado_2025_2/results/20260808_012650/board_routed_2025_2.dcp`
- 同目录的综合/实现利用率、时序、DRC、功耗、route status 与完整日志。

bitstream SHA-256：
`1A6CDA833627AA197AB111EB426E6CA70405E69D657B3528C3B6D9CF1A0BCB2F`

### 276-LUT 验证结果

- Release RTL 回归 17/17 PASS；全链冲激、10 seeds、正/负满量程和强 −1 dBFS 共 14 组，
  4x/8x/128x 全部 0 LSB；
- Stage1 行为 RAM 与 RAMB18E1 原语各 1400 个输出 0 LSB；
- 8 类内部状态复位恢复、10 次不停机动态切档、ROM、DAC offset-binary、系数/历史 BRAM、
  CDC、按键和双时钟族测试全部通过；
- 外层回归脚本在最后一个动态切档用例 elaboration 时到达 603 s 时限；随后在同一用例目录
  完成该仿真并 PASS。最终审计 17 份 `xsim.log` 均包含 PASS/finish，且无 ERROR/FATAL；
- 正式 routed DCP 六档测试全部通过：44.1 kHz 为 `177/353/5645 edges/ms`，48 kHz 为
  `192/384/6144 edges/ms`，各档 DAC 数据均持续变化且无 X。177/353/5645 是 1 ms 窗口内
  的整数计数，对应理论 176.4/352.8/5644.8 kHz。

RTL 回归目录：
`matlab_fir/national_finals/_work/rtl_regression/20260808_011426`

六档布局布线后回归目录：
`matlab_fir/national_finals/_work/postroute_six_mode_dac/20260808_013106`

### 276-LUT 实板验证

2026-08-08 用户下载上述 SHA-256 对应的 276-LUT bitstream 完成物理板验证：44.1 kHz 与
48 kHz 两个输入采样率族下，各公开插值档位的输出采样率均正确，AD9708 DAC 输出波形均
正常。该结论与 RTL 17/17、routed-DCP 六档计数和 DAC 数据活动测试一致，因此本版状态由
`tool-verified` 正式升级为 `board-verified`。用户未提供逐档仪器数值，本文只记录已确认的
通过结论，不虚构额外测量数据。

## 结论

工程 `XC7A35T_interp_opt_2025.2/XC7A35T_interp.xpr` 已在 Vivado 2025.2 下完成迁移和验证。
2026-08-07 的签核运行成功完成综合、实现、DRC、时序、功耗分析和 bitstream 生成，且直接针对
该复制工程源码执行的全国赛 RTL Smoke 回归为 17/17 PASS。由 2025.2 routed DCP 导出的布线后
功能网表也通过了六档 DAC 活动与采样率检查。

本次只处理工具版本迁移、IP、工程运行状态和验证脚本，没有修改滤波器算法、定点字长、系数或
板级接口。该 2025.2 bitstream 已通过工具和仿真验证；用户随后完成实板复测，确认所有档位的
实际采样率均正确，DAC 输出波形正常。因此本版本已形成 RTL、实现、bitstream 与板级验证闭环。

## 原始失败原因

初始 GUI 综合日志没有 RTL `ERROR`，而是在综合后段突然终止。日志记录的 Windows 提交内存
上限约 46--49 GB，当时剩余提交余量最低只有约 0.45 GB；排查时也只剩约 3.04 GB。
Vivado GUI 和综合子进程合计所需空间超过了余量，因此 Windows 可能直接终止子进程，表现为
综合无明确 RTL 错误、运行突然失败。

此外，命令行复现还发现两个独立的迁移问题：

1. 用户 Tcl Store 目录不完整，缺失 `::tclapp::support::appinit 1.2`，触发
   `[Common 17-539] Failed to load tclapp initializer`。
2. 复制工程仍带有 Vivado 2018.3 生成缓存，Clocking Wizard 6.0 IP 处于旧修订版/锁定状态。

处理方法为：使用 Vivado 自带 `tclapp::reset_tclstore -force` 重建用户 Tcl Store；把
`clk_wiz_audio_44k1` 升级到 Vivado 2025.2 的 Clocking Wizard 6.0 Rev17；重新生成 IP target、
更新编译顺序，并通过 Vivado 的 `reset_run` 重置 `synth_1` 和 `impl_1`。没有删除 RTL 源码。

用户关闭不需要的软件后，实测提交内存余量从约 3.04 GB 上升到约 8.67 GB。这里的“提交内存”
是 Windows 对所有进程承诺的内存总量，受物理 RAM 与页面文件共同限制；它不是 FPGA 的 BRAM，
也不是磁盘剩余空间。

## 2025.2 签核结果

结果目录：`tools/vivado_2025_2/results/20260807_210642`

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | BRAM Tile | RAMB18E1 | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 361 | 1 | 384 | 4 | 2 | 4 | 17 | 2 |
| 布局布线后 | **292** | **1** | **376** | **4** | **2** | **4** | **17** | **2** |

注意：Vivado 2018.3 与 2025.2 的综合、逻辑优化和统计结果不能直接混用。292 LUT 是同一 RTL
在 2025.2 本次实际 routed DCP 中的结果，不表示源码又做了一轮算法/RTL 优化。

| 检查项 | 结果 |
|---|---:|
| WNS / TNS | +44.234 ns / 0 ns |
| WHS / THS | +0.112 ns / 0 ns |
| 时序失败端点 | 0 |
| DRC Error | 0 |
| 总片上功耗 | 0.271 W |
| 动态 / 静态功耗 | 0.199 W / 0.072 W |
| 功耗置信度 | Medium（无 SAIF 的 vectorless 估算） |

DRC 中保留 9 条 DPIP-1 和 2 条 DPOP-1 DSP 流水线建议。这些是性能/功耗建议，不是错误；
当前全部时序约束已经满足，不能为了消除建议而随意增加寄存器并改变已签核的周期行为。

生成文件：

- `tools/vivado_2025_2/results/20260807_210642/board_demo_competition_dac8_top_2025_2.bit`
- `tools/vivado_2025_2/results/20260807_210642/board_routed_2025_2.dcp`
- 同目录下保存综合/实现利用率、时序、DRC、功耗、布线状态和完整日志。

bitstream SHA-256：
`040D70619A0693FA9E450350801E79BE934B6E2AA8B2C4A20159249B1A1ECBEC`

## 前一 292-LUT 基线实板验证

2026-08-07 用户使用上述 2025.2 bitstream 完成板级验证：44.1 kHz/48 kHz 两个输入采样率族、
全部公开插值档位的 DA_CLK 实测均正确，AD9708 DAC 输出波形均正常。该结果与 RTL 回归及
布线后六档功能网表计数一致，本版本状态由 `tool-verified` 更新为 `board-verified`。

## 功能验证结果

直接指定 `XC7A35T_interp_opt_2025.2` 工程源码，使用 Vivado 2025.2 xvlog/xelab/xsim：

- 全国赛 RTL Smoke 回归：17/17 PASS；
- 全链路冲激 + 1 个随机种子在 4x/8x/128x 各节点均为 0 LSB；
- Stage1 行为模型与 RAMB18E1 原语各 1400 个输出均为 0 LSB；
- 8 类内部状态复位恢复全部通过；
- 10 次无复位动态切档无 runt pulse、无 X；
- ROM、DAC offset-binary、系数/历史 BRAM、双时钟族和模式 CDC 均通过。

RTL 回归目录：
`matlab_fir/national_finals/_work/rtl_regression/20260807_213020`

2025.2 routed DCP 六档布线后功能网表结果：

| 档位 | 1 ms 内 DA_CLK 边沿 | DAC 数据变化次数 |
|---|---:|---:|
| 44.1 kHz / 4x | 177 | 175 |
| 44.1 kHz / 8x | 353 | 342 |
| 44.1 kHz / 128x | 5645 | 3710 |
| 48 kHz / 4x | 192 | 192 |
| 48 kHz / 8x | 384 | 372 |
| 48 kHz / 128x | 6144 | 3810 |

177/353/5645 是 1 ms 有限观察窗内的整数边沿计数，分别对应理论 176.4/352.8/5644.8 kHz，
并不表示 44.1 kHz 族的 4x 频率被改成了 177 kHz。

布线后回归目录：
`matlab_fir/national_finals/_work/postroute_six_mode_dac/20260807_211646`

## 276-LUT 正式实板版及板测后审计

在 292-LUT 板测基线上继续采用 `AreaOptimized_high/full/on`、`SHREG_MIN_SIZE=5`，并把
Stage2/3 无效历史抽头由 Fabric 宽零值选择器改为 DSP PREG CE 门控后，正式实现为：

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | BRAM Tile | RAMB18E1 | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 341 | 0 | 387 | 4 | 2 | 4 | 17 | 2 |
| 布局布线 | **276** | **0** | **379** | **4** | **2** | **4** | **17** | **2** |

WNS/WHS 为 `+44.885/+0.112 ns`，TNS/THS 为 0，DRC Error 为 0，总功耗为 0.271 W。
Release RTL 回归 17/17 和 routed-DCP 六档仿真均通过。2026-08-08 用户完成物理板复测，确认
两个输入采样率族下各公开档位采样率正确、DAC 输出波形正常，故标签
`nf-vivado2025.2-276lut-379ff-4dsp-2bram-17io-2mmcm-board-pass` 为当前正式发布点。

板测后从同一 341-LUT 综合 DCP 扫描 7 组实现策略，最低仍为 276 LUT；历史有效位粘滞化
RTL 候选虽通过 17/17 回归，但综合恶化为 345 LUT / 388 FF，已经回退。因此没有新的
bitstream 替代该板测版本。完整审计见
`matlab_fir/national_finals/results/post276_lut_optimization_audit_execution_feedback.md`。

该结论只对应当时的微调和策略扫描。后续采用本文件顶部所述 Stage1 顺序抽头重大架构重构后，
已经得到 258-LUT 工具签核候选；在其物理板复测完成前，276-LUT 版本仍保持正式发布状态。

## 推荐的手动使用方法

### GUI

1. 确认没有其它 Vivado 实例仍在后台运行。
2. 打开 `XC7A35T_interp_opt_2025.2/XC7A35T_interp.xpr`。
3. 依次运行 `Run Synthesis`、`Run Implementation`、`Generate Bitstream`。
4. 如果可用提交内存不足 4 GB，先关闭浏览器、办公软件等大内存程序，再重试。
5. 比较资源时必须打开本次最新 `impl_1` 的 Utilization Report，不能拿旧 run 或综合报告比较。

### 一键低内存完整构建

在 PowerShell 中执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  ".\tools\vivado_2025_2\run_full_build_2025_2.ps1" -Jobs 1
```

脚本会先检查 Vivado GUI 是否关闭和提交内存余量，然后把所有 `.log/.jou/.rpt/.dcp/.bit`
集中放入带时间戳的 `tools/vivado_2025_2/results` 子目录，不污染工程主目录。
2026-08-10 已把该入口改为单 Vivado 进程的 in-memory 综合/实现流：仍从正式 `.xpr` 读取
源文件集、顶层和约束，但不再调用本机曾经卡在 `.vivado.begin.rst` 的命令行
`launch_runs`/VRS 调度器。生产入口已从空结果目录复跑并出现
`VIVADO_2025_2_FULL_BUILD_PASS`，精确复现 221 LUT、367 FF 和正式 bitstream。入口同时固定使用
Vivado 安装目录中的 Tcl Store；用户缓存损坏时会出现警告，但不会阻止构建。

若 Tcl Store 错误再次出现，请先关闭 Vivado，再执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  ".\tools\vivado_2025_2\run_tclstore_maintenance_clean.ps1" -Action Reset
```

然后执行同一脚本的 `-Action Query`，检查输出是否包含 `APPINIT_REQUIRE_PASS=1.2`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  ".\tools\vivado_2025_2\run_tclstore_maintenance_clean.ps1" -Action Query
```

该入口会先切换到系统临时目录，并使用 `-nojournal -nolog` 启动 Vivado，因此不会再在仓库
主目录生成 `.Xil`、`dfx_runtime.txt`、`vivado.jou/.log` 或 backup journal。不要在仓库根目录
直接调用 `vivado.bat -source reset_tclstore.tcl/query_tclstore.tcl`。
