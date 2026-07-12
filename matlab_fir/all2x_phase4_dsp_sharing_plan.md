# 全 2x Phase 4 Stage 2/3 共享 DSP 执行计划

> 分支：`codex/all2x-phase4-dsp-sharing`  
> 起始提交：`8912d5a`  
> 稳定板级基线：`6132cbb` / `LUT3676_DSP1_FF1106_board_successful`  
> 日期：2026-07-12

## 1. 目标

当前 V3 BRAM 版本已经完成 MATLAB、RTL、Vivado 和板级验证：

```text
独立插值链：3222 LUT / 925 FF / 1 DSP / 1 BRAM Tile
完整板级  ：3676 LUT / 1106 FF / 1 DSP / 1 BRAM Tile
时序      ：WNS +44.204 ns，WHS +0.108 ns
功能      ：冲激与随机 PCM 均为 0 LSB
板测      ：4x、8x、128x 三档 DA_CLK 与 DA 波形正常
```

Phase 4 的目标是在不修改 FIR 系数、不降低频响指标、不改变 24 bit 定点结果的前提下，增加第 2 个 DSP，由 Stage 2 和 Stage 3 共享，替换两级当前的 LUT 常系数乘法网络。

## 2. 设计边界

Phase 4 实验必须遵循以下边界：

1. 保留 V3 Stage 1 strict-halfband BRAM 单 DSP MAC。
2. 保留 Stage 4～7 canonical Q4 shift-add。
3. Stage 2/3 使用现有 Q15/Q14 系数，禁止重新设计频响。
4. 新结构先通过独立实验顶层验证，不直接修改板级稳定实例。
5. 所有临时 Vivado/XSim 文件放在 `%TEMP%/codex_fir_interpolation/`。
6. 新建 Verilog、MATLAB、Tcl 文件继续使用项目统一中文文件头。
7. 只有 Phase 4D 满足 Stop/Go 条件，才允许接入板级工程。

## 3. 稳定基线

### 3.1 当前结构

```text
Stage 1：105 tap strict-halfband BRAM，26 次单 DSP MAC
Stage 2：17 tap true-polyphase，LUT 常系数乘法
Stage 3：11 tap true-polyphase，LUT 常系数乘法
Stage 4～7：canonical halfband7，shift-add
级间桥：valid-only
```

### 3.2 Stage 2/3 当前参数

| 级数 | 输出速率 | CE 周期 | phase0 | phase1 | 最坏 MAC 数 |
|---:|---:|---:|---:|---:|---:|
| Stage 2 | 176.4 kHz | 32 个 5.6448 MHz 时钟 | 9 tap，对称后 5 MAC | 8 tap，对称后 4 MAC | 5 |
| Stage 3 | 352.8 kHz | 16 个 5.6448 MHz 时钟 | 6 tap，对称后 3 MAC | 5 tap，对称后 3 MAC | 3 |

## 4. Phase 4A：调度可行性分析

### 4.1 最坏周期预算

Stage 3 每 16 拍产生一个输出任务，Stage 2 每 32 拍产生一个输出任务。每隔 32 拍，两级任务同时到达一次：

```text
最坏同拍工作量：Stage 2 5 MAC + Stage 3 3 MAC = 8 MAC
下一个 Stage 3 到达间隔：16 拍
理论原始余量：16 - 8 = 8 拍
```

共享调度器采用 Stage 3 优先，确保高速级先完成：

```text
同拍到达：先执行 Stage 3，后执行 Stage 2
Stage 3 单独到达：立即执行 Stage 3
```

实际 RTL 需要把任务入队、任务启动、最后一次 MAC 和结果 valid 的控制开销计入。完成 4B 后必须用断言统计真实 arrival/start/finish/deadline/slack。

### 4.2 4A 通过条件

```text
最坏 MAC 需求 <= 8
最短到达间隔 = 16
理论 slack >= 8 拍
每个客户端最多保留 1 个 pending job
不存在同一客户端 pending 覆盖
```

### 4.3 4A 实际结果

`v4_01_analyze_stage23_shared_dsp_schedule.m` 已生成 64 拍超周期调度：

| 顺序 | Stage | phase | arrival | MAC | start | finish | deadline | slack |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 3 | 1 | 0 | 3 | 1 | 4 | 8 | 4 |
| 2 | 2 | 1 | 0 | 4 | 5 | 9 | 16 | 7 |
| 3 | 3 | 0 | 16 | 3 | 17 | 20 | 24 | 4 |
| 4 | 3 | 1 | 32 | 3 | 33 | 36 | 40 | 4 |
| 5 | 2 | 0 | 32 | 5 | 37 | 42 | 48 | 6 |
| 6 | 3 | 0 | 48 | 3 | 49 | 52 | 56 | 4 |

```text
最坏同拍 MAC 数 = 8
最坏实际 slack   = 4 拍
deadline miss    = 0
Phase 4A 判定    = PASS
```

输出文件：

```text
matlab_fir/alt_all2x_v4/phase4_stage23_schedule.csv
matlab_fir/alt_all2x_v4/phase4_stage23_schedule_summary.txt
```

## 5. Phase 4B：独立 RTL 实验

计划新增：

```text
sources_1/new/all2x_v4/
    interp2_stage23_shared_dsp_ce.v
    interp128_all2x_v4_shared_dsp_top_ce.v
    interp128_all2x_v4_shared_dsp_bram_top_ce.v

sim_1/new/all2x_v4/
    tb_interp2_stage23_shared_dsp_ce.v
    tb_interp128_all2x_v4_shared_dsp_ce.v
```

`interp2_stage23_shared_dsp_ce` 负责：

1. 保存 Stage 2 的 9 个真实输入历史点。
2. 保存 Stage 3 的 6 个真实输入历史点。
3. 在两级 CE 到达时生成 MAC job。
4. 使用一个 25x16 signed 乘法器并约束 `use_dsp=yes`。
5. 使用足够宽的共享累加器保持整数和完全一致。
6. Stage 2 按 Q15 舍入饱和，Stage 3 按 Q14 舍入饱和。
7. 产生独立的 Stage 2/3 `data + valid` 输出。
8. 仿真时记录 job 调度并检查 pending、deadline 和结果完整性。

## 6. Phase 4C：功能验证

### 6.1 单元验证

共享 DSP 模块与当前 Stage 2/3 true-polyphase 参考模块并行输入，检查：

```text
Stage 2 impulse  最大误差 = 0 LSB
Stage 2 random   最大误差 = 0 LSB
Stage 3 impulse  最大误差 = 0 LSB
Stage 3 random   最大误差 = 0 LSB
deadline miss                = 0
pending overwrite            = 0
```

### 6.2 完整七级验证

V4 完整链与 MATLAB V3 golden 对拍：

```text
冲激响应最大误差 = 0 LSB
随机 PCM 最大误差 = 0 LSB
所有 mismatch      = 0
固定实现延迟单独记录
```

### 6.3 4C Stop 条件

出现以下任一情况立即停止板级接入：

1. 任一正常测试出现非 0 LSB。
2. 任一 job 发生 pending 覆盖或 deadline miss。
3. 正常输入新增溢出或饱和。
4. 任务顺序不能稳定复现。

## 7. Phase 4D：Vivado 资源与时序

综合对象为独立 V4 128 倍插值链，不包含板级外设。与 V3 独立链比较：

| 项目 | V3 基线 | Phase 4 Go 条件 |
|---|---:|---:|
| LUT | 3222 | **< 2800** |
| FF | 925 | 不显著恶化，目标 <= 1100 |
| DSP | 1 | 2 |
| BRAM Tile | 1 | <= 1 |
| WNS | +159.809 ns | > 0 ns |
| RTL 对拍 | 0 LSB | 0 LSB |
| deadline miss | 0 | 0 |

若 LUT 未低于 2800，即使功能通过，也不替换当前稳定板级版本。

## 8. 板级接入

只有 4D 判定为 Go，才执行：

1. 新建 V4 板级包装顶层，保持 V3 文件可独立回退。
2. 将 `demo_interp_dac8_audio_pcm_common.v` 切换到 V4 包装顶层。
3. 把 V4 文件正式加入 `sources_1`。
4. 重跑正式 `synth_1` 和 `impl_1`。
5. 检查资源、setup/hold、DRC 和功耗。
6. 生成 bitstream 并完成实板回归；新增四档扩展后需再次执行。

板级目标为：

```text
LUT < 3300
FF  <= 1300
DSP = 2
BRAM Tile <= 1
WNS/WHS > 0
```

## 9. 进度对齐

| 阶段 | 状态 | 结果 |
|---|---|---|
| 计划建立 | 已完成 | 基线、边界和 Stop/Go 指标已锁定 |
| Phase 4A | 已完成 | 最坏 slack=4 拍，全部任务 PASS |
| Phase 4B | 已完成 | 共享 DSP RTL、独立七级顶层和回归平台均已完成编译 |
| Phase 4C | 已完成 | 六组冲激/随机分级及链尾对拍均为 0 LSB，调度断言无触发 |
| Phase 4D | 已完成 | 1648 LUT / 1016 FF / 2 DSP / 1 BRAM Tile，WNS +161.944ns，判定 Go |
| 板级接入 | 已完成三档实测 | 176.37kHz / 352.86kHz / 5.64MHz，三档 DA 波形正常 |
| 四档展示扩展 | RTL 已完成 | 新增 15kHz ROM 与 1x 旁路，等待重新综合、实现和四档板测 |
| 文档收尾 | 已完成 | README 已更新 V4 结构、回归、资源、时序、实现截图和版本对比 |

### 9.1 Phase 4C 实测结果

| 对拍节点 | 输入 | 比较点数 | 固定延迟 | 最大误差 | mismatch |
|---|---|---:|---:|---:|---:|
| Stage 2 | 冲激 | 2188 | 0 | 0 LSB | 0 |
| Stage 2 | 随机 PCM | 2188 | 0 | 0 LSB | 0 |
| Stage 3 | 冲激 | 4375 | 0 | 0 LSB | 0 |
| Stage 3 | 随机 PCM | 4375 | 0 | 0 LSB | 0 |
| 完整 128x | 冲激 | 40059 | 127 | 0 LSB | 0 |
| 完整 128x | 随机 PCM | 23675 | 127 | 0 LSB | 0 |

```text
pending overwrite = 0
deadline miss     = 0
Phase 4C 判定     = PASS
```

### 9.2 Phase 4D 独立综合结果

| 项目 | V3 独立链 | V4 共享 DSP | 变化 | Go 条件 | 判定 |
|---|---:|---:|---:|---:|---|
| LUT | 3222 | 1648 | -1574（-48.85%） | < 2800 | PASS |
| FF | 925 | 1016 | +91（+9.84%） | <= 1100 | PASS |
| DSP | 1 | 2 | +1 | = 2 | PASS |
| BRAM Tile | 1 | 1 | 0 | <= 1 | PASS |
| WNS | +159.809ns | +161.944ns | +2.135ns | > 0ns | PASS |
| RTL 对拍 | 0 LSB | 0 LSB | 不变 | 0 LSB | PASS |

```text
Phase 4D Stop/Go = GO
```

正式报告位于：

```text
matlab_fir/alt_all2x_v4/vivado_results/stage23_shared_dsp/
```

### 9.3 V4 板级实现结果

| 项目 | V3 已实板版本 | V4 实现结果 | 变化 |
|---|---:|---:|---:|
| LUT | 3676 | 2122 | -1554（-42.27%） |
| FF | 1106 | 1198 | +92（+8.32%） |
| DSP | 1 | 2 | +1 |
| BRAM Tile | 1 | 1 | 0 |
| WNS | +44.204ns | +44.960ns | +0.756ns |
| WHS | +0.108ns | +0.121ns | +0.013ns |

```text
板级综合/实现 = PASS
DRC            = 0 Error / 30 Warning
bitstream      = 已生成并完成三档实测
实板三档回归   = 已通过
```

三档实测结果：

```text
4x   = 176.37 kHz，DA 波形正常
8x   = 352.86 kHz，DA 波形正常
128x = 5.64 MHz，DA 波形正常
```

### 9.4 15kHz 与 1x 四档展示扩展

为了放大示波器上的阶梯粗糙度差异，测试输入改为 44.1kHz 采样、
15kHz、0.80FS 的单正弦，并新增未经过插值链的 1x DAC 旁路：

| 档位 | DA_CLK | 每周期采样点 | 按键 |
|---|---:|---:|---|
| 1x | 44.1kHz | 2.94 | SW1 / SW5 |
| 4x | 176.4kHz | 11.76 | SW2 / SW6 |
| 8x | 352.8kHz | 23.52 | SW3 / SW7 |
| 128x | 5.6448MHz | 376.32 | SW4 / SW8 |

```text
四档 DA_CLK 边沿检查 = 32 / 128 / 256 / 4096，PASS
四档 DAC 数据变化    = 32 / 127 / 251 / 3306，PASS
SW1～SW8 模式编码    = 0/1/2/3/0/1/2/3，PASS
```

该扩展不修改 FIR 系数和 V4 共享 DSP 内核，但修改了 ROM、按键编码、
DAC 数据选择和 DA_CLK 选择，因此上一轮 2122 LUT 的实现结果需要重跑。

## 10. 回退点

任何阶段失败时，正式板级稳定版本保持：

```text
commit : 6132cbb
tag    : LUT3676_DSP1_FF1106_board_successful
```

Phase 4 的失败只影响 `codex/all2x-phase4-dsp-sharing` 实验分支，不影响比赛稳定版本。
