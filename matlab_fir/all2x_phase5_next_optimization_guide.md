# 全 2× 128× 插值器 Phase 5/6 下一步优化指导

> 分析对象：上传的 `codex/all2x-phase4-dsp-sharing` 分支压缩包  
> 当前独立插值链基线：`1648 LUT / 1016 FF / 2 DSP / 1 BRAM Tile`  
> 当前板级三档基线：`2122 LUT / 1198 FF / 2 DSP / 1 BRAM Tile`  
> FPGA：XC7A35T-FGG484-2  
> 日期：2026-07-12

---

# 0. 结论

当前版本已经完成了几轮最主要的结构优化：

```text
七级 2× 分解
true-polyphase
Stage 1 严格半带
Stage 1 BRAM 循环缓存
Stage 1 单 DSP MAC
Stage 2/3 共享 DSP
Stage 4～7 canonical halfband shift-add
valid-only bridge
```

因此，下一步不应继续盲目减少 Stage 1 tap，或继续修改已经是 Q4 的
Stage 4～7 系数。根据当前 RTL 和层次综合报告，剩余资源主要集中在：

| 模块 | LUT | FF | 说明 |
|---|---:|---:|---|
| Stage 2/3 共享 DSP | 707 | 469 | 当前最大热点 |
| Stage 1 strict-HB BRAM | 264 | 143 | 其中舍入模块占 106 LUT |
| Stage 4～7 | 301 | 392 | 四套相同 canonical 核 |
| 6 个 valid-only bridge | 84 | 12 | 固定时序仍使用状态桥 |
| 顶层归属逻辑 | 292 | 0 | 需要进一步诊断其来源 |
| 合计 | 1648 | 1016 | 与报告一致 |

Stage 2/3 的 707 LUT 中：

```text
共享数据通路主体：519 LUT
Stage 2 舍入饱和：94 LUT
Stage 3 舍入饱和：94 LUT
```

由此可以看出，下一轮最有把握的方向是：

\[
\boxed{
\text{统一 Q 格式}
+
\text{合并/内置舍入}
+
\text{DSP48 完整 MAC 映射}
}
\]

随后比较：

\[
\boxed{
\text{当前 2 DSP 共享版}
\quad\text{与}\quad
\text{3 DSP 独立串行版}
}
\]

再继续研究：

\[
\boxed{
\text{Stage 2/3 循环 LUTRAM 历史}
+
\text{微码描述符 ROM}
}
\]

更激进的后续路线包括：

```text
Stage 1～3 共用一个可抢占 DSP
Stage 4～7 共享一个 canonical 计算核
逐级数据字长优化
16× CIC 尾部替换
```

---

# 1. 当前代码中最明确的剩余问题

## 1.1 Stage 2 和 Stage 3 放了两个几乎相同的舍入器

当前代码：

```verilog
round_sat_q16_to24 #(
    .FRAC_W (15)
) u_round_stage2 (...);

round_sat_q16_to24 #(
    .FRAC_W (14)
) u_round_stage3 (...);
```

层次综合结果：

```text
u_round_stage2 = 94 LUT
u_round_stage3 = 94 LUT
```

仅两个舍入器就使用：

\[
94+94=188\text{ LUT}
\]

而 Stage 2 和 Stage 3 本来已经共享乘法器和累加器。输出任务不会在同一拍完成，
所以没有必要长期保留两个并行舍入数据通路。

---

## 1.2 当前 DSP 前后仍存在大量 CARRY4

最差时序路径包含：

```text
25 个 CARRY4
1 个 DSP48E1
```

路径大致为：

```text
历史样点选择
→ 25 bit 对称预加
→ DSP 乘法/累加
→ 42 bit 舍入偏置加法
→ 饱和判断
→ 输出寄存器
```

这说明当前 `use_dsp="yes"` 并没有把所有适合的算术都吸收到 DSP48 内部：

- 25 bit 对称预加很可能仍在 LUT/CARRY 中；
- 42 bit 舍入偏置加法明确仍在 LUT/CARRY 中；
- 饱和比较和输出选择也在 LUT 中。

---

## 1.3 Stage 2/3 历史仍由 360 个 FF 组成

当前历史数组：

```verilog
stage2_hist[0:8]  // 9 × 24 = 216 FF
stage3_hist[0:5]  // 6 × 24 = 144 FF
```

合计：

\[
216+144=360\text{ FF}
\]

每次输入更新还会整体移动数组。虽然当前 FF 占用不高，但这部分同时会产生：

- 大量历史选择 mux；
- 多个样点地址 case；
- 较大的数据翻转活动。

---

## 1.4 共享 DSP 的选择逻辑是手写大 case 树

当前代码用：

```text
job_stage
job_phase
job_mac_index
```

进入多层 `if + case`，再选择：

```text
历史地址 A
历史地址 B
系数
中心 tap 或对称 tap
```

这种写法功能清楚，但综合后会形成较大的组合 mux。当前共享模块主体仍占：

```text
519 LUT
```

其中相当一部分来自样点和系数选择。

---

## 1.5 当前“DSP 越少越好”的目标可能已经不再合理

XC7A35T 共有：

```text
90 个 DSP48E1
```

当前完整链只使用：

```text
2 个 DSP
```

占比只有：

\[
2.22\%
\]

Phase 4 为了让 Stage 2/3 共用一个 DSP，引入了：

- stage 选择 mux；
- pending；
- deadline；
- job 调度；
- 共用历史选择逻辑。

从“减少 DSP 数”角度很好，但如果下一目标是进一步降低 LUT，反而应比较：

```text
Stage 1 一个 DSP
Stage 2 一个串行 DSP
Stage 3 一个串行 DSP
```

也就是总共 3 个 DSP。

增加 1 个 DSP 可能消除跨级调度和大范围选择 mux，得到更低 LUT、更简单的 RTL。

---

# 2. Phase 5A：先补齐验证与统计口径

这一步不直接降资源，但必须先做。

## 2.1 不再自动搜索最佳延迟后才判定通过

当前 MATLAB 对拍会在一定范围内搜索 `FIXED_SHIFT`，然后选择误差最小的对齐。

这适合初期定位，但最终回归应使用固定值：

```text
完整链固定 shift = 127
Stage 2 shift      = 0
Stage 3 shift      = 0
```

建议新增：

```matlab
EXPECTED_SHIFT_STAGE2 = 0;
EXPECTED_SHIFT_STAGE3 = 0;
EXPECTED_SHIFT_FULL   = 127;
```

只有固定延迟完全匹配才通过。否则漏样、重复样点或 phase 错位可能被“自动搜索”
掩盖。

---

## 2.2 补充四档版正式实现报告

README 中的：

```text
2122 LUT / 1198 FF
```

对应三档 V4 实板版本。

新增：

```text
15 kHz ROM
1× 旁路
四档按键
```

后必须重新运行：

```text
synth_1
impl_1
write_bitstream
```

再建立新的 Phase 5 基线。后续所有优化都应与同一功能范围的四档版比较。

---

## 2.3 明确 valid 语义

当前代码：

```verilog
x_current = x_in_valid ? x_in : 0;
```

所以：

```text
valid=0 表示当前固定采样时刻输入值为 0
```

而不是：

```text
valid=0 表示整个数据流暂停
```

随机 valid 空洞测试必须按“零样点语义”编写。若未来需要真正流式暂停，
必须整体增加 ready/valid 和状态冻结，不能只改一个模块。

---

# 3. Phase 5B：把 Stage 3 从 Q14 精确改写为 Q15

这是最推荐先做的低风险优化。

## 3.1 当前 Stage 3 Q14 系数

```text
phase0 = [202, -1636, 9625, 9625, -1636, 202]
phase1 = [-74, 261, 16008, 261, -74]
```

将每个系数乘 2：

```text
phase0 = [404, -3272, 19250, 19250, -3272, 404]
phase1 = [-148, 522, 32016, 522, -148]
```

最大绝对值：

\[
32016 < 32767
\]

所以仍能放入 16 bit signed 系数。

---

## 3.2 为什么数值可以完全等价

原 Stage 3 累加值记作 \(A\)，Q14 输出为：

\[
y=
\operatorname{RoundSat}
\left(
\frac{A}{2^{14}}
\right)
\]

新系数全部乘 2 后，累加值变为：

\[
A'=2A
\]

使用 Q15：

\[
y'=
\operatorname{RoundSat}
\left(
\frac{2A}{2^{15}}
\right)
=
\operatorname{RoundSat}
\left(
\frac{A}{2^{14}}
\right)
\]

由于现有正负数舍入偏置规则具有二进制尺度一致性，理论上输出可保持完全一致。

但仍必须做：

```text
边界值
所有量化余数
随机完整 24 bit
饱和边界
```

的 bit-true 穷举/随机验证，不能只依赖代数推导。

---

## 3.3 改完后的直接收益

Stage 2 和 Stage 3 都变成：

```text
Q15
16 bit signed coefficient
```

于是只需一个：

```verilog
round_sat_q15_to24
```

共享输出。

当前两个舍入器为 188 LUT，一个舍入器约94 LUT，因此第一步理论目标是：

```text
减少约 80～100 LUT
```

Stop/Go：

```text
Stage 2/3 中间节点全部 0 LSB
完整链 0 LSB
LUT 至少减少 70
FF 不显著增加
```

---

# 4. Phase 5C：将预加、MAC 和舍入偏置尽量放进 DSP48E1

## 4.1 当前问题

当前代码分开写：

```verilog
pair_sum = sample_a + sample_b;
product  = pair_sum * coeff;
mac_sum  = acc + product;
round    = mac_sum + round_bias;
```

Vivado 目前至少将 42 bit 舍入加法留在 LUT/CARRY 中。

---

## 4.2 目标 DSP 数据通路

理想映射：

```text
DSP A/D 预加器：
sample_a + sample_b

DSP B：
coefficient

DSP M：
pair_sum × coefficient

DSP P：
P + M

最后一个 MAC 周期：
P + sign_dependent_round_bias
```

即尽量使用：

```text
DSP48E1 pre-adder
multiplier
48 bit accumulator
C input / ALU
```

而不是只使用 DSP 的乘法部分。

---

## 4.3 舍入偏置如何放入 DSP

Q15：

```text
正数 bias = 16384
负数 bias = 16383
```

在最后一次 MAC 后增加一个“ROUND”状态：

```text
MAC 最后一拍：得到完整累加结果
ROUND 拍：DSP ALU 加 sign-dependent bias
OUTPUT 拍：取 P[38:15] 并饱和
```

也可以在第一个 MAC 周期预装 bias，但必须保证：

- 累加顺序不改变结果；
- 负数 bias 取决于最终和的符号，而不是第一项符号。

因此更稳妥的是增加一个最终 ROUND 周期。

当前调度最小 slack 为 4 拍，可以先检查增加 1 拍后是否仍满足 deadline。

---

## 4.4 饱和不必做两个宽比较器

右移后判断是否能放入 24 bit，可用高位一致性检查。

令舍入后 42 bit 值为 `v`，输出候选为：

```verilog
v[38:15]
```

若高于输出范围，正数的更高位不全为 0；若低于范围，负数的更高位不全为 1。

可以采用：

```text
positive_overflow = 正数 && 高位存在 1
negative_overflow = 负数 && 高位存在 0
```

避免两个完整的 42 bit 有符号大小比较器。

---

## 4.5 预期收益

当前：

```text
Stage 2/3 两个 rounder = 188 LUT
Stage 1 rounder         = 106 LUT
```

若先合并 Stage 2/3 rounder，再把舍入偏置加法放进 DSP，Stage 2/3 可继续减少约：

```text
50～100 LUT
```

Stage 1 同样可采用该方法，再减少一部分 LUT。

此外，25 bit 对称预加器若成功进入 DSP，可进一步减少 CARRY4 和 LUT。

必须新增：

```tcl
report_dsp_utilization
report_schematic
```

不能只看到 `DSP=1` 就认为预加器和累加器都已经进入 DSP。

---

# 5. Phase 5D：缩小 ACC_W

这是小收益但低风险的配套优化。

## 5.1 Stage 2/3 的严格上界

24 bit signed 输入最大绝对值按：

\[
|x|\le2^{23}
\]

计算。

Stage 2 最坏相位的整数系数绝对值和：

\[
\sum |h|=51952
\]

所以：

\[
|A_2|
\le2^{23}\times51952
<2^{39}
\]

40 bit signed 的范围为：

\[
-2^{39}\sim2^{39}-1
\]

因此从严格绝对值上界看：

```text
Stage 2 ACC_W = 40 足够
```

Stage 3 改为 Q15 后，绝对值和翻倍，但仍可放入 40 bit signed。

当前共享累加器为：

```text
42 bit
```

建议综合比较：

```text
ACC_W = 42
ACC_W = 41
ACC_W = 40
```

---

## 5.2 Stage 1

Stage 1 滤波相系数绝对值和约为：

\[
89512
\]

严格上界需要：

```text
41 bit signed
```

当前使用42 bit，可尝试降到41 bit。

---

## 5.3 注意

ACC_W 减少本身不会带来很大的资源下降，因为 DSP P 端固定为48 bit，
但会减少：

- 外部 acc 寄存器；
- 舍入器位宽；
- 饱和检测宽度；
- 部分控制和 mux 位宽。

它应和 Phase 5C 一起做，而不是单独作为主优化。

---

# 6. Phase 5E：比较 2 DSP 共享版与 3 DSP 独立串行版

这是非常值得做的资源 Pareto。

## 6.1 当前 2 DSP 结构

```text
DSP0：Stage 1
DSP1：Stage 2/3 共享
```

Stage 2/3 共享模块需要：

```text
跨级调度
stage 选择
phase 选择
大范围历史 mux
系数 mux
pending/deadline
```

主体仍占：

```text
519 LUT
```

---

## 6.2 3 DSP 候选

```text
DSP0：Stage 1
DSP1：Stage 2 串行 MAC
DSP2：Stage 3 串行 MAC
```

Stage 2 和 Stage 3 各自的运算窗口非常宽：

```text
Stage 2 最坏 5 MAC，间隔 32 拍
Stage 3 最坏 3 MAC，间隔 16 拍
```

每一级都可以采用极简状态机：

```text
phase
mac_index
acc
history
```

不再需要跨级调度器。

---

## 6.3 为什么可能比共享版更省 LUT

增加1个DSP，但可以删除：

```text
job_stage
跨级 pair mux
跨级 coefficient mux
Stage3优先调度
部分 pending/deadline 控制
```

XC7A35T有90个DSP，使用3个仍只有：

\[
3.33\%
\]

如果目标是最低 LUT，而不是最低 DSP 数，3 DSP 很可能是更优点。

Stop/Go：

```text
相对优化后的2 DSP版本，LUT至少再减少150
FF增加不超过100
DSP=3
0 LSB
时序通过
功耗不高于2 DSP版太多
```

不能预设3 DSP一定更差。

---

# 7. Phase 5F：用微码 ROM 替代手写 case 树

无论最终选择2 DSP还是3 DSP，都可以把 MAC 描述改成“微码”。

## 7.1 当前 case 实际描述的信息

每个 MAC 项只需要：

```text
history address A
history address B
coefficient
是否中心 tap
是否最后一项
```

可以定义一个描述符：

```verilog
typedef struct packed {
    logic [3:0] addr_a;
    logic [3:0] addr_b;
    logic signed [15:0] coeff;
    logic center;
    logic last;
} mac_desc_t;
```

用：

```text
stage + phase + mac_index
```

形成 ROM 地址。

---

## 7.2 ROM 大小

Stage 2/3 总共只需约15条描述：

```text
Stage2 phase0：5
Stage2 phase1：4
Stage3 phase0：3
Stage3 phase1：3
```

即使按32深度存储，每条约25～30 bit，也只是一个很小的 LUT ROM。

这样可以替代多层 `if/case`，并为未来 Stage 1～3 全共享打基础。

---

# 8. Phase 5G：Stage 2/3 历史改成循环 LUTRAM

## 8.1 目标

当前360个历史FF改为：

```text
小深度循环地址
双读端口分布式RAM
```

由于每个 MAC 需要同时读取两个对称样点，可以对同一历史数据复制两份：

```text
RAM_A：读端口 A
RAM_B：读端口 B
写入时两份同时写
```

Stage 2 深度9，Stage 3深度6，可统一映射为32深度分布式RAM。

---

## 8.2 潜在收益

可显著减少：

```text
360 个历史 FF
整体移位活动
大范围寄存器选择 mux
```

代价是增加少量 LUTRAM 和地址逻辑。

Stop/Go：

```text
FF至少减少250
LUT增加不超过80
0 LSB
复位后旧RAM数据被fill_count正确屏蔽
```

如果 LUT 增幅过大，则保留 FF 版本，因为当前主要优化目标仍是 LUT。

---

# 9. Phase 5H：消除 valid-only bridge

当前6个 bridge 合计：

```text
84 LUT / 12 FF
```

固定CE和phase关系完全确定，可以尝试把“何时消费上一级结果”直接集成到下一级：

```text
consumer_accept =
ce_out_next && consumer_phase_is_input_phase
```

上一级输出寄存器保持数据，下一级在固定接受相位直接读取。

若完全确定不会覆盖，可以删除：

```text
pending
phase_mirror
bridge模块
```

这项优化理论上可回收约：

```text
50～84 LUT
```

但必须增加：

```text
producer output hold断言
consumer固定相位断言
输入数量断言
```

不能为了省桥接而破坏phase对齐。

---

# 10. Phase 6A：Stage 1～3 共用一个可抢占 DSP

这是更激进的架构。

## 10.1 总乘法量

每个44.1 kHz输入周期：

```text
Stage 1：26 MAC
Stage 2：18 MAC
Stage 3：24 MAC
```

合计：

\[
26+18+24=68<128
\]

平均吞吐量上一个DSP足够。

---

## 10.2 为什么当前不能简单让 Stage 1 连续运行26拍

现有 Stage2/3 的64拍调度中，空闲窗口为：

```text
7 拍
12 拍
6 拍
12 拍
```

总空闲37拍，但最大连续空闲只有12拍。

Stage 1需要26次MAC，所以必须支持：

```text
Stage 1 job 可暂停
Stage 3 到来时抢占
Stage 2 到来时次优先
空闲时恢复 Stage 1
```

需要保存独立上下文：

```text
acc_stage1
mac_index_stage1
BRAM read state
acc_stage2
acc_stage3
```

调度优先级建议：

```text
Stage 3 > Stage 2 > Stage 1
```

---

## 10.3 价值和风险

可能收益：

```text
DSP从2降到1
合并两套DSP数据通路
合并rounder
减少重复控制
```

风险：

```text
BRAM同步读的暂停/恢复
多上下文累加器
deadline证明更复杂
RTL可读性下降
```

只有在 MATLAB 周期仿真证明：

```text
最小slack >= 2
长期队列有界
```

后才进入RTL。

由于器件DSP非常充足，这不是下一步第一优先级；它更适合作为架构创新实验。

---

# 11. Phase 6B：共享 Stage 4～7 canonical 运算单元

当前四级合计：

```text
约301 LUT / 392 FF
```

每个 Stage 3 输入对应的滤波相计算数：

```text
Stage4：1
Stage5：2
Stage6：4
Stage7：8
合计：15
```

而一个 Stage 3 输入周期正好有16个当前主时钟周期。

因此理论上一个 canonical 计算核可在16拍内完成15个滤波任务，但只剩1拍余量，
且存在级间依赖，不适合直接在当前时钟下实现。

更稳妥的研究方案是将内部计算时钟提高为：

```text
2 × 5.6448 MHz = 11.2896 MHz
```

此时每个 Stage 3 输入有32个计算周期，15个任务有较充足余量。

候选结构：

```text
一套 canonical shift-add
四套小历史状态
静态树形调度
Stage7 每个DAC周期输出
```

目标：

```text
减少100～200 LUT
减少部分输出/历史FF
```

代价：

```text
新增内部快时钟或统一快时钟域
功耗增加
CE和DAC时钟重新设计
```

---

# 12. Phase 6C：逐级数据字长优化

当前所有级的输入、历史和输出均为24 bit。之前主要优化的是：

```text
COEFF_W
FRAC_W
ACC_W
```

还没有系统搜索 `DATA_W`。

建议从后级开始：

```text
Stage4～7：24 / 22 / 20 / 18 bit
Stage3    ：24 / 22 / 20 bit
Stage2    ：24 / 22 bit
Stage1    ：保持24 bit
```

缩窄后再左移补零恢复统一24 bit接口，保持固定二进制标度。

验收分两档：

### 高保真档

```text
SNR相对基线下降 <=0.5 dB
-110 dBFS仍可观察
THD/SINAD无明显恶化
```

### 资源档

```text
SNR >= 85～90 dB
-90 dBFS仍可识别
允许更低幅度归零
```

必须在文档中明确选择哪一档。

---

# 13. Phase 7：16× CIC 尾部研究

可建立独立分支，将：

```text
Stage4～7 四级halfband
```

替换为：

```text
Stage3输出352.8 kHz
→ 16× CIC
→ 5.6448 MHz
→ 低速补偿FIR
```

这是算法级探索，不保证资源一定更低。

需要搜索：

```text
CIC阶数 N=3/4/5
Hogenauer pruning
补偿FIR tap
逐级位宽
```

当前 canonical 尾部只占约301 LUT，所以 CIC 只有在：

```text
补偿和宽积分器总资源明显低于301 LUT/392 FF
```

时才值得替换。

它不是 Phase 5 的首选。

---

# 14. 推荐实施顺序

## 第一步：固定基线

```text
重跑四档综合实现
固定延迟断言
多随机种子
完整24bit压力
生成SAIF功耗
```

## 第二步：Q15统一与一个rounder

```text
Stage3系数×2
Q14 -> Q15
Stage2/3共用一个rounder
```

## 第三步：DSP48完整映射

```text
预加器进入DSP
乘法与累加进入DSP
最终bias加法进入DSP
高位一致性饱和判断
ACC_W 42 -> 40/41
```

## 第四步：DSP Pareto

```text
2 DSP：Stage2/3共享
3 DSP：Stage2、Stage3各自串行
```

以实际LUT和功耗选择，不以DSP最少作为唯一标准。

## 第五步：微码ROM和历史LUTRAM

```text
case树 -> descriptor ROM
FF shift history -> circular LUTRAM
```

## 第六步：删除bridge

在固定相位断言通过后删除。

## 第七步：高级架构

```text
Stage1～3一DSP可抢占调度
尾级共享canonical核
混合数据字长
CIC尾部
```

---

# 15. 推荐 Stop/Go 表

| 实验 | Go 条件 |
|---|---|
| Q15统一 | LUT减少≥70，0 LSB |
| DSP内舍入 | LUT再减少≥50，deadline通过 |
| ACC_W缩小 | 全范围无溢出，0 LSB |
| 3 DSP独立 | 比优化后的2 DSP再少≥150 LUT |
| 微码ROM | LUT下降且代码可维护 |
| 历史LUTRAM | FF减少≥250，LUT增加≤80 |
| 删除bridge | LUT减少≥50，固定相位断言通过 |
| 1 DSP全共享 | 无deadline miss，LUT不反增 |
| 尾级共享 | 至少减少100 LUT，功耗可接受 |
| 数据字长 | 频响、SNR、THD达到选定档位 |
| CIC | 总资源低于canonical尾部且全阻带通过 |

---

# 16. 建议的结果记录表

```markdown
| 版本 | LUT | FF | DSP | BRAM | WNS | 功耗 | 0 LSB | 最小slack |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| V4四档基线 | | | 2 | 1 | | | 是 | 4 |
| Q15 one-rounder | | | 2 | 1 | | | | |
| DSP internal round | | | 2 | 1 | | | | |
| ACC40 | | | 2 | 1 | | | | |
| 3 DSP serial | | | 3 | 1 | | | | |
| microcode | | | | | | | | |
| LUTRAM history | | | | | | | | |
| no bridge | | | | | | | | |
| 1 DSP S1～S3 | | | 1 | 1 | | | | |
| shared tail | | | | | | | | |
```

---

# 17. 立即执行的具体任务

建议现在先做下面五件事：

```text
1. 新建 opt/phase5-q15-single-rounder
2. 将Stage3所有整数系数×2，改成Q15
3. 用一个Q15 round_sat同时服务Stage2和Stage3
4. 完成Stage2/Stage3/完整链0 LSB对拍和综合
5. 在此基础上将最终round bias加法移入DSP48
```

完成后再新开：

```text
opt/phase5-three-dsp-pareto
```

实现 Stage 2、Stage 3 各自独立的串行 DSP MAC，与当前共享版直接比较。

---

# 18. 最终判断

当前仍有优化空间，但下一步的重点已经不是滤波器频率设计，而是：

\[
\boxed{
\text{DSP48内部资源利用率}
}
\]

\[
\boxed{
\text{舍入与饱和数据通路}
}
\]

\[
\boxed{
\text{历史存储和选择网络}
}
\]

\[
\boxed{
\text{DSP数量与LUT之间的Pareto}
}
\]

最值得优先验证的三项是：

1. **Stage 3 Q14 精确改写为 Q15，Stage 2/3 共用一个舍入器；**
2. **把预加、MAC和最终舍入偏置尽量映射进DSP48；**
3. **比较2 DSP共享版和3 DSP独立串行版，不再把DSP最少作为唯一目标。**

这三项完成后，独立插值链继续下降到约 `1200～1450 LUT` 是可以探索的目标，
但必须以实际 Vivado 综合为准，不能预先视为保证结果。
