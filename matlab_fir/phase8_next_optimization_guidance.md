# Phase 8 下一阶段优化指导：从最低 LUT 候选走向架构—功耗 Pareto

> 适用分支：`codex/phase7-lut-min-next`  
> FPGA：Xilinx Artix-7 XC7A35T-FGG484-2  
> 输入/输出：44.1 kHz、24 bit signed PCM → 5.6448 MHz、128×  
> 展示：15 kHz 正弦，1× / 4× / 8× / 128×，矩阵按键切换，单 DAC  
> 当前最低 LUT 候选：`478 LUT / 565 FF / 9 DSP / 3 BRAM Tile`  
> 当前状态：自动化仿真、daily/nightly bit-true、复位、动态切档、实现和 bitstream 均通过；478 LUT 版本仍需完成实板四档复测。

---

# 0. 当前工程处于什么阶段

当前版本已经完成了以下主要优化：

```text
多级 2× + CIC16
strict-halfband Stage1
true-polyphase Stage2/3
Stage3 折叠 CIC 补偿
Stage1 BRAM 环形历史
Stage2/3 单读环形 RAM
单 DSP 串行 MAC
CIC 宽位加减映射 DSP48
紧凑舍入
PCM ROM BRAM
Stage2/3 历史/系数 BRAM
紧凑矩阵键盘
共享扫描计数器
无毛刺档位切换
Vivado 面积优化策略
```

当前算法指标：

| 指标 | 当前结果 | 赛题要求 |
|---|---:|---:|
| 最终通带最大绝对误差 | 0.00303062 dB | ≤ ±0.05 dB |
| 最终阻带衰减 | 72.349 dB | ≥ 70 dB |
| 128×冲激对称误差 | 0 output LSB | 严格线性相位 |
| MATLAB/RTL | daily/nightly均0 LSB | 功能一致 |
| 128×群延迟 | 3686.5 samples | 线性相位 |

当前资源存在多个 Pareto 点：

| 候选 | LUT | FF | DSP | BRAM Tile | 特点 |
|---|---:|---:|---:|---:|---|
| 低 DSP 回退 | 941 | 940 | 2 | 1.5 | 专用资源少 |
| LUTRAM 回退 | 578 | 619 | 9 | 1.5 | BRAM少、LUT较低 |
| 默认策略 BRAM版 | 496 | 565 | 9 | 3 | RTL最低面积基线 |
| 面积策略最低 LUT | 478 | 565 | 9 | 3 | 当前最低LUT |

因此下一阶段不应继续无目标地“少几个 tap、少几位数据”，而应转向：

\[
oxed{
	ext{实板闭环}
+
	ext{真实功耗 Pareto}
+
	ext{后级架构联合搜索}
+
	ext{全局计算资源调度}
}
\]

---

# 1. 总体实施原则

## 1.1 冻结稳定回退版本

必须同时保留：

```text
A. 已实板稳定 Phase6/早期Phase7版本
B. 941 LUT / 2 DSP 回退版本
C. 578 LUT / 9 DSP / LUTRAM版本
D. 496 LUT / 9 DSP / BRAM默认策略版本
E. 478 LUT / 9 DSP / 面积策略候选
```

禁止在478 LUT候选实板闭环前覆盖稳定 MCS。

## 1.2 每个实验必须改变一个主要变量

例如：

```text
只改变 CIC 阶数；
只改变 CIC 倍率；
只改变剩余 halfband 数量；
只改变处理时钟；
只改变 RAM 打包；
只改变 Vivado 策略。
```

不要一次同时改系数、字长、时钟、调度和存储，否则无法判断资源变化来源。

## 1.3 所有候选必须通过同一验证门槛

至少包括：

```text
正式顶层冲激0 LSB
daily：4 seed × 1024输入
nightly：10 seed × 4096输入
4×/8×/128×三个节点固定延迟对拍
8场景中途复位
10次动态四档切换
RTL冲激FFT
post-route时序和DRC
```

---

# 2. Phase 8A：478 LUT候选实板闭环（必须先做）

这一步不是新的算法优化，但它决定478 LUT是否能成为新基线。

## 2.1 下载前校验

记录：

```text
.bit完整路径
SHA256
综合顶层参数
综合/实现策略
生成时间
Git commit
```

确认使用的是：

```text
BRAM Stage2/3历史
BRAM Stage2/3系数
紧凑键盘
共享扫描
AreaOptimized_high
ExploreArea
0.50FS / 15 kHz ROM
```

## 2.2 四档静态实测

| 档位 | 理论 DA_CLK | 允许误差建议 | 需要记录 |
|---|---:|---:|---|
| 1× | 44.1 kHz | ±0.2% | 波形、频率、DAC码范围 |
| 4× | 176.4 kHz | ±0.2% | 波形、频率、DAC码范围 |
| 8× | 352.8 kHz | ±0.2% | 波形、频率、DAC码范围 |
| 128× | 5.6448 MHz | ±0.2% | 波形、频率、DAC码范围 |

注意：

```text
8×是CIC预补偿内部节点，高频增益略有上扬；
现场主要展示波形采样密度，不把8×节点误当最终频响验收节点。
```

## 2.3 动态测试

至少完成：

```text
1×→4×→8×→128×→8×→4×→1×
连续往返20轮
运行中按复位
掉电再上电
JTAG下载后与Flash启动后对比
```

检查：

```text
无DA_CLK窄脉冲
无波形停顿
无异常直流偏置
无旧CIC积分器状态泄漏
无按键切换失效
```

## 2.4 Phase 8A Go条件

```text
四档频率全部正确；
15 kHz波形正常；
动态切换20轮无异常；
运行中复位可恢复；
掉电重启加载正确固件；
连续运行30分钟无失稳。
```

若失败，立即回退496/578/941 LUT候选定位，不继续在478上叠加新优化。

---

# 3. Phase 8B：真实活动率功耗 Pareto

当前 `0.168 W` 为 vectorless、Low confidence，不能据此判断：

```text
941 LUT / 2 DSP
和
478 LUT / 9 DSP
```

谁的真实动态功耗更低。

## 3.1 必测候选

```text
P1：941 LUT / 2 DSP / 1.5 BRAM
P2：578 LUT / 9 DSP / 1.5 BRAM
P3：496 LUT / 9 DSP / 3 BRAM
P4：478 LUT / 9 DSP / 3 BRAM
```

## 3.2 必测激励

```text
静音
15 kHz / 0.50FS
20 kHz / -6 dBFS
随机PCM正常幅度
四档动态切换
```

## 3.3 实施方法

1. 在post-route网表上运行代表性仿真；
2. 导出 SAIF 或 VCD；
3. 在 Vivado `report_power` 中加载活动率文件；
4. 保持相同温度、电压、IO负载、仿真时长和激励；
5. 分别记录 Clock、Logic、Signals、BRAM、DSP、I/O 和 Total Dynamic。

## 3.4 功耗成本模型

建议计算：

\[
J=
w_Lrac{LUT}{20800}
+w_Frac{FF}{41600}
+w_Drac{DSP}{90}
+w_Brac{BRAM}{50}
+w_Prac{P_{\mathrm{dyn}}}{P_{\mathrm{ref}}}
\]

至少给出三套权重：

```text
最低LUT档：wL最大
低功耗档：wP最大
均衡档：wL、wD、wB、wP均衡
```

## 3.5 Phase 8B Go条件

如果478 LUT候选相对941 LUT候选：

```text
动态功耗增加≤10%：保留为最低LUT正式候选；
动态功耗增加>10%且比赛不按LUT单项评分：保留两个Pareto版本；
动态功耗下降：将“DSP换LUT同时降低开关活动”作为创新结果。
```

---

# 4. Phase 8C：CIC倍率—阶数—剩余Halfband联合搜索

这是下一阶段最值得做的算法—架构联合优化。

当前尾部总倍率：

\[
16
\]

当前结构：

\[
	ext{CIC}_{16},\quad N=3
\]

但总倍率16还可以拆成：

\[
16=8	imes2
\]

\[
16=4	imes2	imes2
\]

候选满足：

\[
R_{\mathrm{CIC}}2^K=16
\]

其中：

- \(R_{\mathrm{CIC}}\)：CIC倍率；
- \(K\)：剩余2×halfband级数。

## 4.1 第一批候选

| 编号 | 尾部结构 |
|---|---|
| A | CIC16，N=2/3/4 |
| B | CIC8，N=2/3 + 2×HB |
| C | 2×HB + CIC8，N=2/3 |
| D | CIC4，N=2/3 + 2×HB + 2×HB |
| E | 2×HB + CIC4，N=2/3 + 2×HB |
| F | 2×HB + 2×HB + CIC4，N=2/3 |

要同时搜索“CIC在前还是halfband在前”，因为CIC输入采样率、零点位置和通带下垂会随位置改变。

## 4.2 每个候选的频率响应

尾部响应：

\[
H_{\mathrm{tail}}(f)=
H_{\mathrm{CIC}}(f)
\prod_{j=1}^{K}H_{\mathrm{HB},j}(f)
\]

完整链：

\[
H_{\mathrm{total}}(f)=
H_1(f)H_2(f)H_{3,\mathrm{new}}(f)H_{\mathrm{tail}}(f)
\]

Stage3重新设计目标：

\[
H_{3,\mathrm{new}}(f)
pprox
rac{H_{\mathrm{target}}(f)}
{H_1(f)H_2(f)H_{\mathrm{tail}}(f)}
\]

通带内可写为：

\[
D_3(f)=
rac{2}
{G_1(f)G_2(f)G_{\mathrm{tail}}(f)}
\]

## 4.3 MATLAB脚本建议

```text
matlab_fir/alt_all2x_v8/
├── phase8_01_enumerate_tail_architectures.m
├── phase8_02_design_folded_stage3.m
├── phase8_03_bittrue_wordlength_search.m
├── phase8_04_estimate_hardware_cost.m
├── phase8_05_generate_pareto.m
└── phase8_06_export_candidate_manifest.m
```

输出：

```text
phase8_tail_candidates.csv
phase8_frequency_pareto.csv
phase8_hardware_cost_pareto.csv
phase8_selected_candidates.md
```

## 4.4 参数搜索空间

```text
R_CIC ∈ {4, 8, 16}
N_CIC ∈ {2, 3, 4}
M = 1
Stage3 taps ∈ {11, 15, 19}
Stage3 Q格式 ∈ {Q14, Q15}
剩余HB taps ∈ {7 canonical, 11/15 strict-HB}
内部数据位宽：从现有位宽开始，仅做有证据的±1～2 bit搜索
```

## 4.5 候选估算成本

CIC平均宽位加减/最终输出样点：

\[
N_{\mathrm{add,CIC}}
=
N_{\mathrm{CIC}}
+
rac{N_{\mathrm{CIC}}}{R_{\mathrm{CIC}}}
\]

位宽增长：

\[
B_{\mathrm{growth}}
=
N_{\mathrm{CIC}}\log_2(R_{\mathrm{CIC}}M)
\]

剩余Halfband按非零tap、对称折叠、shift-add、工作采样率和历史存储bit数估算。

## 4.6 Phase 8C Stop/Go

进入RTL至少满足：

```text
最终通带最大绝对误差≤0.01 dB
最终阻带≥72 dB
严格线性相位
随机PCM Delta-SNR≥94 dB
正常输入无饱和
```

进入板级至少满足以下任意一项：

```text
1. LUT < 478，DSP≤9，BRAM≤3；
2. DSP减少≥3，且LUT≤650；
3. BRAM减少≥1 Tile，且LUT≤550；
4. SAIF动态功耗相对478版本下降≥10%；
5. 在资源相近时，阻带余量提升≥3 dB。
```

---

# 5. Phase 8D：更高内部处理时钟下的全局DSP共享

当前最低LUT版使用9个DSP，其中7个用于CIC宽位加减。

CIC N=3平均运算量约：

\[
3+rac{3}{16}=3.1875
\]

次宽位加减/最终输出样点。

若内部处理时钟高于最终采样时钟数倍，可以用更少DSP串行完成：

```text
comb0/1/2
integrator0/1/2
Stage2/3 MAC
```

## 5.1 时钟候选

先用Clocking Wizard验证从20 MHz输入能否生成：

```text
22.5792 MHz（4×最终采样率）
45.1584 MHz（8×最终采样率）
```

检查：

```text
实际频率误差
MMCM VCO范围
输出抖动
占空比
是否需要第二个MMCM
```

若无法精确或稳定地产生，则该路线No-Go。

## 5.2 调度模型

将每个运算建模为：

```text
arrival
execution_cycles
dependency
deadline
state_context
```

优先级可先从：

```text
最终输出integrator
> Stage3
> Stage2
> comb
```

开始，再用EDF或静态周期表搜索。

必须考虑：

```text
BRAM同步读延迟
DSP输入/输出寄存器
累加器上下文切换
模2^W运算
最终输出提交时刻
```

## 5.3 MATLAB调度器

新增：

```text
phase8_07_fastclock_schedule_search.m
```

输出：

```text
cycle
job
stage
operation
operand_source
acc_context
deadline
slack
```

检查：

```text
最小slack≥2个处理时钟
队列长期有界
每个5.6448 MHz输出时刻结果已提交
```

## 5.4 目标

```text
DSP：9 → 2～4
LUT：≤550
FF：≤700
BRAM：≤3
```

这一路线主要目标是减少DSP/功耗，不保证低于478 LUT。

---

# 6. Phase 8E：剩余微型资源优化

只有在Phase8A～D之后，再处理个位到几十LUT级优化。

## 6.1 Stage2/3公共舍入器

设计一个公共“商—余数—单bit进位”舍入器：

\[
x=q2^{15}+r
\]

\[
q_{\mathrm{round}}=q+\mathrm{inc}(sign,r)
\]

由 `job_stage` 选择22 bit或20 bit饱和宽度。

Go条件：

```text
减少≥12 LUT
0 LSB
不增加deadline风险
```

## 6.2 进一步移除数据寄存器复位

仅对“只有valid=1时才读取，且复位后有fill_count/valid屏蔽”的数据寄存器取消复位。

控制状态、CIC积分器和comb历史仍必须确定复位。

Go条件：

```text
FF/LUT可测下降
8场景复位全部通过
BRAM/LUTRAM推断不退化
```

## 6.3 Stage2/3历史与系数BRAM打包

研究在更少RAMB18中同时容纳：

```text
Stage2历史
Stage3历史
顺序系数
```

重点是端口冲突，不是容量。

Stop/Go：

```text
BRAM至少减少0.5 Tile
LUT增加≤20
WNS/WHS通过
nightly 0 LSB
```

## 6.4 DAC输出与模式控制A/B

比较：

```text
当前安全提交时钟
ODDR输出
单高速时钟+数据更新使能
预计算toggle状态
```

必须保持：

```text
无runt pulse
四档频率正确
DAC数据建立保持正确
```

Go条件：

```text
减少≥10 LUT或显著改善板级波形/时钟质量
```

## 6.5 Vivado策略搜索

以相同RTL批量搜索：

```text
Flow_AreaOptimized_high
ExploreArea
AlternateRoutability
不同place/route directive
多个seed
```

必须在报告中区分：

```text
RTL优化收益
工具策略收益
```

---

# 7. 当前不建议继续做的方向

```text
不再缩短Stage1 taps；
不再无证据降低字长；
不重复三DSP独立Stage2/3；
不强制所有小系数ROM进入BRAM；
不直接覆盖稳定MCS。
```

原因是最终阻带余量只有约：

\[
72.349-70=2.349	ext{ dB}
\]

继续激进截位或缩tap的风险已经大于预期收益。

---

# 8. 推荐分支规划

```text
validation/phase7-478-board-closeout
explore/phase8-power-pareto
explore/phase8-tail-architecture-pareto
explore/phase8-fastclock-global-share
opt/phase8-round-control-min
release/regional-final-phase8
```

合并顺序：

```text
478实板闭环
→ 功耗Pareto
→ 尾部架构搜索
→ 选择1～2个候选写RTL
→ 全量验证
→ 板测
→ 决赛release
```

---

# 9. 每轮统一结果表

```markdown
| 版本 | LUT | FF | DSP | BRAM | WNS | WHS | Dynamic Power | Passband | Stopband | 0 LSB | Board |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 941 LUT低DSP | | | | | | | | | | | |
| 578 LUTRAM | | | | | | | | | | | |
| 496 BRAM默认 | | | | | | | | | | | |
| 478面积策略 | | | | | | | | | | | |
| Phase8候选A | | | | | | | | | | | |
| Phase8候选B | | | | | | | | | | | |
```

---

# 10. 最推荐的执行顺序

## 第一阶段：比赛可靠性

```text
1. 完成478 LUT实板四档复测；
2. 固化正确MCS；
3. 形成示波器截图与频率表；
4. 冻结稳定版本。
```

## 第二阶段：真实Pareto

```text
5. 对941/578/496/478四个版本生成相同SAIF；
6. 比较LUT-DSP-BRAM-功耗；
7. 决定“最低LUT版”和“均衡版”。
```

## 第三阶段：新架构创新

```text
8. 搜索CIC16/CIC8/CIC4与剩余HB组合；
9. 重新设计Stage3折叠补偿；
10. 先MATLAB和成本模型筛选；
11. 只实现最优1～2个RTL候选。
```

## 第四阶段：高风险研究

```text
12. 验证更高内部时钟；
13. 建立全局DSP微调度；
14. 目标DSP 9→2～4；
15. 仅在功耗/资源Pareto明显改善时保留。
```

## 第五阶段：微优化和发布

```text
16. 公共舍入器/复位/BRAM打包；
17. Vivado多策略搜索；
18. 全量nightly、复位、切档；
19. 最终板测；
20. 生成release与答辩材料。
```

---

# 11. 最终目标建议

建议同时保留三个正式候选。

## 最低LUT版

```text
目标：LUT≤478
用途：突出结构优化和专用资源迁移
```

## 均衡资源版

```text
目标：LUT≤650，DSP≤4，BRAM≤2
用途：展示总资源Pareto
```

## 最低功耗版

```text
目标：以SAIF实测动态功耗最低为准
用途：回应赛题功耗评估与工程价值
```

最终答辩可以形成：

> 本项目不是仅针对单一资源指标优化，而是建立从算法参数、定点字长、运算调度、存储映射到实现策略的多目标设计空间，并形成最低LUT、均衡资源和低功耗三个Pareto候选。

这比继续单独压十几个LUT更具有创新性和完整性。
