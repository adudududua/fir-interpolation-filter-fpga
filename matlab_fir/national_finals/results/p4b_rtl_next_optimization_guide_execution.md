# P4-B RTL 下一阶段优化指导执行反馈

> 对照文档：[`national_finals_p4b_rtl_next_optimization_guide.md`](../../national_finals_p4b_rtl_next_optimization_guide.md)  
> 执行分支：`codex/national-finals-p4c-rtl-guide-opt`  
> 起点：P4-B `504 LUT / 493 FF / 202 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM`  
> 工具：MATLAB R2023a、Vivado/XSim 2018.3、器件 `xc7a35tfgg484-2`

## 1. 总体结论

这份指导有较高参考价值。P0、P1、P2 和 P3 中的大部分建议可以在不改变滤波传递函数的前提下实施，实际也获得了可复现收益；但其中若干资源预估和适用前提必须通过当前 RTL 实测修正，不能直接当作结论。

本轮完成后的最低 LUT/FF 默认候选为：

```text
479 LUT / 468 FF / 198 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM
WNS/TNS = +45.734/0 ns
WHS/THS = +0.121/0 ns
Total/Dynamic = 0.271/0.199 W（vectorless，非实测）
RTL = 15/15 PASS
```

相对 P4-B，默认候选减少 `25 LUT / 25 FF / 4 Slice`，DSP、BRAM、MMCM 不变。另有经过同一最终 RTL 从头综合、实现并生成 bitstream 的 3-DSP 和 2-DSP Pareto 档；它们不是“全资源更优”，而是用 LUT/FF 交换 DSP。

## 2. 建议采纳情况

| 指导项 | 判断 | 执行状态 | 结论 |
|---|---|---|---|
| 48 kHz 切换首样点修复 | 正确且必须 | 完成 | 先构造失败测试，再修复 family 同步器；首地址风险被真实复现并关闭 |
| GUI 仿真配置与综合配置统一 | 正确且必须 | 完成 | XPR、GUI 配置脚本和 CLI 回归使用同一顶层与宏 |
| 历史 RAM primitive-vs-behavioral | 正确 | 完成 | 新增专用参数和 5000 拍随机对拍，不全局定义 `SYNTHESIS` |
| 删除 Stage2/3 死写队列 | 有条件正确 | 完成，限制在板级固定 CE | 省 25 FF 和部分 LUT；任意 CE 停顿的通用模式仍保留队列 |
| Stage1 DSP48 预加器 | 值得 A/B，不能只凭结构判断 | 完成 | 当前单 BRAM 核中综合 LUT 再降 7；与早期 434-LUT 架构的结论不同 |
| `SETTLE_CYCLES` 位宽修复 | 正确 | 完成 | `SETTLE_CYCLES=7` 定向测试通过，消除原 2-bit 截断 |
| CIC 33 bit 收窄为 26/29 bit | 正确，但必须证明 | 完成 | 与 33-bit 参考在连续、停顿、复位和 10 个随机 seed 下 0 LSB |
| CIC 4→3→2 DSP | 正确的 Pareto 路线 | 完成 | 4/3/2-DSP 三档均完成 post-route、时序、功耗报告和 bitstream |
| 小范围策略扫描 | 正确 | 完成 | `AreaOptimized_high + rebuilt + Default opt` 保持最优 |
| 独立暖机静音 | 思路合理，验收定义不足 | 暂不合入 | 会改变切换静音时长；需实板确定可接受恢复时间 |
| DSP PREG 级联 | 可行但改变固定延迟 | 未执行 | 与 CARRY Pareto 分支分开，避免一次提交叠加两项时序语义变化 |
| 1.5/1 BRAM Tile 打包 | 有研究价值、调度风险较高 | 未执行 | 当前轮先完成低风险 RTL 和 CIC Pareto；后续应独立分支 |
| 未选 MMCM `PWRDWN` | 功耗价值最高 | 审计完成，未合入 | 必须新增唤醒、等待 LOCKED、切换、关闭旧 MMCM 的状态机和 SAIF/板测 |
| N4、单 FIR DSP、噪声整形 | 独立性能/研究路线 | 未执行 | 会改变 golden、全局调度或模拟输出风险，不覆盖稳定主线 |

## 3. P0 正确性与配置闭环

### 3.1 48 kHz 首样点地址

原板级顶层在音频数据通路复位时把 `family_audio_meta/sync` 清零。测试 ROM 在复位分支根据该信号选择首地址：44.1 kHz 为地址 0，48 kHz 为地址 147。因此切换到 48 kHz 后，首个 ROM 地址仍可能错误地取 0。

旧测试没有发现问题，是因为当前测试音在两个首地址处恰好都是 0，比较数据值无法区分地址。解决过程如下：

1. 在板级集成 TB 中直接断言 48 kHz 音频复位释放时 `family_audio_sync==1`；
2. 修改前测试按预期失败：`first ROM address would be wrong`；
3. family 同步器改为在数据通路复位期间继续跟踪 `family_active`；
4. 修改后板级集成、ROM、家族切换和全链回归全部通过。

该修复不增加滤波资源，也不改变稳态样点，只关闭切换后的首地址漏洞。

### 3.2 GUI/CLI 配置漂移

新增 `configure_national_finals_gui_project.tcl`，把 GUI `sim_1` 固定为：

- 顶层 `tb_phase7_full_chain_bittrue`；
- 与命令行回归完全相同的全国赛宏；
- Stage1 预加器开启；
- CIC 默认模式为 2 个积分器 DSP，即全机 4 DSP。

`open_national_finals_gui_clean.ps1` 会先执行配置检查，再从 `_work/vivado_gui/<timestamp>` 打开 GUI，避免 `.Xil`、journal 和 log 污染仓库根目录。最终配置脚本已实际运行并输出 `NATIONAL_FINALS_GUI_SIM_CONFIGURED`。

### 3.3 参数化 CDC

原 `nf_mode_cdc_handshake` 的 settle 计数器固定为 2 bit，只能可靠覆盖较小参数。现在使用：

```text
SETTLE_COUNT_W = max(1, clog2(SETTLE_CYCLES + 1))
```

测试额外实例化 `SETTLE_CYCLES=7`，并继续完成 1200 次全方向原子切换；没有发生计数截断、重复 ACK 或中间模式提交。

## 4. P1/P2 低风险面积优化

### 4.1 Stage2/3 写队列删除

板级正式 CE 为固定 2 的幂调度：Stage2 phase0 写事件与 Stage3 phase0 写事件在 64 拍周期中的集合不相交，因此原来的 1 项 Stage3 待写队列在正式配置中不可达。

实现没有无条件删除队列，而是增加 `ASSUME_ALIGNED_POW2_CE`：

- 默认 `0`：通用 IP 保留队列，支持任意停顿和相位；
- 全国赛板级连续 CE 配置为 `1`：综合删除队列，并保留碰撞 `$fatal`。

一次测试曾把该参数错误地用于会主动停顿 CE 的通用等价 TB，测试正确失败。这说明指导中的前提必须保留在接口上，不能把板级调度证明扩大到任意 CE。恢复通用 TB 的默认队列后，全回归通过。

综合 A/B：

| 候选 | 综合 LUT | 综合 FF | DSP | BRAM Tile |
|---|---:|---:|---:|---:|
| P4-B 原队列、预加器关 | 525 | 499 | 4 | 2 |
| 固定 CE 删除队列、预加器关 | 511 | 474 | 4 | 2 |
| 删除队列、预加器开 | 504 | 474 | 4 | 2 |

队列删除带来约 `-14 LUT/-25 FF`；预加器在当前结构中再减少 7 个综合 LUT。

### 4.2 Stage1 DSP48 预加器

早期 434-LUT 架构中，显式预加器 A/B 曾增加资源，因此本轮没有盲目照搬指导，而是在当前“Stage1 单 BRAM 串行读”结构上重新综合。当前结构的 `left + right` 25-bit 对称和可直接使用 DSP48E1 `D+A`，且乘法前不截位，单元与整链均 0 LSB。

结论是：优化是否有效依赖周边结构；当前版开启，不能把这一结论反向套用到旧 Route 1。

### 4.3 历史 RAM 原语测试

两个历史 RAM wrapper 新增 `SIM_USE_PRIMITIVE` 参数。综合始终选择 RAMB18E1；普通仿真默认选择行为模型；专用测试只让候选实例选择原语分支。

测试覆盖：

- Stage1 `64×24` 全地址和符号拼接；
- Stage2/3 `32×22` 全地址和符号拼接；
- 128 拍完整地址扫描；
- 5000 拍随机并发读写；
- 正负满量程数据。

正式滤波器通过当前输入旁路避免同地址碰撞，因此测试也不把器件未约定的碰撞输出作为接口契约。

## 5. P3 CIC 位宽证明与 DSP Pareto

### 5.1 位宽不是机械删位

输入补偿器为 signed 21 bit。对 `C² → Hold16 → I²`：

- 第一积分器在一个 16 拍 block 内的系数形式为 `[k, 16-2k, k-16]`，绝对值和最大为 32，因此 signed `21+5=26 bit` 足够；
- 第二积分器等效于 N3 CIC 的非负三角多相核，每相系数和为 `16²=256`，因此 signed `21+8=29 bit` 足够。

该证明依赖当前 `R=16、N=3、DATA_W=21、零初态和完整 comb/hold 结构`。参数变化后必须重新推导，不能把 26/29 写成通用常数。

### 5.2 等价验证

同一 TB 并行实例化：

- 旧 33-bit 参考；
- 26/29-bit、两个积分器 DSP；
- 第一积分器 CARRY、第二积分器 DSP；
- 两个积分器均 CARRY。

覆盖连续 320 组、随机停顿 480 组、burst 中复位，以及 `10 seed × 256` 含正负满量程随机输入；4096 个随机段输出和全部定向输出均 0 LSB。

### 5.3 最终同源实现结果

以下三档由完全相同的最终 RTL、顶层、XDC 和策略从头生成：

| 全机档位 | CIC 映射 | LUT | FF | Slice | DSP | BRAM Tile | MMCM | WNS/WHS | Total/Dynamic power |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 默认低 LUT/FF | 26-bit DSP + 29-bit DSP | **479** | **468** | **198** | **4** | 2 | 2 | +45.734/+0.121 ns | 0.271/0.199 W |
| 低 DSP-A | 26-bit CARRY + 29-bit DSP | 504 | 494 | 198 | 3 | 2 | 2 | +45.853/+0.121 ns | 0.271/0.199 W |
| 低 DSP-B | 26-bit CARRY + 29-bit CARRY | 523 | 523 | 197 | 2 | 2 | 2 | +45.802/+0.121 ns | 0.270/0.198 W |

相对默认档：

- 3-DSP：`+25 LUT/+26 FF/0 Slice/-1 DSP`；
- 2-DSP：`+44 LUT/+55 FF/-1 Slice/-2 DSP`。

指导预期的 CARRY LUT 增量基本正确，但“FF 近似不变”的预估与当前 Vivado 映射不符：禁止 DSP 后，26/29-bit 累加状态实际落入 Slice Register，分别增加约 26/55 FF。最终以层次综合和 post-route 为准。

功耗差只有报告分辨率内的 0.001 W，且没有 SAIF，不能据此宣称减少 DSP 会显著省电。两颗 MMCM 仍占约 0.197 W，是下一阶段真正的功耗重点。

### 5.4 bitstream

| 档位 | 结果目录 | SHA-256 |
|---|---|---|
| 4 DSP | `vivado_results/p4c_signed_479lut_468ff_4dsp_2bram` | `814465320512830C98D0EDA5352D36797BF5C442CD27E3520B5B89601F1C52D3` |
| 3 DSP | `vivado_results/p4c_signed_3dsp_2bram` | `81AA1B27AE84D24071507E7FB06E9FAE357BF85400FCE4C3DFCA18A14F915DFA` |
| 2 DSP | `vivado_results/p4c_signed_2dsp_2bram` | `0F82EB84C2E22264454F504F183FC979486DF0BD4103F0F275334FB78EC66CDD` |

## 6. 策略扫描

在 4-DSP 最低 LUT/FF 档上进行受控小扫描：

| 综合/实现设置 | 结果 | 判断 |
|---|---|---|
| `AreaOptimized_high + rebuilt + ResourceSharing=on + Default` | 综合 503 LUT；post-route 479 LUT | 正式默认 |
| `AreaOptimized_medium + rebuilt` | 综合 514 LUT | +11，拒绝 |
| `AreaOptimized_high + full` | 综合 503 LUT | 无收益，保留较清晰 `rebuilt` |
| `opt_design ExploreArea` | post-route 495 LUT | +16，拒绝 |
| `opt_design AddRemap` | post-route 479 LUT | 无收益，保留 Default |

最近几轮优化已经进入个位数边际区，因此停止继续大范围扫随机策略；只有结构变化后才重新评估。

## 7. 最终 RTL、频响和实现门禁

### 7.1 RTL

最终从空目录运行：

```text
NATIONAL FINALS RTL REGRESSION PASS (15/15)
_work/rtl_regression/20260801_143047
```

除原 14 项外新增历史 RAMB18 原语对拍；同时扩展了：

- 48 kHz 音频复位释放首地址断言；
- CIC 26/29-bit 与 4/3/2-DSP 三种映射随机等价；
- CDC `SETTLE_CYCLES=7` 参数化测试。

### 7.2 六工况频响

MATLAB 直接分析本轮 RTL 发布的 impulse CSV：

| 输入 | 节点 | 通带最大偏差 | 峰峰纹波 | 阻带衰减 | 绝对增益 |
|---:|---:|---:|---:|---:|---:|
| 44.1 kHz | 4× | 0.004610111 dB | 0.005702880 dB | 78.668823410 dB | -0.001598865 dB |
| 44.1 kHz | 8× | 0.005394745 dB | 0.006173687 dB | 78.561809849 dB | -0.002709130 dB |
| 44.1 kHz | 128× | 0.006116383 dB | 0.008055724 dB | 72.331082151 dB | -0.003479771 dB |
| 48 kHz | 4× | 0.004610111 dB | 0.005702880 dB | 78.668823410 dB | -0.001598865 dB |
| 48 kHz | 8× | 0.005394745 dB | 0.005718829 dB | 78.561809849 dB | -0.002709130 dB |
| 48 kHz | 128× | 0.006116383 dB | 0.006115655 dB | 72.331082151 dB | -0.003479771 dB |

六工况均满足通带 ±0.05 dB、阻带不低于 70 dB，RTL impulse 对称误差为 0 LSB，线性相位 PASS。

### 7.3 实现/DRC/CDC

- 1159/1159 个可布线网络完成，routing error=0；
- setup/hold 失败端点均为 0；
- DRC 无 Error/Critical Warning，保留 10 条 DSP 流水建议 Warning 和 1 条 Advisory；当前约 45.7 ns WNS 下不为功能阻塞项；
- CDC 保留 BUFGMUX 专用时钟选择和 bundled-data shadow bus 的已解释条目；它们由专用原语、握手稳定窗口和压力测试覆盖，未用虚假路径掩盖。

## 8. 未执行项与后续顺序

### 8.1 未选 MMCM 掉电

这是指导中最有潜在功耗价值的下一项，但不能把 `PWRDWN` 简单接成 `~family_48k`。目标 MMCM 必须先唤醒并等待 `LOCKED`，再切 BUFGMUX，最后关闭旧 MMCM；否则可能选择一个尚未振荡的时钟，甚至让无毛刺 mux 的切换握手停住。

建议独立分支按以下状态机执行：

```text
IDLE -> WAKE_TARGET -> WAIT_TARGET_LOCK -> SWITCH -> GUARD -> POWER_DOWN_OLD -> RELEASE
```

合入门槛应包含 UNISIM 100 次往返、超时错误路径、板级示波器最短脉宽、SAIF 功耗 A/B 和六组合实板复测。当前稳定主线不承担这项时钟风险。

### 8.2 暖机静音

指导建议 64 个输入样点暖机有助于隐藏历史零填充暂态，但它会把切换静音延长约 1.33～1.45 ms，并改变用户可感知恢复时间。当前已有复位、LOCKED 和 CDC 静音窗口；是否再加固定 64 样点需先在板上观察切换波形和声音，故未直接合入。

### 8.3 BRAM 与研究结构

- Stage1 history 与 PCM ROM 合并：可望 `2 -> 1.5 BRAM Tile`，但需要在 Stage1 空闲时隙预取测试音，必须独立验证 ROM 首地址、读延迟和仲裁截止期；
- Stage2/3 history 改 LUTRAM：可望达到 1 BRAM Tile，但会增加约 20～30 LUT，属于新的 Pareto 点；
- RAMB36 双读、三级 FIR 一颗 DSP：需要完整 64-slot 形式调度证明，不能复用已经失败的单读 72>64 原型；
- N4、联合系数/字长、DAC 误差反馈：都会改变传递函数、golden 或模拟带外风险，必须独立性能分支。

## 9. 推荐使用方式

当前默认推荐 **479 LUT / 468 FF / 4 DSP / 2 BRAM Tile**，因为它在保持低 BRAM 的同时具有最低 LUT/FF，并且时序余量最大量级不变。若比赛评分对 DSP 权重明显更高，可切换：

```powershell
# 3-DSP 档
...run_national_finals_vivado_build.ps1 -Step all -CicIntegratorDspMode 1

# 2-DSP 档
...run_national_finals_vivado_build.ps1 -Step all -CicIntegratorDspMode 0
```

三档算法输出严格相同；区别只在 CIC 两个积分器映射到 DSP48E1 还是 LUT CARRY4。

## 10. 尚未完成的物理门禁

当前环境不能接触实物板，因此以下项目仍必须由现场完成，不能把 bitstream 和 UNISIM 通过写成“板级已验证”：

1. 下载默认 4-DSP bitstream，确认 DONE 和器件 ID；
2. 44.1/48 kHz × 4×/8×/128× 六组合逐项测 DA_CLK；
3. 家族/倍率每个方向至少切换 100 次，记录静音窗口、最短高低脉宽和恢复时间；
4. 检查 DAC 中点、Vpp、DC 偏置、15 kHz 主音和首镜像；
5. 记录示波器、频谱仪、供电电流和环境温度；
6. 若要发布 MMCM 低功耗版，再重复同一套门禁。

