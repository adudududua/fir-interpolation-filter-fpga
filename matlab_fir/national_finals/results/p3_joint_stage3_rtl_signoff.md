# P3-J：Stage3/均衡器联合设计 RTL 签核

## 1. 结论

P4-D 指导中的 P3 创新点已经从 MATLAB 候选完整落地到 RTL、XSim、Vivado 布局布线和 bitstream。当前选定配置为：

```text
CONFIG_ID=NF-P3-RTL-JOINT-STAGE3-EQ-R1
branch=national-finals-p3-rtl-equalizer-fold
synthesis=AreaOptimized_high
flatten_hierarchy=full
resource_sharing=on
implementation_opt=Default
stage1_dsp48_preadder=1
cic_integrator_dsp_mode=2
p3_joint_stage3=1
```

板级 post-route 结果为 **432 LUT / 431 FF / 174 Slice / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM**。相对 P4-D R2 的 479 LUT / 468 FF / 198 Slice，减少 **47 LUT（9.81%）/ 37 FF（7.91%）/ 24 Slice（12.12%）**，DSP、BRAM 和 MMCM 不增加。WNS/WHS 为 **+45.624/+0.105 ns**，TNS/THS 为 0，vectorless 功耗为 **0.271 W（0.199 W dynamic + 0.072 W static）**。

最终 clean-source 构建起点为提交 `d441c49958439e1624ff08a73a1c4263de5686ea`，`source_worktree_dirty=false`。正式结果目录为 `matlab_fir/national_finals/vivado_results/p3_joint_stage3_432lut_431ff_174slice_4dsp_2bram_signedoff`；bitstream SHA-256 为 `8E2C2DB3329BBE519CB8F87249961A35E120A79EE49A2CC706C62D9D037FA85C`，routed DCP SHA-256 为 `6DB2FA7BDD26FAE35E603577D4F708E7CB75BF7B4684F1DAB54E8AEBFDE3F004`。

这不是仅看综合结果的估算，而是完整板级布局布线结果。物理板下载、六档 DA_CLK 和频谱仪测试仍需现场完成，因此本文件只声明工具侧签核通过。

## 2. 创新结构与优化原理

P4-D 的 128x 路径为：

```text
Stage2 -> flat Stage3 -> 独立 11-tap shift-add CIC equalizer -> N3 Hold CIC16
```

P3-J 将 Stage3 和独立均衡器联合设计为一组 11-tap、Q15/signed-18 线性相位系数：

```text
[561, 137, -4232, -1554, 20046, 35584,
 20046, -1554, -4232, 137, 561]
```

正式数据路径变为：

```text
4x/8x  : Stage2 -> flat Stage3
128x   : Stage2 -> compensated Stage3 (signed-21) -> N3 Hold CIC16
```

4x/8x 必须继续使用 flat bank；曾实测“所有模式永久使用 compensated bank”，44.1/48 kHz 的 8x 绝对通带偏差分别达到 0.129854/0.112188 dB，超过 ±0.05 dB，已判 No-Go。

两组 Stage3 系数利用原统一 RAMB18E1 的空闲地址保存；signed-18 的高两位使用 RAMB18 parity 位，不新增 BRAM 或 LUTROM。模式在 Stage3 pending/job 边界快照，避免动态切档时一个 MAC job 混用两组系数。补偿路径保留 signed-21 边界；满量程模型的最大绝对值为 527320，已超过 signed-20 最大值 524287，因此不能盲目缩回 20 bit。独立 `cic3_compensator_shiftadd_ce` 在 P3-J 板级结构中不再 elaboration，这是 LUT/FF 下降的主要来源。

## 3. MATLAB 六工况

下表同时列出赛题直接使用的“相对 0 dB 最大绝对偏差”、峰峰纹波和阻带衰减。全部满足绝对通带偏差/纹波不超过 0.05 dB、阻带不低于 70 dB和严格线性相位要求。

| 输入 | 输出 | 绝对通带最大偏差 | 通带峰峰纹波 | 阻带衰减 |
|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x / 176.4 kHz | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8x / 352.8 kHz | 0.003521 dB | 0.006192 dB | 78.609 dB |
| 44.1 kHz | 128x / 5.6448 MHz | 0.007730 dB | 0.005848 dB | 72.371 dB |
| 48 kHz | 4x / 192 kHz | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 48 kHz | 8x / 384 kHz | 0.003007 dB | 0.005678 dB | 78.609 dB |
| 48 kHz | 128x / 6.144 MHz | 0.007606 dB | 0.005724 dB | 72.371 dB |

冲激对称误差为 0，最大相位残差不超过 `1.42e-13 rad`。MATLAB 定点门禁 10/10 PASS；独立 RTL golden 共 13 组，P3 Stage3 与 CIC 饱和计数均为 0。

## 4. RTL 回归

Smoke 与 Release 均从零编译并 **15/15 PASS**：

- Smoke：冲激 + 1 个 seed×1024，4x/8x/128x 全部 0 LSB；
- Release：冲激 + 10 个固定 seed×4096 + 正/负满量程，共 13 组全链向量，4x/8x/128x 全部 0 LSB；
- 每个随机用例的输出数为 16605/33219/531584；冲激和满量程用例为 1245/2499/40064；
- 8 个内部状态复位恢复场景通过，覆盖 Stage1 MAC、Stage2 pending、Stage2/3 job、CIC pending 和 burst remaining 15/8/1；
- 10 次无复位动态倍率切换通过，无 runt、X 或 pending overwrite；
- 统一系数 RAMB18 原语测试覆盖 32 个 Stage1 地址和 128 个 Stage2/3 signed-18/parity 地址；
- 模式 request/ack CDC 1200 次定向切换通过，双 MMCM 100 次切换压力测试通过。

Smoke 工作目录为 `_work/rtl_regression/20260802_154458`，Release 为 `_work/rtl_regression/20260802_155006`。`_work` 被 Git 忽略；最终结果目录中的发布清单会复制两份全链 XSim 日志并固定 SHA-256。

## 5. 综合与实现策略扫描

先固定 RTL，仅扫描综合参数：

| 综合组合 | 综合 LUT | 综合 FF | 结论 |
|---|---:|---:|---|
| AreaOptimized_high / full / on | **460** | **437** | 选入实现扫描 |
| AreaOptimized_high / rebuilt / auto | 460 | 437 | LUT/FF 同分，层次策略不如 full 便于最终实现收敛 |
| AreaOptimized_high / rebuilt / on | 461 | 437 | 比选中项多 1 LUT |
| AreaOptimized_medium / rebuilt / on | 466 | 437 | 多 6 LUT |
| Default / rebuilt / on | 479 | 437 | 多 19 LUT |
| AreaOptimized_high / none / on | 487 | 437 | 多 27 LUT |

随后固定 `AreaOptimized_high/full/on` 的同一个综合 DCP，扫描实现策略：

| opt_design 指令 | LUT | FF | Slice | WNS/WHS | 结论 |
|---|---:|---:|---:|---:|---|
| **Default** | **432** | **431** | **174** | **+45.624/+0.105 ns** | 选定，最低 LUT 且流程最简单 |
| AddRemap | 432 | 431 | 174 | +45.624/+0.105 ns | 完全同分，无额外收益 |
| Explore | 432 | 431 | 174 | +45.624/+0.105 ns | 完全同分，无额外收益 |
| ExploreWithRemap | 442 | 431 | 178 | +45.598/+0.121 ns | 多 10 LUT/4 Slice，No-Go |
| ExploreArea | 486 | 431 | 183 | +45.806/+0.097 ns | 多 54 LUT/9 Slice，No-Go |

所有实现均为 0.271 W。扫描说明当前改善来自 RTL 结构本身，而不是偶然选中了某个“更激进”策略。

## 6. 物理实现检查

- route status：fully routed，routing error=0；
- setup/hold：WNS/WHS `+45.624/+0.105 ns`，TNS/THS `0/0 ns`，失败端点 0；
- AD9708 输出 setup/hold：`+76.116/+78.117 ns`；
- `check_timing`：无时钟端点 0，未约束内部 max-delay 端点 0；
- CDC：CDC-3 Info 10；CDC-13 Critical 2 为 BUFGMUX 专用 S0/S1；CDC-15 Warning 4 为已采用 request/ack 和 50 ns bus-skew/absolute-delay 约束的 bundled mode bus；
- DRC：error=0；保留 8 个 DPIP-1、2 个 DPOP-1 和 1 个 AVAL-4 非功能性提示，均未产生时序违例。
- bundled mode bus：50 ns bus-skew 门槛下实际 1.801 ns；absolute data delay 最大 1.000 ns；

## 7. 回退路线

- P4-D R2 稳定标签：`nf-p4d-r2-479lut-468ff-4dsp-2bram-2mmcm-clean`；
- P3-J 阶段提交依次为 MATLAB 门禁、架构冻结、RTL 实现、复位/动态回归、可复现构建和策略扫描；
- 最终 P3-J 签核标签：`nf-p3j-432lut-431ff-174slice-4dsp-2bram-2mmcm-signedoff`。
