# 全国赛下一阶段优化指导执行反馈

> 对照文档：[国赛双时钟插值滤波器下一阶段修改与优化指导](../../national_finals_next_stage_optimization_guide.md)
> 复核日期：2026-08-01
> 当前工作分支：`codex/national-finals-p4b-bram2`
> 当前文档提交前 HEAD：`3727b34`
> 当前硬件签核基线：`d25a0e2` / `national-finals-p4b-504LUT-493FF-4DSP-2BRAM-2MMCM`

> 后续更新：本文记录的是上一份指导截至 P4-B 的执行快照。P4-C 已继续完成死队列删除、Stage1 预加器、CIC 26/29-bit 与 4/3/2-DSP 三档；最新结果请见 [P4-B RTL 下一阶段优化指导执行反馈](p4b_rtl_next_optimization_guide_execution.md)。

## 1. 结论

指导文档的总体判断和执行顺序是合理的，尤其是“先修正确性和验证闭环，再做严格等效资源优化，最后开展性能/研究支线”。本轮没有继续以错误的 `436 LUT / 5 DSP` 版本作为发布基线，而是实际完成了以下主线演进：

```text
436 LUT / 5 DSP：发现 Stage 3 绝对增益错误，仅保留为诊断基线
  -> P1：修复真 Q15、恢复绝对增益和 38-bit 饱和路径
  -> P2：恢复 MATLAB/位真/RTL 核心回归
  -> P3：完成原子 CDC、同步复位和 AD9708 工具侧时序闭环
  -> P4-A：N3 Hold 严格等效，DSP 5 -> 4
  -> P4-B：Stage 1/2/3 历史 RAM 时分复用，BRAM Tile 3 -> 2
```

截至本反馈，P0～P4 的资源主线已经做到 MATLAB、RTL、XSim、综合、布局布线、时序、DRC/CDC 分析、功耗估计和 bitstream 生成。当前最低 BRAM 的工具侧候选为：

```text
504 LUT / 493 FF / 202 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM
WNS/TNS = +45.637/0 ns
WHS/THS = +0.119/0 ns
功耗 = 0.271 W（vectorless，Medium confidence）
RTL = 14/14 PASS
```

但若按指导中的完整发布门禁严格判定，目前还不能写成“全国赛最终全部完成”，原因是：

1. P2 的发布级 T00～T15 全激励和 `10 seed × 4096` 尚未全部执行，当前正式整链回归为冲激加 1 个固定随机 seed；
2. P3 的家族切换仍以固定倒计时为主，只在复位释放处检查 `LOCKED`，尚未改成完整的 `WAIT_TARGET_LOCK` 状态机；
3. P4-B 结果目录没有重新导出 P3 的全部 `check_timing`、DAC setup/hold 和 route-status 报告；
4. 当前版本尚未在实物板上完成六组合、100 次切换、示波器和频谱/音频仪器验收；
5. P5-A～P5-D 尚未进入正式主线实施。

因此最准确的状态是：**P0～P4 资源主线已完成软件/FPGA 工具侧闭环，P2/P3 的发布级增强项和所有物理板门禁仍待完成，P5 研究支线尚未执行。**

## 2. 状态定义

本文使用四种状态，避免把“写了代码”误写成“发布完成”：

| 状态 | 含义 |
|---|---|
| 完成 | 指导目标已经实现，并有对应 MATLAB/RTL/实现证据 |
| 工具侧完成 | 软件、仿真、Vivado 和 bitstream 已通过，但物理板门禁未执行 |
| 部分完成 | 核心问题已解决，但指导列出的全量测试、报告或工程化要求仍有缺项 |
| 未执行 / No-Go | 尚未开始，或实验已经证明不满足硬门槛并保留回退路线 |

## 3. 总体执行进度

| 指导阶段 | 当前状态 | 已完成的核心内容 | 仍未完成的内容 |
|---|---|---|---|
| P0 基线冻结/构建统一 | 部分完成 | 冻结 pre-fix 标签和 manifest；P1/P3/P4-A/P4-B 独立分支、提交和标签；建立固定 Tcl/PowerShell 构建入口和 GUI generic 核验 | 未采用指导建议的 `baseline/*` 命名；未形成独立 `filter_core`/`board_demo` 两套正式资源流水；manifest 仍有两处文本问题 |
| P1 Stage 3 Q14/Q15 | 完成 | 系数统一为真 Q15；修复所有 RTL/MATLAB 系数路径；恢复完整 38-bit MAC 视图和 signed 饱和；增加绝对增益门禁 | 尚未生成指导建议的统一系数 `.vh + manifest + SHA-256`；未形成专用的 Stage 3 累加范围统计报告 |
| P2 MATLAB/位真/RTL | 部分完成 | 修复 `.mem` 路径；独立 MATLAB 位真生成 golden；六工况频响；整链冲激/随机 0 LSB；当前 XSim 14/14 | T00～T15 未全部覆盖；当前整链发布脚本只使用 seed01；没有完整 `10 seed × 4096` 发布回归和统一 latency/config schema |
| P3 CDC/复位/DAC I/O | 工具侧部分完成 | request/ack 原子模式握手；同步复位；MMCM 锁定同步；静音；IOB 数据；ODDR 时钟；output delay；STA/CDC/DRC 报告 | 家族切换仍含固定倒计时；没有显式 bus-skew 约束；CDC-13/15 和 TIMING-18 仍以书面 waiver 保留；物理板门禁未执行 |
| P4-A N3 Hold | 工具侧完成 | `C³ -> up16 -> I³` 严格改写为 `C² -> Hold16 -> I²`；7680 输出 0 LSB；DSP 5 -> 4 | 六组合实物板复测未执行；3-DSP 极限候选未作为主线尝试 |
| P4-B 两项 BRAM 调度 | 工具侧完成 | Stage 1 单 RAM 串行双读；Stage 2/3 统一历史 RAM；BRAM Tile 3 -> 2；14/14 RTL | P4-B 未重新导出完整 P3 外设签核报告集；物理板复测未执行 |
| P5-A MMCM 功耗 | 未执行 | 仅保留双 MMCM 常开基线和 vectorless 功耗 | `PWRDWN`、SAIF、单 MMCM+DRP、模式 CE 功耗对比均未执行 |
| P5-B N4 Hold 性能版 | 未执行 | 仅有指导中的预筛选数据；历史 Phase 7 N4 文件不计入本轮签核 | 新补偿器、37-bit 位真、全国赛 RTL/实现/板测均未执行 |
| P5-C 联合整数系数/混合字长 | 未执行 | 早期工程做过传统字长搜索，但不是修正后全国赛基线上的联合 TPE 搜索 | TPE/Bayesian Pareto 搜索、候选综合/布局布线/SAIF 未执行 |
| P5-D 256×/2 DSP | 未执行；相关简化方案 No-Go | 额外测试了“当前时钟下三级 FIR 共用一颗 DSP”，证明 72 拍工作量无法满足 64 拍截止期 | 指导中的 256×计算时钟、上下文切换和两级积分器复用未设计 |

## 4. P0：基线冻结和构建配置

### 4.1 实际执行

pre-fix 诊断基线被冻结在：

| 项目 | 实际值 |
|---|---|
| Git commit | `34593d3` |
| 标签 | `national-finals-436LUT-471FF-5DSP-3BRAM-2MMCM` |
| 资源 | 436 LUT / 471 FF / 5 DSP / 3 BRAM Tile / 2 MMCM |
| manifest | [nf_p1_prefix_baseline_manifest.json](nf_p1_prefix_baseline_manifest.json) |
| 状态 | 仅用于诊断和回退定位，不具备发布资格 |

后续主线按照问题边界拆成独立回退点：

| 阶段 | 分支 | commit / tag |
|---|---|---|
| P1 | `codex/national-finals-p1-qformat-fix` | `d321f6e` / `national-finals-p1-446LUT-471FF-5DSP-Q15-gain-fixed` |
| P3 | `codex/national-finals-p3-engineering-closure` | `43c44be` / `national-finals-p3-462LUT-447FF-5DSP-3BRAM-2MMCM-CDC-ODDR` |
| P4-A | `codex/national-finals-p4a-n3-hold-4dsp` | `5dc78ce` / `national-finals-p4a-491LUT-444FF-4DSP-3BRAM-2MMCM-N3-Hold` |
| P4-B | `codex/national-finals-p4b-bram2` | `d25a0e2` / `national-finals-p4b-504LUT-493FF-4DSP-2BRAM-2MMCM` |

构建入口没有照搬指导建议的文件名，而是复用并强化现有流程：

- `vivado/build_national_finals_board.tcl`：固定器件、顶层、源文件、generic、综合策略和报告；
- `vivado/implement_national_finals_single_process.tcl`：低内存单进程实现、bitstream 和完整报告；
- `vivado/run_national_finals_vivado_build.ps1`：将日志和 `.Xil` 放进 `_work`，避免污染项目根目录；
- `vivado/verify_national_finals_gui_project.tcl`：检查 GUI XPR 的 generic 和实际 LUT/FF/DSP/BRAM/MMCM，解决“脚本结果与 GUI 结果不一致”的问题。

这属于对指导目标的等价落实，但还不是指导建议的“单一 JSON/Tcl 配置源”。

### 4.2 遇到的问题和解决办法

| 问题 | 原因 | 解决办法 | 结果 |
|---|---|---|---|
| Vivado GUI 曾显示 482 LUT / 8 DSP，与脚本声称值不一致 | XPR 中的 generic、已打开 run 和独立 Tcl 构建配置不是同一套 | 将正式 generic 写入 XPR，增加 `verify_national_finals_gui_project.tcl` 从普通工程重新实现并检查层级资源 | 当前 GUI 与独立 P4-B 签核均为 504 LUT / 493 FF / 4 DSP / 4 RAMB18E1 |
| 工具临时文件污染主目录 | Vivado/XSim 默认在当前目录产生 `.Xil`、`xsim.dir`、日志 | 所有批处理从 `_work/<tool>/<timestamp>` 运行，正式产物只复制到 `vivado_results` | 项目根目录不再产生新工具垃圾文件 |
| 同一资源点可能被旧报告误引用 | 仓库保留多代全 FIR、全 2×、FIR-CIC 和全国赛报告 | 每个正式结果目录保存 build manifest、报告、bitstream 和 SHA-256，README 只引用同一板级顶层的 post-route 数据 | 资源比较口径基本统一 |

### 4.3 未完全执行的内容

1. 没有创建指导原文建议的 `baseline/nf-dualclock-*` 分支名，而是保留现有 `codex/*` 分支和资源标签。回退能力已经具备，差异只在命名规范。
2. 还没有把配置进一步收敛为独立 `config/nf_release_config.tcl` 或 JSON schema；当前配置仍分布在 XPR、Tcl 和顶层 generic 中，但已有一致性检查。
3. 尚未建立独立 `filter_core` 与 `board_demo` 两套正式构建；当前正式数字均为完整板级顶层，层次报告只能辅助拆分核心资源。
4. `nf_p1_prefix_baseline_manifest.json` 中 `config_id` 的 `prefx` 和器件字符串 `xc7a35tffg484-2` 存在拼写问题；实际器件和所有 Vivado实现均为 `xc7a35tfgg484-2`。

## 5. P1：Stage 3 真 Q15 和绝对增益闭环

### 5.1 原问题

旧 Stage 3 两相系数和为 `16382`，数值实际为 Q14，但共享 MAC 固定按 Q15 右移。归一化频响会把 DC 增益重新拉到 0 dB，因此旧的通带纹波和阻带检查看不出错误；绝对幅度测试才暴露出 8×/128× 比 4×低约 6.02 dB。

| 模式 | pre-fix 绝对增益 |
|---|---:|
| 4× | -0.001599 dB |
| 8× | -6.023392 dB |
| 128× | -6.024933 dB |

### 5.2 实际修复

1. 将 Stage 3 统一为真 Q15 系数：`[404,-148,-3272,522,19250,32016,19250,522,-3272,-148,404]`；
2. 同步更新 MATLAB 位真模型、统一 RAMB18E1 的初始化/仿真数组、后备系数 ROM 和 primitive 测试；
3. 删除只对旧半幅系数成立的 35-bit 直接截取捷径；
4. 保留完整 38-bit MAC 视图并恢复 signed 20-bit 饱和判断；
5. 新增“旧版本必须失败、修复版本必须通过”的绝对增益负向/正向门禁。

修复后的绝对增益为：

| 模式 | 修复后绝对增益 | 与 4×差值 |
|---|---:|---:|
| 4× | -0.001599 dB | 0 |
| 8× | -0.002709 dB | -0.001110 dB |
| 128× | -0.003480 dB | -0.001881 dB |

最大模式间差为 `0.001881 dB`，满足指导的 `≤0.01 dB` 门槛。

### 5.3 代价和验证

| 指标 | pre-fix | P1 | 变化 |
|---|---:|---:|---:|
| LUT | 436 | 446 | +10 |
| FF | 471 | 471 | 0 |
| DSP | 5 | 5 | 0 |
| BRAM Tile | 3 | 3 | 0 |
| WNS | +45.662 ns | +45.104 ns | -0.558 ns，仍通过 |
| WHS | +0.116 ns | +0.121 ns | +0.005 ns |
| 功耗 | 0.271 W | 0.271 W | 报告精度下不变 |

新增 10 LUT 是恢复可达 38-bit signed 饱和检查的正确性成本，不能为了回到 436 LUT 再删除。

详细证据见 [P1 Stage 3 Q 格式修复签核](p1_stage3_qformat_fix_summary.md)。

### 5.4 未完全照做的建议

- 指导建议从单一整数数组自动生成 `.vh`、RAMB18 INIT 和 coefficient manifest。当前使用 `f_stage3_q15_coefficients.m` 作为 MATLAB 权威源，并由 primitive TB 检查 RTL BRAM，但尚未做到所有 RTL 表均由脚本自动生成。
- 已恢复安全的 38-bit 饱和路径，但没有单独输出 Stage 3 `min/max/max_abs/headroom/saturation_count` 的发布 manifest，也没有专用的运行时累加高位 `$fatal`；当前证据来自数学边界、完整位真和输出饱和逻辑。

## 6. P2：MATLAB—位真—RTL 验证闭环

### 6.1 遇到的问题

最初整链 XSim 报告 `mismatch=43776`，但根因不是 RTL 数值错误，而是仿真工作目录中缺少输入和 golden `.mem`。`$readmemh` 读不到文件后产生 X，随后大量比较失配。因此该次结果被重新标记为“测试无效”，没有用于证明 RTL 对错。

### 6.2 解决办法

- 用 `f_build_bittrue_case.m` 和 `f_03_generate_bittrue_vectors.m` 从独立整数位真模型生成输入和 `y4/y8/y128` golden；
- 将 daily 向量固定放在 `national_finals/vectors/daily`；
- 回归脚本为每个测试创建独立 `_work/rtl_regression/<timestamp>/<case>` 目录，并在编译前复制所需资产；资产缺失时 PowerShell 立即失败，不再让无效 X 进入结果；
- XSim 日志必须同时包含预期 PASS marker，且不能包含行首 `FAIL/FATAL/ERROR`；
- RTL impulse 输出重新送回 MATLAB 分析，不用 RTL 反向生成 golden。

### 6.3 当前 14 项 RTL 回归

P4-B 从空目录运行的正式结果为 `14/14 PASS`，目录：

```text
matlab_fir/national_finals/_work/rtl_regression/20260801_022831
```

| # | 测试 | 当前证据 |
|---:|---|---|
| 1 | 双采样率测试 ROM | 44.1/48 kHz 数据、地址回绕和 family reset |
| 2 | 统一系数 RAMB18E1 | 两端口及 96 个 Stage 1/2/3 地址 |
| 3 | Stage 1 单 BRAM 等价 | 1400 个输出，数据/valid 0 LSB |
| 4 | 三抽头补偿器 | 2009 个定向样本 |
| 5 | Stage 2/3 统一历史 | Stage 2/3 分别 336/671 个输出 0 LSB，含写队列 |
| 6 | 串行 comb 等价 | 连续、停顿、复位中断，共 3840 个输出 |
| 7 | N3 Hold 等价 | 连续 320、随机停顿 480、复位中断，共 7680 个输出 |
| 8 | 双 MMCM/BUFGMUX | 两家族、往返切换、无 runt high pulse |
| 9 | 模式 CDC | 12 个方向各 100 次，共 1200 次原子事务 |
| 10 | 紧凑键盘 | SW1～SW8 家族/模式功能 |
| 11 | 板级集成 | 上电复位、共享扫描和受保护切换 |
| 12 | 完整链位真 | 冲激 + seed01，Stage 1/2/3/y128 均 0 LSB |
| 13 | 完整链复位恢复 | 8 个内部状态中断场景，每场 4096 个 y128 输出 |
| 14 | 不停机模式切换 | 10 次切换，无 runt/X/锁死/停止输出 |

### 6.4 六工况算法指标

P1、P3、P4-A 和 P4-B 的 FIR/CIC传递函数相同，因此共享以下修复后指标：

| 输入家族 | 节点 | 通带最大绝对偏差 | 峰峰纹波 | 最差阻带 | 绝对增益 |
|---:|---:|---:|---:|---:|---:|
| 44.1 kHz | 4× | 0.004610111 dB | 0.005702880 dB | 78.668823410 dB | -0.001598865 dB |
| 44.1 kHz | 8× | 0.005394745 dB | 0.006173687 dB | 78.561809849 dB | -0.002709130 dB |
| 44.1 kHz | 128× | 0.006116383 dB | 0.008055724 dB | 72.331082151 dB | -0.003479771 dB |
| 48 kHz | 4× | 0.004610111 dB | 0.005702880 dB | 78.668823410 dB | -0.001598865 dB |
| 48 kHz | 8× | 0.005394745 dB | 0.005718829 dB | 78.561809849 dB | -0.002709130 dB |
| 48 kHz | 128× | 0.006116383 dB | 0.006115655 dB | 72.331082151 dB | -0.003479771 dB |

所有量化系数保持严格对称，RTL impulse 的对称误差为 0 LSB；六工况均满足 `≤0.010 dB` 通带峰峰纹波、`≥70 dB` 阻带和 `≤0.01 dB` 绝对增益门槛。

### 6.5 尚未执行的 P2 项目

1. 当前 `vectors/daily` 只有冲激和 `random_seed01`。TB 已预留 seed02～seed10 分支，但正式 runner 只要求“impulse + 1 seeds”，因此不能声称已完成 `10 seed × 4096` 发布回归。
2. T00～T15 中，冲激、随机、停顿、复位、模式/家族切换已覆盖；负冲激、正负 DC、阶跃、最大/最小码、满幅交替、997 Hz 正弦、19.9/20 kHz 和多音尚未全部形成统一的整链自动回归。
3. 尚未建立指导建议的统一 `nf_filter_config.json`、`nf_latency_manifest.json` 和 schema；当前固定延迟由 TB/脚本隐含管理。
4. 普通音频向量已证明无输出失配，但内部各节点的 `headroom_bits/overflow_count/wrap_count/saturation_count` 尚未全部自动汇总为发布报告。

因此 P2 应写成“核心位真闭环完成，发布级全激励矩阵部分完成”，而不是无条件的全量完成。

## 7. P3：CDC、复位和 AD9708 工程闭环

### 7.1 已执行修改

| 原问题 | 实际处理 | 验证 |
|---|---|---|
| 两位模式总线逐 bit 同步，可能出现撕裂 | 新增 request/ack toggle bundled-data 原子握手；事务期间 shadow 保持稳定，音频域稳定等待后一次锁存 | 1200 次全方向事件，一次请求/提交/应答，无中间编码 |
| 异步复位阻碍 DSP/BRAM 吸收并产生 DPIR/DPOR/REQP | FIR、CIC、bridge、键盘和模式状态改同步复位；异步置位/同步释放只保留在同步器边界 | 8 个内部状态中断恢复，无旧数据泄漏 |
| MMCM 未锁定时可能释放数据 | `LOCKED` 进入同步器，只有选中 family 锁定且切换窗口结束才释放音频复位 | 双家族往返和 100 次压力切换通过 |
| 模式/家族切换时输出可能出现旧数据 | 切换期间强制 DAC 输出中点码 `8'h80`，清空/预热后恢复 | 动态模式测试无 runt/X/锁死 |
| DAC 数据未锁定到 IOB、时钟为普通逻辑 | 8 位数据寄存器设置 `IOB=TRUE`，`dac_clk` 由 ODDR 转发 | 实现报告确认 OLOGIC/ODDR |
| 内部时序通过但无法证明 DAC setup/hold | 为两个互斥 forwarded clock 设置 `set_output_delay -max 2.5 ns/-min -2.0 ns`，生成逐家族 setup/hold 报告 | 44.1 kHz 最差 +84.287/+86.288 ns；48 kHz 最差 +76.116/+78.117 ns |

P3 post-route 为：

```text
462 LUT / 447 FF / 180 Slice / 5 DSP / 3 BRAM Tile / 2 MMCM / 17 IO
WNS/WHS = +46.140/+0.050 ns
TNS/THS = 0/0 ns
功耗 = 0.271 W（0.199 W dynamic / 0.072 W static）
RTL = 11/11 PASS
```

详细证据见 [P3 工程闭环签核](p3_engineering_closure_summary.md)。

### 7.2 没有完全执行的部分及原因

1. **家族切换状态机没有完全按指导重写。** 当前 `family_switch_cnt` 仍在固定倒计时位置切换 `family_active`，但复位释放会等待目标 `LOCKED`。由于两颗 MMCM 当前始终常开，该结构已通过仿真；一旦执行 P5-A 的 MMCM 掉电或 DRP，就必须先改成 `WAKE -> WAIT_LOCK -> SWITCH -> ACK` 状态机。
2. **CDC 报告没有字面全绿。** `CDC-13` 两条来自 `family_active` 到 `BUFGMUX_CTRL S0/S1` 的专用无毛刺时钟选择入口；`CDC-15` 四条来自已验证的 bundled-data shadow bus。两类路径均保留书面结构 waiver，没有用 false path 隐藏。
3. **Vivado 2018.3 Methodology 的 TIMING-18 仍保留 8 条。** XDC 实际已对 `dac_data[7:0]` 添加两个 forwarded clock 的 min/max output delay，逐时钟 timing report 也有正裕量；工具仍对同一端口挂两个互斥生成时钟报缺失，当前按工具版本局限书面说明。
4. **未显式建立 `set_bus_skew` 或独立 bus-skew 报告。** IOB 数据寄存器能显著降低位间偏差，但指导建议的 `≤1 ns` 仍需专门报告或板测确认。
5. **物理板级尚未执行。** 当前没有 P3/P4 的 100 次实板切换、DAC walking-one/walking-zero、占空比、最短脉宽和模拟幅度差记录。

## 8. P4-A：N3 Hold 严格等效，DSP 5 -> 4

### 8.1 实际实现

按照多速率恒等式将：

```text
C^3 -> upsample-by-16 -> I^3
```

严格改写为：

```text
C^2 -> hold each sample for 16 output enables -> I^2
```

实现中保留 33-bit 模运算宽度、最终右移 8 bit、舍入/饱和和输出 valid 周期。两个低速 comb 映射到 LUT/CARRY4，两个高速 integrator 各占一颗 DSP48E1。因此全机 DSP 从：

```text
Stage 1 1 + Stage 2/3 1 + CIC integrator 3 = 5
```

变为：

```text
Stage 1 1 + Stage 2/3 1 + CIC integrator 2 = 4
```

### 8.2 关键问题和解决办法

| 问题 | 处理 |
|---|---|
| Hold 不能被当作“一级 CIC 近似” | 以 `C -> up16 -> I == Hold16` 的严格恒等式实现，并保留新旧模块并行对拍 |
| 删除一级后内部位宽容易误减 | 仍按原 N3 总增长保留 33 bit，输出归一化仍右移 8 bit |
| 串行 comb 由 3 拍变 2 拍可能改变首 valid | 在测试中显式对齐固定延迟，不允许自动搜索任意对齐量 |
| LUT comb/计数器可能又被 Vivado 推进 DSP | 对低速差分和计数器施加 `use_dsp="no"`，并检查最终 DSP 原语层级 |

### 8.3 结果

| 指标 | P3 | P4-A | 变化 |
|---|---:|---:|---:|
| LUT | 462 | 491 | +29 |
| FF | 447 | 444 | -3 |
| Slice | 180 | 197 | +17 |
| DSP | 5 | 4 | -1 |
| BRAM Tile | 3 | 3 | 0 |
| WNS/WHS | +46.140/+0.050 ns | +45.738/+0.052 ns | 全部通过 |
| 功耗 | 0.271 W | 0.271 W | 报告精度下不变 |

N3 Hold 与旧 N3 在连续、随机停顿和中途复位场景共比较 7680 个输出，误差 0 LSB；完整回归 `12/12 PASS`。该版本是低 LUT/FF 的 4-DSP Pareto 点，而不是所有资源同时下降。

详细证据见 [P4-A N3 Hold 签核](p4a_n3_hold_4dsp_summary.md)。

## 9. P4-B：两项 BRAM 调度，3 -> 2 Tile

### 9.1 Stage 1 单 RAM 串行双样本读取

原 Stage 1 用两个 RAMB18E1 同拍读出对称样本。新核采用一个 64×24-bit SDP RAMB18E1：

1. 当前输入旁路为第 0 对左样本，同时写入环形历史；
2. 单读端口按 `R0,L1,R1,...,L25,R25` 发出 51 次读请求；
3. 左样本暂存，右样本返回时组成对称和并送入原 Stage 1 DSP；
4. 26 次 MAC 约 53 拍完成，早于下一个 64 拍截止期；
5. `$fatal` 检查 deadline miss 和 result-not-ready。

这解决了“24-bit 双读导致两颗 RAMB18E1”的问题，同时避免依赖 BRAM 同地址读写模式。

### 9.2 Stage 2/3 统一历史 RAM

Stage 2 和 Stage 3 已共享一颗 MAC，因此读端口可天然复用。两级历史合并到一个 32×22-bit SDP RAMB18E1，用高地址位选择 bank。真正的风险是两级 CE 同拍到达时会产生两个写请求；实现没有用 `if/else` 丢弃其中一个，而是让 Stage 2 当拍优先，Stage 3 进入一项写队列，并增加 queue overflow `$fatal`。

### 9.3 结果和代价

| 指标 | P4-A | P4-B | 变化 |
|---|---:|---:|---:|
| post-route LUT | 491 | 504 | +13 |
| post-route FF | 444 | 493 | +49 |
| Slice | 197 | 202 | +5 |
| DSP | 4 | 4 | 0 |
| RAMB18E1 / BRAM Tile | 6 / 3 | 4 / 2 | -2 / -1 |
| MMCM | 2 | 2 | 0 |
| WNS/WHS | +45.738/+0.052 ns | +45.637/+0.119 ns | 全部通过 |
| TNS/THS | 0/0 ns | 0/0 ns | 0 |
| 功耗 | 0.271 W | 0.271 W | 报告精度下不变 |

P4-B 用 `+13 LUT / +49 FF / +5 Slice` 换掉一个 BRAM Tile，因此 P4-A 和 P4-B 必须同时保留：

- P4-A：较低 LUT/FF 的 4-DSP 版本；
- P4-B：较低 BRAM 的 4-DSP 版本。

P4-B 的 14/14 XSim、资源、时序、DRC/CDC、功耗和 bitstream 已生成。bitstream SHA-256：

```text
DA0665E43A8DA5230AB93FC786AB0EED47BD83FE393C9B1416BA3360B8DE5E85
```

详细证据见 [P4-B 单 BRAM 签核](p4b_single_bram_4dsp_summary.md)。

### 9.4 本次复核发现的 P4-B 报告问题

1. `board_dual_rate_p4b2_bram2_v1/build_manifest.txt` 仍写着“Stage3: proven 35-bit MAC bound removes unreachable saturation logic”，这是 P1 以前的旧描述；当前 RTL 实际保留真 Q15 的完整 38-bit 视图和 explicit signed saturation。该行不能作为当前算法证据，后续应修正 manifest 生成文本并重建。
2. P4-B 结果目录包含 utilization、timing summary、power、DRC、CDC 和 bitstream，但没有像 P3 目录那样单独保存 `check_timing_routed.rpt`、`dac_output_setup_routed.rpt`、`dac_output_hold_routed.rpt` 和 `route_status_routed.rpt`。P4-B 的 DAC 数字引用了未改变 I/O 结构的 P3 结果；最终发布前应在 P4-B 自身 checkpoint 上重新导出完整报告集。

## 10. P5：未执行项目及原因

### 10.1 P5-A 双 MMCM 功耗

**状态：未执行。** 当前 `dual_family_audio_clock.v` 中两颗 MMCM 的 `PWRDWN` 均接 `1'b0`，功耗仍为 vectorless `0.271 W`，其中 P3 报告的 MMCM 合计约 `0.197 W`。

未执行原因：

- 当前家族切换仍依赖两颗 MMCM 常开；直接掉电会破坏现有固定倒计时假设；
- 必须先完成基于 `LOCKED` 的唤醒/超时/切换/关闭旧 MMCM 状态机；
- 当前没有 SAIF，无法满足“动态功耗下降 ≥5% 才宣称成功”的指导门槛；
- 低功耗改动风险集中在时钟和板级切换，应该在 P4 资源版实板通过后从标签单独开分支。

因此没有把 `0.197 W / 2` 当作省电结果，也没有宣称单 MMCM 已完成。

### 10.2 P5-B N4 Hold 性能版

**状态：未执行。** 指导中的 `C³ -> Hold16 -> I³`、`[-11,86,-11]/64`、37-bit 内部位宽、右移 12 bit 和 `≥77 dB` Go 门槛尚未转成当前全国赛 MATLAB/RTL。

仓库中存在早期 Phase 7 的 N4/CIC 文件，但它们早于本轮真 Q15、P3 CDC 和 P4-B 存储结构，不能当成指导已经执行，更不能把旧 N4 golden 直接复用于新的性能版。

未执行原因：P4-B 资源版尚待实板闭环，N4 会改变传递函数和 golden，必须独立建模、定点、RTL、实现和板测，不能与当前正确性主线混改。

### 10.3 P5-C 联合整数系数与混合字长/TPE

**状态：未执行。** 早期 Phase 5/6 做过手工和网格化字长优化，但没有在修正后的双家族全国赛基线上执行“整数系数重新搜索 + 混合字长 + TPE/Bayesian + Vivado Pareto”的完整流程。

未执行原因：当前 128×最差阻带只有约 `72.331 dB`，离 `70 dB` 硬门槛只有约 2.33 dB；在 P1 修复后继续机械减位风险很高。指导也明确要求资源收益不足 5% 时停止，因此该项优先级低于 P4 实板和 P5-A 时钟功耗。

### 10.4 P5-D 256×计算时钟/2 DSP

**状态：指导方案未执行；相关简化实验 No-Go。** 独立分支 `codex/national-finals-shared-fir-mac-v1`、提交 `354b890` 曾尝试在现有调度约束下让 Stage 1/2/3 共用一颗 FIR DSP。Xvlog 和展开通过，但全链 XSim 正确报出 `Shared FIR Stage1 result not ready`。

64 拍截止期内的最低工作量为：

| 工作 | 时钟数 |
|---|---:|
| Stage 1：26 MAC + 舍入 | 27 |
| Stage 2：两相 MAC + 两次舍入 | 19 |
| Stage 3：四相 MAC + 四次舍入 | 26 |
| 合计 | 72 |

`72 > 64` 是硬截止期冲突，增加 FIFO 或改变优先级无法解决，因此该原型保留为 [No-Go 记录](shared_fir_mac_v1_nogo.md)，没有合入板级主线。

这项失败反而验证了指导 P5-D 的判断：如果还要追求 2 DSP，不能只把当前三个 FIR 核简单接到同一乘法器，必须完整引入 256×计算时钟、上下文寄存器、两级积分器时分调度和 deadline assertion。该改造风险高，不适合在 P4 尚未实板签核时替换主线。

## 11. 统一结果汇总

所有数字均为同一全国赛板级顶层的 post-route 结果，不混用核心 OOC 或早期全 2×报告。

| 版本 | LUT | FF | Slice | DSP | BRAM Tile | MMCM | WNS/WHS | 功耗 | RTL | 发布状态 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| pre-fix 诊断基线 | 436 | 471 | 181 | 5 | 3 | 2 | +45.662/+0.116 ns | 0.271 W | 旧模型 10/10 | 有 -6.02 dB 缺陷，不可发布 |
| P1 真 Q15 | 446 | 471 | 193 | 5 | 3 | 2 | +45.104/+0.121 ns | 0.271 W | 10/10 | 算法正确基线，待实板 |
| P3 工程闭环 | 462 | 447 | 180 | 5 | 3 | 2 | +46.140/+0.050 ns | 0.271 W | 11/11 | 推荐稳定回退，待实板 |
| P4-A N3 Hold | 491 | 444 | 197 | 4 | 3 | 2 | +45.738/+0.052 ns | 0.271 W | 12/12 | 低 LUT/FF 的 4-DSP Pareto，待实板 |
| P4-B BRAM2 | 504 | 493 | 202 | 4 | 2 | 2 | +45.637/+0.119 ns | 0.271 W | 14/14 | 最低 BRAM 的 4-DSP Pareto，待实板 |

功耗均为无 SAIF 的 vectorless 估计，不能据此宣称 P4 比 P3 更省电。P4 的价值是 DSP/BRAM 结构资源下降，而不是功耗下降。

## 12. 仍需解决的问题和建议顺序

### 第一优先级：形成真正的当前版本板级闭环

1. 分别下载 P4-A 和 P4-B bitstream；
2. 测试 44.1/48 kHz × 4×/8×/128× 六组合；
3. 记录 `dac_clk` 频率、占空比、最短高/低脉宽；
4. 执行固定码、walking-one、walking-zero 和 ramp；
5. 每个模式/家族方向执行至少 100 次切换；
6. 记录 Vpp、DC 偏置、模式间模拟幅度差、最大瞬态和恢复时间；
7. 保存示波器/频谱仪截图及原始 CSV/WFM。

### 第二优先级：补齐 P2/P3 发布报告

1. 生成 seed02～seed10 的 4096 点输入和三节点 golden，并运行完整发布回归；
2. 补齐负冲激、DC、阶跃、满幅边界、交替码、997 Hz、20 kHz 和多音；
3. 修正 P4-B manifest 的 Stage 3 35-bit 旧描述；
4. 在 P4-B routed checkpoint 上重新导出 `check_timing`、DAC setup/hold、route status 和 bus-skew；
5. 将最终配置、延迟和向量 SHA-256 收敛到 manifest。

### 第三优先级：再进入 P5 独立分支

1. 先把家族切换改成 `LOCKED` 驱动状态机；
2. 再做未选 MMCM `PWRDWN` 和 SAIF 功耗 A/B；
3. P4 资源版实板稳定后，再独立尝试 N4 Hold 性能版；
4. TPE 和 256×/2-DSP 只作为研究分支，不覆盖 P3/P4 回退点。

## 13. 最终评价

这份指导最大的实际价值不是让 LUT 再减少几十个，而是发现了旧低资源版本被归一化频响掩盖的 Stage 3 标度错误，并迫使工程按“正确性—验证—CDC/I/O—严格等效资源优化”的顺序重新闭环。其核心 P4 预测已经被实现结果证明可行：

- N3 Hold 确实把 DSP 从 5 降到 4，并保持输出 0 LSB；
- 两项 BRAM 调度确实把 BRAM Tile 从 3 降到 2；
- 代价为 LUT/FF 增加，形成 P4-A/P4-B 两个而不是一个所谓“全资源最优”版本。

没有执行的 P5 项目并不是被遗忘，而是因为它们会改变时钟、传递函数或全局调度，必须建立在 P4 实物板闭环之后。当前最重要的工作不应继续压资源，而应补齐 P2/P3 报告和实物板门禁，随后再从已验证标签开展 MMCM 低功耗或 N4 性能支线。
