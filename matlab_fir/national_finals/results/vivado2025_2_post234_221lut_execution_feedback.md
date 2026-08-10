# Vivado 2025.2 234→221 LUT routed 网表不变量优化执行反馈

## 1. 结论与版本状态

本轮从用户已经完成物理板验证的 234-LUT 版本继续优化，保持滤波器系数、各级定点字长、
舍入/饱和、4x/8x/128x 数据路径、44.1/48 kHz 双时钟族、4 DSP48E1、2 BRAM Tile 和
2 MMCM 不变。正式 Vivado 2025.2 布局布线结果为：

**221 LUT / 0 LUTRAM / 367 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**。

相对 234-LUT 板测基线减少 **13 LUT（5.56%）和 2 FF（0.54%）**，DSP、BRAM、IO、MMCM
和 vectorless 功耗不变。该版本已经通过 RTL、实现、bitstream 与 routed-DCP 工具闭环，当前
状态已由 **tool-verified** 升级为 **board-verified**：2026-08-10 用户完成物理板验证，确认
44.1/48 kHz 两个采样率族下各倍率档位输出采样率均正确，DAC 波形均正常。正式安全回退为
`nf-vivado2025.2-234lut-369ff-4dsp-2bram-board-pass`。

## 2. Git 与回退路线

- 234-LUT 板测标签：`nf-vivado2025.2-234lut-369ff-4dsp-2bram-board-pass`；
- 221-LUT 工具签核标签：`nf-vivado2025.2-221lut-367ff-4dsp-2bram-toolverified`；
- 221-LUT 正式板测标签：`nf-vivado2025.2-221lut-367ff-4dsp-2bram-board-pass`；
- 本轮分支：`national-finals-v2025.2-post234-lut-optimization`；
- 分支、提交和标签均不使用 `codex` 字样；
- 候选综合、网表审计和仿真临时文件全部位于被忽略的
  `matlab_fir/national_finals/_work` 或正式工具目录的嵌套 `results` 中，没有把 `.Xil`、
  `vivado.log/.jou`、`xsim.dir` 等生成到仓库主目录；
- 正式 221-LUT bitstream、DCP 与报告位于
  `XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260810_181833`。

## 3. routed 网表审计结论

234-LUT routed DCP 的逻辑原语按层级归属审计后，主要热点为 Stage2/3、Stage1、CIC16、
DAC/audio 包装、时钟/复位、按键和 CDC。审计没有只看 RTL 行数，而是继续追踪 LUT 输入网，
发现 Stage1 RAM 输入的 24 个数据位均被同一 `x_in_valid` 门控。这组 24-bit 数据/零选择器是
本轮主要可删热点。审计清单保存在被忽略的工作目录中：

`matlab_fir/national_finals/_work/post234_audit/lut_cells_234.tsv`。

234 LUT 在当时已试过的索引、phase、原子切档和策略空间中确实是局部最优；本轮通过审计物理
网表发现了 RTL 表面不明显的复位零值不变量，才跳出了原局部最优。221 LUT 是当前结构和固定
4-DSP/2-BRAM 约束下更强的局部最优，不代表所有可能微架构的数学全局最优。

## 4. 最终采用的三项优化

### 4.1 CDC acknowledgement 兼任本地 seen token

`nf_mode_cdc_handshake` 原来同时保存 `req_seen` 与 `ack_toggle`。二者使用相同复位值，并在 request
完成捕获的同一时钟边沿同时更新为 `req_sync`；`ack_toggle` 在音频域本来就是本地寄存器。因此
用 `ack_toggle` 直接判断 `req_sync != ack_toggle`，删除重复 `req_seen`，不会减少两级异步同步器、
settle 周期或静音保护。

### 4.2 Stage2/3 删除重复补偿模式 job 快照

Stage3 任务启动时原来把 `stage3_pending_compensated` 再复制到
`job_stage3_compensated`。调度审计确认单次 Stage3 MAC 任务在下一次 Stage3 CE 到达前完成，任务
期间 pending 模式保持稳定；系数 BRAM 可以直接使用该权威 pending 状态。因此删除第二份快照
寄存器和对应选择逻辑，不改变系数地址、MAC 次数或输出 valid 相位。

### 4.3 全国赛同步复位零值不变量删除 24-bit 输入/零门控

全国赛路径的测试音 ROM 输出、Stage1/2/3 历史存储和下游状态全部同步复位为零。复位释放后的
第一个 CE 中，ROM 仍向数据路径提供零样本；所以全国赛活动路径把 `x_in_valid` 从“复位后延迟
一拍拉高”改为常量 1，第一拍被接收的仍是同一个零值，之后 valid 本来就永久为 1。这样综合器
可删除 Stage1 RAM 前逐位生成的 24-bit 输入/零选择器。区域赛/旧路径继续使用
`x_in_valid_legacy`，兼容行为不变。

该项不是假设未初始化 RAM 为零：RTL Release、RAMB18 原语仿真和 routed 仿真均包含复位恢复，
正式路径的 ROM、寄存器与历史 RAM 均有明确零值来源。

## 5. 候选矩阵与 No-Go

所有候选先跑定向 RTL/Smoke；只有资源优于 234 的候选才进入更完整的实现或 Release。下表为
同一 Vivado 2025.2、同一器件、约束与面积策略下的 post-route 结果：

| 候选 | LUT | FF | DSP | RAMB18 | WNS/WHS | 结论 |
|---|---:|---:|---:|---:|---:|---|
| 234-LUT 板测基线 | 234 | 369 | 4 | 4 | +44.925/+0.060 ns | 安全回退 |
| CDC ack 兼任 seen | 233 | 369 | 4 | 4 | +44.738/+0.070 ns | 有效，保留 |
| CDC + 单补偿快照 | 233 | 368 | 4 | 4 | +45.175/+0.083 ns | FF 改善，保留 |
| 再让 ODDR 使用当前分频位 | 233 | 368 | 4 | 4 | +43.901 ns setup | LUT 不降且增加 DAC 相位风险，回退 |
| **CDC + 单快照 + 全国赛常量 valid** | **221** | **367** | **4** | **4** | **+44.556/+0.079 ns** | **最终候选** |

常量 valid 加入前后，同一组合的综合资源从 **309 LUT / 376 FF** 降到
**285 LUT / 375 FF**；正式布局布线从 233 LUT / 368 FF 降到 221 LUT / 367 FF。ODDR 候选
没有带来 LUT 收益，还降低 setup 余量并触及 DAC 边沿相位，所以没有把“代码更短”误写成优化。

## 6. RTL 验证

最终 221-LUT RTL 的证据目录：

- Smoke 17/17：`matlab_fir/national_finals/_work/rtl_regression/20260810_175430`；
- Release 17/17：`matlab_fir/national_finals/_work/rtl_regression/20260810_180048`。

Release 覆盖：CIC 连续/停顿/随机停顿/中途复位定向等价；冲激、10 个固定 seed、正负满量程、
强 −1 dBFS 共 14 组输入；4x/8x/128x 三节点逐样本比较全部 0 LSB；Stage1 行为 RAM 与
RAMB18E1 原语；8 类复位恢复；1200 次 CDC；100 次双时钟族切换；10 次不停机动态切档；
ROM、DAC、按键与模式控制。全部独立日志均以 PASS 结束，无 ERROR/FATAL/FAIL。

## 7. 正式实现、时序、DRC 与功耗

正式 `.xpr` 工程从头综合、opt、place、route 并生成 bitstream，结果目录为
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260810_181833`：

| 项目 | 综合 | post-route |
|---|---:|---:|
| LUT | 285 | **221** |
| LUTRAM | 0 | **0** |
| FF | 375 | **367** |
| DSP48E1 | 4 | **4** |
| RAMB18E1 / BRAM Tile | 4 / 2 | **4 / 2** |
| IO / MMCM | 17 / 2 | **17 / 2** |

- WNS/WHS=`+44.556/+0.079 ns`，TNS/THS=0，失败端点 0；
- 路由失败网络 0，DRC Error 0；
- CDC 模式总线 bus-skew：约束 50.000 ns，实际 0.433 ns，slack `+49.567 ns (MET)`；
- vectorless 总/动态/静态功耗=`0.271/0.199/0.072 W`，置信度 Medium；
- bitstream SHA-256：
  `08B2DE6DB8DF1FBC9E59EA78808C57BD007E414243B5F6FF9C7FF1B2797D91A7`；
- routed DCP SHA-256：
  `BFE4A9A25958C232E24091A08EE7A2F0E564AB3DF8C45EEFEB9CCA3CF1DC943F`。

## 8. 路由后 DAC 与六模式验证

- 默认 44.1 kHz/128x routed 测试：11290 个 DAC 边沿、7462 次数据变化，6 ms 内持续活动；
  证据目录为 `matlab_fir/national_finals/_work/postroute_dac_activity/20260810_182224`；
- 六模式 routed 测试：
  - 44.1 kHz：4x/8x/128x 为 `177/353/5645 edges/ms`；
  - 48 kHz：4x/8x/128x 为 `192/384/6144 edges/ms`；
  - 六档 DAC 数据均持续变化且无 X；
  - 证据目录为 `matlab_fir/national_finals/_work/postroute_six_mode_dac/20260810_182335`。

`177 edges/ms` 是 1 ms 观察窗口中的整数边沿计数，理想 176.4 个边沿无法以小数形式计数，
因此该读数表示 176.4 kHz 目标的有限窗口结果，而不是标称频率变成 177 kHz。

## 9. 插值滤波器核心 OOC

使用独立顶层 `interp128_all2x_v7_folded_fir_cic_top_ce`、器件 `xc7a35tfgg484-2` 和 6.144 MHz
核心时钟，从空结果目录重新综合、布局和布线。连续两次均得到相同资源，更新门禁后正式 PASS：

**193 LUT / 0 LUTRAM / 281 FF / 4 DSP48E1 / 3 RAMB18E1（1.5 BRAM Tile）/ 0 MMCM**，
内部寄存器到寄存器 WNS/WHS=`+151.232/+0.166 ns`，DRC Error=0。

正式证据目录：
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/core_ooc/results/20260810_184031`。

核心 OOC 与完整系统具有不同综合边界和跨层级打包，不能用 `221-193` 宣称外围精确占用
28 LUT；论文和答辩应分别报告“核心独立实现资源”和“完整系统实现资源”。

## 10. Tcl Store 故障与修复

正式构建最初两次在综合前失败，报错为找不到 `::tclapp::support::appinit 1.2`。根因是用户目录
`C:/Users/Lenovo/AppData/Roaming/Xilinx/Vivado/2025.2/XilinxTclStore` 缓存损坏，且第一次环境
修复使用反斜杠拼接 `TCLLIBPATH`，没有正确进入 Tcl `auto_path`。

正式构建、核心 OOC 与两个 post-route 包装脚本现在把 `XILINX_TCLAPP_REPO` 和使用正斜杠的
`TCLLIBPATH` 固定到 Vivado 安装目录内置 Tcl Store。用户缓存仍可能显示 warning，但不再阻止
`open_project`、综合或网表导出；不需要在仓库主目录运行 Vivado 维护命令。

## 11. 现场复现

关闭所有 Vivado GUI 后，在仓库根目录运行完整构建：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  ".\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\run_full_build_2025_2.ps1" -Jobs 1
```

运行核心 OOC：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  ".\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\core_ooc\run_core_ooc_2025_2.ps1" -Jobs 1
```

完整构建应出现 `VIVADO_2025_2_FULL_BUILD_PASS`，核心 OOC 应出现
`CORE_OOC_2025_2_DEMO_PASS`。普通 GUI 工程仍可按 Run Synthesis → Run Implementation →
Generate Bitstream 手动运行；必须 reset 旧 run，并确认查看的是本次最新 impl_1 报告。

## 12. 稳定性边界与下一步

工具侧稳定性证据已经覆盖 RTL、复位、CDC、切档、BRAM 原语、正式实现、bitstream、时序、
DRC、bus-skew 和 routed DAC 活性。2026-08-10 用户进一步完成物理板六档采样率与 DAC 波形
验证，所有档位均正常，当前没有发现功能、时序或板级输出不稳定因素。

在固定 4 DSP / 2 BRAM Tile、现有系数和定点语义下，221 LUT 已接近当前微架构的局部最优。
继续依靠单寄存器、单比较器或策略扫描，预期收益通常为 0～2 LUT，且可能被布局打包波动抵消。
若要显著继续下降，需要重新设计 Stage1/Stage2/3/CIC 的统一调度或存储边界，验证成本和板级
风险会明显上升；因此后续继续优化时应以 221-LUT board-pass 为当前基线，并保留 234-LUT
board-pass 作为前一安全回退点。
