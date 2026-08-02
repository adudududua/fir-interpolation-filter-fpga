# P3-J 后续优化指导执行反馈

> 对应指导：`matlab_fir/p3j_next_optimization_execution_guide.md`
> 执行日期：2026-08-02～2026-08-03
> 最终推荐分支：`national-finals-p3j-cic-dsp-pareto`
> 可复现性修复提交：`008a03122101833a596397013172a4d65b208a14`
> 工具：MATLAB R2023a、Vivado/XSim 2018.3、`xc7a35tfgg484-2`

## 1. 执行结论

指导具有明确参考价值。P0 的强信号闭环、P1 的 4/3/2-DSP 扫描、P2 的 2/1.5/1-BRAM 扫描、P3 的有效交叉点，以及 P5 的 signed-20/9-tap 搜索均已执行；P4 的物理板、SAIF 和 MMCM 动态掉电没有在当前环境中伪造结论。

最终默认仍选择 P3-J 4-DSP/2-BRAM/2-MMCM，但将旧的 432-LUT 结果进一步收敛并修复为可重复生成的 430-LUT 版本：

```text
430 LUT / 431 FF / 176 Slice / 4 DSP48E1
4 RAMB18E1 = 2 BRAM Tile / 2 MMCM
WNS/WHS = +45.636/+0.119 ns
AD9708 setup/hold slack = +76.116/+78.117 ns
Total/Dynamic/Static = 0.271/0.199/0.072 W（vectorless）
MATLAB = PASS；Release RTL = 15/15 PASS；bitstream = PASS
physical board = NOT EXECUTED
```

本轮最重要的工程修复不是再减少个位数 RTL，而是解决 430/436 LUT 复现不一致：历史 430 结果实际来自 `flatten_hierarchy=full` 的综合网表，批处理包装器却默认 `rebuilt`，而“只实现”流程又可静默复用旧 DCP。现在默认已统一为 `AreaOptimized_high/full/on + Default`，综合后写入配置指纹，实现前强制校验，避免再把不同配置的 DCP 误报为同一版本。

## 2. 最终推荐版验证闭环

### 2.1 MATLAB 六工况

2026-08-03 重新运行 `p3_01_search_joint_stage3_equalizer.m`，退出码为 0，并输出 `P3_JOINT_STAGE3_EQUALIZER_MATLAB_GATE_PASS`。MATLAB 用户偏好和图形缓存因当前账户权限产生警告，但数值门禁、CSV/JSON 生成和最终 PASS 不受影响。

| 输入 | 输出 | 最大绝对通带偏差 | 峰峰纹波 | 阻带衰减 | 相位 |
|---:|---:|---:|---:|---:|---|
| 44.1 kHz | 4x / 176.4 kHz | 0.003022 dB | 0.005709 dB | 78.568 dB | 严格线性 |
| 44.1 kHz | 8x / 352.8 kHz | 0.003521 dB | 0.006192 dB | 78.609 dB | 严格线性 |
| 44.1 kHz | 128x / 5.6448 MHz | 0.007730 dB | 0.005848 dB | 72.371 dB | 严格线性 |
| 48 kHz | 4x / 192 kHz | 0.003022 dB | 0.005709 dB | 78.568 dB | 严格线性 |
| 48 kHz | 8x / 384 kHz | 0.003007 dB | 0.005678 dB | 78.609 dB | 严格线性 |
| 48 kHz | 128x / 6.144 MHz | 0.007606 dB | 0.005724 dB | 72.371 dB | 严格线性 |

六档均满足绝对通带偏差/纹波不超过 0.05 dB、阻带不低于 70 dB。128x 阻带裕量约为 2.371 dB，因此后续不能只为了面积继续盲目缩短滤波器。

### 2.2 RTL Release

本次从当前最终分支重新运行 Release，工作目录为 `_work/rtl_regression/20260803_010216`，正式汇总为 **15/15 PASS**：

- 全链 14 组：冲激、10 个固定 seed×4096、正/负满量程、997 Hz/−1 dBFS 强信号；
- 4x/8x/128x 三个正式节点逐样本最大误差 0 LSB；
- 8/8 内部状态复位恢复；
- 10 次无复位动态模式切换，无 X、runt pulse；
- N3 Hold CIC 覆盖 DSP 模式 2/1/0、连续、停顿、10×256 随机和 burst 内复位；
- BRAM 原语、ROM、按键、双家族时钟与 CDC 独立测试全部通过。

### 2.3 干净综合、实现与 bitstream

最终证据从干净来源提交 `008a031` 构建，`source_worktree_dirty=false`。构建参数由综合指纹确认：

```text
synth_directive=AreaOptimized_high
flatten_hierarchy=full
resource_sharing=on
stage1_dsp48_preadder=1
cic_integrator_dsp_mode=2
p3_joint_stage3=1
jobs=4
implementation_opt_directive=Default
```

最终 bitstream SHA-256：

```text
C4DBB066030B92D387D799688D4010AB98F22B13BDA1623367EBCC8BE8BC0490
```

此外又使用普通 Vivado 工程 run 从零执行 `synth_1/impl_1 -> write_bitstream`，固定 `-jobs 4`，约 103 秒完成并输出 `NATIONAL_FINALS_GUI_IMPLEMENTATION_PASS`；GUI 实测仍为 430 LUT、431 FF、4 DSP、4 RAMB18E1、2 MMCM。XPR 的 8 个日常仿真向量也已从旧 `vectors/daily` 更正为 P3-J 专用 `vectors/p3j_daily`。

完整报告、DCP、bit、RTL 日志和 SHA 清单位于：

```text
matlab_fir/national_finals/vivado_results/
  p3j_final_430lut_431ff_176slice_4dsp_2bram_reproducible/
```

## 3. P0：强信号与实物板

### 3.1 已执行：−1 dBFS 强信号闭环

早期“0 次与 16 次饱和”来自刺激和观测位置不一致。已固定 `997 Hz / −1 dBFS / 44.1 kHz` 输入及 4x/8x/128x golden 到 `vectors/p3j_strong_signal/`，并加入 SHA-256 与 Release。

检查发现 8x 可见输出原先把 signed-21 直接截低 20 bit，正峰接近满量程时可能翻成负数。修复只在 8x 可见端增加明确的 signed-21→signed-20 饱和；128x 补偿链继续保留 signed-21，不改变 CIC 输入。最终强信号三节点与 MATLAB bit-true 为 0 LSB。

### 3.2 未执行：实物板和仪器

当前环境无法接触 FPGA 板、示波器、频谱仪和电流表，所以下列内容仍为待办：

- 六档 `DA_CLK` 频率、占空比和脉宽；
- DAC 主音、镜像和模式切换波形；
- 100 次家族/倍率往返切换；
- 实板电流和环境温度记录。

bitstream 成功只能表述为“工具侧可下载位流已生成”，不能写成物理板通过。

## 4. P1：4/3/2-DSP 正交扫描

固定 P3-J、BRAM、时钟、系数和实现策略，只改变 `CicIntegratorDspMode`。三档均完成 Release 15/15、原语审计、post-route、时序、功耗和 bitstream。

| 档位 | LUT | FF | Slice | DSP | BRAM Tile | WNS/WHS | 功耗（总/动态/静态） | 判定 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| mode=2 默认 | **430** | **431** | **176** | **4** | 2.0 | +45.636/+0.119 ns | 0.271/0.199/0.072 W | 默认最低 LUT/FF |
| mode=1 | 466 | 457 | 188 | 3 | 2.0 | +45.785/+0.121 ns | 0.271/0.198/0.072 W | 低 DSP Pareto |
| mode=0 | 488 | 486 | 191 | 2 | 2.0 | +45.736/+0.060 ns | 0.270/0.198/0.072 W | 最低 DSP Pareto |

3-DSP 和 2-DSP 分别比指导的严格 LUT 停止线高 1 和 3 LUT，因此不替代默认版；但它们功能、时序和 bitstream 完整通过，并明显支配旧 504/494/3-DSP 与 523/523/2-DSP 点，故作为明确的 DSP Pareto 保留。

## 5. P2：2/1.5/1-BRAM 正交扫描

| 档位 | LUT | FF | Slice | DSP | RAMB18 / Tile | WNS/WHS | 功耗 | 判定 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 默认 | 430 | 431 | 176 | 4 | 4 / 2.0 | +45.636/+0.119 ns | 0.271 W | 默认 |
| PCM+Stage1 共享 | 456 | 450 | 181 | 4 | 3 / 1.5 | +46.033/+0.116 ns | 0.271 W | 低 BRAM Pareto |
| distributed 双 Bank | 495 | 480 | 186 | 4 | 2 / 1.0 | +45.807/+0.108 ns | 0.270 W | No-Go，不满足 LUT≤490 |

1.5-BRAM 候选只比“优选线”455 LUT 高 1 LUT，但低于继续观察线 465/475，且完整功能、时序和 bitstream 通过，因此保留。1-BRAM 候选为 495 LUT，越过指导停止线，不再通过大范围策略碰运气；旧 1-BRAM 版本仍可作为硬宏资源极限历史点，但不是本轮推荐。

## 6. P3：DSP×BRAM 交叉 Pareto

只构建了具备价值的 `3-DSP + 1.5-BRAM`：

```text
478 LUT / 476 FF / 191 Slice / 3 DSP / 3 RAMB18 = 1.5 BRAM Tile
WNS/WHS = +45.610/+0.115 ns
vectorless = 0.271/0.199/0.072 W
```

该点满足指导 X1 的 500 LUT/510 FF 停止线，保留在 `national-finals-p3j-bram-pareto`。未继续构建 `3-DSP+1-BRAM` 和 `2-DSP+1-BRAM`，原因是独立 1-BRAM 已越过 490-LUT 门槛，继续交叉只会增加验证成本并形成被支配或高 LUT 点。

## 7. P4：MMCM 与真实功耗

本轮没有把 P4 写成已完成：

- 单家族单 MMCM 会失去 44.1/48 kHz 实时切换，不适合作为默认全国赛交付；
- 动态 `PWRDWN` 需要常开 50 MHz FSM、锁定故障注入、runt 检测、SAIF 和实板电流闭环，当前缺少物理设备；
- vectorless 的 0.270/0.271 W 差异低于可声明范围；
- mode-gated CE 在没有 post-route SAIF 层级占比前不应增加隐藏状态风险。

仓库中已有历史单家族实验分支，但本轮未将其冒充为指导 P4 的双家族安全掉电签核。待板卡可用后，应按指导 FSM 顺序单独立项。

## 8. P5：signed-20 与 9-tap

### 8.1 signed-20：No-Go

搜索 80,001 个全局/局部 11-tap signed-20 候选，其中 31,233 个通过初步频率门禁，但没有候选同时满足：

- 六工况精确门禁；
- 128x 最大绝对通带偏差不超过 0.02 dB；
- 阻带不低于 71 dB；
- 强信号峰值不超过 signed-20 上限 524287。

因此保持 signed-21，未通过简单整体缩放消耗全部通带裕量。

### 8.2 9-tap：MATLAB/RTL Go，资源 No-Go

搜索 40,008 个候选，54 个通过精确频率门禁，最终选定：

```text
[-943, -2793, 2406, 19161, 29851,
 19161, 2406, -2793, -943]
```

最差绝对通带偏差 0.0198073 dB、阻带 72.390 dB、严格对称；Stage3 两相任务由 6/5 拍降为 5/4 拍。候选经过 17/17 Smoke、冲激和随机全链 0 LSB、8/8 复位和 10/10 动态切换后，clean post-route 为：

```text
441 LUT / 431 FF / 177 Slice / 4 DSP / 2 BRAM Tile
WNS/WHS = +46.190/+0.121 ns；功耗 = 0.271 W
```

它比最终 430-LUT 基线增加 11 LUT，没有减少 DSP、BRAM 或 FF，故资源门禁 No-Go。候选和完整失败证据保留在 `national-finals-p3j-stage3-fwl-search`，不会污染默认分支。

## 9. 实施中遇到的问题与解决方法

| 问题 | 根因 | 解决 |
|---|---|---|
| GUI 实现运行很久或失败 | GUI 曾以 `-jobs 19` 启动，`pwropt` 内存不足；另一次 route worker 无 CPU/日志增长 | 综合/实现统一限制为 4 jobs；独立低内存单进程实现；清理失效 run 后重建 |
| 历史 430，手动重跑却为 436 | 历史实现复用了 `full` DCP，包装器默认却是 `rebuilt`；旧清单未记录真实 DCP 配置 | 默认统一为 `full`；综合写配置指纹；只实现强制校验；清单记录真实参数 |
| `ExploreArea` 名称看似省面积却更差 | 实现指令对本小设计的重映射增加 LUT | 实测 Default/AddRemap/ExploreWithRemap=436，ExploreArea=444；停止策略碰运气，回到正确 full 综合 |
| 8x 强信号正峰翻负 | signed-21 可见输出直接截低 20 bit | 仅在 8x 可见端显式 signed 饱和；128x 补偿链保留 signed-21 |
| 9-tap board TB 无法 elaboration | 测试 stub 缺少新增参数 | 给 stub 补齐参数并重新编译 |
| 9-tap 全链少 32 个尾点 | TB 沿用 11-tap 固定输出计数 | 按候选实际群延迟/尾长计算计数；数值对拍恢复 0 LSB |
| 禁用 P2/P5 功能后仍比基线多 LUT | 兼容参数代码仍参与跨层级优化，Vivado 网表发生变化 | 默认版停留在独立 P1 源分支；P2/P5 各用独立分支保存，不把兼容硬件合回默认 |
| MATLAB 偏好/图形警告 | 当前账户不能访问 Roaming 偏好文件 | 数值脚本仍 exit 0/PASS；记录警告，不把图形初始化警告误判为频响失败 |

## 10. Git、分支和回退路线

本轮新建/使用的正式分支均不含 `codex`：

| 用途 | 分支/标签 |
|---|---|
| 最终默认与 4/3/2-DSP | `national-finals-p3j-cic-dsp-pareto` |
| 1.5/1-BRAM 与交叉点 | `national-finals-p3j-bram-pareto` |
| signed-20/9-tap | `national-finals-p3j-stage3-fwl-search` |
| 旧 430 源标签 | `nf-p3j-430lut-431ff-176slice-4dsp-strong-signedoff` |
| 最终可复现标签 | `nf-p3j-final-430lut-431ff-176slice-4dsp-2bram-reproducible` |

历史远端已有的 `codex/...` 分支没有在本轮重命名或删除，以免破坏既有回退引用；新提交、分支和标签均遵守用户要求。

## 11. 手动复现命令

在仓库根目录运行最终批处理构建：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1 `
  -Step all `
  -ResultTag manual_p3j_final_430_repro
```

脚本默认即为最终参数，无需再手写 `full`。本机实测总耗时约 102 秒；日志全部进入 `_work/vivado/<时间戳>`，不会散落在项目根目录。

运行 Release RTL：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1 `
  -RegressionScale Release
```

GUI 工程应先执行 `configure_national_finals_gui_project.tcl`，确认 `AreaOptimized_high/full/on`、P3-J=1、CIC DSP mode=2，再在 Vivado 中 Generate Bitstream。验证脚本固定 `-jobs 4`，避免再次以 19 jobs 启动。

## 12. 最终建议

- 默认比赛交付：430 LUT / 431 FF / 4 DSP / 2 BRAM Tile / 2 MMCM；
- DSP 评分较重：466/457/3-DSP 或 488/486/2-DSP；
- BRAM 评分较重：456/450/4-DSP/1.5-BRAM；
- 同时压 DSP/BRAM：478/476/3-DSP/1.5-BRAM；
- 不推荐：495-LUT 1-BRAM、441-LUT 9-tap、未经实板/SAIF 的 MMCM 掉电声明。

工具侧已闭环；全国赛最终提交前仍必须由用户在目标板上完成六档时钟、DAC 波形、动态切换和供电电流记录。
