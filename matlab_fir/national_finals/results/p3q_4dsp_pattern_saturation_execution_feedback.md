# P3-Q 4-DSP DSP48 PATTERNDETECT 饱和优化执行反馈

## 1. 结论

本轮保持 **4 DSP、4 RAMB18E1（2 BRAM Tile）** 不变，尝试把 Stage1 与
Stage2/3 的宽位符号扩展/饱和判定迁入现有 DSP48E1 的 `PATTERNDETECT` 和
`PATTERNBDETECT`。候选 RTL 功能正确，Smoke 回归 **17/17 PASS**，关键逐样本比较均为
**0 LSB**；但四组同策略综合表明该结构在 XC7A35T + Vivado 2018.3 上不能降低 LUT：

| 综合配置 | Stage1 Pattern | Stage2/3 Pattern | LUT | FF | DSP | BRAM Tile | 相对基线 |
|---|---:|---:|---:|---:|---:|---:|---:|
| P3-O 公平基线 | 0 | 0 | 395 | 388 | 4 | 2 | 0 LUT |
| 仅 Stage1 | 1 | 0 | 396 | 388 | 4 | 2 | +1 LUT |
| 仅 Stage2/3 | 0 | 1 | 414 | 388 | 4 | 2 | +19 LUT |
| 两处组合 | 1 | 1 | 415 | 388 | 4 | 2 | +20 LUT |

因此本轮判定 **No-Go**：不进入布局布线、Timing、功耗和 bitstream 阶段，不把“功能
跑通”误写成资源优化成功。试验 RTL、测试参数和构建参数已经逐项撤销，正式工作树恢复
到 P3-O；当前推荐工具签核候选仍为 **361 LUT / 386 FF / 158 Slice / 4 DSP /
2 BRAM Tile / 2 MMCM**。

## 2. 优化原理与边界证明

P3-O 的三个 FIR 输出都需要判断截位后的高位是否只是目标符号位的扩展。理论上可利用
DSP48E1 的模式检测硬件，避免在 Fabric 中实现宽比较器：

- Stage1 令 `MASK[38:0]=1`，比较 `P[47:39]` 是否全 0 或全 1；目标 24-bit 符号位
  `P[38]` 再选择 `PATTERNDETECT` 或 `PATTERNBDETECT`；
- Stage2/3 令 `MASK[35:0]=1`，比较 `P[47:36]`；Stage3 的 21-bit 符号位为
  `P[35]`；当前 Stage2=22 bit、Stage3=21 bit，因此 Stage2 符号位 `P[36]` 正好包含
  在检测区间中，同一组标志可精确服务两级；
- 现有 DSP 使用 `PREG=1`，UNISIM 原语模型确认 P 与模式检测标志在 `CEP` 下同拍更新，
  不需要增加延迟或改变 `valid` 相位。

该推导仅对当前签核字长成立；候选中保留了参数合法性约束，并对非 22/21-bit 情形回退
到原比较器。所有候选都只替换饱和判定，不修改系数、累加、Q15 舍入、数据倍率、CIC、
时钟、ROM、按键或 DAC 接口。

## 3. RTL 验证

先验证原语语义，再跑全国赛 Smoke 门禁。结果目录为临时隔离目录
`matlab_fir/national_finals/_work/rtl_regression/20260805_210601`，完成后按主目录整洁
要求删除；以下定量结果记录在本反馈中：

- Stage1 行为 RAM：1400 个有效输出，候选与基线 **0 LSB**；
- Stage1 真实 UNISIM RAMB18E1：1400 个有效输出，候选与基线 **0 LSB**；
- Stage2：336 个有效输出，**0 LSB**；Stage3：671 个有效输出，**0 LSB**；
- 全链冲激与 `+1` seed：4x/8x/128x 三节点全部 **0 LSB**；
- 8 类复位恢复，每类 4096 输入：全部通过；
- 1200 次原子 CDC 变更、100 次时钟族切换、10 次动态倍率切换：无 X、无残缺脉冲，
  数据持续活动；
- 最终汇总：`NATIONAL FINALS RTL REGRESSION PASS (17/17)`。

第一次 Smoke 在板级 keypad 测试桩处停止，原因是公共模块新增参数未同步到测试桩的
接口声明，并非数值失配。补齐测试桩参数后从头重跑得到上述 17/17；该临时修正也随
No-Go RTL 一并撤销。

## 4. 为什么 LUT 反而增加

基线与候选使用完全相同的 `AreaOptimized_high / flatten_hierarchy=full /
resource_sharing=on`，只有两个 Pattern 开关变化。细分原语计数显示：

| 配置 | LUT as Logic | LUT1 | LUT2 | LUT3 | LUT4 | LUT5 | LUT6 | CARRY4 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 基线 | 394 | 32 | 130 | 94 | 102 | 77 | 65 | 30 |
| 仅 Stage1 | 395 | 31 | 129 | 94 | 98 | 81 | 66 | 30 |
| 仅 Stage2/3 | 413 | 30 | 131 | 73 | 82 | 121 | 65 | 30 |
| 组合 | 414 | 30 | 129 | 73 | 83 | 118 | 67 | 30 |

`CARRY4` 始终为 30，增加主要表现为 Stage2/3 候选多出大量 LUT5，而不是算术进位链或
DSP 数量变化。Vivado 2018.3 能把固定宽度的原符号扩展比较与后级饱和多路选择联合
折叠；改用 DSP Pattern 标志后，标志极性选择、Stage2/Stage3 两种边界和饱和输出选择
破坏了这种折叠，反而形成更多 5 输入 LUT。因此“把比较移进 DSP”在逻辑图上减少了
比较表达式，却没有减少最终 FPGA 映射面积。

## 5. Stop/Go、Timing、功耗与频响口径

本项目按“先综合筛选，再对有希望者实现”的门禁执行。最佳候选综合已经比基线多
1 LUT，Stage2/3 与组合候选分别多 19/20 LUT；它们不可能成为可信的 361→355～362
候选，所以停止在综合阶段：

- 候选 **没有** post-route LUT、Slice、Timing、功耗、DRC/CDC、bitstream 或板测结论；
- 不用 P3-O 的 Timing/功耗冒充候选结果；
- 正式 RTL 恢复后，P3-O 原有工具签核与 P3-M 实板结论均不受影响。

P3-Q 不修改滤波系数或定点数据路径，候选 0-LSB 验证也证明传递函数不变，因此六工况
频响继承 P3-O/P3-M：

| 输入 | 节点 | 通带最大绝对偏差 | 峰峰纹波 | 阻带衰减 |
|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB |

继续保留的 P3-O 物理结果为 WNS/WHS `+44.989/+0.103 ns`、AD9708 setup/hold
`+76.116/+78.117 ns`、总/动态/静态功耗 `0.271/0.199/0.072 W`；这些数值明确属于
恢复后的 P3-O，不属于被淘汰的 P3-Q 候选。

## 6. Git 与回退路线

- 实验分支：`national-finals-p3q-4dsp-pattern-saturation`；
- 分支和提交名称不包含 `codex`；
- 分支基点为 P3-P 审计提交，正式 RTL 最终恢复到同一 P3-O 内容；
- P3-O 工具回退标签：`nf-p3o-toolverified-361lut-386ff-158slice-4dsp-2bram`；
- P3-M 实板安全回退标签：`nf-p3m-final-368lut-386ff-156slice-4dsp-2bram-boardverified`。

本轮只提交 README 与本执行反馈，不提交失败试验 RTL、Vivado 临时目录或用户原有未提交
修改。
