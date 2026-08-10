# Vivado 2025.2 239→234 LUT 挑战执行反馈

## 1. 结论

本轮从用户已经完成物理板验证的 239-LUT 版本继续优化，保持滤波器系数、各级定点字长、
舍入/饱和、4x/8x/128x 数据路径、44.1/48 kHz 双时钟族、4 DSP48E1 和 2 BRAM Tile 不变。
最终正式 Vivado 2025.2 布局布线结果为：

**234 LUT / 0 LUTRAM / 369 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**。

相对 239-LUT 板测基线减少 **5 LUT（2.09%）和 8 FF（2.12%）**，DSP、BRAM、IO、MMCM
与 vectorless 功耗不变。当前版本已经完成完整工具闭环；用户随后完成物理板验证，确认两个
输入采样率族下各档输出采样率均正确、DAC 输出波形均正常，因此状态正式升级为
**board-verified**。239-LUT board-pass 标签继续作为前一安全回退点。

## 2. Git 与回退路线

- 239-LUT 板测标签：`nf-vivado2025.2-239lut-377ff-4dsp-2bram-board-pass`；
- 234-LUT 工具签核标签：`nf-vivado2025.2-234lut-369ff-4dsp-2bram-toolverified`；
- 234-LUT 正式板测标签：`nf-vivado2025.2-234lut-369ff-4dsp-2bram-board-pass`；
- 本轮分支：`national-finals-v2025.2-230to234-lut-challenge`；
- 分支、提交和标签均不使用 `codex` 字样；
- 临时综合、候选网表和仿真输出全部位于 `matlab_fir/national_finals/_work`；
- 正式 234-LUT bitstream、DCP 与报告归档在
  `XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260810_160858`。
- 用户实际下载并通过板测的 bitstream 与对应 routed DCP 归档在
  `XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260810_170616_board_pass`；bitstream
  SHA-256 为 `F9DB8E33C3959C448FDE316A51BA9A13ABC83D5AE1F69655CD5D0B698A871E85`，DCP
  SHA-256 为 `47CDCA8E43C2DA817D028828564862EC56C64F0E791C6F845DE05A3E03DA3162`。

若后续板级环境或工程状态异常，可先回到上述 239-LUT board-pass 标签进行 A/B 排查。

## 3. 最终采用的三项优化

### 3.1 Stage1 发射/调度索引合并

Stage1 顺序 MAC 原来保留用途高度重合的 `schedule_index` 与 `issue_index`。本轮用一个发射索引
同时表达当前 BRAM 请求位置和下一次调度位置，保留 BRAM 一拍读延迟、中心抽头捕获、52 拍
累加及输出 valid 相位。该修改把 239-LUT 基线降到约 236 LUT，未改变 RAMB18E1 或 DSP 数量。

### 3.2 Stage2/3 共享权威 phase 状态

两个 `bridge_valid_quantized_to_interp2_ce` 原来各自维护一个 `phase_mirror`，而 Stage2/3 核内部
已经存在相同相位状态。正式版本增加可选的外部 phase 输入，在全国赛活动路径中直接复用
Stage2/3 核的权威 `phase_current`，旧顶层仍默认使用内部 mirror，保持兼容。这样删除两套重复
状态及其更新逻辑，最终 Stage2/3 共享 phase 候选为 **236 LUT / 369 FF**。

### 3.3 负边沿原子切档并删除冗余 mismatch 静音项

板级模式切换时，CDC 控制器先拉高 `force_mute`。正式版本在 `force_mute` 已经有效期间，于
DAC 分频器负边沿一次性提交 `mode_state`；`audio_mode` 在正边沿更新，因此静音撤销前两者已经
一致。由此可证明全国赛活动路径上的 `mode_state != audio_mode` 不可能在非静音周期泄漏到 DAC，
可从 DAC 静音表达式中删除这项重复比较，保留 `force_mute` 作为唯一安全门控。旧数据路径仍保留
原比较逻辑。该优化没有缩短 CDC 静音保护，没有产生 runt pulse，最终再减少 2 LUT，得到
**234 LUT / 369 FF**。

## 4. 候选筛选与 No-Go 结果

所有候选均先做定向 RTL/Smoke；只有资源优于 239 的候选才进入实现。以下资源为同一
Vivado 2025.2、同一约束与同一面积策略下的 routed 数据：

| 候选 | LUT | FF | DSP | RAMB18 | 结论 |
|---|---:|---:|---:|---:|---|
| 239-LUT 板测基线 | 239 | 377 | 4 | 4 | 安全回退 |
| Stage1 单发射索引 | 236 | 371 | 4 | 4 | 保留为后续共同基础 |
| Stage2/3 单补偿快照 | 237 | 370 | 4 | 4 | 改善较小，未选 |
| Stage1 idle sentinel 替代 active 位 | 239 | 370 | 4 | 4 | LUT 不降，No-Go |
| CDC `ack_toggle` 复用为 seen 状态 | 237 | 371 | 4 | 4 | 不如最终版，回退 |
| ODDR 直接使用当前分频位 | 237 | 371 | 4 | 4 | 不如最终版，回退 |
| 仅负边沿立即提交模式 | 237 | 371 | 4 | 4 | 单独收益不足，回退 |
| Stage2/3 共享 phase | 236 | 369 | 4 | 4 | 保留 |
| **共享 phase + 原子模式提交** | **234** | **369** | **4** | **4** | **最终正式候选** |

策略扫描没有替代 RTL 优化：`Default` 与 `Explore` 均复现 234 LUT；`RuntimeOptimized` 和
`Quick` 为 260 LUT；文档中可见的 `AggressiveExplore` 对 XC7A35T/本实现步骤不受支持，Vivado
直接拒绝，因此没有把无效策略写成成功结果。

## 5. 正式实现、时序、DRC 与功耗

正式发布使用 `AreaOptimized_high + flatten_hierarchy=full + resource_sharing=on +
shreg_min_size=5`，实现使用 `opt_design ExploreArea + place_design Explore + route_design`。

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | RAMB18E1 | BRAM Tile | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 310 | 0 | 377 | 4 | 4 | 2 | 2 |
| **布局布线后** | **234** | **0** | **369** | **4** | **4** | **2** | **2** |

| 检查项 | 结果 |
|---|---:|
| WNS / TNS | +44.925 ns / 0 ns |
| WHS / THS | +0.060 ns / 0 ns |
| 失败端点 | 0 |
| 路由失败网络 | 0 |
| DRC Error | 0 |
| CDC 模式总线 bus-skew | 要求 50.000 ns，实际 0.533 ns，余量 +49.467 ns（MET） |
| 总/动态/静态功耗 | 0.271 / 0.199 / 0.072 W |
| 功耗置信度 | Medium（无 SAIF 的 vectorless 估算） |

正式 bitstream SHA-256：
`3076AB46767D4BA6DB058DA73662E074053A4E5E694FF0E6417DE1D7ABDF7025`。

正式 routed DCP SHA-256：
`C24148332AC9A4C9A7456B052812183132F0830A823F77CDF1E83584053830B2`。

## 6. RTL 与路由后验证

- 最终候选 Smoke 回归：**17/17 PASS**；
- 最终候选 Release 回归：**17/17 PASS**；
- Release 包含 CIC 定向等价、连续/停顿/复位、随机 seed、正负满量程、强负 dBFS、全链
  4x/8x/128x 三节点逐样本比对、BRAM 原语等价、CDC、ROM、DAC、按键和动态切档；
- 动态切档连续完成 10 次，不复位，DAC 时钟无毛刺、无 X，边沿数保持 32/128/256/4096；
- 正式 routed DCP 六模式门级功能回归：

| 输入族/档位 | 1 ms 内 DAC 时钟边沿 | DAC 数据变化次数 | 结果 |
|---|---:|---:|---|
| 44.1 kHz / 4x | 177 | 175 | PASS |
| 44.1 kHz / 8x | 353 | 342 | PASS |
| 44.1 kHz / 128x | 5645 | 3710 | PASS |
| 48 kHz / 4x | 192 | 192 | PASS |
| 48 kHz / 8x | 384 | 372 | PASS |
| 48 kHz / 128x | 6144 | 3810 | PASS |

最终日志包含 `BOARD POSTROUTE SIX-MODE DAC PASS`。177/353/5645 是 1 ms 测量窗口的整数
边沿计数，对应理论 176.4/352.8/5644.8 kHz，并不是把 176.4 kHz 改成了 177 kHz。

## 7. 插值滤波器核心 OOC 独立资源

使用 `interp128_all2x_v7_folded_fir_cic_top_ce` 作为独立顶层、6.144 MHz 最坏公开时钟，
从空结果目录重新完成综合、布局、布线、内部时序和 OOC DRC：

**194 LUT / 0 LUTRAM / 282 FF / 4 DSP48E1 / 3 RAMB18E1（1.5 BRAM Tile）/
0 MMCM，内部 WNS/WHS=+151.280/+0.089 ns，DRC Error=0。**

整板 234 LUT 与核心 OOC 194 LUT 具有不同综合边界，不能用 `234-194` 宣称外围精确占用
40 LUT。论文和答辩应分别报告“完整系统实现资源”和“核心独立实现资源”。现场复现命令见
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/core_ooc/README.md`。

## 8. 频响继承与板测边界

本轮没有修改滤波器系数、字长、舍入或饱和，频响严格继承已签核路径：4x/8x/128x 最差通带
最大绝对偏差为 `0.003022/0.003521/0.007730 dB`，峰峰纹波为
`0.005709/0.006192/0.005848 dB`，阻带衰减为 `78.568/78.609/72.371 dB`，严格线性相位。

工具验证能够排除 RTL、定点、时序、DRC、路由和门级六档中的已覆盖问题，但不能替代 AD9708、
探头、供电、板级连线和真实模拟波形检查。2026-08-10 用户已下载本轮 bitstream 并完成物理板
验证，确认 44.1/48 kHz 两个输入采样率族下所有档位的实际输出采样率均正确，DAC 输出波形均
正常。因此 234-LUT 版本已满足 `board-pass` 条件。

## 9. 执行中遇到的问题与处理

1. 原 `run_full_build_2025_2.ps1` 通过 `launch_runs` 启动 VRS，命令行运行只生成
   `.vivado.begin.rst` 后不再进入综合。确认 VRS CPU 与日志均无进展后停止该次运行，把生产
   Tcl 入口改为单 Vivado 进程的 in-memory 综合/实现；正式入口随后从空目录完整 PASS。
2. Windows 提交内存余量为 2.8～3.3 GB，低于脚本保守的 4 GB 门槛。用户关闭其它软件并
   明确授权后，以 `Jobs=1 -SkipMemoryGate` 运行；Vivado 峰值约 2.33 GB，完整构建成功。
   日常仍建议保持至少 4 GB 提交余量，不把本次成功理解为低内存永远安全。
3. 第一份临时单进程 DCP 与生产入口 DCP 的资源/时序一致，但文件哈希不同。因此没有复用旧
   六模式结论，而是对最终正式归档 DCP 重新导出门级网表并再次运行六模式回归。
4. Vivado 临时日志、`.Xil`、候选 DCP 和仿真工作目录均放在时间戳结果目录或 `_work`，没有
   在仓库主目录新增 `vivado.log/.jou`、`xsim.dir`、`-p` 等散落文件；重复正式归档也已清除。
5. 用户在 GUI 中生成 bitstream 时曾遇到 `[Designutils 20-1700] bad allocation`。实现、路由、
   时序和 DRC 均已通过，失败仅发生在 Bitgen 载入数据阶段。复用当前 routed DCP、仅打开该
   checkpoint 并把 `general.maxThreads` 设为 1 后，Bitgen 以约 1.88 GB 峰值内存成功完成；
   该恢复过程不修改 RTL 或布局布线。用户随后使用生成的 bitstream 完成上述板级验证。
